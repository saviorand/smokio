"""Task state machine for async coroutines.

This module defines the Task type which represents an async coroutine
with a type-safe state machine using Variant.
"""

from utils import Variant
from builtin.builtin_list import _LITRefPackHelper
from ..aio.completion import Completion

# State variants

@fieldwise_init
struct DeadState(Copyable & Movable):
    """Task is not in use (available in pool)."""
    pass

@fieldwise_init
struct RunnableState(Copyable & Movable):
    """Task is ready to run."""
    pass

@fieldwise_init
struct WaitForIoState(Copyable & Movable):
    """Task is waiting for I/O to complete."""
    pass

# Variant type for task state
comptime TaskState = Variant[
    DeadState,
    RunnableState,
    WaitForIoState,
]

struct Task(Copyable & Movable & ImplicitlyDestructible & Defaultable):
    """A task representing an async coroutine.

    Tasks move through states: Dead -> Runnable -> WaitForIo -> Runnable -> ...
    When a task completes, it transitions back to Dead and is returned to the pool.
    """
    var index: Int
    var state: TaskState
    var coro_handle: AnyCoroutine
    var result: Optional[Completion]

    fn __init__(out self):
        """Initialize a task in the Dead state."""
        self.index = -1
        self.state = TaskState(DeadState())
        self.coro_handle = __mlir_attr[`#interp.pointer<0> : `, AnyCoroutine]
        self.result = None

    # State transitions

    fn set_runnable(mut self):
        """Transition task to Runnable state."""
        self.state.set[RunnableState](RunnableState())

    fn set_waiting(mut self):
        """Transition task to WaitForIo state."""
        self.state.set[WaitForIoState](WaitForIoState())

    fn set_dead(mut self):
        """Transition task to Dead state and clear result."""
        self.state.set[DeadState](DeadState())
        self.result = None

    # Result management

    fn store_completion(mut self, var completion: Completion):
        """Store a completion result for this task.

        Args:
            completion: The completion result to store.
        """
        self.result = completion^

    fn take_completion(mut self) -> Optional[Completion]:
        """Take the stored completion, leaving None.

        Returns:
            The stored completion, or None if no result is stored.
        """
        var result = self.result^
        self.result = None
        return result^

    # State checks

    fn is_dead(self) -> Bool:
        """Check if task is in Dead state.

        Returns:
            True if the task is dead (not in use).
        """
        return self.state.isa[DeadState]()

    fn is_runnable(self) -> Bool:
        """Check if task is in Runnable state.

        Returns:
            True if the task is ready to run.
        """
        return self.state.isa[RunnableState]()

    fn is_waiting_io(self) -> Bool:
        """Check if task is in WaitForIo state.

        Returns:
            True if the task is waiting for I/O.
        """
        return self.state.isa[WaitForIoState]()
