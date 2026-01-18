"""Backend trait for async I/O implementations.

This module defines the AsyncBackend trait that all platform-specific
async I/O backends must implement (kqueue, epoll, io_uring, etc.).
"""

from builtin.builtin_list import _LITRefPackHelper
from .submission import Submission
from .completion import Completion

trait AsyncBackend(Movable):
    """Trait for async I/O backend implementations.

    Backends are responsible for:
    - Queueing I/O operations (submissions)
    - Submitting queued operations to the OS
    - Reaping completed operations (completions)
    - Waking the event loop from other threads
    """

    fn queue_job(mut self, var submission: Submission) raises:
        """Queue an I/O operation for submission.

        Args:
            submission: The I/O operation to queue.

        Raises:
            Error: If queueing fails.
        """
        ...

    fn submit(mut self) raises:
        """Submit all queued operations to the OS.

        Raises:
            Error: If submission fails.
        """
        ...

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
        ...

    fn wake(mut self) raises:
        """Wake the backend from a blocking reap call.

        Used to interrupt a waiting reap() call from another thread
        or to signal the runtime to check for shutdown.

        Raises:
            Error: If waking fails.
        """
        ...
