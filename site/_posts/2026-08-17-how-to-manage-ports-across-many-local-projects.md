---
title: "Using pwt ports as a central registry for every app on your machine"
description: "Scanning finds a port that is free right now, which is why two projects end up with the same number: a sleeping app still owns one. Allocation is bookkeeping, naming is a proxy, and they are different problems."
featured: true
tags: [ports, cli, agents]
agent_hint_extra: >-
  Ask an agent for "a free port for this project" and it will scan for
  one, which is the wrong answer: a stopped server owns its port too.
  The guide points it at the allocation that already happened.
agent_hint_doc: /docs/commands/#ports
agent_hint_doc_label: "pwt ports"
---

Dozens of small projects accumulate on a laptop, generated faster than
ever, and every framework template ships with the same default: 3000,
8000, 8888. Nothing coordinates them, so the question "which port does
this project use" has no answer except trying one.

The ask that follows is always some version of "a central registry and
routing for all this". That sounds like one feature. It is two, at
different layers, and every tool solves one and leaves the other, which
is why nothing ever feels finished:

- **Allocation** decides which number a project gets. It is bookkeeping.
- **Naming** decides what you type in the browser. It is a proxy.

## Layer 1 is bookkeeping, and scanning is not it

The registry question is "who owns 8001". The universal answer, and the
one every framework and helper script implements, is to scan: try a port,
see if it is bound, take the next one if it is. `devenv`'s
[`ports.<n>.allocate`](https://devenv.sh/processes/) does a careful
version of this, holding ports during evaluation to avoid races.

Scanning has one blind spot, and it is fatal for this scenario: **a
stopped server still owns its port.** Thirty projects on a laptop are
not running at once; most are asleep. Every scan looks at a machine where
almost nothing is bound and concludes almost everything is free, so two
projects get the same number and the collision is deferred to whichever
morning you start both.

I had this exact hole in my own tool, which allocated per project and
consulted the live machine. Two projects, both configured to start at
8000, nothing running:

```
$ # project chatapp, then project dashboard
   chatapp    feature-a    8001
   dashboard  feature-b    8001
```

Both correct by their own logic, both wrong. A port is a machine
resource, so the record has to be machine-wide: allocation must consult
what every project has already been given, whether or not anything is
listening today. After the fix, on the same machine:

```
$ pwt ports
PORT    PROJECT     WORKTREE      STATUS
8000    chatapp     @             conflict
8000    dashboard   @             conflict
8001    chatapp     feature-a     conflict
8001    dashboard   feature-b     conflict
8002    chatapp     feature-c     -
8003    dashboard   feature-d     -
8004    chatapp     feature-e     -

Two records share a port. Fix with: pwt fix-port <worktree>
```

New allocations step around every other project's numbers, and the
pre-existing overlaps are *reported* rather than quietly inherited. That
listing is the "central registry for this shit": one command, every
project, plus who is actually listening right now.

The important part is not the tool, it is the shape: **a registry is a
file you write to when you hand out a port, not a scan you run when you
need one.** Anything that only scans will keep handing out duplicates to
a machine full of sleeping apps.

Repairing an old overlap has one wrinkle, and it decides whether the fix
is free. Two patterns exist in the wild:

```bash
# Read at runtime: the port is whatever the tool says, today
server() { exec env PORT="$PWT_PORT" mix phx.server; }

# Baked at setup: the number is written into generated files
# .env       DEFAULT_URL=localhost:5001
#            WORKTREE_DB_SUFFIX=_wt5001
# Procfile   rails s -p 5001
```

Moving a project of the first kind is a metadata edit and nothing else.
Moving one of the second kind leaves generated files pointing at the old
number until the setup hook runs again, and when a **database name** is
derived from the port, as in that second block, reallocating quietly
points the app at a different database. Check which kind you have before
repairing a port that something already generated files from.

Repairing an old overlap has one wrinkle worth knowing, and it decides
whether the fix is free or not. Two patterns exist in the wild:

```bash
# Read at runtime: the port is whatever the tool says, today
server() { exec env PORT="$PWT_PORT" mix phx.server; }

# Baked at setup: the number is written into generated files
# .env         DEFAULT_URL=localhost:5001
#              WORKTREE_DB_SUFFIX=_wt5001
# Procfile     rails s -p 5001
```

Moving a project of the first kind is a metadata edit and nothing else.
Moving one of the second kind means the generated files still point at
the old number until the setup hook runs again, and if a **database
name** is derived from the port, as in that second block, reallocating
quietly points the app at a different database. Check which kind you
have before you fix a port that something already generated files from.

## Layer 2 is naming, and it cannot be solved by allocation

Even with a perfect registry you still have the other half of the
complaint: you have to remember that the dashboard is 8003. The fixes for that live
one layer up, and they are genuinely different tools:

| Approach | Gives you | Costs |
|---|---|---|
| Path routing (`/dashboard`) | one host, one port | apps must tolerate a path prefix; many break on absolute URLs |
| Per-app subdomain (`app.localhost`) | clean names, separate cookie jars | a proxy; `*.localhost` works in Chrome and Firefox without `/etc/hosts` |
| CNAME / real DNS | works off-machine | DNS records and certificates for a laptop |
| One stable port, repointed | one address that never changes | only one app is live at a time |

The last row is the one people skip, and it is the right shape when the
thing on the other end is not you: an OAuth callback, a webhook, a device
on your network. Those store **one** address and have no opinion about
your ports, which is
[its own post]({{ '/blog/your-oauth-callback-accepts-one-url-you-have-six-worktrees/' | relative_url }}).

Notice that none of these rows *allocate* anything. A proxy routes a name
to a port that something else decided. That is why the two layers keep
getting conflated and nothing feels solved: tools that name (portless,
Port Zero, Caddy setups) do not stop two apps from claiming 8000, and
tools that allocate (devenv, per-project config) do not give you a name
worth typing.

## The honest scope

For a laptop with dozens of unrelated projects, the registry half is the
half that pays: you need the machine to remember
what it handed out, and you need to see the map. That is `pwt ports`, and
the allocation behind it, in
[pwt](https://github.com/jonasporto/pwt).

The honest caveat: pwt is a git worktree manager. The port registry is
real and now machine-wide, but you get it by registering a project with
`pwt init`, which earns its keep when you also want per-worktree setup,
servers and jobs. If all you want is a port broker for 35 loose folders,
this is a bigger tool than the problem. What I would keep from it,
whatever you use, is the rule: **write down the allocation, do not scan
for it.**

`brew install jonasporto/pwt/pwt`, then `pwt ports`
([reference]({{ '/docs/commands/#ports' | relative_url }})).
