---
title: "Concurrent Counters"
date: 2024-11-09T21:52:52+01:00
draft: true
---


## Why the leaves intertwine and interleave

To intuit concurrency, perhaps lets first look at what is _presumed_ to be the order of a program. Take counting to 10, how is this evaluated? 
```go
var counter int
for i := 0; i < 10; i++ {
    counter++
}
```
This program will get compiled to a series of assembly instructions, and something called a program counter traverses this binary -- 
a distinction highlighted here as **execution order**, generated by the go compiler, not only is this compiler is free to re-order for performance, but that 'applying' each of these sequence of state transformations(ISA registers), it does not appear "instantaneous" to an observer, this is a tricky distinction, one that can produce logically incorrect concurrent programs.

> The orderings are very abstract and do not directly reflect the actual compiler and processor mechanisms involved, such as instruction reordering. This makes it possible for your concurrent code to be architecture-independent and future-proof. It allows for verification without knowing the details of every single current and future processor and compiler version.

To be sure, you don't have to take my word for it! -- just check the disassembly, `objdump` doesn't work, but thankfully [go maintains a similar package](https://pkg.go.dev/cmd/objdump):
```
go build .
go tool objdump -gnu counter > counter.md
```

sometime [after hundreds of thousands of autogenerated lines](https://raw.githubusercontent.com/hailelagi/tiny-concurrency/refs/heads/main/counter/counter.md?token=GHSAT0AAAAAACKMUG5I6XMPMVZ3VRP74K2QZYXZTBA) of go's asm, doing "go internal things", the [_text segment_](https://en.wikipedia.org/wiki/Code_segment) of our go program appears:

```
TEXT main.main(SB) /Users/haile/Documents/GitHub/tiny-concurrency/counter/counter.go
  counter.go:3		0x100066320		aa1f03e0		MOVD ZR, R0                          // mov x0, xzr			
  counter.go:5		0x100066324		14000002		JMP 2(PC)                            // b .+0x8				
  counter.go:5		0x100066328		91000400		ADD $1, R0, R0                       // add x0, x0, #0x1		
  counter.go:5		0x10006632c		f100281f		CMP $10, R0                          // cmp x0, #0xa			
  counter.go:5		0x100066330		54ffffcb		BLT -2(PC)                           // b.lt .+0xfffffffffffffff8	
  counter.go:8		0x100066334		d65f03c0		RET                                  // ret				
  counter.go:8		0x100066338		00000000		?									
  counter.go:8		0x10006633c		00000000		?									
```

That doesn't mean much, but it's not alot of output. It's possible to _infer_ without knowing too much asm of this specific architecture.

```asm
MOVD and JMP // init our "loop"
ADD $1, R0, R0 // counter++
CMP $10, R0 // i < 10;
BLT //'termination' case
RET //returns!
```

A useful model, is to imagine a single cpu core - a program starts within a single `main` thread, it can fork into one of
 many [_threads of execution_](https://en.wikipedia.org/wiki/Thread_control_block) by saving and restoring few private registers and state, 
but only one at a time -- it "jumps around" or context switches _within the same process address space_, which is mostly accurate with 
[caveats](https://wiki.xenproject.org/wiki/Hyperthreading), this distinction helps us understand _why_ concurrent programs can be **sometimes** more performant,
useful programs need to do "slow" things, like reading packets from a network card, or telling some magnetic head to spin around, 
while these very real, physical operations occur, the cpu is bored, it can do so much more, so it "switches" to other cpu work. 
A concurrent program **is not** inherently faster than a sequential one. It's only _more efficient_ at not doing the worst case of "waiting/blocking",
you don't magically get more cpu cycles, you just use them _efficiently_ by intertwining and interleaving work.

Except in a multi-core -- where a program really can get split into literal, physically different computations, however there's a catch,  in between these independent cores are slow "connections" and many important layers of caches to speed up access, and herein lies the difficulty, the ever more wrestle with cache invalidation. Given this reality, how do we write fast data structures for modern cpu architectures?
