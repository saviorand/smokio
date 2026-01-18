"""Platform-specific async I/O backend implementations.

This package contains platform-specific implementations of the AsyncBackend trait:
- kqueue: macOS and BSD systems
- (future: epoll for Linux, io_uring, IOCP for Windows)
"""

from .kqueue import KqueueBackend
