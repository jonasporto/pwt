---
title: "How to deal with port allocation in git worktrees"
description: "Every dev server in every worktree wants port 3000. Half your stack dies with EADDRINUSE, the other half silently moves to 3001, and the tab you are debugging is now served by the wrong branch."
featured: true
tags: [ports, worktrees, env-config, proxy]
agent_hint_extra: >-
  Ports are in that guide too: an agent reads `$PWT_PORT` from the
  worktree's environment instead of picking a number at runtime, which is
  the whole fix from this post.
agent_hint_doc: /docs/pwtfile/
agent_hint_doc_label: "PWT_PORT and Pwtfile variables"
---

Start a dev server in a second git worktree and one of two things happens.
Either it dies with `EADDRINUSE`, or it quietly starts on a different port
and keeps going. The loud one costs you a minute. The quiet one cost me an
afternoon, because the page I was reloading was served by a branch I was not
editing.

The short answer: **allocate the port when the worktree is created, not when
the server boots, and record which worktree owns which port.** Every
shortcut below skips one half of that sentence, and each half has its own
failure mode. Both are measured in this post.

## The errors, by stack

Same collision, different message. What your framework prints when the port
is taken:

| Stack | What you see | What it does next |
|---|---|---|
| Node / Express | `Error: listen EADDRINUSE: address already in use :::3000` | dies |
| Rails (Puma) | `Address already in use - bind(2) for "127.0.0.1" port 3000 (Errno::EADDRINUSE)` | dies |
| Django / Flask | `OSError: [Errno 48] Address already in use` (Errno 98 on Linux) | dies |
| Go `net/http` | `listen tcp :8080: bind: address already in use` | dies |
| Spring Boot | `Web server failed to start. Port 8080 was already in use.` | dies |
| Docker | `Bind for 0.0.0.0:5432 failed: port is already allocated` | dies |
| Vite | `Port 3000 is in use, trying another one...` | **moves, keeps going** |
| Next.js | `⚠ Port 3000 is in use, trying 3001 instead.` | **moves, keeps going** |
| Create React App | `Something is already running on port 3000.` | asks, then moves |

The stacks that die are doing you a favor. You see the error, you kill
something or change a number, and you know exactly what state you are in.
The interesting failures are the two rows in bold.

## The quiet failure: the wrong server answered

Two worktrees of the same project, `wt-a` on the branch `feature-a` and
`wt-b` on `feature-b`, both configured for port 3000. Start `wt-a` first,
then `wt-b`, with Vite 8.2.1:

```
Port 3000 is in use, trying another one...

  VITE v8.2.1  ready in 131 ms

  ➜  Local:   http://localhost:3001/
```

One line of notice, then business as usual. Now the measurement that
matters. You are editing `wt-b`. Your browser tab, open since this morning,
points at `localhost:3000`:

```
-- curl localhost:3000
<h1>branch: feature-a</h1>
-- curl localhost:3001
<h1>branch: feature-b</h1>
```

**The tab you are debugging is served by the branch you are not editing.**
Nothing is broken, so nothing tells you. You change code in `wt-b`, reload
3000, see no effect, and start doubting the change instead of the port. Vite
has `strictPort: true` to die loudly instead, but that only converts the
quiet failure into the loud one. It does not give the second worktree a
port.

## The failure nobody mentions: cookies do not carry a port

Suppose you fix the ports by hand: `wt-a` on 3000, `wt-b` on 3001. Distinct
ports, distinct servers, distinct databases. One thing is still shared, and
it is the browser.

Cookies are scoped by host, not by origin. `localhost:3000` and
`localhost:3001` are different origins, but for the cookie jar they are the
same host (that is RFC 6265, not a browser bug). Measured with curl
following the same rule a browser does:

```
-- log in on worktree A (port 3000):
   server=wt-a received Cookie: (none)
-- request worktree B (port 3001) with the same browser:
   server=wt-b received Cookie: session=logged-in-as-wt-a
```

Worktree B received worktree A's session. If the two branches disagree about
the session schema, or one branch's login flow sets a cookie the other
crashes on, you get bugs that exist only in your browser and reproduce in
neither worktree alone.

Two fixes, both cheap:

**Give each worktree its own hostname.** Cookies are scoped by host, so
`wt-a.localhost:3000` and `wt-b.localhost:3001` keep separate jars
(session cookies carry no `Domain` attribute, which makes them
host-only). Chrome and Firefox resolve any `*.localhost` name to loopback
without touching `/etc/hosts`, so this costs nothing: stop opening
`localhost:3001` and open `wt-b.localhost:3001` instead.

**Or derive the cookie name from the port.** If the session cookie is
named per worktree, the host no longer matters:

```bash
# in the worktree setup hook, next to PORT itself
echo "SESSION_COOKIE_KEY=_myapp_session_${PWT_PORT}" >> .env
```

A private window still has a use, but as triage, not as the fix: when a
bug reproduces in your normal browser and not in a private window, it is
a cookie, and you can stop bisecting code.

## The fixes that do not survive N=3

**Boot-time auto-increment** is the Vite default above: whoever boots first
gets the real port, everyone else gets a surprise. The port depends on start
order, so it changes across reboots, and nothing you wrote down yesterday
points at the right server today.

**A free-port scan at creation time** is the fix I wrote first, and it has a
hole I did not see until it fired. The scan asks the operating system, and
the operating system only knows about servers that are *running*:

```
-- no servers running. worktree A scans for a free port:
   3000
-- worktree B, created five minutes later, runs the same scan:
   3000
```

Both scans are correct, both worktrees get 3000, and the collision is
deferred to the first day both servers are up at once. A worktree that is
not running is invisible to `lsof`, but it still owns its port. The machine
only knows what is bound right now, so ownership has to be recorded
somewhere the scan can read.

**Hashing the branch name** ([portree](https://github.com/fairy-pitta/portree)
does this) is stateless and survives the stopped-server problem, but two
branch names can hash to the same port, and the number tells you nothing:
you cannot look at 7433 and know which worktree it belongs to, or whether it
is safe to reuse.

Several published tools attack this with a reverse proxy and per-branch
subdomains:
[worktree-devservers](https://github.com/viktormarinho/worktree-devservers),
[portless](https://mcpservers.org/agent-skills/vercel/portless),
[Port Zero](https://portzero.net/). That shape solves two real problems,
the name you type in the browser and the cookie isolation from the
previous section, since each worktree gets its own hostname for free. It
is also the right shape when an external service needs
[one stable URL]({{ '/blog/your-oauth-callback-accepts-one-url-you-have-six-worktrees/' | relative_url }}).
But behind the proxy every server still needs its own distinct port, so a
proxy does not replace the allocator. It sits on top of one.

## Allocation with memory

What survives is boring: a base port per project, plus a record of which
worktree owns which offset. The allocator consults two sources, its own
records and the live machine, and a port is free only if both agree. This is
how [pwt](https://github.com/jonasporto/pwt) does it; the transcript below
is a real session:

```
-- base_port=3000; the main checkout keeps 3000. three creates:
   feature-a -> port 3001
   feature-b -> port 3002
   feature-c -> port 3003
-- remove feature-b, create feature-d: the freed port is reused
   feature-d -> port 3002
-- remove feature-d, let an unrelated process squat 3002, create feature-e:
   feature-e -> port 3004
```

Each line is one rule. Ports are handed out in order from a base you chose,
so the number is predictable and you can read `3003` and know it is the
third worktree of this project. Removed worktrees free their slot, so the
range does not grow forever. And the squatter line is the records
and the machine disagreeing: 3002 is free in the records but busy on the
machine, 3003 is free on the machine but owned by `feature-c` in the
records, so the allocator skips both.

The allocation happens at creation, which means the port exists *before the
app ever boots*. That ordering is what makes the number usable as an
identity: the setup hook can write it into `.env`, name the database after
it, and label the container with it, all before first boot. That derivation
step is [its own post]({{ '/blog/how-to-copy-env-into-a-git-worktree-and-what-it-breaks/' | relative_url }});
inside a Pwtfile the number is just `$PWT_PORT`.

Two honest caveats from running this for months. Reusing freed slots means
a recycled port inherits the previous owner's leftovers: `feature-d` took
3002 and, per the cookie measurement above, the browser will happily send it
a session cookie set by `feature-b`, which is one more reason to name the
cookie after the worktree. And an allocation check at creation
time cannot stop some later process from squatting your port while the
server is down; when that happens the record is stale, and `pwt fix-port`
reallocates instead of you editing metadata by hand.

> Running parallel coding agents in worktrees? Every failure in this post is
> invisible at N=1 and nearly guaranteed at N=3, and an agent will not
> notice a "trying another one" line in a server log it never reads. Give
> each agent's worktree its port at creation and pass it in the
> environment, so no agent ever picks a number at runtime.

The allocator, the metadata behind it and `$PWT_PORT` are part of
[pwt](https://github.com/jonasporto/pwt), a git worktree manager for
parallel development: `brew install jonasporto/pwt/pwt`. `pwt create` is the
allocation, `pwt list` shows who owns what, and `pwt fix-port` handles the
squatters.
