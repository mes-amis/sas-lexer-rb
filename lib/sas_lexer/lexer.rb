# frozen_string_literal: true

require "ffi"

module SasLexer
  # Ruby wrapper around the `sas-lexer` Rust crate, accessed through
  # the small C ABI shim built from `ffi-wrapper/`.
  #
  # Loads the prebuilt shared library shipped under `lib/native/` (or
  # the dev-build flat path produced by `rake sas_lexer:install`).
  class Lexer
    extend FFI::Library

    gem_root = File.expand_path("../..", __dir__)
    lib_native_dir = File.join(gem_root, "lib", "native")

    host_os = case RbConfig::CONFIG["host_os"]
              when /darwin/ then "darwin"
              when /linux/ then "linux"
              when /mswin|mingw|cygwin/ then "windows"
              else
                raise SasLexer::Error,
                      "Unsupported host OS: #{RbConfig::CONFIG["host_os"]}"
              end

    library_ext = { "darwin" => "dylib", "linux" => "so", "windows" => "dll" }.fetch(host_os)
    host_platform = "#{RbConfig::CONFIG["host_cpu"]}-#{host_os}"

    # Probe order:
    #   1. `lib/native/<host_cpu>-<host_os>/libsas_lexer_ffi.<ext>` —
    #      prebuilt artifact shipped inside the published universal gem
    #      for the host's exact platform.
    #   2. `lib/native/libsas_lexer_ffi.<ext>` — flat path produced
    #      by `bundle exec rake sas_lexer:install` for local
    #      development.
    LIBRARY_PATH = [
      File.join(lib_native_dir, host_platform, "libsas_lexer_ffi.#{library_ext}"),
      File.join(lib_native_dir, "libsas_lexer_ffi.#{library_ext}"),
    ].find { |path| File.exist?(path) }

    if LIBRARY_PATH.nil?
      raise SasLexer::Error,
            "Could not find a prebuilt sas-lexer FFI library at " \
            "lib/native/#{host_platform}/libsas_lexer_ffi.#{library_ext}. " \
            "Build one with `bundle exec rake sas_lexer:install` " \
            "or add a prebuilt for #{host_platform} under lib/native/."
    end

    ffi_lib LIBRARY_PATH

    # FFI struct mirroring the `SasToken` C struct in `ffi-wrapper/src/lib.rs`.
    class Token < FFI::Struct
      layout :token_type, :uint32,
             :channel, :uint8,
             :start, :size_t,
             :end, :size_t,
             :start_line, :uint32,
             :end_line, :uint32,
             :start_column, :uint32,
             :end_column, :uint32
    end

    attach_function :sas_lexer_new, [], :pointer
    attach_function :sas_lexer_free, [:pointer], :void
    attach_function :sas_lexer_tokenize, [:pointer, :string], :int
    attach_function :sas_lexer_token_count, [:pointer], :size_t
    attach_function :sas_lexer_get_token, [:pointer, :size_t, :pointer], :int
    attach_function :sas_lexer_get_token_text, [:pointer, :size_t], :pointer
    attach_function :sas_lexer_free_string, [:pointer], :void
    attach_function :sas_lexer_get_last_error, [], :pointer
    attach_function :sas_lexer_clear_error, [], :void

    # Error code values returned by the C ABI.
    module ErrorCode
      SUCCESS = 0
      NULL_POINTER = 1
      INVALID_UTF8 = 2
      LEXING_ERROR = 3
      INDEX_OUT_OF_BOUNDS = 4
      TOKEN_NOT_FOUND = 5
      BUFFER_NOT_INITIALIZED = 6
    end

    # Token channels — match the `TokenChannel` enum in the Rust crate.
    module TokenChannel
      DEFAULT = 0  # Most tokens (keywords, identifiers, operators, etc.)
      HIDDEN = 1   # Whitespace and other insignificant tokens
      COMMENT = 2  # All comment tokens
    end

    # Token type constants — match the `TokenType` enum in the Rust crate.
    # Full enum: https://github.com/mishamsk/sas-lexer/blob/main/crates/sas-lexer/src/lexer/token_type.rs
    module TokenType
      # Special tokens
      EOF = 0
      MACRO_SEP = 1
      CATCH_ALL = 2
      WS = 3
      WHITESPACE = 3  # Alias for WS

      # Punctuation and operators
      SEMI = 4          # ';'
      AMP = 5           # '&'
      PERCENT = 6       # '%'
      LPAREN = 7        # '('
      RPAREN = 8        # ')'
      LCURLY = 9        # '{'
      RCURLY = 10       # '}'
      LBRACK = 11       # '['
      RBRACK = 12       # ']'
      STAR = 13         # '*'
      EXCL = 14         # '!'
      EXCL2 = 15        # '!!'
      BPIPE = 16        # '!|'
      BPIPE2 = 17       # '!|!'
      PIPE2 = 18        # '||'
      STAR2 = 19        # '**'
      NOT = 20          # '¬' or '^'
      FSLASH = 21       # '/'
      PLUS = 22         # '+'
      MINUS = 23        # '-'
      GTLT = 24         # '><'
      LTGT = 25         # '<>'
      LT = 26           # '<'
      LE = 27           # '<='
      NE = 28           # '!=' or '^='
      GT = 29           # '>'
      GE = 30           # '>='
      SOUNDS_LIKE = 31  # '=*'
      PIPE = 32         # '|'
      DOT = 33          # '.'
      COMMA = 34        # ','
      COLON = 35        # ':'
      ASSIGN = 36       # '='
      DOLLAR = 37       # '$'
      AT = 38           # '@'
      HASH = 39         # '#'
      QUESTION = 40     # '?'

      # Logical operators (mnemonic keywords)
      KW_LT = 41        # LT
      KW_LE = 42        # LE
      KW_EQ = 43        # EQ
      KW_IN = 44        # IN
      KW_NE = 45        # NE
      KW_GT = 46        # GT
      KW_GE = 47        # GE
      KW_AND = 48       # AND
      KW_OR = 49        # OR
      KW_NOT = 50       # NOT

      # Literals
      INTEGER_LITERAL = 51
      FLOAT_LITERAL = 52
      FLOAT_EXPONENT_LITERAL = 53
      STRING_LITERAL = 54
      BIT_TESTING_LITERAL = 55
      DATE_LITERAL = 56
      DATE_TIME_LITERAL = 57
      NAME_LITERAL = 58
      TIME_LITERAL = 59
      HEX_STRING_LITERAL = 60
      STRING_EXPR_START = 61
      STRING_EXPR_TEXT = 62
      STRING_EXPR_END = 63
      BIT_TESTING_LITERAL_EXPR_END = 64
      DATE_LITERAL_EXPR_END = 65
      DATE_TIME_LITERAL_EXPR_END = 66
      NAME_LITERAL_EXPR_END = 67
      TIME_LITERAL_EXPR_END = 68
      HEX_STRING_LITERAL_EXPR_END = 69

      # Comments
      C_STYLE_COMMENT = 70              # /* ... */
      PREDICTED_COMMENT_STAT = 71       # * ...; and ** ... **;
      COMMENT_STAT = 71                 # Alias for PREDICTED_COMMENT_STAT
      DATALINES_START = 72
      DATALINES_DATA = 73
      CHAR_FORMAT = 74
      MACRO_COMMENT = 75                # %* ...;
      MACRO_VAR_RESOLVE = 76
      MACRO_VAR_TERM = 77
      MACRO_STRING = 78
      MACRO_STRING_EMPTY = 79
      MACRO_LABEL = 80
      MACRO_IDENTIFIER = 81

      # Macro functions
      KWM_CMPRES = 82
      KWM_COMPSTOR = 83
      KWM_DATATYP = 84
      KWM_EVAL = 85
      KWM_INDEX = 86
      KWM_LEFT = 87
      KWM_LENGTH = 88
      KWM_LOWCASE = 89
      KWM_SCAN = 90
      KWM_SUBSTR = 91
      KWM_SYM_EXIST = 92
      KWM_SYM_GLOBL = 93
      KWM_SYM_LOCAL = 94
      KWM_SYSEVALF = 95
      KWM_SYSFUNC = 96
      KWM_SYSGET = 97
      KWM_SYSMACEXEC = 98
      KWM_SYSMACEXIST = 99
      KWM_SYSMEXECDEPTH = 100
      KWM_SYSMEXECNAME = 101
      KWM_SYSPROD = 102
      KWM_TRIM = 103
      KWM_UNQUOTE = 104
      KWM_UPCASE = 105
      KWM_VERIFY = 106
      KWM_K_CMPRES = 107
      KWM_K_INDEX = 108
      KWM_K_LEFT = 109
      KWM_K_LENGTH = 110
      KWM_K_LOWCASE = 111
      KWM_K_SCAN = 112
      KWM_K_SUBSTR = 113
      KWM_K_TRIM = 114
      KWM_K_UPCASE = 115
      KWM_K_VERIFY = 116
      KWM_VALIDCHS = 117
      KWM_Q_CMPRES = 118
      KWM_Q_LEFT = 119
      KWM_Q_LOWCASE = 120
      KWM_Q_SCAN = 121
      KWM_Q_SUBSTR = 122
      KWM_Q_TRIM = 123
      KWM_Q_SYSFUNC = 124
      KWM_Q_UPCASE = 125
      KWM_QK_CMPRES = 126
      KWM_QK_LEFT = 127
      KWM_QK_LOWCASE = 128
      KWM_QK_SCAN = 129
      KWM_QK_SUBSTR = 130
      KWM_QK_TRIM = 131
      KWM_QK_UPCASE = 132
      KWM_BQUOTE = 133
      KWM_NR_BQUOTE = 134
      KWM_NR_QUOTE = 135
      KWM_QUOTE = 136
      KWM_SUPERQ = 137
      KWM_STR = 138
      KWM_NR_STR = 139

      # Macro statements
      KWM_ABORT = 140
      KWM_COPY = 141
      KWM_DISPLAY = 142
      KWM_DO = 143
      KWM_TO = 144
      KWM_BY = 145
      KWM_UNTIL = 146
      KWM_WHILE = 147
      KWM_END = 148
      KWM_GLOBAL = 149
      KWM_GOTO = 150
      KWM_IF = 151
      KWM_THEN = 152
      KWM_ELSE = 153
      KWM_INPUT = 154
      KWM_LET = 155
      KWM_LOCAL = 156
      KWM_MACRO = 157
      KWM_MEND = 158
      KWM_PUT = 159
      KWM_RETURN = 160
      KWM_SYMDEL = 161
      KWM_SYSCALL = 162
      KWM_SYSEXEC = 163
      KWM_SYSLPUT = 164
      KWM_SYSMACDELETE = 165
      KWM_SYSMSTORECLEAR = 166
      KWM_SYSRPUT = 167
      KWM_WINDOW = 168
      KWM_INCLUDE = 169
      KWM_LIST = 170
      KWM_RUN = 171

      # Identifiers (variable names, dataset names, etc.)
      IDENTIFIER = 172

      # Additional keyword operators
      KW_EQT = 173
      KW_GTT = 174
      KW_LTT = 175
      KW_GET = 176
      KW_LET = 177
      KW_NET = 178

      # SAS statement keywords
      KW_LIBNAME = 179
      KW_FILENAME = 180
      KW_CLEAR = 181
      KW_LIST = 182
      KW_CANCEL = 183
      KW_ALL_VAR = 184
      KW_ARRAY = 185
      KW_ATTRIB = 186
      KW_CALL = 187
      KW_DATA = 188
      KW_DEFAULT = 189
      KW_DESCENDING = 190
      KW_FORMAT = 191
      KW_GROUPFORMAT = 192
      KW_ID = 193
      KW_IF = 194
      KW_INFILE = 195
      KW_INFORMAT = 196
      KW_KEEP = 197
      KW_LABEL = 198
      KW_LENGTH = 199
      KW_MERGE = 200
      KW_NULL_DATASET = 201
      KW_OUTPUT = 202
      KW_PGM = 203
      KW_RENAME = 204
      KW_RUN = 205
      KW_SET = 206
      KW_STOP = 207
      KW_VAR = 208
      KW_VIEW = 209
      KW_WITH = 210
      KW_DELETE = 211
      KW_NOTSORTED = 212
      KW_PROC = 213
      KW_QUIT = 214
      KW_RANKS = 215

      # SQL and other SAS keywords
      KW_ALL = 216
      KW_ANY = 217
      KW_AS = 218
      KW_ASC = 219
      KW_BETWEEN = 220
      KW_BOTH = 221
      KW_BTRIM = 222
      KW_BY = 223
      KW_CALCULATED = 224
      KW_CASE = 225
      KW_CONNECT = 226
      KW_CONNECTION = 227
      KW_CONTAINS = 228
      KW_CORR = 229
      KW_CREATE = 230
      KW_CROSS = 231
      KW_DESC = 232
      KW_DISCONNECT = 233
      KW_DISTINCT = 234
      KW_DO = 235
      KW_DROP = 236
      KW_ELSE = 237
      KW_END = 238
      KW_ESCAPE = 239
      KW_EXCEPT = 240
      KW_EXECUTE = 241
      KW_EXISTS = 242
      KW_FOR = 243
      KW_FROM = 244
      KW_FULL = 245
      KW_GROUP = 246
      KW_HAVING = 247
      KW_INDEX = 248
      KW_INNER = 249
      KW_INSERT = 250
      KW_INTERSECT = 251
      KW_INTO = 252
      KW_IS = 253
      KW_JOIN = 254
      KW_KEY = 255
      KW_LEADING = 256
      KW_LEFT = 257
      KW_LIKE = 258
      KW_MISSING = 259
      KW_NATURAL = 260
      KW_NOTRIM = 261
      KW_NULL = 262
      KW_ON = 263
      KW_ORDER = 264
      KW_OUTER = 265
      KW_PRIMARY = 266
      KW_RIGHT = 267
      KW_SELECT = 268
      KW_SEPARATED = 269
      KW_SUBSTRING = 270
      KW_TABLE = 271
      KW_THEN = 272
      KW_TO = 273
      KW_TRAILING = 274
      KW_TRIMMED = 275
      KW_UNION = 276
      KW_UNIQUE = 277
      KW_UPDATE = 278
      KW_USING = 279
      KW_VALUES = 280
      KW_WHEN = 281
      KW_WHERE = 282
      KW_DECLARE = 283
      KW_HASH = 284
      KW_HITER = 285
      KW_INPUT = 286
      KW_PUT = 287
    end

    def initialize
      @lexer_ptr = self.class.sas_lexer_new
      raise SasLexer::Error, "Failed to create SAS lexer" if @lexer_ptr.null?
    end

    def tokenize(sas_code)
      raise SasLexer::Error, "Lexer has been freed" if @lexer_ptr.null?
      raise SasLexer::Error, "Null pointer provided" if sas_code.nil?

      result = self.class.sas_lexer_tokenize(@lexer_ptr, sas_code)

      if result != ErrorCode::SUCCESS
        error_msg = get_last_error_message
        raise SasLexer::Error, error_msg || "Failed to tokenize SAS code (error code: #{result})"
      end

      token_count = self.class.sas_lexer_token_count(@lexer_ptr)

      tokens = []

      (0...token_count).each do |index|
        text_ptr = self.class.sas_lexer_get_token_text(@lexer_ptr, index)

        next if text_ptr.null?

        text = text_ptr.read_string

        token_struct = Token.new
        token_result = self.class.sas_lexer_get_token(@lexer_ptr, index, token_struct)

        if token_result == ErrorCode::SUCCESS
          tokens << {
            index: index,
            text: text,
            type: token_struct[:token_type],
            channel: token_struct[:channel],
            start: token_struct[:start],
            end: token_struct[:end],
            start_line: token_struct[:start_line],
            end_line: token_struct[:end_line],
            start_column: token_struct[:start_column],
            end_column: token_struct[:end_column]
          }
        else
          tokens << {
            index: index,
            text: text,
            type: nil,
            channel: nil
          }
        end

        self.class.sas_lexer_free_string(text_ptr)
      end

      tokens
    end

    def free
      return if @lexer_ptr.null?

      self.class.sas_lexer_free(@lexer_ptr)
      @lexer_ptr = FFI::Pointer::NULL
    end

    def finalize
      free
    end

    private

    def get_last_error_message
      error_ptr = self.class.sas_lexer_get_last_error
      return nil if error_ptr.null?

      begin
        error_ptr.read_string
      ensure
        self.class.sas_lexer_free_string(error_ptr)
      end
    end
  end
end
