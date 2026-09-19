# frozen_string_literal: true

# Gerbil v0.19 staging toolchain built and relocation-tested by gerbil-bazel.
class GerbilSchemeAT019 < Formula
  desc "Opinionated dialect of Scheme designed for Systems Programming"
  homepage "https://cons.io"
  url "https://github.com/tao3k/gerbil-bazel/releases/download/gerbil-v0.19-0c276b3b12c5f277ab5697c711c370cf377c6a21-darwin-aarch64-gcc16-native-full/gerbil-v0.19-0c276b3b12c5f277ab5697c711c370cf377c6a21-darwin-aarch64-gcc16-native-full.tar.gz"
  version "0.19.0c276b3"
  sha256 "5649f7d111c0c2e11c5e34629be8f156148877788e9a99407f74d33f207b85c6"
  license any_of: ["LGPL-2.1-or-later", "Apache-2.0"]

  keg_only :versioned_formula

  depends_on arch: :arm64
  depends_on "gcc"
  depends_on :macos
  depends_on "openssl@3"
  depends_on "sqlite"
  depends_on "zlib"

  def install
    prefix.install Dir["*"]

    emacs_site_lisp = prefix/"current/share/emacs/site-lisp"
    emacs_files = emacs_site_lisp.children
    (emacs_site_lisp/name).install emacs_files

    release_bin = prefix/"current/bin"
    rm prefix/"bin"
    bin.mkpath
    %w[gerbil gxc gxi gxhttpd gxtest].each do |command|
      executable = release_bin/command
      odie "Missing released executable #{executable}" unless executable.executable?
      (bin/command).write <<~SH
        #!/bin/bash
        export GERBIL_PREFIX="#{prefix}"
        export GERBIL_HOME="#{prefix}/current"
        gerbil_runtime_options="~~=$GERBIL_HOME,~~bin=$GERBIL_HOME/bin,~~lib=$GERBIL_HOME/lib"
        export GAMBOPT="${GAMBOPT:+$GAMBOPT,}$gerbil_runtime_options"
        exec "$GERBIL_HOME/bin/#{command}" "$@"
      SH
      chmod 0755, bin/command
    end
  end

  test do
    assert_match "0c276b3", shell_output("#{bin}/gxi -v 2>&1")
    assert_equal "#t\n", shell_output(
      "#{bin}/gxi -e '(begin (import :gerbil/runtime/system) (write (gerbil-runtime-smp?)) (newline))'",
    )
    assert_equal "std/make-ready\n", shell_output(
      "#{bin}/gxi -e '(begin (import :std/make) (displayln \"std/make-ready\"))'",
    )
    assert_equal "v19-release-ready\n",
                 shell_output("#{bin}/gxi -e '(displayln \"v19-release-ready\")'")
  end
end
