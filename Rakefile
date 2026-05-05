# frozen_string_literal: true

require "bundler/setup"
require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"
require "fileutils"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

# SAS Lexer build tasks. The published gem ships prebuilt native
# libraries under `lib/native/<platform>/`; these tasks let
# contributors build a fresh artifact for their host (e.g. when
# adding a new platform) by cloning the upstream Rust crate and
# compiling the FFI shim under `ffi-wrapper/`.
namespace :sas_lexer do
  SAS_LEXER_REPO = "https://github.com/craigmcnamara/sas-lexer.git"
  SAS_LEXER_BRANCH = "main"
  SAS_LEXER_DIR = "vendor/sas-lexer"
  LIB_DIR = "lib/native"

  desc "Clone (or update) the upstream sas-lexer repository"
  task :clone do
    if Dir.exist?(SAS_LEXER_DIR)
      puts "SAS Lexer repository already exists at #{SAS_LEXER_DIR}"
      puts "Updating repository..."
      Dir.chdir(SAS_LEXER_DIR) do
        sh "git fetch origin"
        sh "git reset --hard origin/#{SAS_LEXER_BRANCH}"
      end
    else
      puts "Cloning sas-lexer repository..."
      FileUtils.mkdir_p("vendor")
      sh "git clone --branch #{SAS_LEXER_BRANCH} #{SAS_LEXER_REPO} #{SAS_LEXER_DIR}"
    end
  end

  desc "Check that Rust and Cargo are installed"
  task :check_rust do
    sh "rustc --version", verbose: false
    sh "cargo --version", verbose: false
    puts "✓ Rust and Cargo are installed"
  rescue StandardError
    puts "✗ Rust is not installed or not in PATH"
    puts "Please install Rust from https://rustup.rs/"
    exit 1
  end

  desc "Build the sas-lexer FFI wrapper library"
  task build: %i[check_rust clone] do
    puts "Building sas-lexer FFI wrapper library..."

    Dir.chdir("ffi-wrapper") do
      target = case RbConfig::CONFIG["host_os"]
               when /darwin/
                 case RbConfig::CONFIG["host_cpu"]
                 when /arm64|aarch64/ then "aarch64-apple-darwin"
                 when /x86_64/ then "x86_64-apple-darwin"
                 end
               when /linux/
                 case RbConfig::CONFIG["host_cpu"]
                 when /aarch64/ then "aarch64-unknown-linux-gnu"
                 when /x86_64/ then "x86_64-unknown-linux-gnu"
                 end
               end

      if target && RbConfig::CONFIG["host_os"] =~ /darwin/
        # Pin the target on macOS so universal-binary hosts produce a
        # single-arch artifact that matches the running Ruby.
        puts "Building FFI wrapper for target: #{target}"
        sh "cargo build --release --target #{target}"
      else
        puts "Building FFI wrapper for default target"
        sh "cargo build --release"
      end
    end

    puts "✓ SAS Lexer FFI wrapper built successfully"
  end

  desc "Install the built library into lib/native/"
  task install: [:build] do
    puts "Installing sas-lexer library locally..."

    FileUtils.mkdir_p(LIB_DIR)

    case RbConfig::CONFIG["host_os"]
    when /darwin/
      lib_extension = "dylib"
      lib_name = "libsas_lexer_ffi.dylib"
    when /linux/
      lib_extension = "so"
      lib_name = "libsas_lexer_ffi.so"
    when /mswin|mingw|cygwin/
      lib_extension = "dll"
      lib_name = "sas_lexer_ffi.dll"
    else
      puts "Unsupported platform: #{RbConfig::CONFIG['host_os']}"
      exit 1
    end

    target_arch = case RbConfig::CONFIG["host_os"]
                  when /darwin/
                    case RbConfig::CONFIG["host_cpu"]
                    when /arm64|aarch64/ then "aarch64-apple-darwin"
                    when /x86_64/ then "x86_64-apple-darwin"
                    end
                  end

    target_dir = if target_arch && RbConfig::CONFIG["host_os"] =~ /darwin/
                   File.join("ffi-wrapper", "target", target_arch, "release")
                 else
                   File.join("ffi-wrapper", "target", "release")
                 end

    possible_names = [
      "libsas_lexer_ffi.#{lib_extension}",
      "sas_lexer_ffi.#{lib_extension}"
    ]

    built_lib = possible_names
                .map { |name| File.join(target_dir, name) }
                .find { |path| File.exist?(path) }

    if built_lib.nil?
      puts "Could not find built library in #{target_dir}"
      puts "Available files:"
      Dir.glob(File.join(target_dir, "*")).each { |f| puts "  #{File.basename(f)}" }
      exit 1
    end

    dest_path = File.join(LIB_DIR, lib_name)
    FileUtils.cp(built_lib, dest_path)

    puts "✓ Library installed to #{dest_path}"
    puts ""
    puts "To ship this artifact in the universal gem, move it under"
    puts "lib/native/<platform>/ and commit it. For example:"
    puts ""
    puts "  mkdir -p lib/native/$(ruby -e 'puts RUBY_PLATFORM')"
    puts "  mv #{dest_path} lib/native/$(ruby -e 'puts RUBY_PLATFORM')/"
    puts "  git add lib/native/$(ruby -e 'puts RUBY_PLATFORM')/#{lib_name}"
  end

  desc "Clean Rust build artifacts"
  task :clean do
    puts "Cleaning sas-lexer build artifacts..."

    if Dir.exist?(SAS_LEXER_DIR)
      Dir.chdir(SAS_LEXER_DIR) do
        sh "cargo clean" if File.exist?("Cargo.toml")
      end
    end

    if Dir.exist?("ffi-wrapper/target")
      Dir.chdir("ffi-wrapper") { sh "cargo clean" }
    end

    [
      File.join(LIB_DIR, "libsas_lexer_ffi.dylib"),
      File.join(LIB_DIR, "libsas_lexer_ffi.so"),
      File.join(LIB_DIR, "sas_lexer_ffi.dll")
    ].each do |path|
      FileUtils.rm_f(path)
    end

    puts "✓ Clean completed"
  end

  desc "Remove the cloned upstream repository and any flat-path libs"
  task :distclean do
    puts "Removing sas-lexer repository..."
    FileUtils.rm_rf(SAS_LEXER_DIR) if Dir.exist?(SAS_LEXER_DIR)
    FileUtils.rm_rf("ffi-wrapper/target") if Dir.exist?("ffi-wrapper/target")
    [
      File.join(LIB_DIR, "libsas_lexer_ffi.dylib"),
      File.join(LIB_DIR, "libsas_lexer_ffi.so"),
      File.join(LIB_DIR, "sas_lexer_ffi.dll")
    ].each { |path| FileUtils.rm_f(path) }
    puts "✓ Repository and flat-path libs removed"
  end

  desc "Check whether a sas-lexer library is available"
  task :check do
    flat_paths = [
      File.join(LIB_DIR, "libsas_lexer_ffi.so"),
      File.join(LIB_DIR, "libsas_lexer_ffi.dylib"),
      File.join(LIB_DIR, "sas_lexer_ffi.dll")
    ]
    platform_paths = Dir.glob(File.join(LIB_DIR, "*", "libsas_lexer_ffi.{so,dylib,dll}"))

    if (found = flat_paths.find { |p| File.exist?(p) })
      puts "✓ SAS Lexer library is available (dev-build): #{found}"
    elsif platform_paths.any?
      puts "✓ SAS Lexer libraries are available (committed):"
      platform_paths.each { |p| puts "    #{p}" }
    else
      puts "✗ SAS Lexer library is not available"
      puts "Run 'rake sas_lexer:install' to build and install it"
    end
  end
end

desc "Build and install the sas-lexer dependency"
task build_deps: ["sas_lexer:install"]

task default: %i[spec]
