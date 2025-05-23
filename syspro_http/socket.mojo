from memory import Span, stack_allocation
from utils import StaticTuple
from sys import sizeof, external_call
from sys.info import os_is_macos
from memory import Pointer, UnsafePointer
from syspro_http.net import Addr
from syspro_http.libc import (
    socket,
    connect,
    recv,
    recvfrom,
    send,
    sendto,
    shutdown,
    inet_pton,
    inet_ntop,
    htons,
    ntohs,
    gai_strerror,
    bind,
    listen,
    accept,
    setsockopt,
    getsockopt,
    getsockname,
    getpeername,
    close,
    sockaddr,
    sockaddr_in,
    addrinfo,
    socklen_t,
    c_void,
    c_uint,
    c_char,
    c_int,
    in_addr,
    SHUT_RDWR,
    SOL_SOCKET,
    AF_INET,
    AF_INET6,
    SOCK_STREAM,
    INET_ADDRSTRLEN,
    SO_REUSEADDR,
    SO_RCVTIMEO,
    CloseInvalidDescriptorError,
    ShutdownInvalidArgumentError,
)
from syspro_http.io.bytes import Bytes
from syspro_http.strings import NetworkType
from syspro_http.myutils import logger
from syspro_http.net import (
    Addr,
    default_buffer_size,
    binary_port_to_int,
    binary_ip_to_string,
    addrinfo_macos,
    addrinfo_unix,
)

alias SocketClosedError = "Socket: Socket is already closed"

struct Socket[AddrType: Addr, address_family: Int = AF_INET](Representable,Stringable, Writable):
    # ネットワークファイル記述子を表す
    
    # ソケットのファイル記述子
    var fd: Int32
    # ソケットタイプ
    var socket_type: Int32
    # The protocol
    var protocol: Byte
    # The local address of the socket
    var _local_address: AddrType
    # The remote address of the socket
    var _remote_address: AddrType
    # Whether the socket is closed
    var _closed: Bool
    # Whether the socket is connected
    var _connected: Bool

    fn __init__(
        out self,
        local_address: AddrType = AddrType(),
        remote_address: AddrType = AddrType(),
        socket_type: Int32 = SOCK_STREAM,
        protocol: Byte = 0,
    ) raises:
        # create a new socket object

        self.socket_type = socket_type
        self.protocol = protocol

        self.fd = socket(address_family, socket_type, 0)
        self._local_address = local_address
        self._remote_address = remote_address
        self._closed = False
        self._connected = False
    
    fn __init__(
        out self,
        fd: Int32,
        socket_type: Int32,
        protocol: Byte,
        local_address: AddrType,
        remote_address: AddrType = AddrType(),
    ):
        # create a new socket object from an existing file descriptor
        # Typically through socket.accept()

        self.fd = fd # ファイルディスクリプタ
        self.socket_type = socket_type
        self.protocol = protocol
        self._local_address = local_address
        self._remote_address = remote_address
        self._closed = False
        self._connected = True
    
    # ムーブコンストラクタ。既存オブジェクトの所有権を新しいオブジェクトに移動する
    # existing: 既存オブジェクト
    fn __moveinit__(out self, owned existing: Self):
        # Initialize a new socket object by moving the data from an existing socket object
        self.fd = existing.fd
        self.socket_type = existing.socket_type
        self.protocol = existing.protocol
        self._local_address = existing._local_address^
        self._remote_address = existing._remote_address^
        self._closed = existing._closed
        self._connected = existing._connected

    fn teardown(mut self) raises:
        # close the socket and free the file descriptor
        # ソケットはファイルとして扱われ、そこにデータを読み書きして管理されている
        if self._connected:
            try:
                self.shutdown()
            except e:
                logger.debug("Socket.teardown: Failed to shutdown socket: " + str(e))
        if not self._closed:
            try:
                self.close()
            except e:
                logger.error("Socket.teardown: Failed to close socket.")
                raise e
    
    # コンテキストマネージャ

    # ソケットを開くとき(__init__)に使う
    # ここではselfを所有権付きで返す
    fn __enter__(owned self) -> Self:
        return self^
    
    # ソケットを閉じるときに使う
    fn __exit__(mut self) raises:
        # リソースの解放
        self.teardown()

    # dunder string methods
    # print()でobjectを出力するときやstr()で文字列に変換するときに使われる
    # これを実装しないと、print(object)でobjectのアドレスが出力される
    fn __str__(self) -> String:
        return String.write(self)
    
    # dunder representation methods
    # print(repr(object))でobjectを出力するときに使われる
    # これは主にデバッグ用途(開発者向け)で使われる
    fn __repr__(self) -> String:
        return String.write(self)
    
    # ソケットオブジェクトを可視化するwiite to関数
    # //の前に宣言されたパラメータ(ここではW: Writer)は型推論される専用のinfer-only parameters
    fn write_to[W: Writer, //](self, mut writer: W):
        @parameter
        fn af() -> String:
            if address_family == AF_INET:
                return "AF_INET"
            else:
                return "AF_INET6"
        
        writer.write(
            "Socket[",
            AddrType._type,
            ", ",
            af(),
            "]",
            "(",
            "fd=",
            str(self.fd),
            ", _local_address=",
            repr(self._local_address),
            ", _remote_address=",
            repr(self._remote_address),
            ", _closed=",
            str(self._closed),
            ", _connected=",
            str(self._connected),
            ")",
        )

    fn local_address(ref self) -> ref [self._local_address] AddrType:
        # return the local address of the socket as a UDP address
        return self._local_address
    
    fn set_local_address(mut self, address: AddrType) -> None:
        # set the local address of the socket
        self._local_address = address
    
    fn remote_address(ref self) -> ref [self._remote_address] AddrType:
        # return the remote address of the socket as a UDP address
        return self._remote_address
    
    fn set_remote_address(mut self, address: AddrType) -> None:
        # set the remote address of the socket
        self._remote_address = address
    
    fn accept(self) raises -> Socket[AddrType]:
        # accept a connection. Return a new socket object and the address of the remote socket.
        var new_socket_fd: c_int
        try:
            new_socket_fd = accept(self.fd)
        except e:
                logger.error(e)
                raise Error("Socket.accept: Failed to accept connection, system `accept()` returned an error.")
        # acceptした後のクライアントとの通信を行うために作成するSocket
        var new_socket = Socket(
            fd=new_socket_fd,
            socket_type=self.socket_type,
            protocol=self.protocol,
            local_address=self.local_address()
        )
        var peer = new_socket.get_peer_name()
        new_socket.set_remote_address(AddrType(peer[0],peer[1]))
        return new_socket^
    
    fn listen(self, backlog: UInt = 0) raises:
        # enable a server to accept connections
        # Args: backlog: 待機中の接続要求の最大数、キュー(待ち行列)に入れる。
        try:
            listen(self.fd, backlog)
        except e:
            logger.error(e)
            raise Error("Socket.listen: Failed to listen for connections.")
    
    # ソケットにIPアドレスとポート番号を割り当てる
    # これは"assigning a name to a socket"(ソケットに名前を付ける)といわれる
    fn bind(mut self, address: String, port: UInt16) raises:
        var binary_ip: c_uint
        try:
            binary_ip = inet_pton[address_family](address.unsafe_ptr())
        except e:
            logger.error(e)
            raise Error("ListenConfig.listen: Failed to convert IP address to binary form.")
        
        var local_address = sockaddr_in(
            address_family=address_family,
            port=port,
            binary_ip=binary_ip,
        )
        try:
            bind(self.fd, local_address)
        except e:
            logger.error(e)
            raise Error("Socket.bind: Binding socket failed.")
        
        var local = self.get_sock_name()
        self._local_address = AddrType(local[0], local[1])
    
    fn get_sock_name(self) raises -> (String, UInt16):
        # return the address of socket
        if self._closed:
            raise SocketClosedError
        
        var local_address = stack_allocation[1, sockaddr]()
        try:
            getsockname(
                self.fd,
                local_address,
                Pointer.address_of(socklen_t(sizeof[sockaddr]())),
            )
        except e:
            logger.error(e)
            raise Error("get_sock_name: Failed to get address of local socket.")
        var addr_in = local_address.bitcast[sockaddr_in]().take_pointee()
        return binary_ip_to_string[address_family](addr_in.sin_addr.s_addr), UInt16(
            binary_port_to_int(addr_in.sin_port)
        )
    
    # 接続相手のIPアドレスとポート番号を取得
    fn get_peer_name(self) raises -> (String, UInt16):
        #　return the address of the peer connected to the socket.
        if self._closed:
            raise SocketClosedError
        
        var addr_in: sockaddr_in
        try:
            addr_in = getpeername(self.fd)
        except e:
            logger.error(e)
            raise Error("get_peer_name: Failed to get address of remote socket.")
        return binary_ip_to_string[address_family](addr_in.sin_addr.s_addr), UInt16(
            binary_port_to_int(addr_in.sin_port)
        )
    
    fn get_socket_option(self, option_name: Int) raises -> Int:
        # return the value of the given socket option.
        try:
            return getsockopt(self.fd, SOL_SOCKET, option_name)
        except e:
            logger.warn("Socket.get_socket_option: Failed to get socket option.")
            raise e
    
    fn set_socket_option(self, option_name: Int, owned option_value: Byte = 1)  raises:
        # return the value of the given socket option
        try:
            setsockopt(self.fd, SOL_SOCKET, option_name, option_value)
        except e:
            logger.warn("Socket.set_socket_option: Failed to set socket option.")
            raise e
    
    fn connect(mut self, address: String, port: UInt16) raises -> None:
        # connect to a remote socket at address.
        @parameter # コンパイル時に評価
        if os_is_macos():
            ip = addrinfo_macos().get_ip_address(address)
        else:
            ip = addrinfo_unix().get_ip_address(address)
        
        var addr = sockaddr_in(address_family=address_family, port=port, binary_ip=ip.s_addr)
        try:
            connect(self.fd, addr)
        except e:
            logger.error("Socket.connect: Failed to establish a connection to the server.")
            raise e
        
        var remote = self.get_peer_name()
        self._remote_address = AddrType(remote[0],remote[1])
    fn send(self, buffer: Span[Byte]) raises -> Int:
        if buffer[-1] == 0:
            raise Error("Socket.send: Buffer must not be null-terminated.")
        
        try:
            return send(self.fd, buffer.unsafe_ptr(), len(buffer),0)
        except e:
            logger.error("Socket.send: Failed to write data to connection.")
            raise e
    
    fn send_all(self, src: Span[Byte], max_attempts: Int = 3) raises -> None:
        # Send data to the socket. The socket must be connected to a remote socket.
        # args: src: The data to send, max_attempts: The maximum number of attempts to send the data.
        var total_bytes_sent = 0
        var attempts = 0
        while total_bytes_sent < len(src):
            if attempts > max_attempts:
                raise Error("Failed to send message after " + str(max_attempts) + " attempts.")
            var sent: Int
            try:
                sent = self.send(src[total_bytes_sent:])
            except e:
                logger.error(e)
                raise Error(
                    "Socket.send_all: Failed to send message, wrote" + str(total_bytes_sent) + "bytes before failing."
                )
            
            total_bytes_sent += sent
            attempts += 1
    
    fn send_to(mut self, src: Span[Byte], address: String, port: UInt16) raises -> UInt:
        # send data to the remote address by connecting to the remote socket before sending.
        # The socket must be not already be connected to a remote socket
        # return the number of bytes sent
        @parameter
        if os_is_macos():
            ip = addrinfo_macos().get_ip_address(address)
        else:
            ip = addrinfo_unix().get_ip_address(address)
        
        var addr = sockaddr_in(address_family=address_family, port=port, binary_ip=ip.s_addr)
        bytes_sent = sendto(self.fd, src.unsafe_ptr(), len(src), 0, UnsafePointer.address_of(addr).bitcast[sockaddr]())

        return bytes_sent
    
    fn _receive(self, mut buffer: Bytes) raises -> UInt:
        # receive data from socket into the buffer
        # return the buffer with the recieved data, and an error if one occurred.
        var bytes_received: Int
        try: 
            bytes_received = recv(
                self.fd,
                buffer.unsafe_ptr().offset(buffer.size),
                buffer.capacity - buffer.size,
                0,
            )
            buffer.size += bytes_received
        except e:
            logger.error(e)
            raise Error("Socket.receive: Failed to read data from connection.")
        
        if bytes_received == 0:
            raise Error("EOF")
        
        return bytes_received
    
    fn receive(self, size: Int = default_buffer_size) raises -> List[Byte, True]:
        # Receive data from the socket into the buffer with capacity of `size` bytes.
        var buffer = Bytes(capacity=size)
        _ = self._receive(buffer)
        return buffer
    fn receive(self, mut buffer: Bytes) raises -> UInt:
        # Receive data from the socket into the buffer.
        return self._receive(buffer)
    
    fn _receive_from(self, mut buffer: Bytes) raises -> (UInt, String, UInt16):
        var remote_address = stack_allocation[1, sockaddr]()
        var bytes_received: UInt
        try:
            bytes_received = recvfrom(
                self.fd, buffer.unsafe_ptr().offset(buffer.size), buffer.capacity - buffer.size, 0, remote_address
            )
            buffer.size += bytes_received
        except e:
            logger.error(e)
            raise Error("Socket._receive_from: Failed to read data from connection.")
        
        if bytes_received == 0:
            raise Error("EOF")
        
        var addr_in = remote_address.bitcast[sockaddr_in]().take_pointee()
        return (
            bytes_received,
            binary_ip_to_string[address_family](addr_in.sin_addr.s_addr),
            UInt16(binary_port_to_int(addr_in.sin_port)),
        )
    fn receive_from(mut self, size: Int = default_buffer_size) raises -> (List[Byte, True], String, UInt16):
        var buffer = Bytes(capacity=size)
        _, host, port = self._receive_from(buffer)
        return buffer, host, port
    
    fn receive_from(mut self, mut dest: List[Byte, True]) raises -> (UInt, String, UInt16):
        return self._receive_from(dest)
    
    fn shutdown(mut self) raises -> None:
        # shut down the socket. The remote end will receive no more data
        try:
            shutdown(self.fd, SHUT_RDWR)
        except e:
            if str(e) == ShutdownInvalidArgumentError:
                logger.error("Socket.shutdown: Failed to shutdown socket.")
                raise e
            logger.debug(e)
        self._connected = False
    
    fn close(mut self) raises -> None:
        # Mark the socket closed
        try:
            close(self.fd)
        except e:
            if str(e) != CloseInvalidDescriptorError:
                logger.error("Socket.close: Failed to close socket.")
                raise e
            logger.debug(e)
        self._closed = True
    
    fn get_timeout(self) raises -> Int:
        # return  the timeout value for the socket
        return self.get_socket_option(SO_RCVTIMEO)
    
    fn set_timeout(self, owned duration: Int) raises:
        # set time out value for the socket
        self.set_socket_option(SO_RCVTIMEO, duration)