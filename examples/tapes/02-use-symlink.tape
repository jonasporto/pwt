# pwt Demo - Use Symlink
# Run: vhs examples/tapes/02-use-symlink.tape

Output examples/gifs/02-use-symlink.gif
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
Type "pwt create feature-a main 'use demo'"
Enter
Type "pwt create feature-b main 'use demo'"
Enter
Show

Type "pwt use feature-a"
Enter
Sleep 700ms

Type "pwt current --path"
Enter
Sleep 500ms

Type "pwt current --path --resolved"
Enter
Sleep 500ms

Type "pwt use feature-b"
Enter
Sleep 700ms

Type "pwt current --path"
Enter
Sleep 500ms

Type "pwt current --path --resolved"
Enter
Sleep 500ms

Type "ls -l ~/.pwt/projects/acme-shop/current"
Enter
Sleep 800ms
