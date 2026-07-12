class GerbilScheme < Formula
  # This .rb file is tangled (AKA generated) from README.org
  desc "Opinionated dialect of Scheme designed for Systems Programming"
  homepage "https://cons.io"
  url "https://github.com/mighty-gerbils/gerbil.git",
      using: :git, tag: "v0.18.2", revision: "07c8481588a8b07dbf05832687817cd398902ac0"
  license any_of: ["LGPL-2.1-or-later", "Apache-2.0"]
  head "https://github.com/mighty-gerbils/gerbil.git", using: :git, branch: "master"

  depends_on "coreutils" => :build
  depends_on "pkg-config" => :build
  depends_on "openssl@3"
  depends_on "sqlite"
  depends_on "zlib"
  on_macos do
    fails_with :gcc do
      cause "Gambit FFI bundles built with Homebrew GCC cannot resolve macOS libSystem symbols"
    end
  end
  on_linux do
    depends_on "gcc@13"
    fails_with :clang do
      cause "Gerbil requires GCC on Linux"
    end
  end
  def install
    nproc = `nproc`.to_i - 1
    ENV["GERBIL_BUILD_CORES"] = nproc.to_s
    if OS.linux?
      ENV.prepend_path("PATH", "/home/linuxbrew/.linuxbrew/bin")
      ENV.prepend_path("PATH", "/home/linuxbrew/.linuxbrew/sbin")
    end

    ENV["GERBIL_GCC"] = ENV.cc.to_s
    ENV["CC"] = ENV.cc.to_s
    ENV["CXX"] = ENV.cxx.to_s
    ENV["LDFLAGS"] = "-Wl,-ld_classic" if OS.mac?

    system ENV.cc.to_s, "--version"
    system "./configure",
      "--prefix=#{prefix}",
      "--enable-march=",
      "--enable-smp",
      "--disable-single-host"
    inreplace "src/build.sh",
      'm="make -j ${GERBIL_BUILD_CORES:-1}" && $m bootstrap && $m from-scratch',
      'm="${MAKE:-make}" && $m bootstrap && $m from-scratch'
    system "make", "-j#{nproc}"
    system "make", "install"

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
    assert_equal "0123456789", shell_output("#{bin}/gxi -e \"(for-each write '(0 1 2 3 4 5 6 7 8 9))\"")
  end
end
