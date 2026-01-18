"""Demo of the new Smokio async runtime architecture.

This demo shows basic usage of the new Variant-based, completion-oriented
async I/O runtime with kqueue backend.
"""

from sys.ffi import external_call, c_int
from memory import UnsafePointer, alloc
from smokio.smokio import Smokio
from smokio.aio.platform.kqueue import KqueueBackend
from smokio.io.read import AsyncRead
from smokio.io.write import AsyncWrite

# Utility functions

fn puts(var s: String):
    """Print a string using C puts."""
    print(s)


fn create_pipe() -> Tuple[Int32, Int32]:
    """Create a pipe and return (read_fd, write_fd)."""
    var fds = alloc[c_int](2)
    _ = external_call["pipe", c_int](fds)
    var read_fd = fds[0]
    var write_fd = fds[1]
    fds.free()
    return (read_fd, write_fd)


fn set_nonblocking(fd: c_int) -> Bool:
    """Set a file descriptor to non-blocking mode."""
    comptime FIONBIO = 0x8004667e
    var nonblock = alloc[c_int](1)
    nonblock[] = 1
    var result = external_call["ioctl", Int, c_int, Int, UnsafePointer[c_int]](
        fd, FIONBIO, nonblock
    )
    nonblock.free()
    return result != -1


fn write_to_fd(fd: c_int, var msg: String):
    """Write a string to a file descriptor."""
    var ptr = msg.unsafe_ptr()
    _ = external_call["write", Int](fd, ptr, len(msg))


fn close_fd(fd: c_int):
    """Close a file descriptor."""
    _ = external_call["close", c_int, c_int](fd)


# Main demo

fn main() raises:
    puts("=== Smokio New Architecture Demo ===\n")

    # Create pipes for testing
    var pipe1 = create_pipe()
    var pipe2 = create_pipe()

    var read_fd1 = pipe1[0]
    var write_fd1 = pipe1[1]
    var read_fd2 = pipe2[0]
    var write_fd2 = pipe2[1]

    # Set read ends to non-blocking
    _ = set_nonblocking(read_fd1)
    _ = set_nonblocking(read_fd2)

    # Create Smokio runtime with kqueue backend
    puts("Creating Smokio runtime with KqueueBackend...\n")
    var backend = KqueueBackend(max_events=64)
    var smokio = Smokio(backend^, max_tasks=100)

    # Get runtime handle for async operations
    var handle = smokio.runtime_handle()

    # Define async tasks
    async fn read_task_1():
        puts("[Task 1] Starting async read from pipe 1...")
        var read_op = AsyncRead(read_fd1, 1024, handle)
        var data = await read_op

        var msg = String("bytes from pipe 1")
        puts("[Task 1] Read " + String(len(data)) + " " + msg)

        # Print the data
        if len(data) > 0:
            var result = String()
            for i in range(len(data)):
                result += chr(int(data[i]))
            puts("[Task 1] Data: " + result)

    async fn read_task_2():
        puts("[Task 2] Starting async read from pipe 2...")
        var read_op = AsyncRead(read_fd2, 1024, handle)
        var data = await read_op

        var msg = String("bytes from pipe 2")
        puts("[Task 2] Read " + String(len(data)) + " " + msg)

        # Print the data
        if len(data) > 0:
            var result = String()
            for i in range(len(data)):
                result += chr(int(data[i]))
            puts("[Task 2] Data: " + result)

    # Spawn tasks
    puts("Spawning async tasks...\n")
    var task1_id = smokio.spawn(read_task_1())
    var task2_id = smokio.spawn(read_task_2())
    puts("Spawned task 1 with ID: " + String(task1_id))
    puts("Spawned task 2 with ID: " + String(task2_id))

    # Write data to pipes (this will wake up the tasks)
    puts("\nWriting data to pipes...")
    write_to_fd(write_fd1, "Hello from pipe 1!")
    write_to_fd(write_fd2, "Hello from pipe 2!")
    puts("Data written.\n")

    # Run the event loop
    puts("Running event loop...\n")
    smokio.run()

    puts("\nEvent loop completed!")

    # Cleanup
    puts("Cleaning up...")
    close_fd(read_fd1)
    close_fd(write_fd1)
    close_fd(read_fd2)
    close_fd(write_fd2)

    puts("\n=== Demo Complete ===")
