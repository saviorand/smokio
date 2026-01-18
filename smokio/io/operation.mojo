"""Base trait for async I/O operations.

This module defines the AsyncOperation trait that all async I/O operations
must implement to work with the __await__ pattern.
"""

from builtin.coroutine import _suspend_async
from builtin.builtin_list import _LITRefPackHelper

trait AsyncOperation:
    """Trait for async I/O operations.

    Async operations implement this trait to provide the standard
    async/await behavior in Mojo. The __await__ method orchestrates
    trying immediate completion, suspending if needed, and retrieving
    the final result.
    """

    # The result type this operation produces
    comptime ResultType: ImplicitlyDestructible

    fn try_immediate(mut self) -> Bool:
        """Try to complete the operation immediately without suspending.

        Returns:
            True if the operation completed immediately, False otherwise.
        """
        ...

    fn should_suspend(self) -> Bool:
        """Check if the coroutine should suspend.

        Returns:
            True if suspension is needed, False otherwise.
        """
        ...

    fn register_with_runtime(mut self, handle: AnyCoroutine) raises:
        """Register this operation with the runtime for later completion.

        Args:
            handle: The coroutine handle to resume when ready.

        Raises:
            Error: If registration fails.
        """
        ...

    fn get_result(mut self) -> Self.ResultType:
        """Get the result of the completed operation.

        Returns:
            The operation result.
        """
        ...

    fn __await__(mut self) -> Self.ResultType:
        """Await this async operation.

        This method implements the standard async/await pattern:
        1. Try immediate completion
        2. If not ready, check if suspension is needed
        3. If suspension needed, register with runtime and suspend
        4. When resumed, try immediate completion again
        5. Return the result

        Returns:
            The operation result.
        """
        # Try to complete immediately (e.g., non-blocking I/O)
        if self.try_immediate():
            return self.get_result()

        # Check if we should suspend
        if not self.should_suspend():
            return self.get_result()

        # Suspend and register with runtime
        @parameter
        fn suspend_callback(cur_hdl: AnyCoroutine):
            try:
                self.register_with_runtime(cur_hdl)
            except:
                # If registration fails, we're in trouble
                # This should not happen in normal operation
                pass

        # Suspend the coroutine
        _suspend_async[suspend_callback]()

        # When we resume, try immediate completion again
        _ = self.try_immediate()

        # Return the result
        return self.get_result()
