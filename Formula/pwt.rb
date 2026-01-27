# typed: false
# frozen_string_literal: true

class Pwt < Formula
  desc "Power Worktrees - Git worktree manager for multiple projects"
  homepage "https://github.com/jonasporto/pwt"
  url "https://github.com/jonasporto/pwt/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "PLACEHOLDER"  # Update with actual sha256 after release
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

    # Install completions
    zsh_completion.install "completions/_pwt"

    # Install plugins (optional)
    (share/"pwt/plugins").install Dir["plugins/*"]
  end

  def caveats
    <<~EOS
      To enable zsh completions, add to ~/.zshrc:
        fpath=(#{HOMEBREW_PREFIX}/share/zsh/site-functions $fpath)
        autoload -Uz compinit && compinit

      To use plugins, copy from #{HOMEBREW_PREFIX}/share/pwt/plugins/ to ~/.pwt/plugins/

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
