"""Async I/O subsystem.

This package provides the core async I/O primitives including:
- Submission and Completion types for I/O operations
- AsyncBackend trait and platform-specific implementations
"""

from .backend import AsyncBackend
from .submission import Submission, SubmissionData, ReadSubmission, WriteSubmission
from .completion import Completion, CompletionResult, ReadResult, WriteResult, ErrorResult, WakeSignal
