from syspro_http import HTTPRequest, HTTPResponse, Server
from syspro_api.routing import (
    BaseRequest,
    FromReq,
    RootRouter,
    Router,
    HandlerResponse,
    JSONType,
)

@value
struct App:
    var router: RootRouter

    fn __init__(out self) raises:
        self.router = RootRouter()

    fn get[
        T: FromReq = BaseRequest
    ](
        mut self,
        path: String,
        handler: fn (T) raises -> HandlerResponse,
    ) raises:
        self.router.get[T](path, handler)

    fn post[
        T: FromReq = BaseRequest
    ](
        mut self,
        path: String,
        handler: fn (T) raises -> HandlerResponse,
    ) raises:
        self.router.post[T](path, handler)

    fn add_router(mut self, owned router: Router) raises -> None:
        self.router.add_router(router)

    fn start_server(mut self, address: StringLiteral = "0.0.0.0:8080") raises:
        var server = Server()
        server.listen_and_serve(address, self.router)
        
