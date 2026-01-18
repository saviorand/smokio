"""Task scheduler for managing async coroutines.

This module provides the Scheduler which manages a pool of tasks,
tracking which are runnable, waiting for I/O, or dead.
"""

from builtin.builtin_list import _LITRefPackHelper
from ..core.pool import Pool, PoolKind, GrowablePool
from .task import Task, RunnableState
from ..aio.completion import Completion

struct Scheduler:
    """Manages the lifecycle and scheduling of async tasks.

    The scheduler uses a Pool to efficiently reuse task slots and tracks
    the count of runnable tasks for determining when to wait on I/O.
    """
    var tasks: Pool[Task]
    var runnable_count: Int

    fn __init__(out self, max_tasks: Int, kind: PoolKind):
        """Initialize a new scheduler.

        Args:
            max_tasks: Initial/maximum task capacity.
            kind: Whether the task pool is static or growable.
        """
        self.tasks = Pool[Task](max_tasks, kind)
        self.runnable_count = 0

    fn spawn(mut self, coro: AnyCoroutine) raises -> Int:
        """Spawn a new task from a coroutine.

        Args:
            coro: The coroutine to spawn as a task.

        Returns:
            The index of the spawned task.

        Raises:
            Error: If the pool is exhausted.
        """
        var index = self.tasks.borrow()
        var task_ref = self.tasks.get_mut(index)
        task_ref[].index = index
        task_ref[].coro_handle = coro
        task_ref[].set_runnable()
        self.runnable_count += 1
        return index

    fn set_runnable(mut self, index: Int) raises:
        """Mark a task as runnable.

        If the task was not already runnable, increments the runnable count.

        Args:
            index: Index of the task to mark as runnable.

        Raises:
            Error: If the task index is invalid.
        """
        var task_ref = self.tasks.get_mut(index)
        if not task_ref[].is_runnable():
            task_ref[].set_runnable()
            self.runnable_count += 1

    fn set_waiting(mut self, index: Int):
        """Mark a task as waiting for I/O.

        If the task was runnable, decrements the runnable count.

        Args:
            index: Index of the task to mark as waiting.
        """
        var task_ref = self.tasks.get_mut(index)
        if task_ref[].is_runnable():
            self.runnable_count -= 1
        task_ref[].set_waiting()

    fn release(mut self, index: Int):
        """Release a completed task back to the pool.

        Transitions the task to Dead state and returns its slot to the pool.
        If the task was runnable, decrements the runnable count.

        Args:
            index: Index of the task to release.
        """
        var task_ref = self.tasks.get_mut(index)
        if task_ref[].is_runnable():
            self.runnable_count -= 1
        task_ref[].set_dead()
        self.tasks.release(index)

    fn process_completion(mut self, var completion: Completion) raises:
        """Process a completion from the backend.

        Stores the completion result in the task and marks it as runnable.

        Args:
            completion: The completion to process.

        Raises:
            Error: If the task index is invalid.
        """
        var task_index = completion.task_index
        var task_ref = self.tasks.get_mut(task_index)
        task_ref[].store_completion(completion^)
        self.set_runnable(task_index)

    fn get_task(mut self, index: Int) -> Pointer[Task, origin_of(self)]:
        """Get a mutable reference to a task.

        Args:
            index: Index of the task to access.

        Returns:
            A mutable reference to the task.
        """
        return self.tasks.get_mut(index)

    fn has_runnable_tasks(self) -> Bool:
        """Check if there are any runnable tasks.

        Returns:
            True if at least one task is runnable.
        """
        return self.runnable_count > 0

    fn iter_borrowed_tasks(self) -> List[Int]:
        """Get a list of all borrowed (in-use) task indices.

        Returns:
            List of task indices that are currently in use.
        """
        var result = List[Int]()
        for i in range(len(self.tasks)):
            if self.tasks.is_borrowed(i):
                result.append(i)
        return result^
