from memory import UnsafePointer
from builtin.coroutine import _coro_resume_fn
from smokio.smokio import Smokio, Pipe, read_pipe, puts

fn main():
    var pipe1 = Pipe()
    var pipe2 = Pipe()

    var smokio = Smokio()
    var rt = smokio.runtime_handle()

    # Spawn two async tasks
    smokio.spawn(read_pipe(rt, 1, pipe1.read_fd))
    smokio.spawn(read_pipe(rt, 2, pipe2.read_fd))

    # Initial resume - each runs until first await
    for i in range(len(smokio._tasks)):
        _coro_resume_fn(smokio._tasks[i])

    var runtime_ptr = UnsafePointer(to=smokio._runtime)

    puts("\nSending data to pipes...\n")
    pipe1.send("Hello A")
    pipe2.send("World B")

    # Event loop - wait for I/O and resume ready tasks
    var iterations = 0
    while runtime_ptr[].num_waiting > 0 and iterations < 10:
        _ = runtime_ptr[].run_once()
        iterations += 1

    pipe1.close()
    pipe2.close()