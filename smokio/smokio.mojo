from memory import UnsafePointer, alloc
# Undocumented coroutine primitives from Mojo stdlib:
# - AnyCoroutine: MLIR type (!co.routine) representing raw coroutine handle
# - _coro_resume_fn: Resume a suspended coroutine from where it left off
# - _suspend_async: Suspend current coroutine and call callback with its handle
from builtin.coroutine import AnyCoroutine, _coro_resume_fn, _suspend_async
from sys.ffi import external_call, c_int
from smokio.kqueue import (
    kqueue,
    kevent,
    _kevent,
    Kevent,
    Timespec,
    EVFILT_READ,
    EV_ADD,
    EV_ENABLE,
)
from smokio.aliases import ExternalMutUnsafePointer, ExternalImmutUnsafePointer


# ===-----------------------------------------------------------------------===#
# Utilities
# ===-----------------------------------------------------------------------===#

fn puts(var s: String):
    var cstr = s.as_c_string_slice()
    _ = external_call["puts", Int32](cstr.unsafe_ptr())


fn set_nonblocking(fd: c_int) -> Bool:
    """Set a file descriptor to non-blocking mode using ioctl."""
    comptime FIONBIO = 0x8004667e
    var nonblock = alloc[c_int](1)
    nonblock[] = 1
    var result = external_call["ioctl", Int, c_int, Int, ExternalMutUnsafePointer[c_int]](fd, FIONBIO, nonblock)
    nonblock.free()
    return result != -1


fn try_read(fd: c_int, buffer: ExternalMutUnsafePointer[UInt8], size: Int) -> Int:
    """Attempt to read from a file descriptor without blocking."""
    return external_call["read", Int, c_int, ExternalMutUnsafePointer[UInt8], UInt](fd, buffer, UInt(size))


@fieldwise_init
struct Pipe(Movable, Copyable):
    """A simple pipe wrapper for IPC communication."""
    var read_fd: c_int
    var write_fd: c_int

    fn __init__(out self):
        """Create a new pipe and set the read end to non-blocking."""
        var fds = alloc[c_int](2)
        _ = external_call["pipe", c_int, ExternalMutUnsafePointer[c_int]](fds)
        self.read_fd = fds[0]
        self.write_fd = fds[1]
        fds.free()
        _ = set_nonblocking(self.read_fd)

    fn send(self, msg: String):
        """Send a string message through the pipe."""
        var ptr = ExternalMutUnsafePointer[UInt8](unsafe_from_address=Int(msg.unsafe_ptr()))
        _ = external_call["write", Int, c_int, ExternalMutUnsafePointer[UInt8], Int](self.write_fd, ptr, len(msg))

    fn close(self):
        """Close both ends of the pipe."""
        var close_fn = external_call["close", c_int, c_int]
        _ = close_fn(self.read_fd)
        _ = close_fn(self.write_fd)


# ===-----------------------------------------------------------------------===#
# Runtime
# ===-----------------------------------------------------------------------===#


@register_passable("trivial")
struct AsyncTask:
    """Pairs a suspended coroutine handle with the fd it's waiting on."""
    var coro_handle: AnyCoroutine  # Raw handle to suspended coroutine
    var fd: c_int                  # File descriptor this task is waiting to read

    fn __init__(out self, handle: AnyCoroutine, fd: c_int):
        self.coro_handle = handle
        self.fd = fd


struct AsyncRuntime:
    """Async runtime using kqueue for I/O event notification."""
    var kq: c_int
    var waiting_tasks: ExternalMutUnsafePointer[AsyncTask]
    var num_waiting: Int
    var max_tasks: Int

    fn __init__(out self, max_tasks: Int = 16):
        """Initialize runtime with kqueue and task storage.

        Args:
            max_tasks: Maximum number of concurrent tasks (default: 16).
        """
        try:
            self.kq = kqueue()
        except:
            puts("Failed to create kqueue")
            self.kq = -1
        self.waiting_tasks = alloc[AsyncTask](max_tasks)
        self.num_waiting = 0
        self.max_tasks = max_tasks

    fn register_read(mut self, handle: AnyCoroutine, fd: c_int) -> Int:
        """Register a suspended coroutine to be resumed when fd is readable.

        Args:
            handle: The coroutine handle to resume when fd is ready.
            fd: The file descriptor to monitor for read events.

        Returns:
            The task index, or -1 on error.
        """
        if self.num_waiting >= self.max_tasks:
            return -1

        # Add fd to kqueue with EVFILT_READ
        var ev = Kevent(
            ident=UInt64(fd),
            filter=EVFILT_READ,
            flags=EV_ADD | EV_ENABLE,
        )
        var ev_ptr = UnsafePointer(to=ev)

        # Use zero timeout for immediate return when registering
        var timeout = alloc[Timespec](1)
        timeout[] = Timespec(0, 0)

        # Use raw _kevent to avoid raises clause - no eventlist needed for registration
        var empty_eventlist = alloc[Kevent](0)
        var result = _kevent(self.kq, ev_ptr, 1, empty_eventlist, 0, timeout)
        empty_eventlist.free()
        timeout.free()

        if result == -1:
            puts("Failed to register fd with kqueue")
            return -1

        puts("  [Runtime] Successfully registered fd " + String(fd))

        # Store handle + fd pair for later resumption
        self.waiting_tasks[self.num_waiting] = AsyncTask(handle, fd)
        self.num_waiting += 1
        return self.num_waiting - 1

    fn run_once(mut self) -> Int:
        """Wait for I/O events and resume ready coroutines.

        Returns:
            The number of coroutines resumed, or 0 if none ready.
        """
        if self.num_waiting == 0:
            puts("  [Runtime] run_once: no tasks waiting")
            return 0

        puts("  [Runtime] run_once: waiting for events on " + String(self.num_waiting) + " fds")

        var events = alloc[Kevent](self.max_tasks)

        # Wait for events with a timeout to avoid hanging
        var timeout = alloc[Timespec](1)
        timeout[] = Timespec(1, 0)  # 1 second timeout
        var nev: c_int
        try:
            puts("  [Runtime] Calling kevent...")
            nev = kevent(self.kq, UnsafePointer[Kevent, origin=ImmutExternalOrigin](), 0, events, c_int(self.max_tasks), rebind[UnsafePointer[Timespec, origin=ImmutExternalOrigin]](timeout))
            puts("  [Runtime] kevent returned " + String(nev) + " events")
        except:
            puts("kevent failed in run_once")
            timeout.free()
            events.free()
            return 0

        timeout.free()

        if nev <= 0:
            events.free()
            return 0

        var resumed = 0

        # For each ready fd, find and resume the waiting coroutine
        for i in range(Int(nev)):
            var ready_fd = c_int(events[i].ident)

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
            _ = external_call["close", c_int, c_int](self.kq)
        if self.waiting_tasks:
            self.waiting_tasks.free()


@register_passable("trivial")
struct RuntimeHandle:
    var _ptr: ExternalMutUnsafePointer[AsyncRuntime]

    fn __init__(out self, ptr: ExternalMutUnsafePointer[AsyncRuntime]):
        self._ptr = ptr


struct AsyncRead:
    """Awaitable read that suspends until fd is readable."""
    var runtime: RuntimeHandle
    var fd: c_int
    var buffer: ExternalMutUnsafePointer[UInt8]
    var size: Int

    fn __init__(out self, runtime: RuntimeHandle, fd: c_int, buffer: ExternalMutUnsafePointer[UInt8], size: Int):
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
        var errno = external_call["__error", ExternalMutUnsafePointer[c_int]]()
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


fn try_write(fd: c_int, buffer: ExternalImmutUnsafePointer[UInt8], size: Int) -> Int:
    """Attempt to write to a file descriptor without blocking."""
    return external_call["write", Int, c_int, ExternalImmutUnsafePointer[UInt8], UInt](fd, buffer, UInt(size))


struct AsyncWrite:
    """Awaitable write that suspends until fd is writable."""
    var runtime: RuntimeHandle
    var fd: c_int
    var buffer: ExternalImmutUnsafePointer[UInt8]
    var size: Int

    fn __init__(out self, runtime: RuntimeHandle, fd: c_int, buffer: ExternalImmutUnsafePointer[UInt8], size: Int):
        self.runtime = runtime
        self.fd = fd
        self.buffer = buffer
        self.size = size

    @always_inline
    fn __await__(mut self) -> Int:
        _ = set_nonblocking(self.fd)

        # Try immediate write first
        var bytes = try_write(self.fd, self.buffer, self.size)
        if bytes >= 0:
            return bytes

        # Check if we got EAGAIN (would block)
        var errno = external_call["__error", ExternalMutUnsafePointer[c_int]]()
        comptime EAGAIN = 35
        if errno[] != EAGAIN:
            return -1

        puts("  [AsyncWrite] fd " + String(self.fd) + " not ready, suspending...")

        # Suspend and register with kqueue (use EVFILT_WRITE for write readiness)
        @always_inline
        @parameter
        fn suspend_callback(cur_hdl: AnyCoroutine):
            # For writes, we'd need to register with EVFILT_WRITE instead of EVFILT_READ
            # For now, using register_read as placeholder - you may want to add register_write
            _ = self.runtime._ptr[].register_read(cur_hdl, self.fd)

        # Suspend execution here - returns when runtime calls _coro_resume_fn
        _suspend_async[suspend_callback]()

        # Execution resumes here when fd is ready
        puts("  [AsyncWrite] fd " + String(self.fd) + " resumed, writing...")
        bytes = try_write(self.fd, self.buffer, self.size)
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
    """Main async runtime coordinator for spawning and managing coroutines."""
    var _runtime: AsyncRuntime
    var _tasks: List[AnyCoroutine]

    fn __init__(out self):
        """Initialize the Smokio runtime."""
        self._runtime = AsyncRuntime()
        self._tasks = List[AnyCoroutine]()

    fn runtime_handle(mut self) -> RuntimeHandle:
        """Get a handle to the internal runtime for passing to async operations."""
        var ptr = UnsafePointer(to=self._runtime)
        var ext_ptr = rebind[ExternalMutUnsafePointer[AsyncRuntime]](ptr)
        return RuntimeHandle(ext_ptr)

    fn spawn[T: ImplicitlyDestructible, origins: OriginSet](mut self, var coro: Coroutine[T, origins]):
        """Spawn a coroutine for manual execution in this runtime.

        Args:
            coro: The coroutine to spawn and manage.

        Notes:
            The coroutine is detached from the stdlib async runtime and will be
            manually resumed by this runtime's event loop.
        """
        # Allocate storage for coroutine's return value
        var result = alloc[T](1)

        # Mark result as initialized - required by MLIR ownership system
        __mlir_op.`lit.ownership.mark_initialized`(__get_mvalue_as_litref(result[]))

        # Override context with no-op to bypass stdlib's asyncrt
        coro._get_ctx[_AsyncContext]()[] = _AsyncContext(_AsyncContext.no_op_callback)

        # Tell coroutine where to write result on completion (by-reference return)
        coro._set_result_slot(result)

        # Take ownership of coroutine handle
        self._tasks.append(coro^._take_handle())

    fn __del__(deinit self):
        """Cleanup all spawned tasks (destroy coroutine handles).

        Uses co.destroy MLIR op following stdlib Coroutine.force_destroy pattern.
        Note: result pointers are leaked - in production would need per-task cleanup.
        """
        for i in range(len(self._tasks)):
            __mlir_op.`co.destroy`(self._tasks[i])


# ===-----------------------------------------------------------------------===#
# Demo
# ===-----------------------------------------------------------------------===#

async fn read_pipe(rt: RuntimeHandle, pipe_id: Int, fd: c_int) -> Int:
    """Demo async function that reads from a pipe.

    Args:
        rt: Runtime handle for async operations.
        pipe_id: Identifier for logging.
        fd: File descriptor to read from.

    Returns:
        Number of bytes read, or -1 on error.
    """
    puts("Task " + String(pipe_id) + " starting")

    var buffer = alloc[UInt8](64)
    var read_op = AsyncRead(rt, fd, buffer, 64)
    var bytes = await read_op

    if bytes > 0:
        puts("Task " + String(pipe_id) + " read " + String(bytes) + " bytes!")

    buffer.free()
    return bytes

