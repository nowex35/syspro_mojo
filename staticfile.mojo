from syspro_mojo import *
from syspro_mojo.io.bytes import Bytes
@value
struct Welcome(HTTPService):
    fn func(mut self, req: HTTPRequest) raises -> HTTPResponse:
        var uri = req.uri

        if uri.path == "/":
            var html: Bytes
            with open("static/lightbug_welcome.html", "rb") as f:
                html = Bytes(f.read_bytes())
            return OK(html, "text/html; charset=utf-8")

        if uri.path == "/logo":
            var image: Bytes
            with open("static/logo.png", "rb") as f:
                image = Bytes(f.read_bytes())
            return OK(image, "image/png")

        return NotFound(uri.path)
    
fn main() raises:
    var server = Server()
    var handler = Welcome()
    server.listen_and_serve("0.0.0.0:8080", handler)