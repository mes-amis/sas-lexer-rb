use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;
use std::sync::Mutex;
use sas_lexer::{lex_program, TokenIdx};

// Thread-local storage for the last error message
thread_local! {
    static LAST_ERROR: Mutex<Option<String>> = Mutex::new(None);
}

/// Error codes for the FFI interface
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum SasLexerError {
    Success = 0,
    NullPointer = 1,
    InvalidUtf8 = 2,
    LexingError = 3,
    IndexOutOfBounds = 4,
    TokenNotFound = 5,
    BufferNotInitialized = 6,
}

impl SasLexerError {
    fn set_last_error(&self, details: Option<String>) {
        let message = match self {
            SasLexerError::Success => return, // Don't set error for success
            SasLexerError::NullPointer => "Null pointer provided".to_string(),
            SasLexerError::InvalidUtf8 => "Invalid UTF-8 in input string".to_string(),
            SasLexerError::LexingError => format!("Failed to lex SAS code{}",
                details.as_ref().map(|s| format!(": {}", s)).unwrap_or_default()),
            SasLexerError::IndexOutOfBounds => format!("Token index out of bounds{}",
                details.as_ref().map(|s| format!(": {}", s)).unwrap_or_default()),
            SasLexerError::TokenNotFound => "Token not found in buffer".to_string(),
            SasLexerError::BufferNotInitialized => "Token buffer not initialized - call tokenize first".to_string(),
        };

        LAST_ERROR.with(|e| {
            *e.lock().unwrap() = Some(message);
        });
    }
}

/// Get the last error message as a C string
/// The caller must free the returned string using sas_lexer_free_string
#[no_mangle]
pub extern "C" fn sas_lexer_get_last_error() -> *mut c_char {
    LAST_ERROR.with(|e| {
        let error = e.lock().unwrap();
        match &*error {
            Some(msg) => {
                match CString::new(msg.as_str()) {
                    Ok(c_string) => c_string.into_raw(),
                    Err(_) => ptr::null_mut(),
                }
            }
            None => ptr::null_mut(),
        }
    })
}

/// Clear the last error message
#[no_mangle]
pub extern "C" fn sas_lexer_clear_error() {
    LAST_ERROR.with(|e| {
        *e.lock().unwrap() = None;
    });
}

/// A structure to hold comprehensive token metadata
#[repr(C)]
pub struct SasToken {
    pub token_type: u32,
    pub channel: u8,
    pub start: usize,
    pub end: usize,
    pub start_line: u32,
    pub end_line: u32,
    pub start_column: u32,
    pub end_column: u32,
}

/// A structure to hold the lexer state and results
#[repr(C)]
pub struct SasLexer {
    buffer: Option<sas_lexer::TokenizedBuffer>,
    source: Option<String>,
    tokens: Vec<TokenIdx>,
    current_index: usize,
}

/// Create a new SAS lexer instance
#[no_mangle]
pub extern "C" fn sas_lexer_new() -> *mut SasLexer {
    let lexer = Box::new(SasLexer {
        buffer: None,
        source: None,
        tokens: Vec::new(),
        current_index: 0,
    });
    Box::into_raw(lexer)
}

/// Free a SAS lexer instance
#[no_mangle]
pub extern "C" fn sas_lexer_free(lexer: *mut SasLexer) {
    if !lexer.is_null() {
        unsafe {
            drop(Box::from_raw(lexer));
        }
    }
}

/// Tokenize SAS code
/// Returns SasLexerError enum value
#[no_mangle]
pub extern "C" fn sas_lexer_tokenize(lexer: *mut SasLexer, code: *const c_char) -> SasLexerError {
    if lexer.is_null() || code.is_null() {
        let error = SasLexerError::NullPointer;
        error.set_last_error(None);
        return error;
    }

    let code_str = unsafe {
        match CStr::from_ptr(code).to_str() {
            Ok(s) => s,
            Err(e) => {
                let error = SasLexerError::InvalidUtf8;
                error.set_last_error(Some(e.to_string()));
                return error;
            }
        }
    };

    let lexer_ref = unsafe { &mut *lexer };

    match lex_program(&code_str) {
        Ok(result) => {
            let tokens: Vec<TokenIdx> = result.buffer.iter_tokens().collect();
            lexer_ref.buffer = Some(result.buffer);
            lexer_ref.source = Some(code_str.to_string());
            lexer_ref.tokens = tokens;
            lexer_ref.current_index = 0;
            SasLexerError::Success
        }
        Err(e) => {
            let error = SasLexerError::LexingError;
            error.set_last_error(Some(format!("{:?}", e)));
            error
        }
    }
}

/// Get the number of tokens
#[no_mangle]
pub extern "C" fn sas_lexer_token_count(lexer: *const SasLexer) -> usize {
    if lexer.is_null() {
        return 0;
    }

    let lexer_ref = unsafe { &*lexer };
    lexer_ref.tokens.len()
}

/// Get a token by index with full metadata
#[no_mangle]
pub extern "C" fn sas_lexer_get_token(
    lexer: *const SasLexer,
    index: usize,
    token_out: *mut SasToken
) -> SasLexerError {
    if lexer.is_null() || token_out.is_null() {
        let error = SasLexerError::NullPointer;
        error.set_last_error(None);
        return error;
    }

    let lexer_ref = unsafe { &*lexer };

    if index >= lexer_ref.tokens.len() {
        let error = SasLexerError::IndexOutOfBounds;
        error.set_last_error(Some(format!("index {} >= token count {}", index, lexer_ref.tokens.len())));
        return error;
    }

    if let Some(buffer) = &lexer_ref.buffer {
        let token_idx = lexer_ref.tokens[index];

        // Get all token metadata
        let token_type = buffer.get_token_type(token_idx);
        let channel = buffer.get_token_channel(token_idx);
        let start = buffer.get_token_start(token_idx);
        let end = buffer.get_token_end(token_idx);
        let start_line = buffer.get_token_start_line(token_idx);
        let end_line = buffer.get_token_end_line(token_idx);
        let start_column = buffer.get_token_start_column(token_idx);
        let end_column = buffer.get_token_end_column(token_idx);

        // Check if all queries succeeded
        if let (Ok(tt), Ok(ch), Ok(s), Ok(e), Ok(sl), Ok(el), Ok(sc), Ok(ec)) =
            (token_type, channel, start, end, start_line, end_line, start_column, end_column) {
            unsafe {
                (*token_out).token_type = tt as u32;
                (*token_out).channel = ch as u8;
                (*token_out).start = s.get() as usize;
                (*token_out).end = e.get() as usize;
                (*token_out).start_line = sl;
                (*token_out).end_line = el;
                (*token_out).start_column = sc;
                (*token_out).end_column = ec;
            }
            return SasLexerError::Success;
        } else {
            let error = SasLexerError::TokenNotFound;
            error.set_last_error(None);
            return error;
        }
    }

    let error = SasLexerError::BufferNotInitialized;
    error.set_last_error(None);
    error
}

/// Get token text by index
#[no_mangle]
pub extern "C" fn sas_lexer_get_token_text(
    lexer: *const SasLexer,
    index: usize
) -> *mut c_char {
    if lexer.is_null() {
        let error = SasLexerError::NullPointer;
        error.set_last_error(Some("lexer pointer is null".to_string()));
        return ptr::null_mut();
    }

    let lexer_ref = unsafe { &*lexer };

    if index >= lexer_ref.tokens.len() {
        let error = SasLexerError::IndexOutOfBounds;
        error.set_last_error(Some(format!("index {} >= token count {}", index, lexer_ref.tokens.len())));
        return ptr::null_mut();
    }

    if let (Some(buffer), Some(source)) = (&lexer_ref.buffer, &lexer_ref.source) {
        let token_idx = lexer_ref.tokens[index];
        match buffer.get_token_raw_text(token_idx, source) {
            Ok(Some(text)) => {
                if let Ok(c_string) = CString::new(text) {
                    return c_string.into_raw();
                }
            }
            Ok(None) => {
                // Empty range, return empty string
                if let Ok(c_string) = CString::new("") {
                    return c_string.into_raw();
                }
            }
            Err(e) => {
                let error = SasLexerError::TokenNotFound;
                error.set_last_error(Some(format!("Failed to get token text: {:?}", e)));
                return ptr::null_mut();
            }
        }
    }

    let error = SasLexerError::BufferNotInitialized;
    error.set_last_error(None);
    ptr::null_mut()
}

/// Free a string returned by sas_lexer_get_token_text or sas_lexer_get_last_error
#[no_mangle]
pub extern "C" fn sas_lexer_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            drop(CString::from_raw(s));
        }
    }
}