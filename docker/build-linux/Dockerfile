# Build the sas-lexer FFI wrapper as an x86_64-linux .so. The image
# itself runs on the host's native architecture (arm64 on Apple
# Silicon, amd64 on Linux x86_64 hosts) — no qemu-user emulation —
# and Rust cross-compiles to `x86_64-unknown-linux-gnu` via the
# multilib cross-linker installed below. That sidesteps the QEMU +
# Rust 1.95 SIGSEGV that surfaces when amd64 images are emulated on
# arm64 hosts.
#
# `bin/build_linux_extension` extracts
# `/build/ffi-wrapper/target/x86_64-unknown-linux-gnu/release/libsas_lexer_ffi.so`
# and writes it to the host's `lib/native/x86_64-linux/`.

FROM rust:1-bullseye

RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc-x86-64-linux-gnu \
      libc6-dev-amd64-cross \
      git \
      ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN rustup target add x86_64-unknown-linux-gnu

ENV CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=x86_64-linux-gnu-gcc

ARG SAS_LEXER_REPO=https://github.com/craigmcnamara/sas-lexer.git
ARG SAS_LEXER_BRANCH=main

WORKDIR /build

# Clone sas-lexer with shallow history — we only need the source.
RUN git clone --branch "$SAS_LEXER_BRANCH" --depth 1 "$SAS_LEXER_REPO" /build/vendor/sas-lexer

# ffi-wrapper's Cargo.toml references `../vendor/sas-lexer/...` as a
# path dependency, so the relative layout inside the container has to
# match the host's. Copy ffi-wrapper LAST so a docs-only edit there
# doesn't bust the sas-lexer clone cache.
COPY ffi-wrapper /build/ffi-wrapper

WORKDIR /build/ffi-wrapper
RUN cargo build --release --target x86_64-unknown-linux-gnu
