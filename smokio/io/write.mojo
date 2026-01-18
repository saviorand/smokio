"""Async write operation.

This module provides AsyncWrite for writing data to file descriptors
asynchronously.
"""

from sys.ffi import external_call, c_int
from memory import UnsafePointer
from builtin.builtin_list import _LITRefPackHelper

from ..aio.backend import AsyncBackend
from ..aio.completion import Completion, WriteResult
from ..runtime.handle import RuntimeHandle
from .operation import AsyncOperation

struct AsyncWrite[B: AsyncBackend](AsyncOperation):
    """Async write operation.

    Writes data to a file descriptor asynchronously, suspending
    the coroutine if the write would block.

    Parameters:
        B: The AsyncBackend type.
    """
    comptime ResultType = Int

    var fd: Int32
    var data: String
    var handle: RuntimeHandle[Self.B]
    var result: Optional[Int]
    var errno: Int

    fn __init__(out self, fd: Int32, data: String, handle: RuntimeHandle[Self.B]):
        """Initialize an async write operation.

        Args:
            fd: File descriptor to write to.
            data: Data to write.
            handle: Runtime handle for registration.
        """
        self.fd = fd
        self.data = data
        self.handle = handle
        self.result = None
        self.errno = 0

    fn try_immediate(mut self) -> Bool:
        """Try to write immediately without blocking.

        Attempts a non-blocking write. If successful, stores the result.

        Returns:
            True if write completed immediately, False if would block.
        """
        # Check if we already have a result from the runtime
        var task_index = -1
        try:
            task_index = self.handle.get_runtime_ref()[].get_current_task_index()
        except:
            return False

        # Check if the task has a completion result
        var task_ref = self.handle.get_runtime_ref()[].scheduler.get_task(task_index)
        if task_ref[].result:
            var completion = task_ref[].take_completion()
            if completion:
                var comp = completion.value()
                if comp.is_write():
                    var write_result = comp.result[WriteResult]
                    self.result = write_result.bytes_written
                    self.errno = write_result.errno
                    return True

        # Try non-blocking write
        var data_ptr = self.data.unsafe_ptr()
        var bytes_written = external_call["write", c_int](
            self.fd,
            data_ptr,
            len(self.data)
        )

        if bytes_written > 0:
            # Write succeeded
            self.result = int(bytes_written)
            return True
        elif bytes_written == 0:
            # Nothing written (shouldn't happen)
            self.result = 0
            return True
        else:
            # Check errno
            var err = external_call["__errno_location", UnsafePointer[c_int]]()[]
            if err == 35 or err == 11:  # EAGAIN or EWOULDBLOCK
                return False
            else:
                # Other error
                self.errno = int(err)
                self.result = 0
                return True

    fn should_suspend(self) -> Bool:
        """Check if suspension is needed.

        Returns:
            True - always suspend if immediate write didn't work.
        """
        return True

    fn register_with_runtime(mut self, handle: AnyCoroutine) raises:
        """Register this write with the runtime.

        Args:
            handle: The coroutine handle.

        Raises:
            Error: If registration fails.
        """
        self.handle.register_wait_for_write(handle, self.fd, self.data)

    fn get_result(mut self) -> Int:
        """Get the write result.

        Returns:
            The number of bytes written.
        """
        if self.result:
            return self.result.value()
        else:
            return 0
