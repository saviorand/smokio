"""KqueueBackend implementation for macOS/BSD."""

from sys.ffi import external_call, c_int
from memory import UnsafePointer, alloc
from smokio.backend.backend import AsyncBackend
from smokio.backend.submission import Submission, ReadSubmission, WriteSubmission
from smokio.backend.completion import Completion
from smokio.backend.apis.kqueue import (
    kqueue,
    _kevent,
    Kevent,
    Timespec,
    EVFILT_READ,
    EVFILT_WRITE,
    EV_ADD,
    EV_ENABLE,
    EV_DELETE,
)
from smokio.aliases import c_void, ExternalMutUnsafePointer


fn try_read(fd: c_int, size: Int) -> List[UInt8]:
    """Try to read from a file descriptor.

    Args:
        fd: The file descriptor to read from.
        size: The number of bytes to read.

    Returns:
        A list of bytes read.
    """
    var buffer = List[UInt8](capacity=size)
    for _ in range(size):
        buffer.append(0)

    var buf_ptr = ExternalMutUnsafePointer[UInt8](unsafe_from_address=Int(buffer.unsafe_ptr()))
    var bytes_read = external_call["read", Int, c_int, ExternalMutUnsafePointer[UInt8], UInt](
        fd, buf_ptr, UInt(size)
    )

    if bytes_read < 0:
        return List[UInt8]()

    # Truncate to actual bytes read
    var result = List[UInt8](capacity=bytes_read)
    for i in range(bytes_read):
        result.append(buffer[i])

    return result^


fn try_write(fd: c_int, data: String) -> Int:
    """Try to write to a file descriptor.

    Args:
        fd: The file descriptor to write to.
        data: The data to write.

    Returns:
        The number of bytes written, or -1 on error.
    """
    var ptr = UnsafePointer[UInt8](unsafe_from_address=Int(data.unsafe_ptr()))
    return external_call["write", Int, c_int, UnsafePointer[UInt8], Int](
        fd, ptr, len(data)
    )


struct KqueueBackend(AsyncBackend, Movable):
    """Kqueue-based async I/O backend for macOS/BSD."""
    var kq: c_int
    var events_buffer: List[Kevent]
    var max_events: Int

    fn __init__(out self, max_events: Int = 64):
        """Initialize the kqueue backend.

        Args:
            max_events: Maximum number of events to process at once.
        """
        try:
            self.kq = kqueue()
        except:
            self.kq = -1
        self.events_buffer = List[Kevent]()
        self.max_events = max_events

    fn queue_job(mut self, submission: Submission) raises:
        """Queue a job to be submitted.

        Args:
            submission: The submission to queue.
        """
        # Kqueue registers events immediately, so we process them here
        if submission.is_read():
            var read_sub = submission.get_read()
            var event = Kevent(
                ident=UInt64(read_sub.fd),
                filter=EVFILT_READ,
                flags=EV_ADD | EV_ENABLE,
                udata=UnsafePointer[c_void, origin=ImmutOrigin.external](unsafe_from_address=submission.task_index),
            )
            var timeout = Timespec(0, 0)
            var empty_eventlist = alloc[Kevent](0)
            _ = _kevent(self.kq, UnsafePointer(to=event), 1, empty_eventlist, 0, UnsafePointer(to=timeout))
            empty_eventlist.free()
        elif submission.is_write():
            var write_sub = submission.get_write()
            var event = Kevent(
                ident=UInt64(write_sub.fd),
                filter=EVFILT_WRITE,
                flags=EV_ADD | EV_ENABLE,
                udata=UnsafePointer[c_void, origin=ImmutOrigin.external](unsafe_from_address=submission.task_index),
            )
            var timeout = Timespec(0, 0)
            var empty_eventlist = alloc[Kevent](0)
            _ = _kevent(self.kq, UnsafePointer(to=event), 1, empty_eventlist, 0, UnsafePointer(to=timeout))
            empty_eventlist.free()

    fn submit(mut self) raises:
        """Submit all queued jobs to the OS.

        Kqueue submits eagerly in queue_job, so this is a no-op.
        """
        pass

    fn reap(mut self, max_events: Int, wait: Bool) raises -> List[Completion]:
        """Reap completed I/O operations.

        Args:
            max_events: Maximum number of events to reap.
            wait: Whether to wait for at least one event.

        Returns:
            A list of completions.
        """
        var completions = List[Completion]()

        # Allocate event buffer
        var events = alloc[Kevent](max_events)

        # Poll kqueue
        var timeout = Timespec(0, 0) if not wait else Timespec(1, 0)
        var n = _kevent(
            self.kq,
            events,  # Pass events buffer as both changelist (unused) and eventlist
            0,
            events,
            c_int(max_events),
            UnsafePointer(to=timeout)
        )

        if n < 0:
            events.free()
            return completions^

        for i in range(Int(n)):
            var event = events[i]
            var task_index = Int(event.udata)

            # Create Completion variant based on event
            if event.filter == EVFILT_READ:
                var fd = c_int(event.ident)
                var data = try_read(fd, Int(event.data))
                completions.append(
                    Completion.for_read(task_index, len(data), data^)
                )
            elif event.filter == EVFILT_WRITE:
                completions.append(
                    Completion.for_write(task_index, Int(event.data))
                )

        events.free()
        return completions^

    fn wake(mut self) raises:
        """Wake up the backend from a blocking reap call.

        Uses a user event to trigger wake-up.
        """
        # For now, we'll skip this - can be implemented later with EVFILT_USER
        pass

    fn __del__(deinit self):
        """Clean up backend resources."""
        if self.kq >= 0:
            _ = external_call["close", c_int, c_int](self.kq)
