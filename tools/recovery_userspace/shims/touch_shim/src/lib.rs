#![no_std]
#![allow(non_snake_case)]

use core::ffi::{c_char, c_int, c_short, c_uint, c_void};
use core::sync::atomic::AtomicPtr;
use shim_common::{
    O_CREAT, cstr_contains, cstr_starts_with, fetch_device_hal_manifest_bypass,
    log_android_message, resolve_cached, resolve_next_symbol, sys_exit_thread, write_cstr_stderr,
    write_stderr,
};

extern "C" fn on_load() {
    write_stderr("=== touch_shim loaded ===\n");
}

#[used]
#[unsafe(link_section = ".init_array")]
static INIT_ARRAY: extern "C" fn() = on_load;

#[unsafe(no_mangle)]
pub unsafe extern "C" fn __android_log_buf_write(
    _buf_id: c_int,
    _prio: c_int,
    tag: *const c_char,
    msg: *const c_char,
) -> c_int {
    unsafe { log_android_message("[TF LOG] ", tag, msg) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn __android_log_write(
    _prio: c_int,
    tag: *const c_char,
    msg: *const c_char,
) -> c_int {
    unsafe { log_android_message("[TF LOG] ", tag, msg) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn __android_log_print(
    _prio: c_int,
    tag: *const c_char,
    fmt: *const c_char,
) -> c_int {
    unsafe { log_android_message("[TF LOG] ", tag, fmt) }
}

/// Kill only the calling thread so an auxiliary thread crash does not stop touch input.
#[unsafe(no_mangle)]
pub extern "C" fn abort() -> ! {
    write_stderr("[TF] ABORT - killing thread only\n");
    unsafe { sys_exit_thread(1) }
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
    unsafe {
        fetch_device_hal_manifest_bypass(
            self_ptr,
            manifest,
            error_out,
            Some("[TF] fetchDeviceHalManifest ELOOP->OK\n"),
        )
    }
}

/// Auxiliary HALs absent in recovery — return null immediately so worker threads never hang.
fn is_auxiliary_hal(service_name: *const c_char) -> bool {
    unsafe {
        cstr_contains(service_name, b"sensorservice")
            || cstr_contains(service_name, b"hardware.sensors")
            || cstr_contains(service_name, b"framecapturemanager")
            || cstr_contains(service_name, b"fingerprintextension")
            || cstr_contains(service_name, b"mtkpower")
    }
}

fn forward_service_lookup(
    service_name: *const c_char,
    sym_name: &[u8],
    log_prefix: &str,
) -> *mut c_void {
    type ServiceLookupFn = unsafe extern "C" fn(*const c_char) -> *mut c_void;
    write_stderr(log_prefix);
    unsafe { write_cstr_stderr(service_name) };
    write_stderr("\n");

    if is_auxiliary_hal(service_name) {
        write_stderr(log_prefix);
        write_stderr("-> NULL (aux, skipped)\n");
        return core::ptr::null_mut();
    }

    let result = match unsafe { resolve_next_symbol(sym_name) } {
        Some(ptr) => {
            let real_fn = unsafe { core::mem::transmute::<*mut c_void, ServiceLookupFn>(ptr) };
            unsafe { real_fn(service_name) }
        }
        None => core::ptr::null_mut(),
    };

    write_stderr(log_prefix);
    write_stderr(if result.is_null() {
        "-> NULL\n"
    } else {
        "-> FOUND\n"
    });
    result
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn AServiceManager_waitForService(
    service_name: *const c_char,
) -> *mut c_void {
    forward_service_lookup(service_name, b"AServiceManager_waitForService\0", "[TF WFS] ")
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn AServiceManager_getService(service_name: *const c_char) -> *mut c_void {
    forward_service_lookup(service_name, b"AServiceManager_getService\0", "[TF GET] ")
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn AServiceManager_checkService(service_name: *const c_char) -> *mut c_void {
    forward_service_lookup(service_name, b"AServiceManager_checkService\0", "[TF CHK] ")
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn AServiceManager_addService(
    binder: *mut c_void,
    service_name: *const c_char,
) -> c_int {
    type AddServiceFn = unsafe extern "C" fn(*mut c_void, *const c_char) -> c_int;
    static REAL_ADD_SERVICE: AtomicPtr<c_void> = AtomicPtr::new(core::ptr::null_mut());

    write_stderr("[TF ADD] ");
    unsafe { write_cstr_stderr(service_name) };
    write_stderr("\n");

    let ret = match unsafe { resolve_cached(&REAL_ADD_SERVICE, b"AServiceManager_addService\0") } {
        Some(ptr) => {
            let real_fn = unsafe { core::mem::transmute::<*mut c_void, AddServiceFn>(ptr) };
            unsafe { real_fn(binder, service_name) }
        }
        None => -1,
    };
    write_stderr(if ret == 0 {
        "[TF ADD] -> OK\n"
    } else {
        "[TF ADD] -> FAIL\n"
    });
    ret
}

fn is_touch_hardware_path(path: *const c_char) -> bool {
    unsafe {
        cstr_starts_with(path, b"/dev/xiaomi-touch")
            || cstr_starts_with(path, b"/dev/xiaomi-thp")
            || cstr_starts_with(path, b"/dev/input")
            || cstr_starts_with(path, b"/dev/uinput")
            || cstr_starts_with(path, b"/sys/class/touch")
            || cstr_starts_with(path, b"/proc/tp_")
    }
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
    if is_touch_hardware_path(path) {
        write_stderr("[TF OPEN] ");
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
    if is_touch_hardware_path(path) {
        write_stderr("[TF OAT] ");
        unsafe { write_cstr_stderr(path) };
        write_stderr(if fd < 0 { " FAIL\n" } else { " OK\n" });
    }
    fd
}
