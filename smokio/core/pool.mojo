"""Generic object pool for efficient resource management.

This module provides a Pool type that manages a collection of reusable objects,
tracking which are in use and which are available. Supports both static (fixed-size)
and growable pools.
"""

from utils import Variant
from builtin.builtin_list import _LITRefPackHelper

# Pool kind variants

@fieldwise_init
struct StaticPool(Copyable & Movable):
    """Pool with a fixed maximum capacity."""
    pass

@fieldwise_init
struct GrowablePool(Copyable & Movable):
    """Pool that can grow beyond initial capacity."""
    pass

comptime PoolKind = Variant[StaticPool, GrowablePool]

struct Pool[T: Copyable & Movable & ImplicitlyDestructible]:
    """A pool of reusable objects.

    The pool maintains a list of items and tracks which indices are available
    for reuse. When an item is borrowed, it's removed from the available list.
    When released, it's added back.

    Parameters:
        T: The type of objects stored in the pool.
    """
    var items: List[Self.T]
    var available: List[Int]  # Stack of free indices
    var capacity: Int
    var kind: PoolKind

    fn __init__(out self, capacity: Int, kind: PoolKind):
        """Initialize a new pool.

        Args:
            capacity: Initial/maximum capacity (depending on kind).
            kind: Whether the pool is static or growable.
        """
        self.items = List[Self.T]()
        self.available = List[Int]()
        self.capacity = capacity
        self.kind = kind

    fn borrow(mut self) raises -> Int:
        """Borrow an item from the pool.

        Returns an index to an item in the pool. The item is marked as in-use
        and won't be returned by subsequent borrows until released.

        Returns:
            Index of the borrowed item.

        Raises:
            Error: If the pool is exhausted (static pool at capacity).
        """
        # Try available stack first
        if len(self.available) > 0:
            return self.available.pop()

        # Allocate new if under capacity
        if len(self.items) < self.capacity:
            var index = len(self.items)
            self.items.append(T())
            return index

        # Grow if allowed
        if self.kind.isa[GrowablePool]():
            self.capacity = max(1, self.capacity * 2)
            var index = len(self.items)
            self.items.append(T())
            return index

        raise Error("Pool exhausted")

    fn release(mut self, index: Int):
        """Release an item back to the pool.

        The item at the given index is marked as available for reuse.

        Args:
            index: Index of the item to release.
        """
        debug_assert(index >= 0 and index < len(self.items), "Invalid pool index")
        self.available.append(index)

    fn get_mut(mut self, index: Int) -> Reference[T, __lifetime_of(self)]:
        """Get a mutable reference to an item in the pool.

        Args:
            index: Index of the item to access.

        Returns:
            A mutable reference to the item.
        """
        return self.items[index]

    fn is_borrowed(self, index: Int) -> Bool:
        """Check if an item is currently borrowed.

        Args:
            index: Index of the item to check.

        Returns:
            True if the item is borrowed (in use), False if available.
        """
        # Check if index is in the available list
        for i in range(len(self.available)):
            if self.available[i] == index:
                return False
        # If not in available list and within items range, it's borrowed
        return index < len(self.items)

    fn __len__(self) -> Int:
        """Get the current number of items in the pool.

        Returns:
            Total number of items (both borrowed and available).
        """
        return len(self.items)
