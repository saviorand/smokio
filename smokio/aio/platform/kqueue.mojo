"""Kqueue-based async I/O backend for macOS and BSD systems.

This module provides a kqueue-based implementation of the AsyncBackend trait.
"""

from sys.ffi import external_call, c_int
from memory import UnsafePointer, alloc
from builtin.builtin_list import _LITRefPackHelper

from ...aliases import c_void
from ...kqueue import (
    kqueue as create_kqueue,
    kevent as call_kevent,
    Kevent,
    Timespec,
    EVFILT_READ,
    EVFILT_WRITE,
    EVFILT_USER,
    EV_ADD,
    EV_DELETE,
    EV_ENABLE,
    EV_ONESHOT,
    NOTE_TRIGGER,
)
from ..backend import AsyncBackend
from ..submission import Submission, ReadSubmission, WriteSubmission
from ..completion import Completion

struct KqueueBackend(AsyncBackend):
    """Kqueue-based async I/O backend.

    Uses kqueue for efficient event notification on macOS and BSD systems.
    Supports read and write operations on file descriptors.
    """
    var kq: Int32
    var max_events: Int
    var pending_changes: List[Kevent]

    fn __init__(out self, max_events: Int = 64):
        """Initialize a new kqueue backend.

        Args:
            max_events: Maximum number of events to process per reap call.
        """
        try:
            self.kq = create_kqueue()
        except:
            self.kq = -1
        self.max_events = max_events
        self.pending_changes = List[Kevent]()

    fn queue_job(mut self, var submission: Submission) raises:
        """Queue an I/O operation for submission.

        Args:
            submission: The I/O operation to queue.

        Raises:
            Error: If queueing fails.
        """
        var event = Kevent()

        if submission.is_read():
            var read_sub = submission.data[ReadSubmission]
            event = Kevent(
                ident=UInt64(read_sub.fd),
                filter=EVFILT_READ,
                flags=EV_ADD | EV_ENABLE | EV_ONESHOT,
                fflags=0,
                data=0,
                udata=UnsafePointer[c_void, ImmutOrigin.external](unsafe_from_address=submission.task_index)
            )
        elif submission.is_write():
            var write_sub = submission.data[WriteSubmission]
            event = Kevent(
                ident=UInt64(write_sub.fd),
                filter=EVFILT_WRITE,
                flags=EV_ADD | EV_ENABLE | EV_ONESHOT,
                fflags=0,
                data=0,
                udata=UnsafePointer[c_void, ImmutOrigin.external](unsafe_from_address=submission.task_index)
            )

        self.pending_changes.append(event)

    fn submit(mut self) raises:
        """Submit all queued operations to kqueue.

        Raises:
            Error: If submission fails.
        """
        if len(self.pending_changes) == 0:
            return

        # Submit pending changes to kqueue
        var changelist = alloc[Kevent](len(self.pending_changes))
        for i in range(len(self.pending_changes)):
            changelist[i] = self.pending_changes[i]

        try:
            _ = call_kevent(
                self.kq,
                changelist,
                c_int(len(self.pending_changes)),
                UnsafePointer[mut=True, Kevent, MutOrigin.external](),
                0,
                UnsafePointer[mut=True, Timespec, MutOrigin.external]()
            )
        finally:
            changelist.free()

        self.pending_changes.clear()

    fn reap(mut self, max_events: Int, wait: Bool) raises -> List[Completion]:
        """Reap completed I/O operations.

        Args:
            max_events: Maximum number of completions to return.
            wait: Whether to block until at least one event is ready.

        Returns:
            List of completions for operations that finished.

        Raises:
            Error: If reaping fails.
        """
        var completions = List[Completion]()
        var events = alloc[Kevent](max_events)

        # Set timeout based on wait flag
        var timeout: UnsafePointer[mut=True, Timespec, MutOrigin.external]
        if wait:
            timeout = UnsafePointer[mut=True, Timespec, MutOrigin.external]()
        else:
            var ts = Timespec(0, 0)  # Non-blocking
            timeout = UnsafePointer[Timespec](to=ts).unsafe_origin_cast[MutOrigin.external]()

        try:
            var n = call_kevent(
                self.kq,
                UnsafePointer[mut=True, Kevent, MutOrigin.external](),
                0,
                events,
                c_int(max_events),
                timeout
            )

            # Process returned events
            for i in range(Int(n)):
                var event = events[i]
                var task_index = Int(event.udata.bitcast[Int]()[])

                if event.filter == EVFILT_READ:
                    # Read operation completed
                    var fd = Int32(event.ident)
                    var available = Int(event.data)

                    # Perform the actual read
                    var buffer = List[UInt8]()
                    if available > 0:
                        var buf_ptr = alloc[UInt8](available)
                        var bytes_read = external_call["read", c_int](
                            fd,
                            buf_ptr,
                            available
                        )

                        if bytes_read > 0:
                            for j in range(Int(bytes_read)):
                                buffer.append(buf_ptr[j])

                        buf_ptr.free()

                        completions.append(
                            Completion.for_read(task_index, Int(bytes_read), buffer^)
                        )
                    else:
                        # EOF or no data available
                        completions.append(
                            Completion.for_read(task_index, 0, buffer^)
                        )

                elif event.filter == EVFILT_WRITE:
                    # Write operation completed
                    var bytes_available = Int(event.data)
                    completions.append(
                        Completion.for_write(task_index, bytes_available)
                    )

                elif event.filter == EVFILT_USER:
                    # Wake signal
                    completions.append(Completion.wake_signal())

        finally:
            events.free()

        return completions^

    fn wake(mut self) raises:
        """Wake the backend from a blocking reap call.

        Uses EVFILT_USER to trigger a user event.

        Raises:
            Error: If waking fails.
        """
        var event = Kevent(
            ident=0,
            filter=EVFILT_USER,
            flags=EV_ADD | EV_ENABLE | EV_ONESHOT,
            fflags=NOTE_TRIGGER,
            data=0,
            udata=UnsafePointer[c_void, origin=ImmutOrigin.external]()
        )

        var changelist = UnsafePointer[Kevent](to=event)

        try:
            _ = call_kevent(
                self.kq,
                changelist,
                1,
                UnsafePointer[mut=True, Kevent, MutOrigin.external](),
                0,
                UnsafePointer[mut=True, Timespec, MutOrigin.external]()
            )
        except:
            raise Error("Failed to wake kqueue backend")

    fn __del__(deinit self):
        """Clean up kqueue file descriptor."""
        if self.kq >= 0:
            _ = external_call["close", c_int](self.kq)
