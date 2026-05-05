# frozen_string_literal: true

require_relative "lib/sas_lexer/version"

Gem::Specification.new do |spec|
  spec.name = "sas-lexer"
  spec.version = SasLexer::VERSION
  spec.authors = ["Craig McNamara"]
  spec.email = ["craig@monami.io"]

  spec.summary = "Ruby FFI wrapper around the sas-lexer Rust crate."
  spec.description = <<~DESC
    A Ruby FFI binding to the `sas-lexer` Rust crate by Misha Perlov
    (https://github.com/mishamsk/sas-lexer). Tokenizes SAS source code
    into a stream of typed tokens with full position metadata. Ships
    prebuilt native libraries for supported platforms; a runtime FFI
    loader picks the matching one for the host.
  DESC
  spec.homepage = "https://github.com/mes-amis/sas-lexer-rb"
  spec.license = "AGPL-3.0-or-later"
  spec.required_ruby_version = ">= 3.4.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml ffi-wrapper/target/ vendor/ docker/ bin/])
    end
  end
  spec.require_paths = ["lib"]

  # ── Native FFI library: universal-gem strategy ───────────────────────────
  #
  # The Rust FFI shim that bridges `sas-lexer` to Ruby is built ahead
  # of time per target platform and committed under `lib/native/<platform>/`.
  # The published gem is universal (`platform: ruby`) and ships every
  # committed platform's prebuilt; the loader in `lib/sas_lexer/lexer.rb`
  # globs `lib/native/*/libsas_lexer_ffi.{so,dylib,dll}` at runtime and
  # picks the one that matches the host.
  #
  # No source-build fallback: a host without a committed prebuilt for
  # its platform fails fast at FFI load time. To add a new platform,
  # build the shim there with `bundle exec rake sas_lexer:install`,
  # move the artifact to `lib/native/<platform>/`, and commit.

  spec.add_dependency "ffi", "~> 1.15"
end
