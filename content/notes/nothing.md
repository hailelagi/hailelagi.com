---
title: "Nothing"
date: 2025-01-21T08:08:15+01:00
draft: false
---

Self reminder for each segment of crt-0:

```c
int main(void) {}
```

```
gcc -o nothing nothing.c -Wall -O
```

```
objdump -S nothing
```

macos:
```
nothing:        file format mach-o arm64

Disassembly of section __TEXT,__text:

0000000100003fa0 <_main>:
100003fa0: 52800000     mov     w0, #0
100003fa4: d65f03c0     ret
```

linux:
```
nothing:     file format elf64-x86-64


Disassembly of section .init:

0000000000001000 <_init>:
    1000:       f3 0f 1e fa             endbr64
    1004:       48 83 ec 08             sub    $0x8,%rsp
    1008:       48 8b 05 d9 2f 00 00    mov    0x2fd9(%rip),%rax        # 3fe8 <__gmon_start__@Base>
    100f:       48 85 c0                test   %rax,%rax
    1012:       74 02                   je     1016 <_init+0x16>
    1014:       ff d0                   call   *%rax
    1016:       48 83 c4 08             add    $0x8,%rsp
    101a:       c3                      ret

Disassembly of section .plt:

0000000000001020 <.plt>:
    1020:       ff 35 a2 2f 00 00       push   0x2fa2(%rip)        # 3fc8 <_GLOBAL_OFFSET_TABLE_+0x8>
    1026:       ff 25 a4 2f 00 00       jmp    *0x2fa4(%rip)        # 3fd0 <_GLOBAL_OFFSET_TABLE_+0x10>
    102c:       0f 1f 40 00             nopl   0x0(%rax)

Disassembly of section .plt.got:

0000000000001030 <__cxa_finalize@plt>:
    1030:       f3 0f 1e fa             endbr64
    1034:       ff 25 be 2f 00 00       jmp    *0x2fbe(%rip)        # 3ff8 <__cxa_finalize@GLIBC_2.2.5>
    103a:       66 0f 1f 44 00 00       nopw   0x0(%rax,%rax,1)

Disassembly of section .text:

0000000000001040 <_start>:
    1040:       f3 0f 1e fa             endbr64
    1044:       31 ed                   xor    %ebp,%ebp
    1046:       49 89 d1                mov    %rdx,%r9
    1049:       5e                      pop    %rsi
    104a:       48 89 e2                mov    %rsp,%rdx
    104d:       48 83 e4 f0             and    $0xfffffffffffffff0,%rsp
    1051:       50                      push   %rax
    1052:       54                      push   %rsp
    1053:       45 31 c0                xor    %r8d,%r8d
    1056:       31 c9                   xor    %ecx,%ecx
    1058:       48 8d 3d ca 00 00 00    lea    0xca(%rip),%rdi        # 1129 <main>
    105f:       ff 15 73 2f 00 00       call   *0x2f73(%rip)        # 3fd8 <__libc_start_main@GLIBC_2.34>
    1065:       f4                      hlt
    1066:       66 2e 0f 1f 84 00 00    cs nopw 0x0(%rax,%rax,1)
    106d:       00 00 00

0000000000001070 <deregister_tm_clones>:
    1070:       48 8d 3d 99 2f 00 00    lea    0x2f99(%rip),%rdi        # 4010 <__TMC_END__>
    1077:       48 8d 05 92 2f 00 00    lea    0x2f92(%rip),%rax        # 4010 <__TMC_END__>
    107e:       48 39 f8                cmp    %rdi,%rax
    1081:       74 15                   je     1098 <deregister_tm_clones+0x28>
    1083:       48 8b 05 56 2f 00 00    mov    0x2f56(%rip),%rax        # 3fe0 <_ITM_deregisterTMCloneTable@Base>
    108a:       48 85 c0                test   %rax,%rax
    108d:       74 09                   je     1098 <deregister_tm_clones+0x28>
    108f:       ff e0                   jmp    *%rax
    1091:       0f 1f 80 00 00 00 00    nopl   0x0(%rax)
    1098:       c3                      ret
    1099:       0f 1f 80 00 00 00 00    nopl   0x0(%rax)

00000000000010a0 <register_tm_clones>:
    10a0:       48 8d 3d 69 2f 00 00    lea    0x2f69(%rip),%rdi        # 4010 <__TMC_END__>
    10a7:       48 8d 35 62 2f 00 00    lea    0x2f62(%rip),%rsi        # 4010 <__TMC_END__>
    10ae:       48 29 fe                sub    %rdi,%rsi
    10b1:       48 89 f0                mov    %rsi,%rax
    10b4:       48 c1 ee 3f             shr    $0x3f,%rsi
    10b8:       48 c1 f8 03             sar    $0x3,%rax
    10bc:       48 01 c6                add    %rax,%rsi
    10bf:       48 d1 fe                sar    $1,%rsi
    10c2:       74 14                   je     10d8 <register_tm_clones+0x38>
    10c4:       48 8b 05 25 2f 00 00    mov    0x2f25(%rip),%rax        # 3ff0 <_ITM_registerTMCloneTable@Base>
    10cb:       48 85 c0                test   %rax,%rax
    10ce:       74 08                   je     10d8 <register_tm_clones+0x38>
    10d0:       ff e0                   jmp    *%rax
    10d2:       66 0f 1f 44 00 00       nopw   0x0(%rax,%rax,1)
    10d8:       c3                      ret
    10d9:       0f 1f 80 00 00 00 00    nopl   0x0(%rax)

00000000000010e0 <__do_global_dtors_aux>:
    10e0:       f3 0f 1e fa             endbr64
    10e4:       80 3d 25 2f 00 00 00    cmpb   $0x0,0x2f25(%rip)        # 4010 <__TMC_END__>
    10eb:       75 2b                   jne    1118 <__do_global_dtors_aux+0x38>
    10ed:       55                      push   %rbp
    10ee:       48 83 3d 02 2f 00 00    cmpq   $0x0,0x2f02(%rip)        # 3ff8 <__cxa_finalize@GLIBC_2.2.5>
    10f5:       00
    10f6:       48 89 e5                mov    %rsp,%rbp
    10f9:       74 0c                   je     1107 <__do_global_dtors_aux+0x27>
    10fb:       48 8b 3d 06 2f 00 00    mov    0x2f06(%rip),%rdi        # 4008 <__dso_handle>
    1102:       e8 29 ff ff ff          call   1030 <__cxa_finalize@plt>
    1107:       e8 64 ff ff ff          call   1070 <deregister_tm_clones>
    110c:       c6 05 fd 2e 00 00 01    movb   $0x1,0x2efd(%rip)        # 4010 <__TMC_END__>
    1113:       5d                      pop    %rbp
    1114:       c3                      ret
    1115:       0f 1f 00                nopl   (%rax)
    1118:       c3                      ret
    1119:       0f 1f 80 00 00 00 00    nopl   0x0(%rax)

0000000000001120 <frame_dummy>:
    1120:       f3 0f 1e fa             endbr64
    1124:       e9 77 ff ff ff          jmp    10a0 <register_tm_clones>

0000000000001129 <main>:
    1129:       f3 0f 1e fa             endbr64
    112d:       b8 00 00 00 00          mov    $0x0,%eax
    1132:       c3                      ret

Disassembly of section .fini:

0000000000001134 <_fini>:
    1134:       f3 0f 1e fa             endbr64
    1138:       48 83 ec 08             sub    $0x8,%rsp
    113c:       48 83 c4 08             add    $0x8,%rsp
    1140:       c3                      ret
```

rustc `library/std/src/rt.rs`:
```rust
fn handle_rt_panic<T>(e: Box<dyn Any + Send>) -> T {
    mem::forget(e);
    rtabort!("initialization or cleanup bug");
}

#[cfg_attr(test, allow(dead_code))]
unsafe fn init(argc: isize, argv: *const *const u8, sigpipe: u8) {
    #[cfg_attr(target_os = "teeos", allow(unused_unsafe))]
    unsafe {
        sys::init(argc, argv, sigpipe)
    };

    // Remember the main thread ID to give it the correct name.
    // SAFETY: this is the only time and place where we call this function.
    unsafe { main_thread::set(thread::current_id()) };
}

/// Clean up the thread-local runtime state. This *should* be run after all other
/// code managed by the Rust runtime, but will not cause UB if that condition is
/// not fulfilled. Also note that this function is not guaranteed to be run, but
/// skipping it will cause leaks and therefore is to be avoided.
pub(crate) fn thread_cleanup() {
    // This function is run in situations where unwinding leads to an abort
    // (think `extern "C"` functions). Abort here instead so that we can
    // print a nice message.
    panic::catch_unwind(|| {
        crate::thread::drop_current();
    })
    .unwrap_or_else(handle_rt_panic);
}

// One-time runtime cleanup.
// Runs after `main` or at program exit.
// NOTE: this is not guaranteed to run, for example when the program aborts.
pub(crate) fn cleanup() {
    static CLEANUP: Once = Once::new();
    CLEANUP.call_once(|| unsafe {
        // Flush stdout and disable buffering.
        crate::io::cleanup();
        // SAFETY: Only called once during runtime cleanup.
        sys::cleanup();
    });
}

// To reduce the generated code of the new `lang_start`, this function is doing
// the real work.
#[cfg(not(test))]
fn lang_start_internal(
    main: &(dyn Fn() -> i32 + Sync + crate::panic::RefUnwindSafe),
    argc: isize,
    argv: *const *const u8,
    sigpipe: u8,
) -> isize {
    // Guard against the code called by this function from unwinding outside of the Rust-controlled
    // code, which is UB. This is a requirement imposed by a combination of how the
    // `#[lang="start"]` attribute is implemented as well as by the implementation of the panicking
    // mechanism itself.
    //
    // There are a couple of instances where unwinding can begin. First is inside of the
    // `rt::init`, `rt::cleanup` and similar functions controlled by bstd. In those instances a
    // panic is a std implementation bug. A quite likely one too, as there isn't any way to
    // prevent std from accidentally introducing a panic to these functions. Another is from
    // user code from `main` or, more nefariously, as described in e.g. issue #86030.
    //
    // We use `catch_unwind` with `handle_rt_panic` instead of `abort_unwind` to make the error in
    // case of a panic a bit nicer.
    panic::catch_unwind(move || {
        // SAFETY: Only called once during runtime initialization.
        unsafe { init(argc, argv, sigpipe) };

        let ret_code = panic::catch_unwind(main).unwrap_or_else(move |payload| {
            // Carefully dispose of the panic payload.
            let payload = panic::AssertUnwindSafe(payload);
            panic::catch_unwind(move || drop({ payload }.0)).unwrap_or_else(move |e| {
                mem::forget(e); // do *not* drop the 2nd payload
                rtabort!("drop of the panic payload panicked");
            });
            // Return error code for panicking programs.
            101
        });
        let ret_code = ret_code as isize;

        cleanup();
        // Guard against multiple threads calling `libc::exit` concurrently.
        // See the documentation for `unique_thread_exit` for more information.
        crate::sys::exit_guard::unique_thread_exit();

        ret_code
    })
    .unwrap_or_else(handle_rt_panic)
}
```
