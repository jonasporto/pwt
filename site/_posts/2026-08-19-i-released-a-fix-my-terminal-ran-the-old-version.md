---
title: "I released the fix. My terminal ran the version from three releases ago."
description: "npm -g does not install globally: it installs into the current node version, nvm puts that directory first on PATH, and your shell quietly answers with whatever lives there. How to see which copy of a CLI is really running, and why npx pkg@latest is the one probe nothing can shadow."
featured: true
tags: [cli, env-config, agents]
agent_hint_extra: >-
  Before debugging pwt behavior, confirm which install answers:
  `pwt doctor` warns when the pwt on PATH is not the binary running, and
  `pwt self` lists every installation with versions.
agent_hint_doc: /docs/commands/#doctor
agent_hint_doc_label: "pwt doctor"
---

I spent an hour debugging two fixes that were correct all along. The
terminal I tested them in was running a version from three releases
earlier:

```
$ pwt --version
pwt version 0.2.8

Update available: 0.2.9
Run: npm i -g @jonasporto/pwt@latest
```

The repository checkout on that same machine carried 0.2.11, freshly
released, symlinked into `~/.local/bin/pwt` exactly so the shell would
always run it. The shell had other plans.

## "Global" installs are not global

`which pwt` pointed here:

```
~/.nvm/versions/node/v22.17.0/bin/pwt
```

That path says everything. `npm i -g` does not install globally: it
installs **into the bin directory of whichever node version is active**.
Under nvm, that directory sits at the front of PATH, ahead of
`~/.local/bin`, ahead of Homebrew, ahead of your intentions.

Two consequences, both measured on this machine:

**Each node version has its own set of "global" CLIs.** Listing the two
node versions installed here: v22 had `pwt` (the stale 0.2.8); v18 has
`gemini` and `task-master` and **no pwt at all**. `nvm use 18` and the
command changes identity or vanishes, with no output telling you so.

**The full inventory was worse than one stale copy.** Asking the tool
itself:

```
$ pwt self
pwt installations:
→ npm    v0.2.8   ~/.nvm/versions/node/v22.17.0/bin/pwt
  local  v0.2.11  ~/code/pwt/bin/pwt    (the dev symlink, shadowed)
  brew   v0.2.0   /opt/homebrew/Cellar/pwt/0.2.0/bin/pwt
```

Three copies, three versions, spanning six months. The arrow marks the
one the shell answers with, and it was the one I had forgotten
installing.

## The probes, ranked by what they can lie about

```
$ which -a pwt      # every match on PATH, in order (zsh: whence -a)
$ type -a pwt       # same, plus functions and aliases -- use this one
```

`type -a` matters because a shell **function** outranks every PATH entry,
and tools like pwt, zoxide and direnv install one. What happens when the
function itself goes stale is [its own
post]({{ '/blog/your-shell-function-outlived-its-binary/' | relative_url }}),
and it is the sequel to this one: I removed the npm copy, and the
function that had it baked in took the shell down with it.

And the one probe that nothing local can shadow:

```
$ npx -y @jonasporto/pwt@latest doctor
```

`npx` is a different command name, so no `pwt` function intercepts it,
and it resolves `@latest` against the **registry**, so no PATH entry
matters. Measured while writing this: it picked up a version published
four minutes earlier. One honest caveat: run it *during* a publish and
you get the previous latest; the registry tag moves when the release
workflow finishes, not when the tag is pushed.

## What the tool now does about it

Two changes shipped in 0.2.12, both born from that hour:

```
$ pwt doctor
⚠  Installation: the pwt on PATH is not the one running
    running:  ~/code/pwt/bin/pwt (v0.2.12)
    on PATH:  ~/.nvm/versions/node/v22.17.0/bin/pwt (v0.2.8)
    Your shell answers with the PATH one. List all: pwt self
```

The check is one comparison: resolve the binary that is executing,
resolve the first `pwt` on PATH, and refuse to stay quiet when they
differ. It costs nothing and it is the setup problem that hides every
other one: **fixes that are correct in one install do nothing while the
shell runs another.**

The second change is the pointer above: the update notice (which is what
cracked the case, a 0.2.8 announcing that 0.2.9 existed), the doctor
warning, and the stale-wrapper error all now name the `npx` rescue,
because it is the only diagnosis that works no matter how tangled the
local installs are.

## The actual fix: one owner per command name

Diagnosis is not the fix. The fix is deciding which install owns the
command and deleting the rest:

```
$ npm rm -g @jonasporto/pwt     # the stale global
$ brew uninstall pwt            # the fossil from February
$ pwt self                      # confirm one entry remains, marked active
```

If you develop the tool, the owner is the dev symlink and everything
else is a trap waiting for a debugging session. If you only use it, pick
**one** package manager and never install the same CLI with two: the
second install does not replace the first, it enters a precedence
contest you will lose track of.

The rule underneath is the same one this blog keeps arriving at from
different directions: "which one answers" is state, state drifts, and
state that drifts needs an inventory command and a doctor that checks
it. `pwt self` is the inventory; `pwt doctor`
([reference]({{ '/docs/commands/#doctor' | relative_url }})) is the
check; `npx @jonasporto/pwt@latest doctor` is the version of the check
you can run from a machine where everything else lies.
