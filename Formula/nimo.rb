# Homebrew formula for nimo.
#
#   brew install danielkopa/tap/nimo
#
# It installs the whole tree and links `min`, because nimo is a script that
# sources its libraries from beside itself.
class Nimo < Formula
  desc "Make your workspace clean"
  homepage "https://danielkopa.github.io/nimo/"
  url "https://github.com/danielkopa/nimo/archive/refs/tags/v0.36.0.tar.gz"
  license "MIT"
  head "https://github.com/danielkopa/nimo.git", branch: "main"

  def install
    libexec.install Dir["*"]
    (bin/"min").write_env_script libexec/"min", {}
    man1.install libexec/"man/min.1"
    bash_completion.install libexec/"completions/min.bash" => "min"
  end

  test do
    assert_match "nimo", shell_output("#{bin}/min version")
    assert_match "safe to clean", shell_output("#{bin}/min preview --no-color -q </dev/null")
  end
end
