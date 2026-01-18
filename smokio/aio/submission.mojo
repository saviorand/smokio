"""Submission types for async I/O operations.

This module defines the submission types used to queue I/O operations
with the async backend. Uses Variant for type-safe tagged unions.
"""

from utils import Variant
from builtin.builtin_list import _LITRefPackHelper

# Individual submission variants

@fieldwise_init
struct ReadSubmission(Copyable & Movable & ImplicitlyCopyable):
    """Submission for a read operation."""
    var fd: Int32
    var buffer_size: Int

@fieldwise_init
struct WriteSubmission(Copyable & Movable & ImplicitlyCopyable):
    """Submission for a write operation."""
    var fd: Int32
    var data: String

# Variant type for submissions
comptime SubmissionData = Variant[
    ReadSubmission,
    WriteSubmission,
]

@fieldwise_init
struct Submission(Copyable & Movable):
    """A submission to be queued with the async backend.

    Contains the task index that will be resumed when complete,
    and the operation-specific data.
    """
    var task_index: Int
    var data: SubmissionData

    # Constructors

    @staticmethod
    fn for_read(task_index: Int, fd: Int32, size: Int) -> Self:
        """Create a read submission.

        Args:
            task_index: Index of the task waiting for this operation.
            fd: File descriptor to read from.
            size: Number of bytes to read.

        Returns:
            A new Submission for a read operation.
        """
        return Self(
            task_index=task_index,
            data=SubmissionData(ReadSubmission(fd, size))
        )

    @staticmethod
    fn for_write(task_index: Int, fd: Int32, data: String) -> Self:
        """Create a write submission.

        Args:
            task_index: Index of the task waiting for this operation.
            fd: File descriptor to write to.
            data: Data to write.

        Returns:
            A new Submission for a write operation.
        """
        return Self(
            task_index=task_index,
            data=SubmissionData(WriteSubmission(fd, data))
        )

    # Helper methods

    fn is_read(self) -> Bool:
        """Check if this is a read submission.

        Returns:
            True if this submission is for a read operation.
        """
        return self.data.isa[ReadSubmission]()

    fn is_write(self) -> Bool:
        """Check if this is a write submission.

        Returns:
            True if this submission is for a write operation.
        """
        return self.data.isa[WriteSubmission]()
