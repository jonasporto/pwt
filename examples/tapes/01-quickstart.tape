# pwt Demo - Quick Start: init to a ready worktree
# Run from the repo root: vhs examples/tapes/01-quickstart.tape

Output examples/videos/01-quickstart.mp4
Output examples/gifs/01-quickstart.gif
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
Type "printf 'API_KEY=dev-secret\n' > .env"
Enter
Type `printf 'PORT_BASE=5001\n\nsetup() {\n    pwtfile_copy ".env"\n    echo "deps installed"\n}\n' > Pwtfile`
Enter
Type "printf 'hello' > README.md && git add -A && git commit -qm init"
Enter
# A local bare origin, so create resolves origin/main silently instead of
# printing the yellow no-origin fallback in the recording.
Type "git init -q --bare $HOME/origin.git && git remote add origin $HOME/origin.git && git push -qu origin main 2>/dev/null"
Enter
Type "source <(pwt shell-init bash) && pwt init >/dev/null 2>&1 && clear"
Enter
Show

Type "pwt create feature-a main 'checkout flow'"
Enter
Sleep 4.5s

Type "pwt cd feature-a"
Enter
Sleep 800ms

Type "pwd"
Enter
Sleep 1.5s

Type "cat .env"
Enter
Sleep 2.5s
