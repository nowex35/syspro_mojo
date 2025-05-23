from syspro_http import *
from syspro_http.io.bytes import Bytes
    
fn main() raises:
    var server = Server()
    var handler = Welcome()
    server.listen_and_serve("0.0.0.0:8084", handler)