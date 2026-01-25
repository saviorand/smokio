from sys.ffi import c_int, c_short, c_uint, external_call, get_errno
from sys.info import size_of
from memory import UnsafePointer
from utils import Variant
from smokio.aliases import c_void


# ===== KQUEUE CONSTANTS =====

# Filter types
comptime EVFILT_READ = -1
"""Data available to read"""
comptime EVFILT_WRITE = -2
"""Writable space available"""
comptime EVFILT_AIO = -3
"""Attached to aio requests"""
comptime EVFILT_VNODE = -4
"""Attached to vnodes"""
comptime EVFILT_PROC = -5
"""Attached to processes"""
comptime EVFILT_SIGNAL = -6
"""Attached to signals"""
comptime EVFILT_TIMER = -7
"""Periodic timer events"""
comptime EVFILT_MACHPORT = -8
"""Mach portsets"""
comptime EVFILT_FS = -9
"""Filesystem events"""
comptime EVFILT_USER = -10
"""User events"""
comptime EVFILT_VM = -12
"""Virtual memory events"""
comptime EVFILT_EXCEPT = -15
"""Exception events"""

# Action flags for the flags field
comptime EV_ADD = 0x0001
"""Add event to kqueue"""
comptime EV_DELETE = 0x0002
"""Delete event from kqueue"""
comptime EV_ENABLE = 0x0004
"""Enable event"""
comptime EV_DISABLE = 0x0008
"""Disable event (not reported)"""
comptime EV_ONESHOT = 0x0010
"""Only report one occurrence"""
comptime EV_CLEAR = 0x0020
"""Clear event state after reporting"""
comptime EV_RECEIPT = 0x0040
"""Force immediate event output with error"""
comptime EV_DISPATCH = 0x0080
"""Disable event after reporting"""

# Return flags for the flags field
comptime EV_EOF = 0x8000
"""EOF detected"""
comptime EV_ERROR = 0x4000
"""Error, data contains errno"""

# Filter-specific flags for EVFILT_VNODE
comptime NOTE_DELETE = 0x0001
"""vnode was removed"""
comptime NOTE_WRITE = 0x0002
"""data contents changed"""
comptime NOTE_EXTEND = 0x0004
"""size increased"""
comptime NOTE_ATTRIB = 0x0008
"""attributes changed"""
comptime NOTE_LINK = 0x0010
"""link count changed"""
comptime NOTE_RENAME = 0x0020
"""vnode was renamed"""
comptime NOTE_REVOKE = 0x0040
"""vnode access was revoked"""

# Filter-specific flags for EVFILT_PROC
comptime NOTE_EXIT = 0x80000000
"""process exited"""
comptime NOTE_FORK = 0x40000000
"""process forked"""
comptime NOTE_EXEC = 0x20000000
"""process exec'd"""
comptime NOTE_REAP = 0x10000000
"""process reaped"""
comptime NOTE_SIGNAL = 0x08000000
"""shared with EVFILT_SIGNAL"""

# Filter-specific flags for EVFILT_TIMER
comptime NOTE_SECONDS = 0x00000001
"""timer in seconds"""
comptime NOTE_USECONDS = 0x00000002
"""timer in microseconds"""
comptime NOTE_NSECONDS = 0x00000004
"""timer in nanoseconds"""
comptime NOTE_ABSOLUTE = 0x00000008
"""absolute timeout"""
comptime NOTE_CRITICAL = 0x00000010
"""critical timer"""
comptime NOTE_BACKGROUND = 0x00000020
"""background timer"""
comptime NOTE_LEEWAY = 0x00000040
"""use leeway for timer coalescing"""


# ===== KQUEUE ERROR STRUCTS =====


@fieldwise_init
@register_passable("trivial")
struct KqueueEACCESError(Stringable, Writable):
    """Error: Permission denied when creating kqueue."""
    
    comptime message = "kqueue Error (EACCES): The process does not have permission to create a kqueue."
    
    fn write_to[W: Writer, //](self, mut writer: W):
        writer.write(Self.message)
    
    fn __str__(self) -> String:
        return Self.message


@fieldwise_init
@register_passable("trivial")
struct KqueueEMFILEError(Stringable, Writable):
    """Error: Per-process descriptor table is full."""
    
    comptime message = "kqueue Error (EMFILE): The per-process descriptor table is full."
    
    fn write_to[W: Writer, //](self, mut writer: W):
        writer.write(Self.message)
    
    fn __str__(self) -> String:
        return Self.message


@fieldwise_init
@register_passable("trivial")
struct KqueueENFILEError(Stringable, Writable):
    """Error: System file table is full."""
    
    comptime message = "kqueue Error (ENFILE): The system file table is full."
    
    fn write_to[W: Writer, //](self, mut writer: W):
        writer.write(Self.message)
    
    fn __str__(self) -> String:
        return Self.message


@fieldwise_init
@register_passable("trivial")
struct KqueueENOMEMError(Stringable, Writable):
    """Error: Kernel failed to allocate memory for kqueue."""
    
    comptime message = "kqueue Error (ENOMEM): The kernel failed to allocate enough memory for the kernel queue."
    
    fn write_to[W: Writer, //](self, mut writer: W):
        writer.write(Self.message)
    
    fn __str__(self) -> String:
        return Self.message


@fieldwise_init
@register_passable("trivial")
struct KeventEACCESError(Stringable, Writable):
    """Error: Attempted to attach to a process without appropriate privilege."""
    
    comptime message = "kevent Error (EACCES): The process does not have permission to attach to the requested event."
    
    fn write_to[W: Writer, //](self, mut writer: W):
        writer.write(Self.message)
    
    fn __str__(self) -> String:
        return Self.message


@fieldwise_init
@register_passable("trivial")
struct KeventEBADFError(Stringable, Writable):
    """Error: Invalid file descriptor."""
    
    comptime message = "kevent Error (EBADF): The specified descriptor is invalid."
    
    fn write_to[W: Writer, //](self, mut writer: W):
        writer.write(Self.message)
    
    fn __str__(self) -> String:
        return Self.message


@fieldwise_init
@register_passable("trivial")
struct KeventEFAULTError(Stringable, Writable):
    """Error: Invalid pointer in changelist or eventlist."""
    
    comptime message = "kevent Error (EFAULT): There was an error reading or writing to the kernel queue from the changelist or eventlist."
    
    fn write_to[W: Writer, //](self, mut writer: W):
        writer.write(Self.message)
    
    fn __str__(self) -> String:
        return Self.message


@fieldwise_init
@register_passable("trivial")
struct KeventEINTRError(Stringable, Writable):
    """Error: Signal was delivered before timeout."""
    
    comptime message = "kevent Error (EINTR): A signal was delivered before the timeout expired and before any events were placed on the kqueue for return."
    
    fn write_to[W: Writer, //](self, mut writer: W):
        writer.write(Self.message)
    
    fn __str__(self) -> String:
        return Self.message


@fieldwise_init
@register_passable("trivial")
struct KeventEINVALError(Stringable, Writable):
    """Error: Invalid timeout or event parameters."""
    
    comptime message = "kevent Error (EINVAL): The specified time limit or filter is invalid."
    
    fn write_to[W: Writer, //](self, mut writer: W):
        writer.write(Self.message)
    
    fn __str__(self) -> String:
        return Self.message


@fieldwise_init
@register_passable("trivial")
struct KeventENOENTError(Stringable, Writable):
    """Error: Event not found or could not be added."""
    
    comptime message = "kevent Error (ENOENT): The event could not be found to be modified or deleted."
    
    fn write_to[W: Writer, //](self, mut writer: W):
        writer.write(Self.message)
    
    fn __str__(self) -> String:
        return Self.message


@fieldwise_init
@register_passable("trivial")
struct KeventENOMEMError(Stringable, Writable):
    """Error: No memory available."""
    
    comptime message = "kevent Error (ENOMEM): No memory was available to register the event or no space in the kqueue."
    
    fn write_to[W: Writer, //](self, mut writer: W):
        writer.write(Self.message)
    
    fn __str__(self) -> String:
        return Self.message


@fieldwise_init
@register_passable("trivial")
struct KeventESRCHError(Stringable, Writable):
    """Error: Process to attach to does not exist."""
    
    comptime message = "kevent Error (ESRCH): The specified process to attach to does not exist."
    
    fn write_to[W: Writer, //](self, mut writer: W):
        writer.write(Self.message)
    
    fn __str__(self) -> String:
        return Self.message


# ===== VARIANT ERROR TYPES =====


@fieldwise_init
struct KqueueError(Movable, Stringable, Writable):
    """Typed error variant for kqueue() function."""
    
    comptime type = Variant[
        KqueueEACCESError,
        KqueueEMFILEError,
        KqueueENFILEError,
        KqueueENOMEMError,
        Error,
    ]
    var value: Self.type
    
    @implicit
    fn __init__(out self, value: KqueueEACCESError):
        self.value = value
    
    @implicit
    fn __init__(out self, value: KqueueEMFILEError):
        self.value = value
    
    @implicit
    fn __init__(out self, value: KqueueENFILEError):
        self.value = value
    
    @implicit
    fn __init__(out self, value: KqueueENOMEMError):
        self.value = value
    
    @implicit
    fn __init__(out self, var value: Error):
        self.value = value^
    
    fn write_to[W: Writer, //](self, mut writer: W):
        if self.value.isa[KqueueEACCESError]():
            writer.write(self.value[KqueueEACCESError])
        elif self.value.isa[KqueueEMFILEError]():
            writer.write(self.value[KqueueEMFILEError])
        elif self.value.isa[KqueueENFILEError]():
            writer.write(self.value[KqueueENFILEError])
        elif self.value.isa[KqueueENOMEMError]():
            writer.write(self.value[KqueueENOMEMError])
        elif self.value.isa[Error]():
            writer.write(self.value[Error])
    
    fn isa[T: AnyType](self) -> Bool:
        return self.value.isa[T]()
    
    fn __getitem__[T: AnyType](self) -> ref [self.value] T:
        return self.value[T]
    
    fn __str__(self) -> String:
        return String.write(self)


@fieldwise_init
struct KeventError(Movable, Stringable, Writable):
    """Typed error variant for kevent() function."""
    
    comptime type = Variant[
        KeventEACCESError,
        KeventEBADFError,
        KeventEFAULTError,
        KeventEINTRError,
        KeventEINVALError,
        KeventENOENTError,
        KeventENOMEMError,
        KeventESRCHError,
        Error,
    ]
    var value: Self.type
    
    @implicit
    fn __init__(out self, value: KeventEACCESError):
        self.value = value
    
    @implicit
    fn __init__(out self, value: KeventEBADFError):
        self.value = value
    
    @implicit
    fn __init__(out self, value: KeventEFAULTError):
        self.value = value
    
    @implicit
    fn __init__(out self, value: KeventEINTRError):
        self.value = value
    
    @implicit
    fn __init__(out self, value: KeventEINVALError):
        self.value = value
    
    @implicit
    fn __init__(out self, value: KeventENOENTError):
        self.value = value
    
    @implicit
    fn __init__(out self, value: KeventENOMEMError):
        self.value = value
    
    @implicit
    fn __init__(out self, value: KeventESRCHError):
        self.value = value
    
    @implicit
    fn __init__(out self, var value: Error):
        self.value = value^
    
    fn write_to[W: Writer, //](self, mut writer: W):
        if self.value.isa[KeventEACCESError]():
            writer.write(self.value[KeventEACCESError])
        elif self.value.isa[KeventEBADFError]():
            writer.write(self.value[KeventEBADFError])
        elif self.value.isa[KeventEFAULTError]():
            writer.write(self.value[KeventEFAULTError])
        elif self.value.isa[KeventEINTRError]():
            writer.write(self.value[KeventEINTRError])
        elif self.value.isa[KeventEINVALError]():
            writer.write(self.value[KeventEINVALError])
        elif self.value.isa[KeventENOENTError]():
            writer.write(self.value[KeventENOENTError])
        elif self.value.isa[KeventENOMEMError]():
            writer.write(self.value[KeventENOMEMError])
        elif self.value.isa[KeventESRCHError]():
            writer.write(self.value[KeventESRCHError])
        elif self.value.isa[Error]():
            writer.write(self.value[Error])
    
    fn isa[T: AnyType](self) -> Bool:
        return self.value.isa[T]()
    
    fn __getitem__[T: AnyType](self) -> ref [self.value] T:
        return self.value[T]
    
    fn __str__(self) -> String:
        return String.write(self)


# ===== KQUEUE STRUCTS =====


comptime intptr_t = Int64
"""Integer type capable of holding a pointer."""
comptime uintptr_t = UInt64
"""Unsigned integer type capable of holding a pointer."""


@register_passable("trivial")
struct Kevent:
    """Kernel event structure.

    This structure is used to specify events to be monitored by kqueue and
    to retrieve events that have occurred.
    """

    var ident: uintptr_t
    """Identifier for this event (e.g., file descriptor)."""
    var filter: c_short
    """Filter for event (e.g., EVFILT_READ, EVFILT_WRITE)."""
    var flags: c_short
    """Action flags for the event (e.g., EV_ADD, EV_DELETE) - MUST be c_short (UInt16) not c_uint!"""
    var fflags: c_uint
    """Filter-specific flags."""
    var data: intptr_t
    """Filter-specific data."""
    var udata: UnsafePointer[c_void, origin=ImmutOrigin.external]
    """User-defined data."""

    fn __init__(out self):
        """Initialize an empty kevent structure."""
        self.ident = 0
        self.filter = 0
        self.flags = 0
        self.fflags = 0
        self.data = 0
        self.udata = UnsafePointer[c_void, origin=ImmutOrigin.external]()
    
    fn __init__(
        out self,
        ident: uintptr_t,
        filter: c_short,
        flags: c_short,
        fflags: c_uint = 0,
        data: intptr_t = 0,
        udata: UnsafePointer[c_void, origin=ImmutOrigin.external] = UnsafePointer[c_void, origin=ImmutOrigin.external](),
    ):
        """Initialize a kevent structure with specific values.

        Args:
            ident: Identifier for this event (e.g., file descriptor).
            filter: Filter for event (e.g., EVFILT_READ).
            flags: Action flags for the event (e.g., EV_ADD) - c_short (UInt16).
            fflags: Filter-specific flags (default: 0).
            data: Filter-specific data (default: 0).
            udata: User-defined data (default: null pointer).
        """
        self.ident = ident
        self.filter = filter
        self.flags = flags
        self.fflags = fflags
        self.data = data
        self.udata = udata


@register_passable("trivial")
struct Timespec:
    """Time value specification for kevent timeout.

    This structure is used to specify timeout values for kevent().
    """

    var tv_sec: Int64
    """Seconds."""
    var tv_nsec: Int64
    """Nanoseconds."""

    fn __init__(out self):
        """Initialize an empty timespec structure (infinite timeout)."""
        self.tv_sec = 0
        self.tv_nsec = 0

    fn __init__(out self, seconds: Int64, nanoseconds: Int64 = 0):
        """Initialize a timespec structure with specific values.
        
        Args:
            seconds: Number of seconds.
            nanoseconds: Number of nanoseconds (default: 0).
        """
        self.tv_sec = seconds
        self.tv_nsec = nanoseconds


# ===== KQUEUE FUNCTIONS =====


fn _kqueue() -> c_int:
    """Raw libc POSIX `kqueue` function.
    
    Returns:
        A file descriptor for the new kernel event queue, or -1 on error.
    
    #### C Function
    ```c
    int kqueue(void)
    ```
    
    #### Notes:
    * Reference: https://man.freebsd.org/cgi/man.cgi?query=kqueue&sektion=2 .
    """
    return external_call["kqueue", c_int]()


fn kqueue() raises KqueueError -> c_int:
    """Libc POSIX `kqueue` function.
    
    Creates a new kernel event queue and returns a file descriptor.
    
    Returns:
        A file descriptor for the new kernel event queue.
    
    Raises:
        KqueueError: If an error occurs while creating the kqueue.
        EACCES: Permission denied.
        EMFILE: The per-process descriptor table is full.
        ENFILE: The system file table is full.
        ENOMEM: The kernel failed to allocate enough memory.
    
    #### C Function
    ```c
    int kqueue(void)
    ```
    
    #### Notes:
    * Reference: https://man.freebsd.org/cgi/man.cgi?query=kqueue&sektion=2 .
    """
    var result = _kqueue()
    if result == -1:
        var errno = get_errno()
        if errno == errno.EACCES:
            raise KqueueEACCESError()
        elif errno == errno.EMFILE:
            raise KqueueEMFILEError()
        elif errno == errno.ENFILE:
            raise KqueueENFILEError()
        elif errno == errno.ENOMEM:
            raise KqueueENOMEMError()
        else:
            raise Error(
                "kqueue Error: An error occurred while creating the kqueue. Error code: ",
                errno,
            )
    
    return result


fn _kevent(
    kq: c_int,
    changelist: UnsafePointer[Kevent],
    nchanges: c_int,
    eventlist: UnsafePointer[Kevent],
    nevents: c_int,
    timeout: UnsafePointer[Timespec],
) -> c_int:
    """Raw libc POSIX `kevent` function.
    
    Args:
        kq: The kqueue file descriptor.
        changelist: Pointer to an array of kevent structures to register.
        nchanges: Number of events in the changelist.
        eventlist: Pointer to an array to receive triggered events.
        nevents: Maximum number of events to return.
        timeout: Pointer to timeout specification (NULL for infinite).
    
    Returns:
        The number of events placed in the eventlist, or -1 on error.
    
    #### C Function
    ```c
    int kevent(int kq, const struct kevent *changelist, int nchanges,
               struct kevent *eventlist, int nevents,
               const struct timespec *timeout)
    ```
    
    #### Notes:
    * Reference: https://man.freebsd.org/cgi/man.cgi?query=kqueue&sektion=2 .
    """
    return external_call[
        "kevent",
        c_int,  # RetType
        type_of(kq),
        type_of(changelist),
        type_of(nchanges),
        type_of(eventlist),
        type_of(nevents),
        type_of(timeout),  # Args
    ](kq, changelist, nchanges, eventlist, nevents, timeout)


fn kevent(
    kq: c_int,
    changelist: UnsafePointer[Kevent],
    nchanges: c_int,
    eventlist: UnsafePointer[Kevent],
    nevents: c_int,
    timeout: UnsafePointer[Timespec, origin=ImmutOrigin.external] = UnsafePointer[Timespec, origin=ImmutOrigin.external](),
) raises KeventError -> c_int:
    """Libc POSIX `kevent` function.
    
    Registers events with a kqueue and/or retrieves pending events.
    
    Args:
        kq: The kqueue file descriptor.
        changelist: Pointer to an array of kevent structures to register.
        nchanges: Number of events in the changelist.
        eventlist: Pointer to an array to receive triggered events.
        nevents: Maximum number of events to return.
        timeout: Pointer to timeout specification (default: null/infinite).
    
    Returns:
        The number of events placed in the eventlist.
    
    Raises:
        KeventError: If an error occurs during the kevent call.
        EACCES: Permission denied when attaching to an event.
        EBADF: The specified descriptor is invalid.
        EFAULT: Invalid pointer in changelist or eventlist.
        EINTR: A signal was delivered before timeout.
        EINVAL: The specified time limit or filter is invalid.
        ENOENT: The event could not be found to be modified or deleted.
        ENOMEM: No memory available to register the event.
        ESRCH: The specified process to attach to does not exist.
    
    #### C Function
    ```c
    int kevent(int kq, const struct kevent *changelist, int nchanges,
               struct kevent *eventlist, int nevents,
               const struct timespec *timeout)
    ```
    
    #### Notes:
    * Reference: https://man.freebsd.org/cgi/man.cgi?query=kqueue&sektion=2 .
    * If timeout is null (default), kevent() blocks indefinitely.
    * If timeout is non-null but both tv_sec and tv_nsec are 0, kevent() returns immediately.
    """
    var result = _kevent(kq, changelist, nchanges, eventlist, nevents, timeout)
    if result == -1:
        var errno = get_errno()
        if errno == errno.EACCES:
            raise KeventEACCESError()
        elif errno == errno.EBADF:
            raise KeventEBADFError()
        elif errno == errno.EFAULT:
            raise KeventEFAULTError()
        elif errno == errno.EINTR:
            raise KeventEINTRError()
        elif errno == errno.EINVAL:
            raise KeventEINVALError()
        elif errno == errno.ENOENT:
            raise KeventENOENTError()
        elif errno == errno.ENOMEM:
            raise KeventENOMEMError()
        elif errno == errno.ESRCH:
            raise KeventESRCHError()
        else:
            raise Error(
                "kevent Error: An error occurred during the kevent call. Error code: ",
                errno,
            )
    
    return result
