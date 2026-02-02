# typed: false
# frozen_string_literal: true

class Pwt < Formula
  desc "Power Worktrees - Git worktree manager for multiple projects"
  homepage "https://github.com/jonasporto/pwt"
  url "https://github.com/jonasporto/pwt/archive/refs/tags/v0.1.6"
  sha256 "PLACEHOLDER"  # Auto-updated by release workflow
  license "MIT"
  head "https://github.com/jonasporto/pwt.git", branch: "main"

  depends_on "bash"
  depends_on "jq"
  depends_on "git"

  def install
    # Install main script
    bin.install "bin/pwt"

    # Install library modules
    (lib/"pwt").install Dir["lib/pwt/*.sh"]

    # Install man page
    man1.install "man/pwt.1"

    # Install completions
    zsh_completion.install "completions/_pwt"
    bash_completion.install "completions/pwt.bash" => "pwt"
    fish_completion.install "completions/pwt.fish"

    # Install plugins (optional)
    (share/"pwt/plugins").install Dir["plugins/*"]
  end

  def caveats
    <<~EOS
      Shell completions have been installed.

      For zsh, ensure your ~/.zshrc includes:
        autoload -Uz compinit && compinit

      For bash, ensure bash-completion is installed:
        brew install bash-completion@2

      For fish, completions should work automatically.

      View the manual:
        man pwt

      Quick start:
        cd your-project
        pwt init            # Initialize project
        pwt create my-branch  # Create a worktree
        pwt list            # List worktrees
    EOS
  end

  test do
    assert_match "pwt", shell_output("#{bin}/pwt --version")
    system bin/"pwt", "help"
  end
end
