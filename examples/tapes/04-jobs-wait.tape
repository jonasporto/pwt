# pwt Demo - Jobs: background work you can wait on
# Run from the repo root: vhs examples/tapes/04-jobs-wait.tape

Output examples/videos/04-jobs-wait.mp4
Output examples/gifs/04-jobs-wait.gif
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
Type `printf 'test() {\n    echo "running specs..."\n    sleep 2\n    echo "42 examples, 0 failures"\n}\n' > Pwtfile`
Enter
Type "printf 'hello' > README.md && git add -A && git commit -qm init"
Enter
Type "git init -q --bare $HOME/origin.git && git remote add origin $HOME/origin.git && git push -qu origin main 2>/dev/null"
Enter
Type "source <(pwt shell-init bash) && pwt init >/dev/null 2>&1"
Enter
Type "pwt create feature-a main 'checkout flow' >/dev/null 2>&1"
Enter
# Sleep-then-clear barrier: Show resumes filming immediately, so the
# setup must have finished and the screen must already be clear.
Sleep 5s
Type "clear"
Enter
Sleep 500ms
Show

Type "pwt feature-a test --bg"
Enter
Sleep 2.5s

Type "pwt jobs wait feature-a"
Enter
Sleep 4s

Type "pwt jobs list --porcelain"
Enter
Sleep 3.5s

Type "# wait returns when the job does: no poll loops"
Enter
Sleep 2.5s
