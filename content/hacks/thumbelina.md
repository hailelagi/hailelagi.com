---
title: 'Thumbelina'
date: 2023-12-20T17:44:15+01:00
draft: false
publicDraft: false
publicArchive: true
tags: producer-consumer, FFI
recommend: false
---

Re-re-re-introducing [thumbelina](https://github.com/hailelagi/thumbelina) ⚗️🧪🔮.

Thumbelina was a project I started thinking about sometime in late 2022 when I was a wee little inexperienced with elixir. The problem I set out to solve was simple, I wanted to manipulate images using elixir, specifically I wanted to generate thumbnails. Seems straightfoward no?

As it turns out this is the kind of thing the language isn't suited for -- most practical roads lead to aws s3 and
adding imagemagick to your dockerfile. For production that is exactly what I did, but I kept wondering what was the "best" solution?

I stumbled upon reading about discord's [SortedSet](https://discord.com/blog/using-rust-to-scale-elixir-for-11-million-concurrent-users) and so began my journey to challenge myself by learning (async) rust, rustler, some systems concepts and tinkering with extending and interfacing with BEAM internals.

Time flies by, off and on whenever I'd get bored in my free time I'd incrementally built out small parts of the library that does image processing -- but I never finished it...until now.

**What was the outcome?**

_It was/is a bad idea_:

- Image manipulation means crossing the FFI boundary by calling a subroutine in a different address space - this has a cost, serialising data between this boundary also has a cost, getting the two things to be happy together is non-obvious and there are much simpler ways to efficiently solve this.

- Image compression, there's very little benefit to doing so on images. To quote the peformance README section of snappy(the underlying compression algorithm used here):

> Typical compression ratios (based on the benchmark suite) are about 1.5-1.7x for plain text, about 2-4x for HTML, and of course 1.0x for JPEGs, PNGs and other already-compressed data.

As it turns out popular binary formats like .png, .jpeg and vectorized formats like .svg are fairly optimized. Who knew? not me. I felt really dumb reading that.

If you'd like to learn _how_ to do it anyway read on!

### Boring High Level Concepts

One approach to using programs written in other languages is opening a `Port`, mogrify an elixir ImageMagick wrapper for example leverages `System.cmd`,
which uses a unix pipe to communicate with the ImageMagick binary via streams of bytes in a different OS process. There are other high level libraries that make this a viable practical approach.

Or to use a similar mechanism and implement the functionality yourself plugging into the VM,
known as "linked-in drivers" or as a "hidden node" via a network pipe such as a TCP socket, the advantage of doing this is you get fault tolerant mechanisms like supervisors. The second node can be in go, rust or elixir itself. The job scheduler Oban has a way to send workers over to other servers too if you don't wanna manage the networking yourself or want a db intermediary. You can mix and match. This is a good overview of the [solution space](https://www.theerlangelist.com/article/outside_elixir).

I used the Natively Implemented Function(NIF) C ABI. This is a managed space outside the BEAM ie rustler
which implements this binary interface and provides high level types in lovely rust.


### In the Weeds

These subroutines are expected to be pre-emptively scheduled in <1ms and are appropriate for `synchronous` operations such as short CPU burst computations and custom data structures, you don't want to copy around the runtime ala sorted set, so we don't wait but exit early, here's how making a thumbnail works:

```elixir
# you can also stream from a network handle!
# but let's keep it simple by reading from disk
{:ok, image} = Thumbelina.open("./path_to_image.jpg") 
width = 50.0
height = 50.0
destination = self()
Thumbelina.Internal.cast(:thumbnail, destination, image.bytes, image.extension, width, height)
iex(1) => :ok
```

This near instantly returns. Tokio first lazily inits on a single worker thread:

```rust
static TOKIO: Lazy<Runtime> = Lazy::new(|| {
    Builder::new_multi_thread()
        .worker_threads(1)
        .build()
        .expect("Thumbelina.Internal - no runtime!")
});
```

now we can start scheduling on the first invocation of this subroutine since there is no `main` [macro to expand](https://tokio.rs/tokio/topics/bridging) in this binary, this is afterall an embed that's statically linked:

```rust
// Asynchronously spawn a green thread on one physical thread
// that's to be managed on the tokio runtime.
pub fn spawn<T>(task: T) -> JoinHandle<T::Output>
where
    T: Future + Send + 'static,
    T::Output: Send + 'static,
{
    TOKIO.spawn(task)
}
```

It gets busy unbeknownst to the BEAM and sends a message when it's done to `destination` with a result, note that you can
also do this with bare [operating system threads](https://docs.rs/rustler/latest/rustler/thread/struct.ThreadSpawner.html) and
in the worker/job:

```rust
// take ownership of the smart pointer to the image binary at runtime
if let Some(buffer) = binary.to_owned() {
    let buffered_lock = Arc::new(RwLock::new(buffer));

    task::spawn(async move {
        let buffer = Arc::clone(&buffered_lock);
        let buffer = buffer.read().unwrap()
        // you pay a serialisation cost
        // we know this is a thumbnail operation via enums
        let result = operation::perform(operation, width, height, extension, &buffer).unwrap();

        Ok(image) => env.send_and_clear(&pid, move |env| {
            // you pay a deserialisation cost
            Success {op: thumbelina::atoms::ok(), result} .encode(env)})
        });
}
```

in our local process which is `self()` here we should eventually get:

```elixir
receive do
  {:ok, result} -> IO.inspect(result)
end

```

Now things get interesting, because the magic of the BEAM is really in distributed networking we can be even more clever, by sending over our
`destination` as the pid of a process on a remote server -- this is possilbe because elixir/erlang has location transparency. I kept it simple by
only allowing a single result store in a clustered setup.

```elixir
GenServer.start_link(__MODULE__, [], name: {:global, __MODULE__})
```

However, you can see how this idea can be expanded on, perhaps you want to model this in a
producer-consumer pipeline? using GenStage?

```
[A] -> [B] -> [C]

A producer continually ingests data from data lake 
B producer consumer (process thumbnail using message passing)
C consumer await result out do stuff with output
```
You may be wondering doesn't reading entire large bytes of images into memory lead to sudden spikes in memory?
You're right. I considered providing a stream/yeilding between the runtime and the C ABI but the [cost/benefit doesn't seem worth it](https://github.com/hailelagi/thumbelina/pull/10).

In theory by inheriting the complexity of owning such a system end to end you can really tune peformance by mixing and matching cool features. BEAM
for simple concurrency and distributed networking and rust for it's type system, memory safety and speed.

### Going forward

I'm not sure I'm going to continue to expand on this idea, and will mostly be moving on. A nod to projects I think
are interesting applications/usecases in the wild:

1. [wasmex](https://github.com/tessi/wasmex) - which provides a low-level interface to wasm/wasi via wasmtime.
2. [explorer](https://github.com/elixir-explorer/explorer) which brings dataframe processing to elixir via polar-rs.
3. [Tigerbeetlex](https://github.com/rbino/tigerbeetlex) a database client, it's
pretty much the same ideas explained here but is written in zig, handles interacting with the C binary ABI
and implements the [TigerBeetle](https://tigerbeetle.com/) client spec by embedding the Zig client.
