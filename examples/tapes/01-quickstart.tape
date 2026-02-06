# pwt Demo - Quick Start
# Run: vhs examples/tapes/01-quickstart.tape

Output examples/gifs/01-quickstart.gif
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
Show

Type "pwt create quickstart main 'quick start'"
Enter
Sleep 1s

Type "pwt cd quickstart"
Enter
Sleep 500ms

Type "pwd"
Enter
Sleep 600ms

Type "pwt cd @"
Enter
Sleep 400ms

Type "pwt remove quickstart -y"
Enter
Sleep 900ms

Type "pwt list"
Enter
Sleep 700ms

Type "# github.com/jonasporto/pwt"
Enter
Sleep 1s
