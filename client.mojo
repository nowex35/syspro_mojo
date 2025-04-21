from collections import Dict
from memory import UnsafePointer
from syspro_mojo.libc import (
    c_int,
    AF_INET,
    SOCK_STREAM,
    socket,
    connect,
    send,
    recv,
    close,
)

from syspro_mojo.strings import to_string
from syspro_mojo.net import default_buffer_size
from syspro_mojo.http import HTTPRequest, HTTPResponse, encode
from syspro_mojo.header import Headers, HeaderKey
from syspro_mojo.net import create_connection, TCPConnection
from syspro_mojo.io.bytes import Bytes
from syspro_mojo.myutils import ByteReader, logger
from syspro_mojo.pool_manager import PoolManager

struct Client:
    var host: String
    var prot: Int
    var name: String
    var allow_redirects: Bool

    var _connections: PoolManager[TCPConnection]

    fn __init__(
        out self,
        host: String = "127.0.0.1",
        port: Int = 8888,
        cached_connections: Int = 10,
        allow_redirects: Bool = False,
    ):
        self.host = host
        self.prot = port
        self.name = "lightbug_http_client"
        self.allow_redirects = allow_redirects
        self._connections = PoolManager[TCPConnection](cached_connections)

    fn do(mut self, owned req: HTTPRequest) raises -> HTTPResponse:
        """The `do` method is responsible for sending an HTTP request to a server and receiving the response.

        1. リクエストで指定されたサーバーへの接続を確立する
        2. 接続を使って、リクエストボディをサーバーに送信する
        3. サーバーからのレスポンスを受け取る
        4. 接続を閉じる
        5. HTTPResponseオブジェクトを返す

        Args:
            req: An `HTTPRequest` object representing the request to be sent.
        Returns:
            The received response.
        
        """
        if req.uri.host == "":
            raise Error("Client.do: Request failed because the host field is empty.")
        var is_tls = False

        if req.uri.is_https():
            is_tls = True

        var host_str: String
        var port: Int
        if ":" in req.uri.host:
            var host_port: List[String]
            try:
                host_port = req.uri.host.split(":")
            except:
                raise Error("Client.do: Failed to split host and port.")
        else:
            host_str = req.uri.host
            if is_tls:
                port = 443
            else:
                port = 80
        
        var cached_connection = False
        var conn: TCPConnection
        try:
            conn = self._connections.get()
            cached_connection = True
        except e:
            if str(e) == "PoolManager.take: key not found.":
                conn = create_connection(host_str, port)
            else:
                logger.error(e)
                raise Error("Client.do: Failed to create a connection to host.")
        # 接続での書き込み
        var bytes_sent: Int
        try:
            bytes_sent = conn.write(encode(req))
        except e:
            if str(e) == "SendError: Connection reset by peer.":
                logger.debug("Client.do: Connection reset by peer. Trying a fresh connection.")
                conn.teardown()
                if cached_connection:
                    return self.do(req^)
            logger.error("Client.do: Failed to send message.")
            raise e
        
        # 接続での読み込み
        var new_buf = Bytes(capacity=default_buffer_size)
        try:
            _ = conn.read(new_buf)
        except e:
            if str(e) == "EOF":
                conn.teardown()
                if cached_connection:
                    return self.do(req^)
                raise Error("Client.do: No response received from the server.")
            else:
                logger.error(e)
                raise Error("Client.do: Failed to read response from peer.")

        var res: HTTPResponse
        try:
            res = HTTPResponse.from_bytes(new_buf, conn)
        except e:
            logger.error("Failed to parse a response...")
            try:
                conn.teardown()
            except:
                logger.error("Failed to teardown connection...")
            raise e
        
        if self.allow_redirects and res.is_redirect():
            conn.teardown()
            return self._handle_redirect(req^, res^)
        # Server told the client to close the connection, we can assume the server closed their side after sending the response.
        elif res.connection_close():
            conn.teardown()
        # Otherwise, persist the connection by giving it back to the pool manager.
        else:
            self._connections.give(host_str, conn^)
        return res

    fn _handle_redirect(mut self, owned original_req: HTTPRequest, owned original_response: HTTPResponse) raises -> HTTPResponse:
        var new_uri: URI
        var new_location: String
        try:
            new_location = original_response.headers[HeaderKey.LOCATION]
        except e:
            raise Error("Client._handle_redirect: `Location` header was not received in the response.")

        if new_location and new_location.startswith("http"):
            new_uri = URI.parse(new_location)
            original_req.headers[HeaderKey.HOST] = new_uri.host
        else:
            new_uri = original_req.uri
            new_uri.path = new_location
        original_req.uri = new_uri
        return self.do(original_req^)