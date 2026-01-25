from memory import UnsafePointer, alloc
from builtin.coroutine import _coro_resume_fn
from smokio.smokio import Smokio, AsyncRead, AsyncWrite, RuntimeHandle, puts, set_nonblocking
from smokio.aliases import ExternalMutUnsafePointer, ExternalImmutUnsafePointer
from sys.ffi import c_int, get_errno
from smokio.c.address import AddressFamily
from smokio.c.aliases import c_void
from smokio.c.network import SocketAddress
from smokio.c.socket import (
    _socket,
    _bind,
    _listen,
    _accept,
    _close,
    _setsockopt,
    SocketType,
    SocketOption,
    SOL_SOCKET,
    sockaddr,
    socklen_t,
)


fn create_server(port: UInt16) raises -> c_int:
    var sockfd = _socket(AddressFamily.AF_INET.value, SocketType.SOCK_STREAM.value, 0)
    if sockfd < 0:
        raise Error("Failed to create socket")

    var optval: c_int = 1
    _ = _setsockopt(sockfd, SOL_SOCKET, SocketOption.SO_REUSEADDR.value, UnsafePointer(to=optval).bitcast[c_void](), 4)

    var address = SocketAddress(AddressFamily.AF_INET, port, 0)
    var result = _bind(sockfd, Pointer(to=address.as_sockaddr_in()), address.SIZE)
    if result < 0:
        _ = _close(sockfd)
        raise Error("Failed to bind")

    result = _listen(sockfd, 10)
    if result < 0:
        _ = _close(sockfd)
        raise Error("Failed to listen")

    return sockfd


async fn handle_client(rt: RuntimeHandle, client_fd: c_int, client_id: Int) -> Int:
    var buffer = alloc[UInt8](1024)
    var read_op = AsyncRead(rt, client_fd, rebind[ExternalMutUnsafePointer[UInt8]](buffer), 1024)
    var bytes_read = await read_op

    if bytes_read > 0:
        var write_op = AsyncWrite(rt, client_fd, rebind[ExternalImmutUnsafePointer[UInt8]](buffer.as_immutable()), bytes_read)
        _ = await write_op

    buffer.free()
    _ = _close(client_fd)
    return bytes_read


fn main():
    var server_fd: c_int
    try:
        server_fd = create_server(8080)
    except e:
        puts("Error: " + String(e))
        return

    var smokio = Smokio()
    var rt = smokio.runtime_handle()

    puts("Server listening on port 8080\n")

    var client_count = 0
    while client_count < 10:
        var client_sockaddr = sockaddr()
        var addr_len = socklen_t(16)
        var client_fd = _accept(server_fd, Pointer(to=client_sockaddr), Pointer(to=addr_len))

        if client_fd < 0:
            continue

        client_count += 1
        _ = set_nonblocking(client_fd)

        smokio.spawn(handle_client(rt, client_fd, client_count))
        _coro_resume_fn(smokio._tasks[len(smokio._tasks) - 1])

        var runtime_ptr = UnsafePointer(to=smokio._runtime)
        var iterations = 0
        while runtime_ptr[].num_waiting > 0 and iterations < 10:
            _ = runtime_ptr[].run_once()
            iterations += 1

    _ = _close(server_fd)
