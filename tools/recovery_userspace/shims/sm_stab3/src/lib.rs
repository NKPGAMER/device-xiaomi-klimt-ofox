#![no_std]
#![allow(non_snake_case)]

use core::ffi::{c_char, c_int, c_short, c_uint, c_ulong, c_void};
use core::sync::atomic::{AtomicBool, AtomicPtr, Ordering};
use shim_common::{
    AT_FDCWD, AT_SYMLINK_NOFOLLOW, ELOOP_ERRNO, O_CREAT, cstr_eq, cstr_starts_with,
    fetch_device_hal_manifest_bypass, log_android_message, resolve_cached, resolve_next_symbol,
    sys_close, sys_nanosleep, sys_newfstatat, sys_openat, write_cstr_stderr, write_int_stderr,
    write_stderr,
};

// Binder ioctl request codes (aarch64)
const BINDER_SET_CONTEXT_MGR: c_ulong = 0x4004_6207;
const BINDER_SET_CONTEXT_MGR_EXT: c_ulong = 0x4018_620d;
const MAX_CONTEXT_MGR_RETRIES: i32 = 120;
const RETRY_DELAY_NS: i64 = 500_000_000;

extern "C" fn on_load() {
    write_stderr("=== sm_stab3 loaded ===\n");
}

#[used]
#[unsafe(link_section = ".init_array")]
static INIT_ARRAY: extern "C" fn() = on_load;

static OPENAT_HOOK_LOGGED: AtomicBool = AtomicBool::new(false);
static STAT_HOOK_LOGGED: AtomicBool = AtomicBool::new(false);

fn is_vintf_or_partition_path(path: *const c_char) -> bool {
    unsafe {
        cstr_starts_with(path, b"/vendor")
            || cstr_starts_with(path, b"/apex")
            || cstr_starts_with(path, b"/odm")
            || cstr_starts_with(path, b"/product")
            || cstr_starts_with(path, b"/system_ext")
            || cstr_starts_with(path, b"/system/etc/vintf")
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn __android_log_buf_write(
    _buf_id: c_int,
    _prio: c_int,
    tag: *const c_char,
    msg: *const c_char,
) -> c_int {
    unsafe { log_android_message("[SM LOG] ", tag, msg) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn __android_log_print(
    _prio: c_int,
    tag: *const c_char,
    fmt: *const c_char,
    arg1: *const c_char,
) -> c_int {
    write_stderr("[SM LOG] ");
    if !tag.is_null() {
        unsafe { write_cstr_stderr(tag) };
        write_stderr(":");
    }
    if !fmt.is_null() {
        unsafe { write_cstr_stderr(fmt) };
    }
    if (arg1 as usize) > 4096 {
        write_stderr(" -> ");
        unsafe { write_cstr_stderr(arg1) };
    }
    write_stderr("\n");
    1
}

/// `android::internal::Stability::requiresVintfDeclaration(android::sp<android::IBinder> const&)`
#[unsafe(no_mangle)]
pub extern "C" fn _ZN7android8internal9Stability24requiresVintfDeclarationERKNS_2spINS_7IBinderEEE(
    _sp: *mut c_void,
) -> u8 {
    0
}

/// `android::internal::Stability::check(short, android::internal::Stability::Level)`
#[unsafe(no_mangle)]
pub extern "C" fn _ZN7android8internal9Stability5checkEsNS1_5LevelE(
    _provided: c_short,
    _required: c_int,
) -> c_int {
    0
}

/// `android::vintf::VintfObject::fetchDeviceHalManifest(HalManifest*, std::__1::basic_string<char>*)`
#[unsafe(no_mangle)]
pub unsafe extern "C" fn _ZN7android5vintf11VintfObject22fetchDeviceHalManifestEPNS0_11HalManifestEPNSt3__112basic_stringIcNS4_11char_traitsIcEENS4_9allocatorIcEEEE(
    self_ptr: *mut c_void,
    manifest: *mut c_void,
    error_out: *mut c_void,
) -> c_int {
    write_stderr("[SM] fetchDeviceHalManifest enter\n");
    let ret = unsafe { fetch_device_hal_manifest_bypass(self_ptr, manifest, error_out, None) };
    if ret == 0 {
        write_stderr("[SM] fetchDeviceHalManifest OK\n");
    } else {
        write_stderr("[SM] fetchDeviceHalManifest FAIL r=");
        write_int_stderr(ret as i64);
    }
    ret
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ioctl(fd: c_int, request: c_ulong, arg: usize) -> c_int {
    type IoctlFn = unsafe extern "C" fn(c_int, c_ulong, usize) -> c_int;
    type PropSetFn = unsafe extern "C" fn(*const c_char, *const c_char) -> c_int;
    static REAL_IOCTL: AtomicPtr<c_void> = AtomicPtr::new(core::ptr::null_mut());
    static REAL_PROP_SET: AtomicPtr<c_void> = AtomicPtr::new(core::ptr::null_mut());

    let Some(ptr) = (unsafe { resolve_cached(&REAL_IOCTL, b"ioctl\0") }) else {
        return -1;
    };
    let real_ioctl = unsafe { core::mem::transmute::<*mut c_void, IoctlFn>(ptr) };

    let mut ret = unsafe { real_ioctl(fd, request, arg) };
    if request == BINDER_SET_CONTEXT_MGR || request == BINDER_SET_CONTEXT_MGR_EXT {
        if ret != 0 {
            write_stderr("[SM] CM failed, retrying...\n");
            let mut attempt = 0;
            while ret != 0 && attempt < MAX_CONTEXT_MGR_RETRIES {
                unsafe { sys_nanosleep(0, RETRY_DELAY_NS) };
                ret = unsafe { real_ioctl(fd, request, arg) };
                attempt += 1;
            }
        }
        if ret == 0 {
            write_stderr("[SM] became CM!\n");
            if let Some(pset_ptr) =
                unsafe { resolve_cached(&REAL_PROP_SET, b"__system_property_set\0") }
            {
                let prop_set = unsafe { core::mem::transmute::<*mut c_void, PropSetFn>(pset_ptr) };
                unsafe {
                    prop_set(
                        b"servicemanager.ready\0".as_ptr().cast::<c_char>(),
                        b"true\0".as_ptr().cast::<c_char>(),
                    );
                }
                write_stderr("[SM] servicemanager.ready=true set\n");
            }
        } else {
            write_stderr("[SM] CM GAVE UP\n");
        }
    }
    ret
}

#[unsafe(no_mangle)]
pub extern "C" fn abort() -> ! {
    write_stderr("[SM] ABORT - spinning\n");
    loop {
        unsafe { core::arch::asm!("wfi", options(nostack, nomem)) };
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn __system_property_set(
    name: *const c_char,
    value: *const c_char,
) -> c_int {
    type PropSetFn = unsafe extern "C" fn(*const c_char, *const c_char) -> c_int;
    static REAL_PROP_SET: AtomicPtr<c_void> = AtomicPtr::new(core::ptr::null_mut());

    let Some(ptr) = (unsafe { resolve_cached(&REAL_PROP_SET, b"__system_property_set\0") }) else {
        return -1;
    };
    let real_prop_set = unsafe { core::mem::transmute::<*mut c_void, PropSetFn>(ptr) };

    if unsafe { cstr_eq(name, b"servicemanager.ready") }
        && !value.is_null()
        && unsafe { *value.cast::<u8>() == b'f' }
    {
        write_stderr("[SM] BLOCKED prop servicemanager.ready=false\n");
        return 0;
    }
    unsafe { real_prop_set(name, value) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn open(path: *const c_char, flags: c_int, mode: c_uint) -> c_int {
    type OpenFn = unsafe extern "C" fn(*const c_char, c_int, ...) -> c_int;
    static REAL_OPEN: AtomicPtr<c_void> = AtomicPtr::new(core::ptr::null_mut());

    let fd = match unsafe { resolve_cached(&REAL_OPEN, b"open\0") } {
        Some(ptr) => {
            let real_open = unsafe { core::mem::transmute::<*mut c_void, OpenFn>(ptr) };
            if (flags & O_CREAT) != 0 {
                unsafe { real_open(path, flags, mode) }
            } else {
                unsafe { real_open(path, flags) }
            }
        }
        None => -1,
    };
    if is_vintf_or_partition_path(path) {
        write_stderr("[SM OPEN] ");
        unsafe { write_cstr_stderr(path) };
        write_stderr(if fd < 0 { " FAIL\n" } else { " OK\n" });
    }
    fd
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn openat(
    dirfd: c_int,
    path: *const c_char,
    flags: c_int,
    mode: c_uint,
) -> c_int {
    type OpenatFn = unsafe extern "C" fn(c_int, *const c_char, c_int, ...) -> c_int;
    static REAL_OPENAT: AtomicPtr<c_void> = AtomicPtr::new(core::ptr::null_mut());

    if !OPENAT_HOOK_LOGGED.swap(true, Ordering::Relaxed) {
        write_stderr("[SM OAT] hook active\n");
    }

    let fd = match unsafe { resolve_cached(&REAL_OPENAT, b"openat\0") } {
        Some(ptr) => {
            let real_openat = unsafe { core::mem::transmute::<*mut c_void, OpenatFn>(ptr) };
            if (flags & O_CREAT) != 0 {
                unsafe { real_openat(dirfd, path, flags, mode) }
            } else {
                unsafe { real_openat(dirfd, path, flags) }
            }
        }
        None => -1,
    };

    if fd < 0 {
        let err = unsafe { sys_openat(dirfd, path, flags) };
        if err >= 0 {
            unsafe { sys_close(err) };
        }
        if err == -(ELOOP_ERRNO as isize) {
            write_stderr("[SM ELOOP openat] p=");
            if path.is_null() {
                write_stderr("(null)");
            } else {
                unsafe { write_cstr_stderr(path) };
            }
            write_stderr("\n");
        } else if is_vintf_or_partition_path(path) {
            write_stderr("[SM OAT FAIL] ");
            unsafe { write_cstr_stderr(path) };
            write_stderr(" errno=");
            write_int_stderr(err as i64);
        }
    } else if is_vintf_or_partition_path(path) {
        write_stderr("[SM OAT OK] ");
        unsafe { write_cstr_stderr(path) };
        write_stderr("\n");
    }
    fd
}

fn trace_stat(
    path: *const c_char,
    stat_buf: *mut c_void,
    flags: i32,
    real_sym: &[u8],
    tag: &str,
) -> c_int {
    type StatFn = unsafe extern "C" fn(*const c_char, *mut c_void) -> c_int;
    let ret = match unsafe { resolve_next_symbol(real_sym) } {
        Some(ptr) => {
            let real_fn = unsafe { core::mem::transmute::<*mut c_void, StatFn>(ptr) };
            unsafe { real_fn(path, stat_buf) }
        }
        None => -1,
    };
    if ret < 0 {
        let mut tmp_stat = [0u8; 512];
        let err = unsafe { sys_newfstatat(AT_FDCWD, path, tmp_stat.as_mut_ptr(), flags) };
        if err == -(ELOOP_ERRNO as isize) {
            write_stderr(tag);
            if path.is_null() {
                write_stderr("(null)");
            } else {
                unsafe { write_cstr_stderr(path) };
            }
            write_stderr("\n");
        } else if flags == 0 && is_vintf_or_partition_path(path) {
            write_stderr("[SM STAT FAIL] ");
            unsafe { write_cstr_stderr(path) };
            write_stderr(" errno=");
            write_int_stderr(err as i64);
        }
    }
    ret
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn stat(path: *const c_char, stat_buf: *mut c_void) -> c_int {
    if !STAT_HOOK_LOGGED.swap(true, Ordering::Relaxed) {
        write_stderr("[SM STAT] hook active\n");
    }
    trace_stat(path, stat_buf, 0, b"stat\0", "[SM ELOOP stat] ")
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn lstat(path: *const c_char, stat_buf: *mut c_void) -> c_int {
    trace_stat(
        path,
        stat_buf,
        AT_SYMLINK_NOFOLLOW,
        b"lstat\0",
        "[SM ELOOP lstat] ",
    )
}
