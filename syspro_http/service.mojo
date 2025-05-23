from syspro_http.http import HTTPRequest, HTTPResponse, OK, NotFound
from syspro_http.io.bytes import Bytes, bytes
from syspro_http.strings import to_string
from syspro_http.header import HeaderKey

trait HTTPService:
    fn func(mut self, req: HTTPRequest) raises -> HTTPResponse:
        ...

@value
struct Printer(HTTPService):
    fn func(mut self, req: HTTPRequest) raises -> HTTPResponse:
        print("Request URI:", req.uri.request_uri)
        print("Request protocol:", req.protocol)
        print("Request method:", req.method)
        print("Request Content-Type:", req.headers[HeaderKey.CONTENT_TYPE])
        print("Request Body:", to_string(req.body_raw))

        return OK(req.body_raw)

@value
struct Welcome(HTTPService):
    fn func(mut self, req: HTTPRequest) raises -> HTTPResponse:
        if req.uri.path == "/":
            with open("static/lightbug_welcome.html", "r") as f:
                return OK(f.read_bytes(), "text/html; charset=utf-8")
        if req.uri.path == "/logo.png":
            with open("static/logo.png", "r") as f:
                return OK(f.read_bytes(), "image/png")

        return NotFound(req.uri.path)

@value
struct ExampleRouter(HTTPService):
    fn func(mut self, req: HTTPRequest) raises -> HTTPResponse:
        if req.uri.path == "/":
            print("I'm on the index path!")
        if req.uri.path == "/first":
            print("I'm on /first!")
        elif req.uri.path == "/second":
            print("I'm on /second!")
        elif req.uri.path == "/echo":
            print(to_string(req.body_raw))

        return OK(req.body_raw)

@value
struct TechEmpowerRouter(HTTPService):
    fn func(mut self, req: HTTPRequest) raises -> HTTPResponse:
        if req.uri.path == "/plaintext":
            return OK("Hello, World!", "text/plain")
        elif req.uri.path == "/json":
            return OK('{"message": "Hello, World!"}', "application/json")

        return OK("Hello world!")

@value
struct Counter(HTTPService):
    var counter: Int

    fn __init__(out self):
        self.counter = 0

    fn func(mut self, req: HTTPRequest) raises -> HTTPResponse:
        self.counter += 1
        return OK("I have been called: " + str(self.counter) + " times")
