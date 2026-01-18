"""Main async runtime for executing coroutines.

This module provides the Runtime which orchestrates task scheduling,
I/O submission, and event processing.
"""

from builtin.builtin_list import _LITRefPackHelper
from ..aio.backend import AsyncBackend
from ..aio.submission import Submission
from ..aio.completion import Completion
from ..core.pool import PoolKind, GrowablePool
from .scheduler import Scheduler

struct Runtime[B: AsyncBackend]:
    """The main async runtime.

    Manages task scheduling, I/O operations, and the event loop.
    Parameterized by backend type for platform-specific I/O.

    Parameters:
        B: The AsyncBackend implementation to use.
    """
    var scheduler: Scheduler
    var backend: Self.B
    var current_task: Optional[Int]
    var running: Bool
    var submission_queue: List[Submission]

    fn __init__(out self, var backend: Self.B, max_tasks: Int = 100):
        """Initialize a new runtime.

        Args:
            backend: The async I/O backend to use.
            max_tasks: Initial task capacity (growable).
        """
        self.scheduler = Scheduler(max_tasks, PoolKind(GrowablePool()))
        self.backend = backend^
        self.current_task = None
        self.running = False
        self.submission_queue = List[Submission]()

    fn spawn(mut self, coro: AnyCoroutine) raises -> Int:
        """Spawn a new task from a coroutine.

        Args:
            coro: The coroutine to spawn.

        Returns:
            The task index.

        Raises:
            Error: If spawning fails.
        """
        return self.scheduler.spawn(coro)

    fn run(mut self) raises:
        """Run the event loop until all tasks complete.

        Executes runnable tasks, submits I/O operations, and processes
        completions in a loop until no more work remains.

        Raises:
            Error: If an error occurs during execution.
        """
        self.running = True

        while self.running:
            # Run all runnable tasks
            var runnable_tasks = self._collect_runnable_tasks()

            for i in range(len(runnable_tasks)):
                var task_idx = runnable_tasks[i]
                self._run_task(task_idx)

            # Submit pending I/O operations
            if len(self.submission_queue) > 0:
                for i in range(len(self.submission_queue)):
                    var submission = self.submission_queue[i]
                    self.backend.queue_job(submission^)
                self.backend.submit()
                self.submission_queue.clear()

            # Reap completions from backend
            var should_wait = self.scheduler.runnable_count == 0
            var completions = self.backend.reap(max_events=64, wait=should_wait)

            for i in range(len(completions)):
                var completion = completions[i]
                if not completion.is_wake():
                    self.scheduler.process_completion(completion^)

            # Check exit condition
            if self.scheduler.runnable_count == 0 and len(self.submission_queue) == 0:
                # No more work to do
                var has_waiting_tasks = self._has_waiting_tasks()
                if not has_waiting_tasks:
                    break

    fn _collect_runnable_tasks(mut self) -> List[Int]:
        """Collect indices of all runnable tasks.

        Returns:
            List of task indices that are runnable.
        """
        var runnable = List[Int]()
        var borrowed = self.scheduler.iter_borrowed_tasks()

        for i in range(len(borrowed)):
            var task_idx = borrowed[i]
            var task_ref = self.scheduler.get_task(task_idx)
            if task_ref[].is_runnable():
                runnable.append(task_idx)

        return runnable

    fn _has_waiting_tasks(mut self) -> Bool:
        """Check if any tasks are waiting for I/O.

        Returns:
            True if at least one task is waiting for I/O.
        """
        var borrowed = self.scheduler.iter_borrowed_tasks()

        for i in range(len(borrowed)):
            var task_idx = borrowed[i]
            var task_ref = self.scheduler.get_task(task_idx)
            if task_ref[].is_waiting_io():
                return True

        return False

    fn _run_task(mut self, task_index: Int) raises:
        """Run a single task.

        Args:
            task_index: Index of the task to run.

        Raises:
            Error: If task execution fails.
        """
        self.current_task = task_index
        var task_ref = self.scheduler.get_task(task_index)

        var coro = task_ref[].coro_handle
        if coro.resume():
            # Task completed
            self.scheduler.release(task_index)

        self.current_task = None

    fn queue_submission(mut self, owned submission: Submission):
        """Queue a submission for the next I/O batch.

        Args:
            submission: The submission to queue.
        """
        self.submission_queue.append(submission^)

    fn get_current_task_index(self) raises -> Int:
        """Get the index of the currently running task.

        Returns:
            The current task index.

        Raises:
            Error: If no task is currently running.
        """
        if self.current_task:
            return self.current_task.value()
        else:
            raise Error("No task is currently running")

    fn stop(mut self):
        """Stop the runtime after the current iteration."""
        self.running = False
