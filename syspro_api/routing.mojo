from utils.variant import Variant
from collections import Dict, List, Optional
from collections.dict import _DictEntryIter

from syspro_http import NotFound, OK, HTTPService, HTTPRequest, HTTPResponse
from syspro_http.strings import RequestMethod

# ルート配下のサブルーターの最大深度
alias MAX_SUB_ROUTER_DEPTH = 20

# ルーターのエラー定義
struct RouterErrors:
    alias ROUTE_NOT_FOUND_ERROR = "ROUTE_NOT_FOUND_ERROR"
    alias INVALID_PATH_ERROR = "INVALID_PATH_ERROR"
    alias INVALID_PATH_FRAGMENT_ERROR = "INVALID_PATH_FRAGMENT_ERROR"

# escapingは関数のスコープ外で使用される可能性を示す
alias HTTPHandlerWrapper = fn (req: HTTPRequest) raises escaping -> HTTPResponse

# TODO: JSONの型定義を厳密にする
alias JSONType = Dict[String, String]

# ハンドラーの返り値の型定義
alias HandlerResponse = Variant[HTTPResponse, String, JSONType]

# リクエストのペイロードをデシリアライズしてT型に変換する
trait FromReq(Movable, Copyable):
    fn __init__(out self, request: HTTPRequest, json: JSONType):
        ...

    fn from_request(mut self, req: HTTPRequest) raises -> Self:
        ...

    fn __str__(self) -> String:
        ...

# Base
@value
struct BaseRequest:
    var request: HTTPRequest
    var json: JSONType

    fn __init__(out self, request: HTTPRequest, json: JSONType):
        self.request = request
        self.json = json

    fn __str__(self) -> String:
        # TODO: デバッグ用の文字列を返す
        return str("")

    # リクエストを処理して追加の情報を取得する
    fn from_request(mut self, req: HTTPRequest) raises -> Self:
        return self
    """
    ex:
        let query = req.query_params()
        if query.has_key("user_id):
            self.json["user_id"] = query["user_id"]
        let auth = req.headers().get("Authorization")
        if auth != "":
            self.json["auth"] = auth
        return self
    """

@value
struct RouteHandler[T: FromReq]:
    var handler: fn (T) raises -> HandlerResponse

    fn __init__(out self, h: fn(T) raises -> HandlerResponse):
        self.handler = h

    # handlerの返り値をHTTPResponseに変換する
    fn _encode_response(self, res: HandlerResponse) raises -> HTTPResponse:
        if res.isa[HTTPResponse]():
            return res[HTTPResponse]
        elif res.isa[String]():
            return OK(res[String])
        elif res.isa[JSONType]():
            return OK(self._serialize_json(res[JSONType]))
        else:
            raise Error("Unsupported response type")
    
    fn _serialize_json(self, json: JSONType) raises -> String:
        fn ser(j: JSONType) raises -> String:
            var str_frags = List[String]()
            # TODO:文字列以外でリスト・ネスト・数値・null・boolに対応
            # TODO:エスケープ処理("や\n)
            for kv in j.items():
                str_frags.append(
                    '"' + str(kv[].key) + '": "' + str(kv[].value) + '"'
                )
            var str_res = str("{") + str(",").join(str_frags) + str("}")
            return str_res

        return ser(json)
    
    # TODO: リクエストのペイロードをデシリアライズしてJSONTypeに変換する
    fn _deserialize_json(self, req: HTTPRequest) raises -> JSONType:
        return JSONType()
    
    # リクエストを処理してハンドラーを呼び出す
    fn handle(self, req: HTTPRequest) raises -> HTTPResponse:
        # リクエストのペイロードをデシリアライズしてT型に変換する
        var payload = T(request=req, json=self._deserialize_json(req)) # var payload = BaseRequest(request=req, json=self._deserialize_json(req))と等価。つまりコンストラクタ呼び出し
        # from_requestはreqの情報を使ってpayloadを更新する。例えば、req.query_params()を使ってpayload.jsonに追加する。
        payload = payload.from_request(req)
        # ハンドラを呼び出して、レスポンスを取得する
        var handler_response = self.handler(payload)
        # ハンドラーの返り値をHTTPResponseに変換する
        return self._encode_response(handler_response)

alias HTTPHandlersMap = Dict[String, HTTPHandlerWrapper]

@value
struct RouterBase[is_main_app: Bool = False](HTTPService):
    var path_fragment: String
    var sub_routers: Dict[String, RouterBase[False]]
    var routes: Dict[String, HTTPHandlersMap]

    fn __init__(out self) raises:
        if not is_main_app:
            raise Error("Sub-router requires url path fragment it will manage")
        self.__init__(path_fragment="/")

    fn __init__(out self, path_fragment: String) raises:
        self.path_fragment = path_fragment
        self.sub_routers = Dict[String, RouterBase[False]]()
        self.routes = Dict[String, HTTPHandlersMap]()

        self.routes[RequestMethod.head.value] = HTTPHandlersMap()
        self.routes[RequestMethod.get.value] = HTTPHandlersMap()
        self.routes[RequestMethod.put.value] = HTTPHandlersMap()
        self.routes[RequestMethod.post.value] = HTTPHandlersMap()
        self.routes[RequestMethod.patch.value] = HTTPHandlersMap()
        self.routes[RequestMethod.delete.value] = HTTPHandlersMap()
        self.routes[RequestMethod.options.value] = HTTPHandlersMap()

        if not self._validate_path_fragment(path_fragment):
            raise Error(RouterErrors.INVALID_PATH_FRAGMENT_ERROR)

    # URLパスを解析して、対応するハンドラを返す
    fn _route(
        mut self, partial_path: String, method: String, depth: Int = 0
    ) raises -> HTTPHandlerWrapper:
        if depth > MAX_SUB_ROUTER_DEPTH:
            raise Error(RouterErrors.ROUTE_NOT_FOUND_ERROR)

        var sub_router_name: String = ""
        var remaining_path: String = ""
        var handler_path = partial_path

        if partial_path:
            var fragments = partial_path.split("/", 1)
            # fragmentsは["", "users"]のようなリストになる

            sub_router_name = fragments[0]
            if len(fragments) == 2:
                # 2つ目の要素がある場合は、それをremaining_pathに設定
                remaining_path = fragments[1]
            else:
                remaining_path = ""

        else:
            handler_path = "/"

        if sub_router_name in self.sub_routers:
            return self.sub_routers[sub_router_name]._route(
                remaining_path, method, depth + 1
            )
        elif handler_path in self.routes[method]:
            return self.routes[method][handler_path]
        else:
            raise Error(RouterErrors.ROUTE_NOT_FOUND_ERROR)

    # _routeを呼び出して、対応するハンドラを取得する
    fn func(mut self, req: HTTPRequest) raises -> HTTPResponse:
        var uri = req.uri
        var path = uri.path.split("/", 1)[1]
        var route_handler_meta: HTTPHandlerWrapper
        try:
            route_handler_meta = self._route(path, req.method)
        except e:
            if str(e) == RouterErrors.ROUTE_NOT_FOUND_ERROR:
                return NotFound(uri.path)
            raise e

        return route_handler_meta(req)

    fn _validate_path_fragment(self, path_fragment: String) -> Bool:
        # TODO: Validate fragment
        return True

    fn _validate_path(self, path: String) -> Bool:
        # TODO: Validate path
        return True

    fn add_router(mut self, owned router: RouterBase[False]) raises -> None:
        self.sub_routers[router.path_fragment] = router

    fn add_route[
        T: FromReq
    ](
        mut self,
        partial_path: String,
        handler: fn (T) raises -> HandlerResponse,
        method: RequestMethod = RequestMethod.get,
    ) raises -> None:
        if not self._validate_path(partial_path):
            raise Error(RouterErrors.INVALID_PATH_ERROR)

        fn handle(req: HTTPRequest) raises escaping -> HTTPResponse:
            return RouteHandler[T](handler).handle(req)

        self.routes[method.value][partial_path] = handle

    fn get[
        T: FromReq = BaseRequest
    ](
        mut self,
        path: String,
        handler: fn (T) raises -> HandlerResponse,
    ) raises:
        self.add_route[T](path, handler, RequestMethod.get)

    fn post[
        T: FromReq = BaseRequest
    ](
        mut self,
        path: String,
        handler: fn (T) raises -> HandlerResponse,
    ) raises:
        self.add_route[T](path, handler, RequestMethod.post)


alias RootRouter = RouterBase[True]
alias Router = RouterBase[False]