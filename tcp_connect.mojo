from memory import UnsafePointer, Span
from utils import StaticTuple
from sys.ffi import external_call, OpaquePointer
from syspro_mojo.myutils import Logger, logger, LogLevel, htons
from syspro_mojo.strings import String, to_string, NetworkType
from syspro_mojo.io.bytes import Bytes
from syspro_mojo.uri import URI
from syspro_mojo.http.request import HTTPRequest
from syspro_mojo.header import Headers, Header
from syspro_mojo.socket import Socket
from syspro_mojo.client import Client
from syspro_mojo.net import AnAddrInfo, getaddrinfo, freeaddrinfo, join_host_port, TCPAddr, TCPConnection, create_connection
from syspro_mojo.libc import (
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

"====================================================================================================="

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


"""
Clientコース
getaddrinfo->
get_ip_address->
struct Socket->
connect->
create_connection->
struct Client->
struct HTTPRequest->
struct URI->
struct Headers->
fn to_string from strings.mojo
lightbug_http/client.mojo->
tcp_connect.mojo             #HTTPクライアントを作成してリクエストを送信


-
Serverコース

net.listen
server.set_address
server.serve
↓
server.listen_and_serve
"""