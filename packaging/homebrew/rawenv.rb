class Rawenv < Formula
  desc "Universal development environment manager"
  homepage "https://github.com/rawenv/rawenv"
  version "VERSION"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/rawenv/rawenv/releases/download/vVERSION/rawenv-macos-arm64"
      sha256 "SHA256_MACOS_ARM64"
    end
    on_intel do
      url "https://github.com/rawenv/rawenv/releases/download/vVERSION/rawenv-macos-x64"
      sha256 "SHA256_MACOS_X64"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/rawenv/rawenv/releases/download/vVERSION/rawenv-linux-arm64"
      sha256 "SHA256_LINUX_ARM64"
    end
    on_intel do
      url "https://github.com/rawenv/rawenv/releases/download/vVERSION/rawenv-linux-x64"
      sha256 "SHA256_LINUX_X64"
    end
  end

  def install
    bin.install "rawenv"
  end

  test do
    assert_match "rawenv", shell_output("#{bin}/rawenv --version")
  end
end
