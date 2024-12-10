---
title: "Atomics"
date: 2024-11-26T12:57:51+01:00
draft: false
---

{{% callout %}}
random notes and scribbles, does not meet any standards of quality or 
comprehension, here it is, anyway, otherwise it may never escape my drafts.
{{% /callout %}}


Atomics, typically a compiler intrinsic, platform/hardware dependent(x86, risc-v, arm etc), OS dependent.
typically at least a pointer size -- in rust a [`usize`](https://doc.rust-lang.org/std/primitive.usize.html)

## Usecases/Patterns
- stop flag/locking primitive/aka naive mutex + busy wait
- thread progress reporting
- synchronization/barrier fence etc
> A SeqCst fence is both a release fence and an acquire fence (just like AcqRel), but also part of the single total order of sequentially consistent operations. However, only the fence is part of the total order, but not necessarily the atomic operations before or after it.

- lazy initialization

## Orderings
- Relaxed: total modification order
- Release & Acquire: happens-before btw  thread A & B
- AcqRel, SeqCst: 
- *Consume

> A happens-before relationship is formed when an acquire-load operation observes the result of a release-store operation. In this case, the store and everything before it, happened before the load and everything after it.

- go mem: https://research.swtch.com/gomm
- overview: https://doc.rust-lang.org/nightly/nomicon/atomics.html
- super helpful summary(formalism): https://gist.github.com/kprotty/bb26b963441baf2ab3486a07fbf4762e
- c++ mem: https://en.cppreference.com/w/cpp/atomic/memory_order


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

CAS Loop lock-free, but not wait-free, dist-sys context, but same principle, wait-free affects availability/liveness:
```go
func (l *replicatedLog) acquireLease(kv *maelstrom.KV) int {
	l.global.Lock()
	defer l.global.Unlock()
	ctx, cancel := context.WithDeadline(context.Background(), time.Now().Add(400*time.Millisecond))
	var count int
	defer cancel()

	err := errors.New("busy wait")

	for err != nil {
		previous, _ := kv.Read(ctx, "monotonic-counter")

		if previous == nil {
			previous = 0
			count = 1
		} else {
			count = previous.(int) + 1
		}

		err = kv.CompareAndSwap(ctx, "monotonic-counter", previous, count, true)
	}

	return count
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
- fairness (FIFO) vs starvation
- correctness (mutual exlusion)
- performance (syscall overhead, space etc)
- priority inversion

mutex lock/unlock atomic:
```rust
use std::sync::atomic::AtomicBool;
use std::sync::atomic::Ordering::{Acquire, Relaxed, Release};
use std::thread;

static mut DATA: String = String::new();
static LOCKED: AtomicBool = AtomicBool::new(false);

fn mu() {
    if LOCKED
        .compare_exchange(false, true, Acquire, Relaxed)
        .is_ok()
    {
        // Safety: We hold the exclusive lock, so nothing else is accessing DATA.
        unsafe { DATA.push('!') };
        LOCKED.store(false, Release);
    }
}
```
