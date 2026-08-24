# pwt Demo - Ports: one machine-wide registry across projects
# Run from the repo root: vhs examples/tapes/03-ports.tape

Output examples/videos/03-ports.mp4
Output examples/gifs/03-ports.gif
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
Type "rm -rf $HOME && source <(pwt shell-init bash)"
Enter
# Two independent projects; allocation is machine-wide, so their ports
# never collide even though both Pwtfiles could claim the same base.
Type `mkproj() { local p=$HOME/projects/$1; mkdir -p $p && cd $p && git init -qb main && git config user.email demo@example.com && git config user.name Demo && printf 'PORT_BASE=%s\n\nserver() {\n    exec python3 -m http.server "$PWT_PORT"\n}\n' $2 > Pwtfile && printf 'hello' > README.md && git add -A && git commit -qm init && git init -q --bare $HOME/origin-$1.git && git remote add origin $HOME/origin-$1.git && git push -qu origin main 2>/dev/null; pwt init >/dev/null 2>&1; }`
Enter
Type "mkproj acme-shop 5001"
Enter
Type "pwt create feature-a main 'checkout flow' >/dev/null 2>&1 && pwt create feature-b main 'search fix' >/dev/null 2>&1"
Enter
Type "pwt server feature-a --bg --no-input >/dev/null 2>&1 && pwt server feature-b --bg --no-input >/dev/null 2>&1"
Enter
Type "pwt server wait feature-a >/dev/null && pwt server wait feature-b >/dev/null"
Enter
Type "mkproj blog-api 5101"
Enter
Type "pwt create redesign main 'new layout' >/dev/null 2>&1"
Enter
Type "pwt server redesign --bg --no-input >/dev/null 2>&1 && pwt server wait redesign >/dev/null"
Enter
# Sleep-then-clear barrier: Show resumes filming immediately, so the
# whole queued setup must have finished and the screen must be clear.
Sleep 12s
Type "clear"
Enter
Sleep 500ms
Show

Type "pwt ports"
Enter
Sleep 4s

Type "# every project on the machine, one registry, zero collisions"
Enter
Sleep 3s

Hide
Type "pwt remove redesign --kill-port -y >/dev/null 2>&1"
Enter
Type "cd $HOME/projects/acme-shop && pwt remove feature-a --kill-port -y >/dev/null 2>&1 && pwt remove feature-b --kill-port -y >/dev/null 2>&1"
Enter
