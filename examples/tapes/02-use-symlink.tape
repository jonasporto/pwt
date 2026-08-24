# pwt Demo - Use: one stable path, branches swap underneath
# Run from the repo root: vhs examples/tapes/02-use-symlink.tape

Output examples/videos/02-use-symlink.mp4
Output examples/gifs/02-use-symlink.gif
Set Shell "bash"
Set FontSize 14
Set Width 900
Set Height 520
Set Theme "Catppuccin Mocha"
Set Padding 12
Set TypingSpeed 40ms

Env HOME "/tmp/pwt-demo-home"

Hide
Type "export PATH=$PWD/bin:$PATH"
Enter
Type "rm -rf $HOME && mkdir -p $HOME/projects/acme-shop && cd $HOME/projects/acme-shop"
Enter
Type "git init -qb main && git config user.email demo@example.com && git config user.name Demo"
Enter
Type "printf 'hello' > README.md && git add -A && git commit -qm init"
Enter
Type "source <(pwt shell-init bash) && pwt init >/dev/null 2>&1"
Enter
Type "pwt create feature-a main 'checkout flow' >/dev/null 2>&1"
Enter
Type "pwt create feature-b main 'search fix' >/dev/null 2>&1"
Enter
# Sleep-then-clear barrier: Show resumes filming immediately, so the
# setup must have finished and the screen must already be clear.
Sleep 6s
Type "clear"
Enter
Sleep 500ms
Show

Type "pwt use feature-a"
Enter
Sleep 1.5s

Type "readlink ~/.pwt/projects/acme-shop/current"
Enter
Sleep 2s

Type "# your editor stays open on 'current' ..."
Enter
Sleep 1.2s

Type "pwt use feature-b"
Enter
Sleep 1.5s

Type "readlink ~/.pwt/projects/acme-shop/current"
Enter
Sleep 2s

Type "pwt current"
Enter
Sleep 2.5s
