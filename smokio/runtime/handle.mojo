"""Runtime handle for async operations to interact with the runtime.

This module provides RuntimeHandle which async operations use to
register I/O operations with the runtime.
"""

from memory import Pointer
from builtin.builtin_list import _LITRefPackHelper
from ..aio.backend import AsyncBackend
from ..aio.submission import Submission
from .runtime import Runtime

struct RuntimeHandle[B: AsyncBackend]:
    """Handle to the runtime for async operations.

    Provides methods for async operations to register themselves
    with the runtime and queue I/O submissions.

    Parameters:
        B: The AsyncBackend type used by the runtime.
    """
    var runtime: Pointer[Runtime[Self.B], origin_of(self)]

    fn __init__(out self, mut runtime: Pointer[Runtime[Self.B], _]):
        """Initialize a runtime handle.

        Args:
            runtime: Pointer to the runtime.
        """
        self.runtime = runtime

    fn register_wait_for_read(self, handle: AnyCoroutine, fd: Int32, size: Int) raises:
        """Register a read operation with the runtime.

        Marks the current task as waiting for I/O and queues a read submission.

        Args:
            handle: The coroutine handle (currently unused, task identified by runtime state).
            fd: File descriptor to read from.
            size: Number of bytes to read.

        Raises:
            Error: If registration fails.
        """
        var task_index = self.runtime[].get_current_task_index()
        var submission = Submission.for_read(task_index, fd, size)
        self.runtime[].scheduler.set_waiting(task_index)
        self.runtime[].queue_submission(submission)

    fn register_wait_for_write(self, handle: AnyCoroutine, fd: Int32, data: String) raises:
        """Register a write operation with the runtime.

        Marks the current task as waiting for I/O and queues a write submission.

        Args:
            handle: The coroutine handle (currently unused, task identified by runtime state).
            fd: File descriptor to write to.
            data: Data to write.

        Raises:
            Error: If registration fails.
        """
        var task_index = self.runtime[].get_current_task_index()
        var submission = Submission.for_write(task_index, fd, data)
        self.runtime[].scheduler.set_waiting(task_index)
        self.runtime[].queue_submission(submission)

    fn get_runtime_ref(self) -> Pointer[Runtime[Self.B], origin_of(self)]:
        """Get a reference to the runtime.

        Returns:
            Pointer to the runtime.
        """
        return self.runtime
