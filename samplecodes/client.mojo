from memory import UnsafePointer, Span
from utils import StaticTuple
from sys.ffi import external_call, OpaquePointer
from syspro_http.myutils import Logger, logger, LogLevel, htons
from syspro_http.strings import String, to_string, NetworkType
from syspro_http.io.bytes import Bytes
from syspro_http.uri import URI
from syspro_http.http.request import HTTPRequest
from syspro_http.header import Headers, Header
from syspro_http.socket import Socket
from syspro_http.client import Client
from syspro_http.net import AnAddrInfo, getaddrinfo, freeaddrinfo, join_host_port, TCPAddr, TCPConnection, create_connection
from syspro_http.libc import (
    c_char,
    c_int,
    c_ushort,
    in_port_t,
    in_addr_t,
    sa_family_t,
    socklen_t,
    AF_INET,
    SOCK_STREAM,
    sockaddr_in,
    sockaddr,
    in_addr,
    gai_strerror,
)

from syspro_http import *

fn test_request(mut client: Client) raises -> None:
    var uri = URI.parse("google.com")
    var headers = Headers(Header("Host", "google.com"))
    var request = HTTPRequest(uri, headers)
    var response = client.do(request^)

    # print status code
    print("Response:", response.status_code)

    print(response.headers)

    print(
        "Is connection set to connection-close? ", response.connection_close()
    )

    # print body
    print(to_string(response.body_raw))


fn main() -> None:
    try:
        var client = Client()
        test_request(client)
    except e:
        print(e)
