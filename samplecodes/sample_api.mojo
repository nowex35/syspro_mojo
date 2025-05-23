from syspro_api import (
    App,
    BaseRequest,
    Router,
    HandlerResponse,
    JSONType
)
from syspro_http import HTTPRequest, HTTPResponse, OK


@always_inline
fn printer(req: BaseRequest) raises -> HandlerResponse:
    print("Got a request on ", req.request.uri.path, " with method ", req.request.method)
    return OK(req.request.body_raw)

@always_inline
fn hello(payload: BaseRequest) raises -> HandlerResponse:
    return OK("Hello mojo!")


@always_inline
fn nested(req: BaseRequest) raises -> HandlerResponse:
    print("Handling route:", req.request.uri.path)

    # Returning a string will get marshaled to a proper `OK` response
    return req.request.uri.path

@value
struct Payload:
  var request: HTTPRequest
  var json: JSONType
  var a: Int

  fn __init__(out self, request: HTTPRequest, json: JSONType):
    self.a = 1
    self.request = request
    self.json = json

  fn __str__(self) -> String:
    return str(self.a)

  fn from_request(mut self, req: HTTPRequest) raises -> Self:
    self.a = 2
    return self
    

@always_inline
fn custom_request_payload(payload: Payload) raises -> HandlerResponse:
    print(payload.a)

    # Returning a JSON as the response, this is a very limited placeholder for now 
    var json_response = JSONType()
    json_response["a"] = str(payload.a)
    return json_response


fn main() raises:
    var app = App()

    app.get[BaseRequest]("/", hello)

    app.get[Payload]("custom/", custom_request_payload)

    # We can skip specifying payload when using BaseRequest
    app.post("/", printer)

    var nested_router = Router("nested")
    nested_router.get(path="all/echo/", handler=nested)
    app.add_router(nested_router)

    app.start_server()