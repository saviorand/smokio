from memory import UnsafePointer, alloc
# Undocumented coroutine primitives from Mojo stdlib:
# - AnyCoroutine: MLIR type (!co.routine) representing raw coroutine handle
# - _coro_resume_fn: Resume a suspended coroutine from where it left off
# - _suspend_async: Suspend current coroutine and call callback with its handle
from builtin.coroutine import AnyCoroutine, _coro_resume_fn, _suspend_async
from sys.ffi import external_call


# ===-----------------------------------------------------------------------===#
# Utilities
# ===-----------------------------------------------------------------------===#

fn puts(var s: String):
    var cstr = s.as_c_string_slice()
    _ = external_call["puts", Int32](cstr.unsafe_ptr())


fn set_nonblocking(fd: Int32) -> Bool:
    comptime FIONBIO = 0x8004667e
    var nonblock = alloc[Int32](1)
    nonblock[] = 1
    var result = external_call["ioctl", Int, Int32, Int, UnsafePointer[Int32, MutOrigin.external]](fd, FIONBIO, nonblock)
    nonblock.free()
    return result != -1


fn try_read(fd: Int32, buffer: UnsafePointer[mut=True, UInt8, MutOrigin.external], size: Int) -> Int:
    return external_call["read", Int, Int32, UnsafePointer[mut=True, UInt8, MutOrigin.external], UInt](fd, buffer, UInt(size))


@fieldwise_init
struct Pipe(Movable, Copyable):
    var read_fd: Int32
    var write_fd: Int32

    fn __init__(out self):
        var fds = alloc[Int32](2)
        _ = external_call["pipe", Int32, UnsafePointer[mut=True, Int32, MutOrigin.external]](fds)
        self.read_fd = fds[0]
        self.write_fd = fds[1]
        fds.free()
        _ = set_nonblocking(self.read_fd)

    fn send(self, msg: String):
        var ptr = UnsafePointer[mut=True, UInt8, MutOrigin.external](unsafe_from_address=Int(msg.unsafe_ptr()))
        _ = external_call["write", Int, Int32, UnsafePointer[mut=True, UInt8, MutOrigin.external], Int](self.write_fd, ptr, len(msg))

    fn close(self):
        var close_fn = external_call["close", Int32, Int32]
        _ = close_fn(self.read_fd)
        _ = close_fn(self.write_fd)


# ===-----------------------------------------------------------------------===#
# Runtime and kqueue
# ===-----------------------------------------------------------------------===#

comptime EVFILT_READ = -1
comptime EV_ADD = 0x0001
comptime EV_ENABLE = 0x0004

@register_passable("trivial")
struct Kevent:
    var ident: UInt64
    var filter: Int16
    var flags: UInt16
    var fflags: UInt32
    var data: Int64
    var udata: UInt64

    fn __init__(out self):
        self.ident = 0
        self.filter = 0
        self.flags = 0
        self.fflags = 0
        self.data = 0
        self.udata = 0


fn kqueue() -> Int32:
    return external_call["kqueue", Int32]()


fn kevent(
    kq: Int32,
    changelist: UnsafePointer[mut=True, Kevent, MutOrigin.external],
    nchanges: Int32,
    eventlist: UnsafePointer[mut=True, Kevent, MutOrigin.external],
    nevents: Int32,
    timeout: UInt64
) -> Int32:
    return external_call["kevent", Int32, Int32, UnsafePointer[mut=True, Kevent, MutOrigin.external], Int32, UnsafePointer[mut=True, Kevent, MutOrigin.external], Int32, UInt64](kq, changelist, nchanges, eventlist, nevents, timeout)


@register_passable("trivial")
struct AsyncTask:
    """Pairs a suspended coroutine handle with the fd it's waiting on."""
    var coro_handle: AnyCoroutine  # Raw handle to suspended coroutine
    var fd: Int32                  # File descriptor this task is waiting to read

    fn __init__(out self, handle: AnyCoroutine, fd: Int32):
        self.coro_handle = handle
        self.fd = fd


struct AsyncRuntime:
    var kq: Int32
    var waiting_tasks: UnsafePointer[mut=True, AsyncTask, MutOrigin.external]
    var num_waiting: Int
    var max_tasks: Int

    fn __init__(out self, max_tasks: Int = 16):
        self.kq = kqueue()
        self.waiting_tasks = alloc[AsyncTask](max_tasks)
        self.num_waiting = 0
        self.max_tasks = max_tasks

    fn register_read(mut self, handle: AnyCoroutine, fd: Int32) -> Int:
        """Register a suspended coroutine to be resumed when fd is readable."""
        if self.num_waiting >= self.max_tasks:
            return -1

        # Add fd to kqueue with EVFILT_READ
        var ev_ptr = alloc[Kevent](1)
        ev_ptr[0].ident = fd.cast[DType.uint64]()
        ev_ptr[0].filter = EVFILT_READ
        ev_ptr[0].flags = EV_ADD | EV_ENABLE

        var null_ptr = alloc[Kevent](0)
        _ = kevent(self.kq, ev_ptr, 1, null_ptr, 0, 0)
        ev_ptr.free()
        null_ptr.free()

        # Store handle + fd pair for later resumption
        self.waiting_tasks[self.num_waiting] = AsyncTask(handle, fd)
        self.num_waiting += 1
        return self.num_waiting - 1

    fn run_once(mut self) -> Int:
        """Wait for I/O events and resume ready coroutines."""
        if self.num_waiting == 0:
            return 0

        var events = alloc[Kevent](self.max_tasks)
        var null_ptr = alloc[Kevent](0)

        # Block until at least one fd is ready
        var nev = kevent(self.kq, null_ptr, 0, events, Int32(self.max_tasks), 0)
        null_ptr.free()

        if nev <= 0:
            events.free()
            return 0

        var resumed = 0

        # For each ready fd, find and resume the waiting coroutine
        for i in range(Int(nev)):
            var ready_fd = events[i].ident.cast[DType.int32]()

            var j = 0
            while j < self.num_waiting:
                if self.waiting_tasks[j].fd == ready_fd:
                    puts("  [Runtime] fd " + String(ready_fd) + " is ready! Resuming task...")
                    # Resume coroutine - continues execution after _suspend_async
                    _coro_resume_fn(self.waiting_tasks[j].coro_handle)

                    # Remove from waiting list (shift remaining tasks down)
                    for k in range(j, self.num_waiting - 1):
                        self.waiting_tasks[k] = self.waiting_tasks[k + 1]
                    self.num_waiting -= 1
                    resumed += 1
                    break
                j += 1

        events.free()
        return resumed

    fn __del__(deinit self):
        if self.kq != -1:
            _ = external_call["close", Int32, Int32](self.kq)
        if self.waiting_tasks:
            self.waiting_tasks.free()


@register_passable("trivial")
struct RuntimeHandle:
    var _ptr: UnsafePointer[mut=True, AsyncRuntime, MutOrigin.external]

    fn __init__(out self, ptr: UnsafePointer[mut=True, AsyncRuntime, MutOrigin.external]):
        self._ptr = ptr


struct AsyncRead:
    """Awaitable read that suspends until fd is readable."""
    var runtime: RuntimeHandle
    var fd: Int32
    var buffer: UnsafePointer[mut=True, UInt8, MutOrigin.external]
    var size: Int

    fn __init__(out self, runtime: RuntimeHandle, fd: Int32, buffer: UnsafePointer[mut=True, UInt8, MutOrigin.external], size: Int):
        self.runtime = runtime
        self.fd = fd
        self.buffer = buffer
        self.size = size

    @always_inline
    fn __await__(mut self) -> Int:
        _ = set_nonblocking(self.fd)

        # Try immediate read first
        var bytes = try_read(self.fd, self.buffer, self.size)
        if bytes >= 0:
            return bytes

        # Check if we got EAGAIN (would block)
        var errno = external_call["__error", UnsafePointer[Int32, MutOrigin.external]]()
        comptime EAGAIN = 35
        if errno[] != EAGAIN:
            return -1

        puts("  [AsyncRead] fd " + String(self.fd) + " not ready, suspending...")

        # Suspend and register with kqueue
        @always_inline
        @parameter
        fn suspend_callback(cur_hdl: AnyCoroutine):
            # This callback receives our suspended coroutine handle
            _ = self.runtime._ptr[].register_read(cur_hdl, self.fd)

        # Suspend execution here - returns when runtime calls _coro_resume_fn
        _suspend_async[suspend_callback]()

        # Execution resumes here when fd is ready
        puts("  [AsyncRead] fd " + String(self.fd) + " resumed, reading...")
        bytes = try_read(self.fd, self.buffer, self.size)
        return bytes


@register_passable("trivial")
struct _AsyncContext:
    """Custom 16-byte context to override stdlib's async runtime behavior.

    Mojo's Coroutine has a 16-byte context slot accessed via _get_ctx.
    We use this to opt out of stdlib's completion callback mechanism.
    """
    comptime callback_fn_type = fn () -> None
    var callback: Self.callback_fn_type  # 8 bytes
    var _padding: Int                    # 8 bytes (total = 16 bytes required)

    fn __init__(out self, callback: Self.callback_fn_type):
        self.callback = callback
        self._padding = 0

    @staticmethod
    fn no_op_callback():
        pass


struct Smokio:
    var _runtime: AsyncRuntime
    var _tasks: List[AnyCoroutine]

    fn __init__(out self):
        self._runtime = AsyncRuntime()
        self._tasks = List[AnyCoroutine]()

    fn runtime_handle(mut self) -> RuntimeHandle:
        var ptr = UnsafePointer(to=self._runtime)
        var ext_ptr = rebind[UnsafePointer[mut=True, AsyncRuntime, MutOrigin.external]](ptr)
        return RuntimeHandle(ext_ptr)

    fn spawn[T: ImplicitlyDestructible, origins: OriginSet](mut self, var coro: Coroutine[T, origins]):
        """Spawn a coroutine for manual execution in this runtime."""
        # Allocate storage for coroutine's return value
        var result = alloc[T](1)

        # Override context with no-op to bypass stdlib's asyncrt
        coro._get_ctx[_AsyncContext]()[] = _AsyncContext(_AsyncContext.no_op_callback)

        # Tell coroutine where to write result on completion (by-reference return)
        coro._set_result_slot(result)

        # Store raw handle for manual lifecycle management
        self._tasks.append(coro._handle)

        # Transfer ownership to prevent automatic cleanup
        __mlir_op.`lit.ownership.mark_destroyed`(__get_mvalue_as_litref(coro))


# ===-----------------------------------------------------------------------===#
# Demo
# ===-----------------------------------------------------------------------===#

async fn read_pipe(rt: RuntimeHandle, pipe_id: Int, fd: Int32) -> Int:
    puts("Task " + String(pipe_id) + " starting")

    var buffer = alloc[UInt8](64)
    var read_op = AsyncRead(rt, fd, buffer, 64)
    var bytes = await read_op

    if bytes > 0:
        puts("Task " + String(pipe_id) + " read " + String(bytes) + " bytes!")

    buffer.free()
    return bytes


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