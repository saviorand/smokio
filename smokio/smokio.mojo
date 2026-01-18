"""Smokio - A completion-based async I/O runtime for Mojo.

This is the main public API module for Smokio, providing a simple interface
for async I/O operations with a type-safe, Variant-based architecture.

Example:
    ```mojo
    from smokio.new_smokio import Smokio
    from smokio.aio.platform.kqueue import KqueueBackend

    fn main() raises:
        var backend = KqueueBackend(max_events=64)
        var smokio = Smokio(backend^, max_tasks=100)

        async fn example_task():
            print("Task started")
            # ... async operations ...
            print("Task completed")

        _ = smokio.spawn(example_task())
        smokio.run()
    ```
"""

from builtin.builtin_list import _LITRefPackHelper
from .aio.backend import AsyncBackend
from .runtime.runtime import Runtime
from .runtime.handle import RuntimeHandle

struct Smokio[B: AsyncBackend]:
    """Main Smokio runtime coordinator.

    Provides a simple API for spawning async tasks and running
    the event loop. Wraps the Runtime type with a cleaner interface.

    Parameters:
        B: The AsyncBackend implementation to use (e.g., KqueueBackend).
    """
    var runtime: Runtime[Self.B]

    fn __init__(out self, var backend: Self.B, max_tasks: Int = 100):
        """Initialize Smokio runtime.

        Args:
            backend: The async I/O backend to use.
            max_tasks: Initial task capacity (can grow if needed).
        """
        self.runtime = Runtime[Self.B](backend^, max_tasks)

    fn spawn(mut self, coro: AnyCoroutine) raises -> Int:
        """Spawn a new async task.

        Args:
            coro: The coroutine to spawn as a task.

        Returns:
            The task index.

        Raises:
            Error: If spawning fails.

        Example:
            ```mojo
            async fn my_task():
                print("Hello from async!")

            var task_id = smokio.spawn(my_task())
            ```
        """
        return self.runtime.spawn(coro)

    fn run(mut self) raises:
        """Run the event loop until all tasks complete.

        Executes tasks, processes I/O events, and manages the runtime
        lifecycle. Blocks until there are no more tasks to run.

        Raises:
            Error: If an error occurs during execution.

        Example:
            ```mojo
            smokio.run()  # Blocks until all spawned tasks complete
            ```
        """
        self.runtime.run()

    fn runtime_handle(mut self) -> RuntimeHandle[Self.B]:
        """Get a handle to the runtime for async operations.

        Returns:
            A RuntimeHandle that can be used by async operations
            to interact with the runtime.

        Example:
            ```mojo
            var handle = smokio.runtime_handle()
            var read_op = AsyncRead(fd, size, handle)
            var data = await read_op
            ```
        """
        return RuntimeHandle[Self.B](Pointer(to=self.runtime))

    fn stop(mut self):
        """Request the runtime to stop after the current iteration.

        The runtime will complete the current event loop iteration
        and then exit, even if there are still pending tasks.

        Example:
            ```mojo
            smokio.stop()  # Request shutdown
            ```
        """
        self.runtime.stop()
