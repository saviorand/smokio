"""Completion types for async I/O operations.

This module defines the completion types returned by the async backend
when I/O operations complete. Uses Variant for type-safe tagged unions.
"""

from utils import Variant
from builtin.builtin_list import _LITRefPackHelper

# Individual result variants

@fieldwise_init
struct ReadResult(Copyable & Movable):
    """Result of a completed read operation."""
    var bytes_read: Int
    var data: List[UInt8]
    var errno: Int

@fieldwise_init
struct WriteResult(Copyable & Movable & ImplicitlyCopyable):
    """Result of a completed write operation."""
    var bytes_written: Int
    var errno: Int

@fieldwise_init
struct ErrorResult(Copyable & Movable):
    """Result indicating an error occurred."""
    var errno: Int
    var message: String

@fieldwise_init
struct WakeSignal(Copyable & Movable):
    """Signal to wake the runtime without a specific task result."""
    pass

# Variant type for completions
comptime CompletionResult = Variant[
    ReadResult,
    WriteResult,
    ErrorResult,
    WakeSignal,
]

@fieldwise_init
struct Completion(Copyable & Movable & ImplicitlyCopyable):
    """A completion returned by the async backend.

    Contains the task index that should be resumed,
    and the operation-specific result data.
    """
    var task_index: Int
    var result: CompletionResult

    # Constructors

    @staticmethod
    fn for_read(task_index: Int, bytes_read: Int, var data: List[UInt8], errno: Int = 0) -> Self:
        """Create a read completion.

        Args:
            task_index: Index of the task to resume.
            bytes_read: Number of bytes read.
            data: Buffer containing the read data.
            errno: Error number (0 for success).

        Returns:
            A new Completion for a read result.
        """
        return Self(
            task_index=task_index,
            result=CompletionResult(ReadResult(bytes_read, data^, errno))
        )

    @staticmethod
    fn for_write(task_index: Int, bytes_written: Int, errno: Int = 0) -> Self:
        """Create a write completion.

        Args:
            task_index: Index of the task to resume.
            bytes_written: Number of bytes written.
            errno: Error number (0 for success).

        Returns:
            A new Completion for a write result.
        """
        return Self(
            task_index=task_index,
            result=CompletionResult(WriteResult(bytes_written, errno))
        )

    @staticmethod
    fn for_error(task_index: Int, errno: Int, message: String) -> Self:
        """Create an error completion.

        Args:
            task_index: Index of the task to resume with error.
            errno: Error number.
            message: Human-readable error message.

        Returns:
            A new Completion for an error result.
        """
        return Self(
            task_index=task_index,
            result=CompletionResult(ErrorResult(errno, message))
        )

    @staticmethod
    fn wake_signal() -> Self:
        """Create a wake signal completion.

        This is used to wake the runtime without resuming a specific task.

        Returns:
            A new Completion for a wake signal.
        """
        return Self(
            task_index=-1,
            result=CompletionResult(WakeSignal())
        )

    # Helper methods

    fn is_read(self) -> Bool:
        """Check if this is a read result.

        Returns:
            True if this completion contains a read result.
        """
        return self.result.isa[ReadResult]()

    fn is_write(self) -> Bool:
        """Check if this is a write result.

        Returns:
            True if this completion contains a write result.
        """
        return self.result.isa[WriteResult]()

    fn is_error(self) -> Bool:
        """Check if this is an error result.

        Returns:
            True if this completion contains an error result.
        """
        return self.result.isa[ErrorResult]()

    fn is_wake(self) -> Bool:
        """Check if this is a wake signal.

        Returns:
            True if this completion is a wake signal.
        """
        return self.result.isa[WakeSignal]()
