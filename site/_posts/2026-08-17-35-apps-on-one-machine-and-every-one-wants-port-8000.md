---
title: "35 apps on one machine, and every one wants port 8000"
description: "Vibecoded projects pile up and every framework defaults to the same port. The ask is a central registry and routing, and those are two different problems: one is bookkeeping, one is a proxy."
featured: true
tags: [ports, cli, agents]
agent_hint_extra: >-
  Ask an agent for "a free port for this project" and it will scan for
  one, which is the wrong answer: a stopped server owns its port too.
  The guide points it at the allocation that already happened.
agent_hint_doc: /docs/commands/#ports
agent_hint_doc_label: "pwt ports"
---

Joshua Schachter, [yesterday](https://x.com/joshu):

> there are like 35 various web applications running on my machine on
> different ports through various vibecoding projects. we really need some
> sort of central routing and registry for this shit. Every vibecoding
> project wants :8888 and :8000

And in the follow-up, the part that names the real difficulty:

> i mean we could also just route the top level of the url path. or use a
> cname. all of these things are at different application layers, it's
> irritating

That is the whole problem in two tweets. **"Central routing and registry"
is not one feature, it is two**, at different layers, and every tool
picks one and calls it solved.

## Layer 1 is bookkeeping, and scanning is not it

The registry question is "who owns 8001". The universal answer, and the
one every framework and helper script implements, is to scan: try a port,
see if it is bound, take the next one if it is. `devenv`'s
[`ports.<n>.allocate`](https://devenv.sh/processes/) does a careful
version of this, holding ports during evaluation to avoid races.

Scanning has one blind spot, and it is fatal for this scenario: **a
stopped server still owns its port.** Thirty-five vibecoded projects are
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

## Layer 2 is naming, and it cannot be solved by allocation

Even with a perfect registry you still have Schachter's other complaint:
you have to remember that the dashboard is 8003. The fixes for that live
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

For the machine described in that tweet, 35 unrelated projects, the
registry half is the half that pays: you need the machine to remember
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
