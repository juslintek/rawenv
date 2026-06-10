class Rawenv < Formula
  desc "Native dev environment manager: zero dependencies, one binary"
  homepage "https://github.com/juslintek/rawenv"
  version "VERSION"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/juslintek/rawenv/releases/download/vVERSION/rawenv-darwin-arm64"
      sha256 "SHA256_DARWIN_ARM64"
    end
    on_intel do
      url "https://github.com/juslintek/rawenv/releases/download/vVERSION/rawenv-darwin-x64"
      sha256 "SHA256_DARWIN_X64"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/juslintek/rawenv/releases/download/vVERSION/rawenv-linux-arm64"
      sha256 "SHA256_LINUX_ARM64"
    end
    on_intel do
      url "https://github.com/juslintek/rawenv/releases/download/vVERSION/rawenv-linux-x64"
      sha256 "SHA256_LINUX_X64"
    end
  end

  def install
    # The release asset is a bare, platform-specific binary (e.g.
    # rawenv-darwin-arm64). Install whichever one was downloaded as "rawenv".
    binary = Dir["rawenv-*"].first
    bin.install binary => "rawenv"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/rawenv --version")
  end
end
