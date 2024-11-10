---
title: "scheduling stuff -_-"
date: 2024-11-10T14:21:59+01:00
draft: true
---

{{% callout %}}
how do we schedule tasks in the face of disk and network access?
{{% /callout %}}

design choices:

1. cooperative vs pre-emptive
2. completion/notify vs polling aka (polling vs interrupt)
3. multicore contention/false sharing dilemmas
4. work distribution + length of tasks

**blocking(old-school)**:
select/poll sync network file inspect if r/w/err on packets

non-blocking magic:
```c
    struct aiocb {
               /* The order of these fields is implementation-dependent */

               int             aio_fildes;     /* File descriptor */
               off_t           aio_offset;     /* File offset */
               volatile void  *aio_buf;        /* Location of buffer */
               size_t          aio_nbytes;     /* Length of transfer */
               int             aio_reqprio;    /* Request priority */
               struct sigevent aio_sigevent;   /* Notification method */
               int             aio_lio_opcode; /* Operation to be performed;
                                                  lio_listio() only */

               /* Various implementation-internal fields not shown */
           };
```

```
man aio
```
see: https://www.gnu.org/s/libc/manual/html_node/Asynchronous-I_002fO.html
rust: these calls are made via mio: https://github.com/tokio-rs/mio
see: https://wycats.gitbooks.io/mio-book/content/

pollers: rust's `Future`, javascript/libuv viz: epoll, kqueue. completion: io_uring

popular frameworks:
- single-threaded
- thread-per-core
- work stealing

## event based scheduling
event handler, event loop

```
run_queue = queue();
s = new StackFrame();

if is != complete + atomic {
    // a suspension must be injected, it is the only opportunity 
    // in a user space scheduler whereas the os can forcibly pre-empt via timers etc
    s.suspend() 
    run_queue.push(s)
}
```

process:

```
while (1) {
    events = getEvents();
    for (e in events)
        processEvent(e);
}
```


```rust
use mio::{Events, Poll, Interest, Token};
use mio::net::TcpStream;

use std::net::{self, SocketAddr};

// Bind a server socket to connect to.
let addr: SocketAddr = "127.0.0.1:0".parse()?;
let server = net::TcpListener::bind(addr)?;

// Construct a new `Poll` handle as well as the `Events` we'll store into
let mut poll = Poll::new()?;
let mut events = Events::with_capacity(1024);

// Connect the stream
let mut stream = TcpStream::connect(server.local_addr()?)?;

// Register the stream with `Poll`
poll.registry().register(&mut stream, Token(0), Interest::READABLE | Interest::WRITABLE)?;

// Wait for the socket to become ready. This has to happens in a loop to
// handle spurious wakeups.
loop {
    poll.poll(&mut events, None)?;

    for event in &events {
        if event.token() == Token(0) && event.is_writable() {
            // The socket connected (probably, it could still be a spurious
            // wakeup)
            return Ok(());
        }
    }
}
```

## Problems
- multicore requires, multi instances of an event loop + sync mechanisms
- implicit blocking due to page faults is hard to avoid and thus can lead to large performance problems when prevalent.
- semantics of the api

