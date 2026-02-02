# pwt Demo - Status TUI
# Run: vhs examples/tapes/03-status-tui.tape

Output examples/gifs/03-status-tui.gif
Set Shell "bash"
Set FontSize 14
Set Width 900
Set Height 520
Set Theme "Catppuccin Mocha"
Set Padding 12
Set TypingSpeed 40ms

Env PATH "./bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
Env PWT_LIB "./lib/pwt"
Env HOME "/tmp/pwt-demo-home"

Hide
Type "rm -rf $HOME"
Enter
Type "mkdir -p $HOME/projects/acme-shop"
Enter
Type "cd $HOME/projects/acme-shop"
Enter
Type "git init -b main"
Enter
Type "git config user.email demo@example.com"
Enter
Type "git config user.name Demo"
Enter
Type "printf 'hello' > README.md"
Enter
Type "git add README.md"
Enter
Type "git commit -m 'init'"
Enter
Type "source <(pwt shell-init bash)"
Enter
Type "pwt init"
Enter
Type "pwt create alpha main 'status demo'"
Enter
Type "pwt create beta main 'status demo'"
Enter
Show

Type "pwt status"
Enter
Sleep 2s

Type "q"
Sleep 500ms
