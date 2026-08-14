---
title: "Your OAuth callback accepts one URL. You have six worktrees."
description: "Per-branch URLs are great for browsing and useless for a provider that knows one address. The fix is the opposite shape: one stable URL you repoint."
featured: true
---

Register `http://localhost:3000/auth/callback` with an identity provider,
then start working in worktrees. The second worktree runs on 3001, the third
on 3002, and neither can complete a login, because the provider only knows
about 3000.

The same wall shows up with a Stripe or GitHub webhook, an SMS callback, a
bank sandbox, anything where a third party stores your address. **You get one
URL. Worktrees give you N ports.**

## Why the usual answers hurt

**Re-register the redirect URI on every switch.** It works, and it costs a
trip through someone's dashboard each time you change branches. It also fails
the moment two things run at once, which is the whole reason you have
worktrees.

**Move the worktree onto the registered port.** Now only one worktree can run
at a time, and you have deleted the parallelism you were trying to get.

**Tunnel it.** ngrok and friends give you a public URL, which is genuinely
required when the provider must reach you from the internet. For a local
provider or a local sandbox it is a lot of moving parts, and free tunnels
hand you a new hostname on restart, which puts you back at re-registering.

**Give every branch its own URL.** This is the popular local answer now.
[portless](https://github.com/vercel-labs/portless) from Vercel Labs does it
well: each worktree gets a name like `fix-ui.myapp.localhost`, so you can
open any of them without remembering a port. If your problem is browsing, it
is the right tool and I would use it.

It does not solve this one. A provider that stores a single redirect URI does
not know about `fix-ui.myapp.localhost`, and adding one entry per branch is
the re-registering problem wearing a different hat. N addresses is the wrong
shape when the constraint is that there can be only one.

## The shape that fits: one URL, repointed

Keep exactly one address, registered once, and change what sits behind it.

```bash
pwt gateway init --port 4500   # once per project
pwt gateway up                 # start the proxy
```

```
Gateway port set to 4500
Gateway running at http://localhost:4500
```

Then point it at whichever worktree should own the callback right now. Here
are three worktrees, each with its own derived port, each serving a file that
names itself, and one URL asked three times:

```
gateway use x -> curl http://localhost:4500/whoami.txt -> you are talking to worktree x (port 3001)
gateway use y -> curl http://localhost:4500/whoami.txt -> you are talking to worktree y (port 3002)
gateway use z -> curl http://localhost:4500/whoami.txt -> you are talking to worktree z (port 3003)
```

`http://localhost:4500/auth/callback` is registered once and never changes.
The worktree behind it is a command.

Switching is not something you wait for. Measured over four consecutive
switches, `gateway use` plus the first request through the proxy:

```
use x + first request: 130 ms
use y + first request: 129 ms
use x + first request: 130 ms
use y + first request: 135 ms
```

## Two behaviours that matter more than the switch

**It starts the target if the target is down.** The worktree you are pointing
at usually has no server running yet, because you were working somewhere
else. Pointing at it starts one:

```
$ curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3003/    # z is dead
000
$ pwt gateway use z
  pwt jobs stop z-server-1786713556       # stop
Gateway target: z -> 127.0.0.1:3003
Gateway URL:    http://localhost:4500

$ curl -s http://localhost:4500/whoami.txt
you are talking to worktree z (port 3003)
```

The server it started is a background job with an id, so it is addressable
later instead of being a process you have to hunt down. That matters because
the thing you registered with a provider should not depend on a terminal
staying open.

**A failed switch does not break the URL.** If the target cannot be started,
the gateway keeps serving whoever it was serving:

```
$ pwt gateway use z
Error: Target port 3003 is not listening and no Pwtfile server command is configured
$ curl -s http://localhost:4500/whoami.txt
you are talking to worktree y (port 3002)
```

That is the right failure. A registered URL that starts returning connection
errors is worse than one still pointing at the previous branch, because the
provider retries against it and you get a pile of failed webhook deliveries
for a mistake you made locally.

`pwt gateway status` says which one is live:

```
Gateway (main)
  URL:     http://localhost:4500
  Status:  running
  PID:     68782
  Target:  y :3002
```

## When you do not need this

Be honest about the shape of your problem before adding a proxy.

- **Just opening branches in a browser?** Per-branch URLs are nicer. Use
  those.
- **Provider must reach you from the public internet?** You need a tunnel.
  A local proxy cannot help, though it can sit behind the tunnel so the
  tunnel's URL stays pointed at one local address.
- **One worktree at a time?** Then you never had the problem.
- **Callback is configurable per-request?** Some providers accept a redirect
  URI parameter validated against a prefix or a wildcard. If yours does, use
  that and skip all of this.

The gateway earns its place in one specific case: a fixed address, registered
somewhere you do not control, that has to follow whichever worktree you are
working in.

> Wiring third-party callbacks with an agent? Give it the stable URL, not the
> port. An agent that reads the port out of a worktree's config will bake the
> wrong one into a fixture the first time you switch branches.

`pwt gateway`, the per-worktree port allocation behind it, and the background
jobs it starts are part of [pwt](https://github.com/jonasporto/pwt), a Git
worktree manager for parallel development:
`brew install jonasporto/pwt/pwt`.
