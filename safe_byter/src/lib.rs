//! Read a byte from memory safely, with signal handling to detect faults
//!
//! References:
//! - [wasmtime vm](https://docs.wasmtime.dev/api/src/wasmtime/runtime/vm/sys/unix/signals.rs.html)
//! - [rust source code](https://github.com/rust-lang/rust/blob/8ac1525e091d3db28e67adcbbd6db1e1deaa37fb/src/libstd/sys/unix/stack_overflow.rs#L56)

use std::ffi::c_char;
use std::mem;
use std::panic;
use std::ptr;
use std::sync::atomic::{AtomicUsize, Ordering};

/// Description of a frame on the stack that is ready to catch an exception.
///
/// From [wasmtime vm](https://docs.rs/wasmtime-internal-unwinder/latest/src/wasmtime_internal_unwinder/throw.rs.html#24)
#[derive(Debug)]
pub struct Handler {
    /// Program counter of handler return point.
    pub pc: usize,
    /// Stack pointer to restore before jumping to handler.
    pub sp: usize,
    /// Frame pointer to restore before jumping to handler.
    pub fp: usize,
}

/// Tracks how many times the external signal handler was invoked
/// Used for testing
static EXTERNAL_HANDLER_CALL_COUNT: AtomicUsize = AtomicUsize::new(0);

const UNINIT_SIGACTION: libc::sigaction = unsafe { mem::zeroed() };
static mut PREV_SIGSEGV: libc::sigaction = UNINIT_SIGACTION;
static mut PREV_SIGBUS: libc::sigaction = UNINIT_SIGACTION;
static mut SAVED_ADDR: Option<usize> = None;
static mut BYTE_READ_HANDLER: Option<Handler> = None;

/// Posted verbatim from [rust source code](https://github.com/rust-lang/rust/blob/8ac1525e091d3db28e67adcbbd6db1e1deaa37fb/src/libstd/sys/unix/stack_overflow.rs#L56)
#[cfg(any(target_os = "linux", target_os = "android"))]
unsafe fn siginfo_si_addr(info: *mut libc::siginfo_t) -> usize {
    #[repr(C)]
    struct siginfo_t {
        a: [libc::c_int; 3], // si_signo, si_errno, si_code
        si_addr: *mut libc::c_void,
    }

    unsafe { (*(info as *const siginfo_t)).si_addr as usize }
}

pub unsafe fn init() {
    let mut action: libc::sigaction = unsafe { mem::zeroed() };
    action.sa_flags = libc::SA_SIGINFO;
    action.sa_sigaction = (signal_handler as *const ()).addr();
    unsafe {
        libc::sigemptyset(&mut action.sa_mask);
        libc::sigaction(libc::SIGSEGV, &action, &raw mut PREV_SIGSEGV);
        libc::sigaction(libc::SIGBUS, &action, &raw mut PREV_SIGBUS);
    }

    unsafe {
        BYTE_READ_HANDLER = None; // Reset state
        SAVED_ADDR = None;
    }

    println!("SIGSEGV set");
}

/// Delegates a signal to the previous handler, or crashes if there is no previous handler
///
/// Posted verbatim from [wasmtime vm](https://docs.wasmtime.dev/api/src/wasmtime/runtime/vm/sys/unix/signals.rs.html#198)
pub unsafe fn delegate_signal_to_previous_handler(
    previous: *const libc::sigaction,
    signum: libc::c_int,
    siginfo: *mut libc::siginfo_t,
    context: *mut libc::c_void,
) {
    println!("in delegate_signal_to_previous_handler");
    // Comment from source code:
    // we need to forward the signal to the next handler. If there is no
    // next handler (SIG_IGN or SIG_DFL), then it's time to crash. To do
    // this, we set the signal back to its original disposition and
    // return. This will cause the faulting op to be re-executed which
    // will crash in the normal way. If there is a next handler, call
    // it. It will either crash synchronously, fix up the instruction
    // so that execution can continue and return, or trigger a crash by
    // returning the signal to it's original disposition and returning.
    unsafe {
        let previous = *previous;
        if previous.sa_flags & libc::SA_SIGINFO != 0 {
            mem::transmute::<
                usize,
                extern "C" fn(libc::c_int, *mut libc::siginfo_t, *mut libc::c_void),
            >(previous.sa_sigaction)(signum, siginfo, context)
        } else if previous.sa_sigaction == libc::SIG_DFL || previous.sa_sigaction == libc::SIG_IGN {
            libc::sigaction(signum, &previous as *const _, ptr::null_mut());
        } else {
            mem::transmute::<usize, extern "C" fn(libc::c_int)>(previous.sa_sigaction)(signum)
        }
    }
}

/// Updates the siginfo context stored in `cx` to resume to `handler` up on
/// resumption while returning from the signal handler.
#[cfg(target_os = "linux")]
unsafe fn store_handler_in_ucontext(cx: *mut libc::c_void, handler: &Handler) {
    let cx = unsafe { cx.cast::<libc::ucontext_t>().as_mut().unwrap() };
    cx.uc_mcontext.gregs[libc::REG_RIP as usize] = handler.pc as _;
    cx.uc_mcontext.gregs[libc::REG_RSP as usize] = handler.sp as _;
    cx.uc_mcontext.gregs[libc::REG_RBP as usize] = handler.fp as _;
    cx.uc_mcontext.gregs[libc::REG_RAX as usize] = 0;
    cx.uc_mcontext.gregs[libc::REG_RDX as usize] = 0;
}

/// Signal handler for SIGSEGV and SIGBUS
unsafe extern "C" fn signal_handler(
    signum: libc::c_int,
    siginfo: *mut libc::siginfo_t,
    context: *mut libc::c_void,
) {
    let previous = match signum {
        libc::SIGSEGV => &raw const PREV_SIGSEGV,
        libc::SIGBUS => &raw const PREV_SIGBUS,
        _ => panic!("unknown signal: {signum}"),
    };

    // We handle this as *our* signal only if it was hit on the same address as the one we are reading
    let faulting_addr = match signum {
        libc::SIGSEGV | libc::SIGBUS => unsafe { Some((*siginfo).si_addr() as usize) },
        _ => None,
    };

    unsafe {
        if faulting_addr == SAVED_ADDR {
            let Some(ref handler) = BYTE_READ_HANDLER else {
                let msg = b"Something is wrong with signal handler\0".as_ptr();
                libc::write(
                    libc::STDERR_FILENO,
                    msg as *mut libc::c_void,
                    libc::strlen(msg as *const c_char),
                );
                libc::abort();
            };
            store_handler_in_ucontext(context, handler);
            return;
        }
    }

    // As a last resort, delegate the signal to the previous handler
    unsafe {
        EXTERNAL_HANDLER_CALL_COUNT.fetch_add(1, Ordering::SeqCst);
        delegate_signal_to_previous_handler(previous, signum, siginfo, context)
    };
}

/// Safely reads a byte from memory
#[allow(dead_code)]
#[cfg(target_os = "linux")]
pub unsafe fn read_u8(from: *const u8) -> Option<u8> {
    unsafe {
        SAVED_ADDR = Some(from.addr());
    }

    // Save current execution state
    unsafe {
        let mut ucp = mem::MaybeUninit::<libc::ucontext_t>::uninit();
        let handler = &raw mut BYTE_READ_HANDLER;
        if libc::getcontext(ucp.as_mut_ptr()) == 0 && (*handler).is_none() {
            println!("saving context in getcontext");
            let handler = Handler {
                pc: ucp.assume_init().uc_mcontext.gregs[libc::REG_RIP as usize] as usize,
                sp: ucp.assume_init().uc_mcontext.gregs[libc::REG_RSP as usize] as usize,
                fp: ucp.assume_init().uc_mcontext.gregs[libc::REG_RBP as usize] as usize,
            };

            BYTE_READ_HANDLER = Some(handler);
        } else {
            return None;
        }
    }

    return unsafe { Some(*from) };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn int_to_ptr() {
        unsafe { init() }
        let pointer = 0x400000 as *const u8;
        let byte = unsafe { read_u8(pointer) };
        assert!(byte.is_none());
    }

    #[test]
    fn real_ptr() {
        unsafe { init() }
        let array = [1u8, 2, 3];
        let pointer = array.as_ptr();
        let byte = unsafe { read_u8(pointer) };
        assert_eq!(byte, Some(1u8));
        assert_eq!(byte.unwrap(), 1u8);
    }

    #[test]
    fn external_handler_not_triggered_on_successful_read() {
        unsafe { init() };

        // Reset the counter
        EXTERNAL_HANDLER_CALL_COUNT.store(0, Ordering::SeqCst);

        // Perform a successful read that should NOT trigger the external handler
        let array = [42u8, 1, 2, 3];
        let pointer = array.as_ptr();
        let byte = unsafe { read_u8(pointer) };

        // Verify the read was successful
        assert!(byte.is_some());
        assert_eq!(byte.unwrap(), 42u8);

        // Verify the external signal handler was NOT triggered
        let count = EXTERNAL_HANDLER_CALL_COUNT.load(Ordering::SeqCst);
        assert_eq!(
            count, 0,
            "External signal handler should not be triggered on successful read, but was called {} times",
            count
        );
    }

    use std::sync::atomic::AtomicBool;

    // Thread-local flag to track if our custom external handler was called
    thread_local! {
        static EXTERNAL_HANDLER_CALLED: AtomicBool = AtomicBool::new(false);
    }

    #[test]
    fn external_handler_triggered_on_unrelated_fault() {
        static mut EXTERNAL_HANDLER: Option<Handler> = None;
        static mut CUSTOM_HANDLER_CALLED: bool = false;

        unsafe extern "C" fn custom_external_handler(
            signum: libc::c_int,
            siginfo: *mut libc::siginfo_t,
            context: *mut libc::c_void,
        ) {
            unsafe {
                let _ = (signum, siginfo, context); // Suppress unused warnings.
                CUSTOM_HANDLER_CALLED = true;
                // Mark that we were called
                // Restore default handler so the process crashes cleanly
                // let mut action: libc::sigaction = std::mem::zeroed();
                // action.sa_sigaction = libc::SIG_DFL;
                // libc::sigaction(signum, &action, ptr::null_mut());
                let Some(ref handler) = EXTERNAL_HANDLER else {
                    let msg = b"Something is wrong with signal handler\0".as_ptr();
                    libc::write(
                        libc::STDERR_FILENO,
                        msg as *mut libc::c_void,
                        libc::strlen(msg as *const c_char),
                    );
                    libc::abort();
                };
                store_handler_in_ucontext(context, handler);
            }
        }

        // Install our custom handler before init()
        unsafe {
            let mut action: libc::sigaction = std::mem::zeroed();
            action.sa_flags = libc::SA_SIGINFO;
            action.sa_sigaction = (custom_external_handler as *const ()).addr();
            libc::sigemptyset(&mut action.sa_mask);
            libc::sigaction(libc::SIGSEGV, &action, ptr::null_mut());
        }

        // Reset the counter
        EXTERNAL_HANDLER_CALL_COUNT.store(0, Ordering::SeqCst);
        unsafe {
            EXTERNAL_HANDLER = None;
        }

        // Now init() will see our handler as the "previous" handler
        unsafe { init() };

        // Set up to read from one address (our "expected" fault address)
        let expected_addr = 0x1000 as *const u8;

        // Set SAVED_ADDR to the expected address
        unsafe {
            SAVED_ADDR = Some(expected_addr.addr());
        }

        // Trigger a fault at a DIFFERENT address
        // Since 0x2000 != 0x1000, it will delegate to our external handler
        let unrelated_addr = 0x2000 as *const u8;

        let _ = unsafe {
            let mut ucp = mem::MaybeUninit::<libc::ucontext_t>::uninit();
            let handler = &raw mut EXTERNAL_HANDLER;
            if libc::getcontext(ucp.as_mut_ptr()) == 0 && (*handler).is_none() {
                println!("saving context in getcontext");
                let handler = Handler {
                    pc: ucp.assume_init().uc_mcontext.gregs[libc::REG_RIP as usize] as usize,
                    sp: ucp.assume_init().uc_mcontext.gregs[libc::REG_RSP as usize] as usize,
                    fp: ucp.assume_init().uc_mcontext.gregs[libc::REG_RBP as usize] as usize,
                };

                EXTERNAL_HANDLER = Some(handler);

                let _val = *unrelated_addr; // This will fault
                Err("panic in external handler")
            } else {
                Ok(())
            }
        };

        // Check if that specific signal handler in this test occured
        unsafe { assert!(CUSTOM_HANDLER_CALLED) };

        // Verify our signal handler attempted to delegate
        let count = EXTERNAL_HANDLER_CALL_COUNT.load(Ordering::SeqCst);
        assert_eq!(
            count, 1,
            "Should attempt to delegate to external handler once"
        );
    }
}
