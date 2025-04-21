from utils import StaticTuple
from time import sleep, perf_counter_ns
from memory import UnsafePointer, stack_allocation, Span
from sys.info import sizeof, os_is_macos
from sys.ffi import external_call, OpaquePointer
from syspro_mojo.libc import in_addr
from syspro_mojo.myutils import Logger, logger, LogLevel
from syspro_mojo.strings import NetworkType
from syspro_mojo.io.bytes import Bytes, Byte
from syspro_mojo.io.sync import Duration
from syspro_mojo.socket import Socket
from syspro_mojo.libc import (
    c_void,
    c_int,
    c_uint,
    c_char,
    c_ssize_t,
    in_addr,
    sockaddr,
    sockaddr_in,
    socklen_t,
    AI_PASSIVE,
    AF_INET,
    AF_INET6,
    SOCK_STREAM,
    SOCK_DGRAM,
    SOL_SOCKET,
    SO_REUSEADDR,
    SO_REUSEPORT,
    SHUT_RDWR,
    htons,
    ntohs,
    ntohl,
    inet_pton,
    inet_ntop,
    socket,
    connect,
    setsockopt,
    listen,
    accept,
    send,
    recv,
    bind,
    shutdown,
    close,
    getsockname,
    getpeername,
    gai_strerror,
    INET_ADDRSTRLEN,
    INET6_ADDRSTRLEN,
)
from syspro_mojo.myutils import logger
from syspro_mojo.socket import Socket

alias default_buffer_size = 4096
trait AnAddrInfo:
    fn get_ip_address(self, host: String) raises -> in_addr:
        ...


# getaddrinfo関数で取得したアドレス情報のメモリを解放する
fn freeaddrinfo[T: AnAddrInfo, //](ptr: UnsafePointer[T]):
    """Free the memory allocated by `getaddrinfo`."""
    external_call["freeaddrinfo", NoneType, UnsafePointer[T]](ptr)

# Cのgetaddrinfo関数を呼び出す
# MutableOriginはvalue ownership関連だが、よくわからない
fn _getaddrinfo[T:AnAddrInfo, hints_origin: MutableOrigin, result_origin: MutableOrigin, //
](
    nodename: UnsafePointer[c_char],
    servname: UnsafePointer[c_char],
    hints: Pointer[T, hints_origin],
    res: Pointer[UnsafePointer[T], result_origin], # 結果を格納するポインタ
) -> c_int:
    return external_call[ # C言語による外部関数を呼び出す
        "getaddrinfo", # 呼び出すC言語の関数名
        c_int, # FnName, RetType
        UnsafePointer[c_char], # node名(ホスト名)の型
        UnsafePointer[c_char], # service名(ポート番号)の型
        Pointer[T,hints_origin], # addrinfoへのヒントのポインタ
        Pointer[UnsafePointer[T], result_origin], # 結果を格納するaddrinfo構造体へのポインタ
    ](nodename, servname, hints, res)

#文字列のホスト名をIPアドレスとポート番号の組に変換する
#resには変換結果の構造体のポインタが格納される
fn getaddrinfo[T: AnAddrInfo](node: String, service: String, mut hints: T, mut res:UnsafePointer[T],) raises:
    # unsafe_ptr()は先頭のポインタを取得するメソッド
    var result = _getaddrinfo(node.unsafe_ptr(), service.unsafe_ptr(), Pointer.address_of(hints),Pointer.address_of(res))
    if result !=0: # エラーが発生した場合の処理.C言語では成功すれば0が返る
        var err = gai_strerror(result)
        # msgにappendしていくことでエラーメッセージを作成
        var msg = List[Byte, True]()
        var i = 0
        while err[i] != 0:
            msg.append(err[i])
            i += 1
        msg.append(0)
        raise Error("getaddrinfo: " + String(msg^))

@value
@register_passable("trivial")
struct addrinfo_macos(AnAddrInfo):
    """
    For MacOS, I had to swap the order of ai_canonname and ai_addr.
    https://stackoverflow.com/questions/53575101/calling-getaddrinfo-directly-from-python-ai-addr-is-null-pointer.
    """

    var ai_flags: c_int
    var ai_family: c_int
    var ai_socktype: c_int
    var ai_protocol: c_int
    var ai_addrlen: socklen_t
    var ai_canonname: UnsafePointer[c_char]
    var ai_addr: UnsafePointer[sockaddr]
    var ai_next: OpaquePointer

    fn __init__(
        out self,
        ai_flags: c_int = 0,
        ai_family: c_int = 0,
        ai_socktype: c_int = 0,
        ai_protocol: c_int = 0,
        ai_addrlen: socklen_t = 0,
    ):
        self.ai_flags = ai_flags
        self.ai_family = ai_family
        self.ai_socktype = ai_socktype
        self.ai_protocol = ai_protocol
        self.ai_addrlen = ai_addrlen
        self.ai_canonname = UnsafePointer[c_char]()
        self.ai_addr = UnsafePointer[sockaddr]()
        self.ai_next = OpaquePointer()

    fn get_ip_address(self, host: String) raises -> in_addr:
        """Returns an IP address based on the host.
        This is a MacOS-specific implementation.

        Args:
            host: String - The host to get the IP from.

        Returns:
            The IP address.
        """
        var result = UnsafePointer[Self]()
        var hints = Self(ai_flags=0, ai_family=AF_INET, ai_socktype=SOCK_STREAM, ai_protocol=0)
        try:
            getaddrinfo(host, String(), hints, result)
        except e:
            logger.error("Failed to get IP address.")
            raise e

        if not result[].ai_addr:
            freeaddrinfo(result)
            raise Error("Failed to get IP address because the response's `ai_addr` was null.")

        var ip = result[].ai_addr.bitcast[sockaddr_in]()[].sin_addr
        freeaddrinfo(result)
        return ip

@value
@register_passable("trivial")
struct addrinfo_unix(AnAddrInfo):
    """
    Unix向けの標準的なアドレス情報の構造体。
    既存のlibcの`getaddrinfo`関数を上書きして、AnAddrInfoトレイトに準拠するようにする。

    c_int -> c言語のint型に対応する型
    c_char -> c言語のchar型に対応する型
    socklen_t -> ソケットアドレスのバイト長を表す型
    sockaddr -> ソケットアドレスを表す構造体
    OpaquePointer -> 不透明なポインタ型
    """

    var ai_flags: c_int 
    var ai_family: c_int
    var ai_socktype: c_int
    var ai_protocol: c_int
    var ai_addrlen: socklen_t
    var ai_addr: UnsafePointer[sockaddr]
    var ai_canonname: UnsafePointer[c_char]
    var ai_next: OpaquePointer

    fn __init__(
        out self,
        ai_flags: c_int = 0,
        ai_family: c_int = 0,
        ai_socktype: c_int = 0,
        ai_protocol: c_int = 0,
        ai_addrlen: socklen_t = 0,
    ):
        self.ai_flags = ai_flags # アドレスをどのように取得して扱うべきかを細かく指定するためのフラグ。追加で調べる
        self.ai_family = ai_family # アドレスファミリでIPv4[AF_INET]かIPv6[SF_INET6]か
        self.ai_socktype = ai_socktype # 使用するソケットの種類でストリーム型:TCP[SOCK_STREAM]かデータグラム型:UDP[SOCK_DGRAM]か
        self.ai_protocol = ai_protocol # 使用するプロトコルでTCP[IPPROTO_TCP]かUDP[IPPROTO_UDP]か。TCPとUDPなら0のとき自動で適したものが選択される
        self.ai_addrlen = ai_addrlen #アドレス情報(ソケットアドレス)のバイト長
        self.ai_addr = UnsafePointer[sockaddr]() # 解析されたソケットアドレスの実データへのポインタ 
        self.ai_canonname = UnsafePointer[c_char]() # 正式な(canonical)ホスト名へのポインタ
        self.ai_next = OpaquePointer() # 次のaddrinfo構造体へのポインタ


    fn get_ip_address(self, host: String) raises -> in_addr:
        """
        ホストに基づいたIPアドレスを返す。
        ここはUnix固有の実装。

        Args:
            host: IPアドレスを取得したいホスト名.

        Returns:
            IPアドレス。
        """
        var result = UnsafePointer[Self]()
        var hints = Self(ai_flags=0, ai_family=AF_INET, ai_socktype=SOCK_STREAM, ai_protocol=0) #IPv4,TCPで新たなaddrinfoインスタンスを作成
        try:
            # getaddrinfo関数を呼び出して第四引数でresとされているresultに結果を格納
            getaddrinfo(host, String(), hints, result)
        except e:
            logger.error("Failed to get IP address.")
            raise e

        if not result[].ai_addr: # ai_addrがnullの場合,reslutを解放してエラーを発生させる
            freeaddrinfo(result)
            raise Error("Failed to get IP address because the response's `ai_addr` was null.")

        # bitcastはある型のビット列を型変換ではなく、ビットの並びそのままで別の型のビット列として解釈する。『再解釈』
        # sockaddr_inはIPv4のアドレス情報を格納する構造体で、sin_addrはsockaddr_inの構造体の中のin_addr型の変数
        var ip = result[].ai_addr.bitcast[sockaddr_in]()[].sin_addr
        freeaddrinfo(result) # 忘れずにメモリを解放
        return ip

fn join_host_port(host: String, port: String) -> String: # ホスト名とポート番号を結合する. 
    #IPv6の対応の余地あり
    #たとえばpythonのipaddressモジュールのような実装や、正規表現によるIPv6リテラルの検出が必要
    #IPv6の省略(2001:db8::1),リンクローカルアドレス(fe80::1),IPv6リテラル([2001:db8::1])などに対応する必要がある
    #IPv4の場合はホスト名とポート番号をコロンで結合するだけ
    if host.find(":") != -1: # must be IPv6 literal
        return "[" + host + "]:" + port
    return host + ":" + port

trait Addr(Stringable,Representable,Writable, EqualityComparableCollectionElement):
    alias _type: StringLiteral

    fn __init__(out self):
        ...

    fn __init__(out self, ip: String, port: UInt16):
        ...
    
    fn network(self) -> String:
        ...

@value
struct TCPAddr(Addr):
    alias _type = "TCPAddr"
    var ip: String
    var port: UInt16
    var zone: String # IPv6の場合のみ使用

    fn __init__(out self):
        self.ip = "127.0.0.1"
        self.port = 8000
        self.zone = ""

    fn __init__(out self, ip: String = "127.0.0.1", port: UInt16 = 8000):
        self.ip = ip
        self.port = port
        self.zone = ""
    
    fn network(self) -> String:
        return NetworkType.tcp.value
    
    fn __eq__(self, other: Self) -> Bool:
        return self.ip == other.ip and self.port == other.port and self.zone == other.zone
    
    fn __ne__(self, other: Self) -> Bool:
        return not self == other
    
    fn __str__(self) -> String:
        if self.zone != "":
            return join_host_port(self.ip + "%" + self.zone, str(self.port))
        return join_host_port(self.ip, str(self.port))
    
    fn __repr__(self) -> String:
        return String.write(self)
    
    fn write_to[W: Writer, //](self, mut writer: W):
        writer.write("TCPAddr(", "ip=", repr(self.ip), ", port=", repr(self.port), ", zone=", repr(self.zone), ")")

struct TCPConnection:
    var socket: Socket[TCPAddr]

    fn __init__(out self, owned socket: Socket[TCPAddr]):
        self.socket = socket^
    
    fn __moveinit__(out self, owned existing: Self):
        self.socket = existing.socket^
    
    fn read(self, mut buf: Bytes) raises -> Int:
        try:
            return self.socket.receive(buf)
        except e:
            if str(e) == "EOF":
                raise e
            else:
                logger.error(e)
                raise Error("TCPConnection.read: Failed to read data from connection.")
    fn write(self, buf: Span[Byte]) raises -> Int:
        if buf[-1] == 0:
            raise Error("TCPConnection.write: Buffer must not be null-terminated.")
        try:
            return self.socket.send(buf)
        except e:
            logger.error("TCPConnection.write: Failed to write data to connection.")
            raise e
    
    fn close(mut self) raises:
        self.socket.close()
    
    fn shutdown(mut self) raises:
        self.socket.shutdown()
    
    fn teardown(mut self) raises:
        self.socket.teardown()

    fn is_closed(self) -> Bool:
        return self.socket._closed

    # TODO: Switch to property or return ref when trait supports attributes.
    # traitが属性をサポートするときには、propertyまたはrefに切り替える
    fn local_addr(self) -> TCPAddr:
        return self.socket.local_address()
    fn remote_addr(self) -> TCPAddr:
        return self.socket.remote_address()


fn create_connection(host: String, port: UInt16) raises -> TCPConnection:
    var socket = Socket[TCPAddr]()
    try:
        socket.connect(host,port)
    except e:
        logger.error(e)
        try:
            socket.shutdown()
        except e:
            logger.error("Failed to shutdown socket: " + str(e))
        raise Error("Failed to establish a connection to the server.")
    return TCPConnection(socket^)

fn binary_port_to_int(port: UInt16) -> Int:
    """Convert a binary port to an integer.

    Args:
        port: The binary port.

    Returns:
        The port as an integer.
    """
    return int(ntohs(port))

fn binary_ip_to_string[address_family: Int32](owned ip_address: UInt32) raises -> String:
    """Convert a binary IP address to a string by calling `inet_ntop`.

    Parameters:
        address_family: The address family of the IP address.

    Args:
        ip_address: The binary IP address.

    Returns:
        The IP address as a string.
    """
    constrained[int(address_family) in [AF_INET, AF_INET6], "Address family must be either AF_INET or AF_INET6."]()
    var ip: String

    @parameter
    if address_family == AF_INET:
        ip = inet_ntop[address_family, INET_ADDRSTRLEN](ip_address)
    else:
        ip = inet_ntop[address_family, INET6_ADDRSTRLEN](ip_address)

    return ip