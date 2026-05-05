# sas-lexer

A Ruby gem that wraps the [`sas-lexer`](https://github.com/mishamsk/sas-lexer) Rust crate through the [FFI](https://github.com/ffi/ffi) interface. Tokenizes SAS source code into a stream of typed tokens with full position metadata.

This gem is a thin Ruby binding only — all lexing logic lives in the upstream Rust crate. The gem ships prebuilt native shims for supported platforms; a runtime loader picks the matching one for the host.

## Installation

Add to your Gemfile:

```ruby
gem "sas-lexer"
```

Or install directly:

```sh
gem install sas-lexer
```

## Usage

```ruby
require "sas_lexer"

lexer = SasLexer::Lexer.new
tokens = lexer.tokenize("data test; set input; run;")
lexer.free  # release the underlying Rust buffers

tokens.each do |t|
  puts "#{t[:start_line]}:#{t[:start_column]}  type=#{t[:type]}  text=#{t[:text].inspect}"
end
```

Each token is a hash with the following keys:

| key             | description                                           |
| --------------- | ----------------------------------------------------- |
| `:index`        | 0-based position in the token stream                  |
| `:text`         | raw source text the token spans                       |
| `:type`         | token type integer (see `SasLexer::Lexer::TokenType`) |
| `:channel`      | `0` default, `1` hidden (whitespace), `2` comment     |
| `:start`        | byte offset of token start in the source              |
| `:end`          | byte offset of token end                              |
| `:start_line`   | 1-based line number of token start                    |
| `:end_line`     | 1-based line number of token end                      |
| `:start_column` | 0-based column number of token start                  |
| `:end_column`   | 0-based column number of token end                    |

Constants for token types and channels are exposed under `SasLexer::Lexer::TokenType` and `SasLexer::Lexer::TokenChannel`. They mirror the enums in `crates/sas-lexer/src/lexer/token_type.rs` of the upstream Rust crate.

## Native library loading

`SasLexer::Lexer` probes for a shared library in this order:

1. `lib/native/<platform>/libsas_lexer_ffi.{so,dylib,dll}` — the prebuilt shipped inside the published universal gem for the host's platform.
2. `lib/native/libsas_lexer_ffi.{so,dylib,dll}` — the flat path produced by `bundle exec rake sas_lexer:install` for local development.

If neither is found, `require "sas_lexer"` raises `SasLexer::Error` immediately. `SasLexer::Lexer::LIBRARY_PATH` exposes the resolved path.

## Building from source

You only need to build from source when contributing a prebuilt for a new platform — the published gem already ships every committed platform's artifact.

Prerequisites:

- Rust toolchain (https://rustup.rs/)
- Ruby 3.4+

```sh
bundle install
bundle exec rake sas_lexer:install
```

This:

1. Clones the upstream `sas-lexer` repo into `vendor/sas-lexer/`.
2. Compiles the FFI shim under `ffi-wrapper/` against it.
3. Installs the resulting shared library at `lib/native/libsas_lexer_ffi.<ext>`.

To ship the artifact in the universal gem, move it under `lib/native/<platform>/` and commit it:

```sh
mkdir -p lib/native/$(ruby -e 'puts RUBY_PLATFORM')
mv lib/native/libsas_lexer_ffi.* lib/native/$(ruby -e 'puts RUBY_PLATFORM')/
git add lib/native/$(ruby -e 'puts RUBY_PLATFORM')/
```

To cross-build an `x86_64-linux` `.so` from any host (typically macOS), use the Docker helper:

```sh
bin/build_linux_extension
```

## Testing

```sh
bundle exec rake spec
```

## Why a universal gem (not platform-tagged)?

The published gem is `platform: ruby` and ships every committed `lib/native/<platform>/` together. The loader globs at runtime to pick the matching one. Empirically, platform-tagged gems served from some private registries can be served under the generic `<gem>-<version>.gem` URL too, which causes Bundler to lock the version without a platform suffix and then fail to materialize at install time. A single universal gem sidesteps that failure mode at the cost of ~1–2 MB extra per platform shipped.

There is no source-build fallback at install time — a host without a committed prebuilt for its platform fails fast at FFI load.

## License

`sas-lexer` (the gem) is licensed under the [GNU Affero General Public License v3.0 or later](LICENSE), matching the upstream Rust crate. See `LICENSE` for the full text.

The upstream Rust crate is © Misha Perlov. The FFI shim and Ruby binding in this repository are © Mon Ami, Inc.
