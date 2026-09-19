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
  end

  test do
    assert_match "0c276b3", shell_output("#{bin}/gxi -v 2>&1")
    assert_equal "v19-release-ready\n",
                 shell_output("#{bin}/gxi -e '(displayln \"v19-release-ready\")'")
  end
end
