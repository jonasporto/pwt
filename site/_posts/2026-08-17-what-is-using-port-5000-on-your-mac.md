---
title: "What is using port 5000 on your Mac (and why your tools call it a running server)"
description: "AirPlay Receiver holds 5000 and 7000, answers HTTP 403 as AirTunes, and satisfies every readiness probe pointed at it. Whether it collides with your server depends on one socket option. Four false positives I found in my own tool, and the classifier that fixes all of them."
featured: true
tags: [ports, macos, cli]
agent_hint_extra: >-
  You do not have to remember which ports macOS takes. `pwt ports` labels
  a port held by a system daemon as `system` instead of `listening`, and
  `--json` carries `"system": true` for scripts.
agent_hint_doc: /docs/commands/#ports
agent_hint_doc_label: "pwt ports"
---

Here is what owns port 5000 on my Mac:

```
$ lsof -nP -iTCP:5000 -sTCP:LISTEN
COMMAND         PID   USER  TYPE  NAME
ControlCenter   649  jonas  IPv4  *:5000 (LISTEN)
```

That is macOS itself: **AirPlay Receiver**, added in Monterey and enabled
silently for anyone who upgraded, with Control Center holding the socket.
It takes 7000 as well. Of the 156 listening sockets on this machine,
those two are the only ones below 10000 owned by a system daemon, and
both belong to that one process.

The Flask documentation states it outright, in the "Address already in
use" section: *"macOS Monterey and later automatically starts a service
that uses port 5000."*

## It does not just occupy the port. It answers.

```
$ curl -i http://127.0.0.1:5000/
HTTP/1.1 403 Forbidden
Content-Length: 0
Server: AirTunes/860.7.1
```

Both ports answer, both with 403, both identifying as AirTunes. That is
the part every write-up about this skips, and the part that causes the
expensive failures. A TCP connect succeeds. An HTTP request gets a
response. Anything built on "can I reach this port" concludes your server
is up.

## Whether it collides with you depends on one socket option

This surprised me, so I measured it instead of assuming. Same machine,
same daemon on `*:5000`, four attempts to bind:

| Bind | Result |
|---|---|
| `127.0.0.1:5000`, no `SO_REUSEADDR` | `OSError: [Errno 48] Address already in use` |
| `127.0.0.1:5000`, with `SO_REUSEADDR` | **binds fine** |
| `0.0.0.0:5000`, with `SO_REUSEADDR` | `Errno 48` |
| Ruby `TCPServer.new('127.0.0.1', 5000)` | **binds fine** |

Control Center holds the **wildcard** address. On BSD, and therefore on
macOS, a socket with `SO_REUSEADDR` may bind a *specific* address while
another socket holds the wildcard on the same port. Linux does not allow
that. Ruby's `TCPServer` sets `SO_REUSEADDR` for you; a raw Python socket
does not.

So "does AirPlay break my dev server" has no single answer. It depends on
your language's socket defaults and on whether you bind localhost or all
interfaces. It also means **a real server and the daemon can be listening
on the same port at the same time**, which turns out to matter later.

The errors, when you do collide, measured here rather than copied:

| Stack | What it prints |
|---|---|
| Python | `OSError: [Errno 48] Address already in use` (Linux says 98) |
| Ruby | `Errno::EADDRINUSE: Address already in use - bind(2) for "0.0.0.0" port 5000` |
| Node | `Error: listen EADDRINUSE: address already in use :::5000` |
| Go | `listen tcp 0.0.0.0:5000: bind: address already in use` |

Those are the honest failures. The interesting ones print nothing at all.

## Four ways my own tool got this wrong

pwt allocates a port per worktree and reports what is running. Pointed at
a machine with AirPlay on, every reporting path was wrong:

```
$ pwt ports
PORT    PROJECT   WORKTREE   STATUS
5000    app       feat       listening        # nothing is running

$ pwt server wait feat --timeout 600
Ready: feat (port 5000)                       # returned immediately

$ pwt info feat
  Server:  running (PID 649)                  # that is Control Center
```

And the one I am least proud of:

```
$ pwt remove feat
Error: Processes detected on port 5000:
  PID 649 (/System/Library/CoreServices/ControlCenter.app/.../ControlCenter)

Options:
  pwt remove feat --kill-port    # Kill port processes
```

The removal was blocked by a process nobody should be killing, and the
suggested way out was `kill -9` on Control Center. I found that by
writing the test before the fix: run it against the old code and the
output reads `✓ Port 5000 freed`, right after the signal goes out.

`pwt server wait` is the one that actually costs you. An agent starts a
server, waits for readiness, gets "Ready" instantly, and calls an
endpoint that belongs to AirTunes. The 403 comes back and the failure
surfaces three steps later, somewhere unrelated to the port.

## Why one command got it right and the rest did not

pwt already knew how to tell a system daemon from a dev server. The check
existed, correct and complete, in **exactly one function**, reached by
exactly one command: `pwt list -v` printed `[port 5000: system]` while
everything else printed `listening`.

That is the general shape of this bug and it deserves a name: **a filter
that lives in one code path is not a filter, it is a coincidence.** Each
later occupancy check was written by someone looking at the socket, not
at the function three files away that had already solved it. No amount of
care prevents that. Only a single callable place does.

## What "a system process" means, mechanically

You cannot ask the kernel whether a listener is "yours". You can ask who
owns the pid:

```bash
port_pid_is_system() {
    cmd=$(ps -p "$1" -o command= 2>/dev/null) || return 1
    exe="${cmd%% *}"
    case "$exe" in /System/* | /usr/libexec/*) return 0 ;; esac
    case "${exe##*/}" in
        ControlCenter | rapportd | AirPlayXPCHelper | sharingd) return 0 ;;
    esac
    return 1
}
```

Two decisions in there carry weight.

**A port counts as system only when every listener on it is one.** This
is where the `SO_REUSEADDR` measurement stops being trivia: a Ruby server
really can hold `127.0.0.1:5000` while Control Center holds `*:5000`.
Verified with both running at once, the port reports `listening`, which
is correct, because one of the two listeners is a server you started.

**Allocation is unchanged.** A system-held port stays unavailable for new
worktrees, because you cannot reliably bind what Control Center holds.
The whole fix is about what gets *reported*, never about what gets handed
out. Making 5000 allocatable again would have been the obvious next step
and the wrong one: it hands a worktree a port whose server may fail to
start depending on how that server opens its socket.

Cost: one `ps` over every listener, once per command, 40ms with 151 of
them. Per-port classification instead would be a fork per worktree, which
is exactly what a snapshot exists to avoid.

## The options, and what each costs

**Turn AirPlay Receiver off.** System Settings, General, AirDrop &
Handoff. It frees both ports, and you lose the ability to AirPlay to that
Mac. If you never use it, do this and stop reading.

**Move your port.** Correct, and more expensive than it looks. On one
project here the port is not just a flag: it is written into `.env`, into
the Procfile, and the database name derives from it, so moving the port
meant recreating a database. That is the argument for a tool that
allocates ports and *derives* the dependent values, instead of copying a
file that already contains a number.

**Teach the tool the difference.** What I shipped in 0.2.9:

```
$ pwt ports
PORT    PROJECT   WORKTREE   STATUS
5000    app       feat       system

system: held by a macOS daemon, not by a server of yours.
  AirPlay Receiver takes 5000 and 7000: turn it off in System
  Settings > General > AirDrop & Handoff, or move the port with
  pwt fix-port <worktree>.
```

`pwt server wait` now refuses immediately, with the reason, instead of
waiting out a ten-minute timeout on a port that can never become yours.

## One myth, since it is everywhere

Several popular write-ups claim Flask changed its default port to 5001 on
macOS because of this. It did not. The current documentation (3.1.x)
still starts the server on `http://localhost:5000/` and tells you to
disable AirPlay Receiver or pass `--port 5001` yourself. Check the docs
of whatever you are actually running before trusting a fix you read
somewhere, this article included.

## The rule underneath

"Something is bound to this port" and "my server is running" are
different questions, and most tools answer the first while printing the
second. It stays invisible until a daemon you did not start occupies
exactly the port your framework defaults to, which on macOS is the
default case.

`brew install jonasporto/pwt/pwt`, then `pwt ports`
([reference]({{ '/docs/commands/#ports' | relative_url }})) to see every
allocation on the machine and who actually holds each one. Ports across
many projects are [their own
post]({{ '/blog/how-to-manage-ports-across-many-local-projects/' | relative_url }}),
and per-worktree allocation is
[here]({{ '/blog/how-to-deal-with-port-allocation-in-git-worktrees/' | relative_url }}).
