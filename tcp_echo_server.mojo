from memory import UnsafePointer, alloc
from builtin.coroutine import _coro_resume_fn
from smokio.smokio import Smokio, AsyncRead, AsyncWrite, RuntimeHandle, puts, set_nonblocking
from smokio.aliases import ExternalMutUnsafePointer, ExternalImmutUnsafePointer
from sys.ffi import c_int, get_errno

# Use existing socket utilities
from smokio.c.address import AddressFamily
from smokio.c.aliases import c_void
from smokio.c.network import sockaddr_in, SocketAddress, htons
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


fn create_listening_socket(port: UInt16) raises -> c_int:
    """Create, bind, and start listening on a TCP socket."""
    # Create socket
    var sockfd = _socket(AddressFamily.AF_INET.value, SocketType.SOCK_STREAM.value, 0)
    if sockfd < 0:
        raise Error("Failed to create socket")

    puts("Created socket fd=" + String(sockfd))

    # Set SO_REUSEADDR
    var optval: c_int = 1
    var result = _setsockopt(
        sockfd,
        SOL_SOCKET,
        SocketOption.SO_REUSEADDR.value,
        UnsafePointer(to=optval).bitcast[c_void](),
        4
    )
    if result < 0:
        puts("Warning: setsockopt failed")
    else:
        puts("Set SO_REUSEADDR successfully")

    # Create address structure
    var address = SocketAddress(AddressFamily.AF_INET, port, 0)  # 0 = INADDR_ANY

    # Bind
    result = _bind(sockfd, Pointer(to=address.as_sockaddr_in()), address.SIZE)
    if result < 0:
        var errno = get_errno()
        _ = _close(sockfd)
        raise Error("Failed to bind socket, errno=" + String(errno))

    puts("Bound successfully to port " + String(port))

    # Listen
    result = _listen(sockfd, 10)
    if result < 0:
        _ = _close(sockfd)
        raise Error("Failed to listen on socket")

    puts("Listening for connections...")

    return sockfd


async fn handle_client(rt: RuntimeHandle, client_fd: c_int, client_id: Int) -> Int:
    """Handle a client connection - read data and echo it back."""
    puts("Client " + String(client_id) + " connected")

    var buffer = alloc[UInt8](1024)

    # Read from client
    var read_op = AsyncRead(rt, client_fd, rebind[ExternalMutUnsafePointer[UInt8]](buffer), 1024)
    var bytes_read = await read_op

    if bytes_read > 0:
        puts("Client " + String(client_id) + " sent " + String(bytes_read) + " bytes")

        # Echo back to client
        var write_op = AsyncWrite(rt, client_fd, rebind[ExternalImmutUnsafePointer[UInt8]](buffer.as_immutable()), bytes_read)
        var bytes_written = await write_op

        if bytes_written > 0:
            puts("Client " + String(client_id) + " echoed " + String(bytes_written) + " bytes")

    buffer.free()
    _ = _close(client_fd)
    puts("Client " + String(client_id) + " disconnected")

    return bytes_read


fn main():
    puts("=== TCP Echo Server Demo ===\n")

    var server_fd: c_int
    try:
        server_fd = create_listening_socket(8080)
    except e:
        puts("Error: " + String(e))
        return

    var smokio = Smokio()
    var rt = smokio.runtime_handle()

    # Accept one client connection for demo
    puts("\nWaiting for client connection...")
    puts("Test with: echo 'Hello' | nc localhost 8080\n")

    var client_sockaddr = sockaddr()
    var addr_len = socklen_t(16)
    var client_fd = _accept(server_fd, Pointer(to=client_sockaddr), Pointer(to=addr_len))

    if client_fd < 0:
        puts("Failed to accept connection")
        _ = _close(server_fd)
        return

    # Set client socket to non-blocking
    _ = set_nonblocking(client_fd)

    # Spawn async task to handle the client
    smokio.spawn(handle_client(rt, client_fd, 1))

    # Initial resume - runs until first await
    for i in range(len(smokio._tasks)):
        _coro_resume_fn(smokio._tasks[i])

    var runtime_ptr = UnsafePointer(to=smokio._runtime)

    # Event loop - wait for I/O and resume ready tasks
    var iterations = 0
    while runtime_ptr[].num_waiting > 0 and iterations < 10:
        puts("\n--- Event loop iteration " + String(iterations) + " ---")
        _ = runtime_ptr[].run_once()
        iterations += 1

    _ = _close(server_fd)
    puts("\nServer shutdown")
