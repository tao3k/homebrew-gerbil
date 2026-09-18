# frozen_string_literal: true

# Gerbil Scheme language implementation and toolchain.
class GerbilScheme < Formula
  # This .rb file is tangled (AKA generated) from README.org
  desc "Opinionated dialect of Scheme designed for Systems Programming"
  homepage "https://cons.io"
  url "https://github.com/mighty-gerbils/gerbil.git",
      using: :git, tag: "v0.18.2", revision: "07c8481588a8b07dbf05832687817cd398902ac0"
  license any_of: ["LGPL-2.1-or-later", "Apache-2.0"]

  revision 6

  head "https://github.com/mighty-gerbils/gerbil.git", using: :git, branch: "master"

  depends_on "coreutils" => :build
  depends_on "pkg-config" => :build
  depends_on "openssl@3"
  depends_on "sqlite"
  depends_on "zlib"
  on_macos do
    depends_on "gcc"
    fails_with :clang do
      cause "the performance build requires Homebrew GCC"
    end
  end
  on_linux do
    depends_on "gcc@13"
    fails_with :clang do
      cause "Gerbil requires GCC on Linux"
    end
  end
  def install
    build_cores = ENV.make_jobs
    ENV["GERBIL_BUILD_CORES"] = build_cores.to_s

    if OS.linux?
      ENV.prepend_path("PATH", "/home/linuxbrew/.linuxbrew/bin")
      ENV.prepend_path("PATH", "/home/linuxbrew/.linuxbrew/sbin")
    else
      ENV.prepend_path("PATH", "/usr/bin")
    end

    ENV["GERBIL_GCC"] = ENV.cc.to_s
    ENV["CC"] = ENV.cc.to_s
    ENV["CXX"] = ENV.cxx.to_s
    ENV.append "CFLAGS", "-pipe"
    openssl_include = formula_opt_include("openssl@3")
    ENV.append "CPPFLAGS", "-I#{openssl_include} -include #{openssl_include}/openssl/kdf.h"
    ENV.append "LDFLAGS", "-L#{formula_opt_lib("openssl@3")}"
    if OS.mac?
      ENV.append "CPPFLAGS", "-isysroot #{MacOS.sdk_path}"
    end

    system ENV.cc.to_s, "--version"
    # Gerbil 0.18.2 injects single-host and fixed runtime options before
    # forwarding user configure arguments. Keep policy in this formula so the
    # v18 runtime stays non-SMP and chooses its own runtime defaults.
    inreplace "configure",
              /readonly default_gambit_config=.*/,
              'readonly default_gambit_config="--enable-targets=${gerbil_targets}"'
    # Gerbil 0.18.2 forces debug source tracking for the entire stdlib.  GCC's
    # generated Scheme #line entries are rejected by modern macOS dsymutil
    # (for example, the synthetic source name "so_prefix").  A release build
    # does not need those debug maps, so keep the stdlib optimized and portable.
    inreplace "src/std/build.ss",
              "srcdir: srcdir libdir: libdir debug: #t",
              "srcdir: srcdir libdir: libdir debug: #f"
    system "./configure",
           "--prefix=#{prefix}",
           "--enable-march=native",
           # Zero removes both limits; keep the release build fully optimized.
           "--enable-single-host=0",
           "--enable-optimized-module-limit=0",
           "--enable-c-opt=-O1",
           "--enable-c-opt-rts=yes",
           "--enable-gcc-opts",
           "--enable-inline-jumps",
           "--enable-dynamic-clib",
           "--enable-trust-c-tco"
    bootstrap_bin = buildpath/"bootstrap/bin"
    %w[
      prepare gambit boot-gxi stage0 stage1 stdlib libgerbil
      lang r7rs-large srfi tools
    ].each do |target|
      ohai "Building Gerbil phase #{target} with #{build_cores} core(s)"
      with_env("GERBIL_BUILD_FLAGS" => "-j#{build_cores}") do
        system "./build.sh", target
      end
      next if target != "gambit"

      bootstrap_gsi = bootstrap_bin/"gsi"
      odie "Gambit phase did not publish executable #{bootstrap_gsi}" unless bootstrap_gsi.executable?
      ENV.prepend_path "PATH", bootstrap_bin
      system bootstrap_gsi, "-e", '(display "gsi-bootstrap-ready\\n")'
    end
    system "./install.sh"

    # We get rid of all the non-LFSH stuff

    rm prefix/"bin"
    rm prefix/"lib"
    rm prefix/"share"
    mkdir prefix/"bin"

    cd prefix/"current/bin" do
      ln "gerbil", prefix/"bin", verbose: true
      cp %w[gxc gxensemble gxi gxpkg gxprof gxtags gxtest], prefix/"bin"
    end
  end
  test do
    command = "#{bin}/gerbil interactive -e " \
              "\"(for-each write '(0 1 2 3 4 5 6 7 8 9))\""
    assert_equal "0123456789", shell_output(command)
    processor_count = shell_output(
      "#{bin}/gxi -e '(write (##current-vm-processor-count))'",
    ).to_i
    assert_equal 1, processor_count
  end
end
