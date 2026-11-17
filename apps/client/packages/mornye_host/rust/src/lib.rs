//! JSON/FFI boundary. Provider code runs in Mornye's permission-scoped QuickJS
//! host; the app's player, secure account store and SMB client stay in Dart.
use serde_json::{Value, json};
use std::ffi::{CStr, CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::{Arc, OnceLock};

mod host;
static HOST: OnceLock<Arc<host::Host>> = OnceLock::new();

fn dispatch(request: Value) -> Result<Value, String> {
    if request["op"] == "init" {
        if HOST.get().is_none() {
            let host = Arc::new(host::Host::new(&request)?);
            HOST.set(host).map_err(|_| "Host was already initialized")?;
        }
        return Ok(json!({"ready":true}));
    }
    HOST.get()
        .ok_or("Extension host is not initialized")?
        .call(&request)
}

/// Input is a NUL-terminated UTF-8 JSON string, owned by the caller. Output
/// remains owned by Rust until hyperstream_mornye_free is called exactly once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hyperstream_mornye_call(input: *const c_char) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if input.is_null() {
            return Err("Missing request".to_owned());
        }
        let raw = unsafe { CStr::from_ptr(input) }
            .to_str()
            .map_err(|_| "Invalid UTF-8")?;
        if raw.len() > 8 * 1024 * 1024 {
            return Err("Request is too large".into());
        }
        dispatch(serde_json::from_str(raw).map_err(|_| "Invalid JSON")?)
    }))
    .unwrap_or_else(|_| Err("Extension host failed; restart the app".into()));
    let value = match result {
        Ok(value) => json!({"ok":true,"value":value}),
        Err(error) => json!({"ok":false,"error":error}),
    };
    CString::new(value.to_string())
        .expect("JSON cannot contain literal NUL")
        .into_raw()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hyperstream_mornye_free(value: *mut c_char) {
    if !value.is_null() {
        drop(unsafe { CString::from_raw(value) });
    }
}
