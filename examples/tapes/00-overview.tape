# pwt Demo - Overview: two worktrees, two servers, zero collisions
# Run from the repo root: vhs examples/tapes/00-overview.tape

Output examples/videos/00-overview.mp4
Output examples/gifs/00-overview.gif
Set Shell "bash"
Set FontSize 14
Set Width 1200
Set Height 700
Set Theme "Catppuccin Mocha"
Set Padding 12
Set TypingSpeed 40ms

Env HOME "/tmp/pwt-demo-home"

Hide
# $PWD expands at runtime, so the tape stays portable; a hardcoded ./bin
# breaks the moment the demo cds away from the repo root.
Type "export PATH=$PWD/bin:$PATH"
Enter
Type "rm -rf $HOME && mkdir -p $HOME/projects/acme-shop && cd $HOME/projects/acme-shop"
Enter
Type "git init -qb main && git config user.email demo@example.com && git config user.name Demo"
Enter
Type "printf 'API_KEY=dev-secret\n' > .env"
Enter
Type `printf 'PORT_BASE=5001\n\nsetup() {\n    pwtfile_copy ".env"\n    echo "deps installed"\n}\n\nserver() {\n    exec python3 -m http.server "$PWT_PORT"\n}\n' > Pwtfile`
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
Sleep 4s

Type "pwt server feature-a --bg --no-input"
Enter
Sleep 2.5s

Type "pwt server wait feature-a"
Enter
Sleep 2s

Type "clear"
Enter

Type "pwt create feature-b main 'search fix'"
Enter
Sleep 4s

Type "pwt server feature-b --bg --no-input"
Enter
Sleep 2.5s

Type "clear"
Enter

Type "pwt ports"
Enter
Sleep 3s

Type "pwt list"
Enter
Sleep 3.5s

Type "pwt remove feature-b --kill-server -y"
Enter
Sleep 2.5s

Type "# github.com/jonasporto/pwt"
Enter
Sleep 2s

Hide
Type "pwt remove feature-a --kill-server -y"
Enter
