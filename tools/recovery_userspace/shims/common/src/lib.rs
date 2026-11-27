#![no_std]
#![allow(non_snake_case)]

use core::ffi::{c_char, c_int, c_void};
use core::sync::atomic::{AtomicPtr, Ordering};

// AArch64 Linux syscall numbers
pub const SYS_OPENAT: i64 = 56;
pub const SYS_CLOSE: i64 = 57;
pub const SYS_WRITE: i64 = 64;
pub const SYS_NEWFSTATAT: i64 = 79;
pub const SYS_EXIT: i64 = 93; // Exits calling thread only (not exit_group)
pub const SYS_NANOSLEEP: i64 = 101;

pub const STDERR_FD: usize = 2;
pub const AT_FDCWD: i32 = -100;
pub const AT_SYMLINK_NOFOLLOW: i32 = 0x0100;
pub const O_CREAT: i32 = 0o100;
pub const ELOOP_ERRNO: i32 = 40;
pub const RTLD_NEXT: *mut c_void = -1isize as *mut c_void;

unsafe extern "C" {
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
}

/// Look up the next symbol in the dynamic link chain via `dlsym(RTLD_NEXT, name)`.
/// `name` must be NUL-terminated.
#[inline]
pub unsafe fn resolve_next_symbol(name: &[u8]) -> Option<*mut c_void> {
    let ptr = unsafe { dlsym(RTLD_NEXT, name.as_ptr().cast::<c_char>()) };
    if ptr.is_null() { None } else { Some(ptr) }
}

/// Resolve and cache a symbol pointer atomically via `dlsym(RTLD_NEXT, name)`.
#[inline]
pub unsafe fn resolve_cached(cache: &AtomicPtr<c_void>, name: &[u8]) -> Option<*mut c_void> {
    let cached = cache.load(Ordering::Acquire);
    if !cached.is_null() {
        return Some(cached);
    }
    let resolved = unsafe { resolve_next_symbol(name) }?;
    cache.store(resolved, Ordering::Release);
    Some(resolved)
}

/// Raw `write(fd, buf, len)` syscall.
#[cfg(target_arch = "aarch64")]
#[inline]
pub unsafe fn sys_write(fd: usize, buf: *const u8, len: usize) -> isize {
    let ret: isize;
    unsafe {
        core::arch::asm!(
            "svc #0",
            in("x8") SYS_WRITE,
            inout("x0") fd => ret,
            in("x1") buf,
            in("x2") len,
            options(nostack),
        );
    }
    ret
}

#[cfg(not(target_arch = "aarch64"))]
pub unsafe fn sys_write(_fd: usize, _buf: *const u8, len: usize) -> isize {
    len as isize
}

/// Raw `exit(status)` syscall — terminates only the calling thread.
#[cfg(target_arch = "aarch64")]
pub unsafe fn sys_exit_thread(status: i32) -> ! {
    unsafe {
        core::arch::asm!(
            "svc #0",
            in("x8") SYS_EXIT,
            in("x0") status as i64,
            options(noreturn, nostack),
        );
    }
}

/// Raw `nanosleep` syscall.
#[cfg(target_arch = "aarch64")]
pub unsafe fn sys_nanosleep(seconds: i64, nanoseconds: i64) {
    let req = [seconds, nanoseconds];
    unsafe {
        core::arch::asm!(
            "svc #0",
            in("x8") SYS_NANOSLEEP,
            inout("x0") req.as_ptr() => _,
            inout("x1") 0usize => _,
            options(nostack),
        );
    }
}

/// Raw `openat(dirfd, path, flags & ~O_CREAT, 0)` syscall returning `-errno` on failure.
#[cfg(target_arch = "aarch64")]
pub unsafe fn sys_openat(dirfd: i32, path: *const c_char, flags: i32) -> isize {
    let ret: isize;
    unsafe {
        core::arch::asm!(
            "svc #0",
            in("x8") SYS_OPENAT,
            inout("x0") (dirfd as u32) as usize => ret,
            in("x1") path,
            in("x2") (flags & !O_CREAT) as usize,
            in("x3") 0usize,
            options(nostack),
        );
    }
    ret
}

/// Raw `close(fd)` syscall.
#[cfg(target_arch = "aarch64")]
pub unsafe fn sys_close(fd: isize) {
    unsafe {
        core::arch::asm!(
            "svc #0",
            in("x8") SYS_CLOSE,
            inout("x0") fd => _,
            options(nostack),
        );
    }
}

/// Raw `newfstatat(dirfd, path, stat_buf, flags)` syscall returning `-errno` on failure.
#[cfg(target_arch = "aarch64")]
pub unsafe fn sys_newfstatat(
    dirfd: i32,
    path: *const c_char,
    stat_buf: *mut u8,
    flags: i32,
) -> isize {
    let ret: isize;
    unsafe {
        core::arch::asm!(
            "svc #0",
            in("x8") SYS_NEWFSTATAT,
            inout("x0") (dirfd as u32) as usize => ret,
            in("x1") path,
            in("x2") stat_buf,
            in("x3") flags as usize,
            options(nostack),
        );
    }
    ret
}

/// Write a UTF-8 string directly to stderr via `SYS_write`.
pub fn write_stderr(msg: &str) {
    if !msg.is_empty() {
        unsafe {
            sys_write(STDERR_FD, msg.as_ptr(), msg.len());
        }
    }
}

/// Write a NUL-terminated C string directly to stderr via `SYS_write`.
pub unsafe fn write_cstr_stderr(ptr: *const c_char) {
    if ptr.is_null() {
        return;
    }
    let bytes = ptr.cast::<u8>();
    let mut len = 0usize;
    unsafe {
        while *bytes.add(len) != 0 {
            len += 1;
        }
        if len > 0 {
            sys_write(STDERR_FD, bytes, len);
        }
    }
}

/// Format a signed 64-bit integer into `buf` and return the populated slice.
pub fn format_i64(value: i64, buf: &mut [u8; 22]) -> &[u8] {
    let mut i = buf.len();
    let negative = value < 0;
    let mut abs_val = value.unsigned_abs();
    if abs_val == 0 {
        i -= 1;
        buf[i] = b'0';
    } else {
        while abs_val > 0 {
            i -= 1;
            buf[i] = b'0' + (abs_val % 10) as u8;
            abs_val /= 10;
        }
    }
    if negative {
        i -= 1;
        buf[i] = b'-';
    }
    &buf[i..]
}

/// Write a signed integer followed by a newline to stderr.
pub fn write_int_stderr(value: i64) {
    let mut buf = [0u8; 22];
    let slice = format_i64(value, &mut buf);
    unsafe {
        sys_write(STDERR_FD, slice.as_ptr(), slice.len());
    }
    write_stderr("\n");
}

/// Log an Android liblog message to stderr with the given prefix.
pub unsafe fn log_android_message(prefix: &str, tag: *const c_char, msg: *const c_char) -> c_int {
    write_stderr(prefix);
    if !tag.is_null() {
        unsafe { write_cstr_stderr(tag) };
        write_stderr(":");
    }
    if !msg.is_null() {
        unsafe { write_cstr_stderr(msg) };
    }
    write_stderr("\n");
    1
}

/// Compare a NUL-terminated C string against an exact byte slice (without NUL).
pub unsafe fn cstr_eq(cstr: *const c_char, expected: &[u8]) -> bool {
    if cstr.is_null() {
        return false;
    }
    let bytes = cstr.cast::<u8>();
    let mut i = 0;
    while i < expected.len() {
        let ch = unsafe { *bytes.add(i) };
        if ch == 0 || ch != expected[i] {
            return false;
        }
        i += 1;
    }
    unsafe { *bytes.add(i) == 0 }
}

/// Return true if a NUL-terminated C string starts with `prefix`.
pub unsafe fn cstr_starts_with(cstr: *const c_char, prefix: &[u8]) -> bool {
    if cstr.is_null() {
        return false;
    }
    let bytes = cstr.cast::<u8>();
    let mut i = 0;
    while i < prefix.len() {
        let ch = unsafe { *bytes.add(i) };
        if ch == 0 || ch != prefix[i] {
            return false;
        }
        i += 1;
    }
    true
}

/// Return true if a NUL-terminated C string contains `needle`.
pub unsafe fn cstr_contains(haystack: *const c_char, needle: &[u8]) -> bool {
    if haystack.is_null() || needle.is_empty() {
        return false;
    }
    let bytes = haystack.cast::<u8>();
    let mut i = 0usize;
    loop {
        let cur = unsafe { *bytes.add(i) };
        if cur == 0 {
            return false;
        }
        let mut k = 0usize;
        while k < needle.len() {
            let hc = unsafe { *bytes.add(i + k) };
            if hc == 0 || hc != needle[k] {
                break;
            }
            k += 1;
        }
        if k == needle.len() {
            return true;
        }
        i += 1;
    }
}

/// Forward `VintfObject::fetchDeviceHalManifest` and convert `-ELOOP` (-40) to 0.
pub unsafe fn fetch_device_hal_manifest_bypass(
    self_ptr: *mut c_void,
    manifest: *mut c_void,
    error_out: *mut c_void,
    log_tag: Option<&str>,
) -> c_int {
    type FetchManifestFn =
        unsafe extern "C" fn(*mut c_void, *mut c_void, *mut c_void) -> c_int;
    static REAL_FN: AtomicPtr<c_void> = AtomicPtr::new(core::ptr::null_mut());
    const SYMBOL: &[u8] = b"_ZN7android5vintf11VintfObject22fetchDeviceHalManifestEPNS0_11HalManifestEPNSt3__112basic_stringIcNS4_11char_traitsIcEENS4_9allocatorIcEEEE\0";

    let result = match unsafe { resolve_cached(&REAL_FN, SYMBOL) } {
        Some(ptr) => {
            let real = unsafe { core::mem::transmute::<*mut c_void, FetchManifestFn>(ptr) };
            unsafe { real(self_ptr, manifest, error_out) }
        }
        None => -99,
    };

    if result == -ELOOP_ERRNO {
        if let Some(tag) = log_tag {
            write_stderr(tag);
        }
        return 0;
    }
    result
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {
        #[cfg(target_arch = "aarch64")]
        unsafe {
            core::arch::asm!("wfi", options(nostack, nomem));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_i64() {
        let mut buf = [0u8; 22];
        assert_eq!(format_i64(0, &mut buf), b"0");
        assert_eq!(format_i64(-40, &mut buf), b"-40");
        assert_eq!(format_i64(12345, &mut buf), b"12345");
    }

    #[test]
    fn test_cstr_helpers() {
        let s = b"vendor.xiaomi.hardware.framecapturemanager\0"
            .as_ptr()
            .cast::<c_char>();
        unsafe {
            assert!(cstr_eq(s, b"vendor.xiaomi.hardware.framecapturemanager"));
            assert!(!cstr_eq(s, b"vendor.xiaomi"));
            assert!(cstr_starts_with(s, b"vendor.xiaomi"));
            assert!(cstr_contains(s, b"framecapturemanager"));
            assert!(!cstr_contains(s, b"mtkpower"));
        }
    }
}
