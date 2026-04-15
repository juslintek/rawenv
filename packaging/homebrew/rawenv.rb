class Rawenv < Formula
  desc "Universal development environment manager"
  homepage "https://github.com/rawenv/rawenv"
  version "VERSION"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/rawenv/rawenv/releases/download/vVERSION/rawenv-aarch64-macos.tar.gz"
      sha256 "SHA256_AARCH64_MACOS"
    end
    on_intel do
      url "https://github.com/rawenv/rawenv/releases/download/vVERSION/rawenv-x86_64-macos.tar.gz"
      sha256 "SHA256_X86_64_MACOS"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/rawenv/rawenv/releases/download/vVERSION/rawenv-aarch64-linux.tar.gz"
      sha256 "SHA256_AARCH64_LINUX"
    end
    on_intel do
      url "https://github.com/rawenv/rawenv/releases/download/vVERSION/rawenv-x86_64-linux.tar.gz"
      sha256 "SHA256_X86_64_LINUX"
    end
  end

  def install
    bin.install "rawenv"
  end

  test do
    assert_match "rawenv", shell_output("#{bin}/rawenv --version")
  end
end
