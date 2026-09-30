# pwt Demo - @there: go where git said the branch already is
# Run from the repo root: vhs examples/tapes/05-there.tape

Output examples/videos/05-there.mp4
Output examples/gifs/05-there.gif
Set Shell "bash"
Set FontSize 14
Set Width 900
Set Height 520
Set Theme "Catppuccin Mocha"
Set Padding 12
Set TypingSpeed 40ms

# Realpath on purpose: git prints resolved paths, and \w only collapses
# to ~ when HOME matches the resolved prefix
Env HOME "/private/tmp/pwt-demo-home"

Hide
Type "export PATH=$PWD/bin:$PATH"
Enter
Type "rm -rf $HOME && mkdir -p $HOME/projects/acme-shop && cd $HOME/projects/acme-shop"
Enter
Type "git init -qb main && git config user.email demo@example.com && git config user.name Demo"
Enter
Type "printf 'hello' > README.md && git add -A && git commit -qm init"
Enter
# vhs starts bash with +o history; @there reads the previous line from it
Type "set -o history && source <(pwt shell-init bash) && pwt init >/dev/null 2>&1 && pwt config branch_prefix feature/ >/dev/null 2>&1"
Enter
Type "pwt create login main >/dev/null 2>&1"
Enter
Type `export PS1='\w $ '`
Enter
# Sleep-then-clear barrier: Show resumes filming immediately, so the
# setup must have finished and the screen must already be clear.
Sleep 5s
Type "clear"
Enter
Sleep 500ms
Show

Type "git checkout feature/login"
Enter
Sleep 2.5s

Type "pwt @there"
Enter
Sleep 2.5s

Type "git branch --show-current"
Enter
Sleep 2s

Type "pwt @"
Enter
Sleep 2s

Type "# @there: where git pointed. @: home. Nothing copied."
Enter
Sleep 3s
