"""Async read operation.

This module provides AsyncRead for reading data from file descriptors
asynchronously.
"""

from sys.ffi import external_call, c_int
from memory import UnsafePointer, alloc
from builtin.builtin_list import _LITRefPackHelper

from ..aio.backend import AsyncBackend
from ..aio.completion import Completion, ReadResult
from ..runtime.handle import RuntimeHandle
from .operation import AsyncOperation

struct AsyncRead[B: AsyncBackend](AsyncOperation):
    """Async read operation.

    Reads data from a file descriptor asynchronously, suspending
    the coroutine if data is not immediately available.

    Parameters:
        B: The AsyncBackend type.
    """
    comptime ResultType = List[UInt8]

    var fd: Int32
    var size: Int
    var handle: RuntimeHandle[Self.B]
    var result: Optional[List[UInt8]]
    var errno: Int

    fn __init__(out self, fd: Int32, size: Int, handle: RuntimeHandle[Self.B]):
        """Initialize an async read operation.

        Args:
            fd: File descriptor to read from.
            size: Number of bytes to read.
            handle: Runtime handle for registration.
        """
        self.fd = fd
        self.size = size
        self.handle = handle.copy()
        self.result = None
        self.errno = 0

    fn try_immediate(mut self) -> Bool:
        """Try to read immediately without blocking.

        Attempts a non-blocking read. If successful, stores the result.

        Returns:
            True if read completed immediately, False if would block.
        """
        # Check if we already have a result from the runtime
        var task_index = -1
        try:
            task_index = self.handle.get_runtime_ref()[].get_current_task_index()
        except:
            return False

        # Check if the task has a completion result
        var task_ref = self.handle.get_runtime_mut()[].scheduler.get_task(task_index)
        if task_ref[].result:
            var completion = task_ref[].take_completion()
            if completion:
                var comp_ptr = completion.value()
                var comp = comp_ptr.copy()
                if comp.is_read():
                    var read_result = comp.result[ReadResult].copy()
                    self.result = read_result.data.copy()
                    self.errno = read_result.errno
                    return True

        # Try non-blocking read
        var buffer = alloc[UInt8](self.size)
        var bytes_read = external_call["read", c_int](
            self.fd,
            buffer,
            self.size
        )

        if bytes_read > 0:
            # Read succeeded
            var data = List[UInt8]()
            for i in range(Int(bytes_read)):
                data.append(buffer[i])
            self.result = data.copy()
            buffer.free()
            return True
        elif bytes_read == 0:
            # EOF
            self.result = List[UInt8]()
            buffer.free()
            return True
        else:
            # Check errno
            var err = external_call["__errno_location", UnsafePointer[origin = MutOrigin.external][c_int]]()[]
            if err == 35 or err == 11:  # EAGAIN or EWOULDBLOCK
                buffer.free()
                return False
            else:
                # Other error
                self.errno = Int(err)
                self.result = List[UInt8]()
                buffer.free()
                return True

    fn should_suspend(self) -> Bool:
        """Check if suspension is needed.

        Returns:
            True - always suspend if immediate read didn't work.
        """
        return True

    fn register_with_runtime(mut self, handle: AnyCoroutine) raises:
        """Register this read with the runtime.

        Args:
            handle: The coroutine handle.

        Raises:
            Error: If registration fails.
        """
        self.handle.register_wait_for_read(handle, self.fd, self.size)

    fn get_result(mut self) -> List[UInt8]:
        """Get the read result.

        Returns:
            The data that was read.
        """
        if self.result:
            var val_ptr = self.result.value().copy()
            return val_ptr^
        else:
            return List[UInt8]()
