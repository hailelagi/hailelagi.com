---
title: "Atomics"
date: 2024-11-26T12:57:51+01:00
draft: true
---

## Usecases/Patterns
- stop flag/locking primitive/aka naive mutex + busy wait
- thread progress reporting
- synchronization/barrier/fence etc
- lazy initialization

Typically a compiler intrinsic, platform/hardware dependent(x86, risc-v, arm etc), OS dependent.
Typically at least a pointer size -- in rust a [`usize`](https://doc.rust-lang.org/std/primitive.usize.html)

## Load and Store

```rust
impl AtomicI32 {
    pub fn load(&self, ordering: Ordering) -> i32;
    pub fn store(&self, value: i32, ordering: Ordering);
}
```

Building a lock with load/store:

> As you can see from this interleaving, with timely (untimely?) interrupts, we can easily produce a case where both threads set the flag to 1 and both threads are thus able to enter the critical section. This behavior is what professionals call “bad” – we have obviously failed to provide the most basic requirement: providing mutual exclusion.

> The performance problem, which we will address more later on, is the fact that the way a thread waits to acquire a lock that is already held: it endlessly checks the value of flag, a technique known as spin-waiting. Spin-waiting wastes time waiting for another thread to release a lock. The waste is exceptionally high on a uniprocessor, where the thread that the waiter is waiting for cannot even run (at least, until a context switch oc- curs)! Thus, as we move forward and develop more sophisticated solu- tions, we should also consider ways to avoid this kind of waste.

## Fetch and Modify (test-and-set, fetch-add, etc)
- can impose 'ordering' of a 'happens before'
- viz can make a binary mutex
- can determine thread progress
- statistics

```rust
impl AtomicI32 {
    pub fn fetch_add(&self, v: i32, ordering: Ordering) -> i32;
    pub fn fetch_sub(&self, v: i32, ordering: Ordering) -> i32;
    pub fn fetch_or(&self, v: i32, ordering: Ordering) -> i32;
    pub fn fetch_and(&self, v: i32, ordering: Ordering) -> i32;
    pub fn fetch_nand(&self, v: i32, ordering: Ordering) -> i32;
    pub fn fetch_xor(&self, v: i32, ordering: Ordering) -> i32;
    pub fn fetch_max(&self, v: i32, ordering: Ordering) -> i32;
    pub fn fetch_min(&self, v: i32, ordering: Ordering) -> i32;
    pub fn swap(&self, v: i32, ordering: Ordering) -> i32; // "fetch_store"
}
```


## Compare and Swap/Compare and Exchange
CAS is a super flexible primitive, can build most things out of it. ABA problem bites you though, 
via logical vs physical "happens-before"

```rust
impl AtomicI32 {
    pub fn compare_exchange(&self, expected: i32, new: i32) -> Result<i32, i32> {
        // In reality, the load, comparison and store,
        // all happen as a single atomic operation.
        let v = self.load();
        if v == expected {
            // Value is as expected.
            // Replace it and report success.
            self.store(new);
            Ok(v)
        } else {
            // The value was not as expected.
            // Leave it untouched and report failure.
            Err(v)
        }
    }
}
```

Monotonic Counter, weak ordering:

```rust
fn increment(a: &AtomicU32) {
    let mut current = a.load(Relaxed);
    loop {
        let new = current + 1;
        match a.compare_exchange(current, new, Relaxed, Relaxed) {
            Ok(_) => return,
            Err(v) => current = v,
        }
    }
}
```

## Locks - Mutexes/ RwLock etc
design axis:
- fairness (FIFO)
- correctness (mutual exlusion)
- performance (syscall overhead, space etc)
- priority inversion
