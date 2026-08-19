---
title: "zsh: no such file or directory, and source ~/.zshrc will not fix it"
description: "A shell function kept calling a binary I had deleted, and re-sourcing the rc file could not heal it, because the broken function intercepts its own repair. The mechanics, the one-line escape (unfunction), and what a tool that installs wrapper functions owes you."
featured: true
tags: [bash, cli, agents]
agent_hint_extra: >-
  If pwt itself misbehaves, `pwt doctor` reports when the pwt on PATH is
  not the binary running, and `npx @jonasporto/pwt@latest doctor` runs
  the latest doctor with no local install at all.
agent_hint_doc: /docs/commands/#doctor
agent_hint_doc_label: "pwt doctor"
---

This terminal is broken in a way that `source ~/.zshrc` cannot fix:

```
$ pwt --version
pwt:128: no such file or directory: ~/.nvm/versions/node/v22.17.0/bin/pwt
$ source ~/.zshrc
$ pwt --version
pwt:128: no such file or directory: ~/.nvm/versions/node/v22.17.0/bin/pwt
```

The error names an nvm path because I had just uninstalled an npm copy
of the tool. Every subsequent call failed, and so did every re-source.
The fix is one word, and the interesting part is why the obvious fix is
not it.

## What `pwt` is in a terminal (and `z`, and `nvm`, and yours)

Tools that need to change your shell's state cannot be plain binaries: a
child process cannot `cd` its parent. So they install a **function**,
usually via a line their setup added to your rc file:

```bash
eval "$(pwt shell-init)"     # pwt
eval "$(zoxide init zsh)"    # z
eval "$(direnv hook zsh)"    # direnv
```

The function decides which calls change the shell (a `cd`, an export)
and forwards everything else to the real binary. And in zsh and bash,
**a function beats a PATH binary with the same name**, verified:

```
$ foo() { echo "function wins"; }
$ printf '#!/bin/sh\necho binary wins\n' > /tmp/bin/foo   # on PATH
$ foo
function wins
$ command foo
binary wins
```

That precedence is the entire feature. It is also the entire bug.

## The deadlock, step by step

1. The generated function had the binary's absolute path **baked in** at
   generation time, pointing at the npm install.
2. I removed the npm install (it was shadowing the checkout I actually
   develop, a story of its own). The baked path now resolves to nothing.
3. Every `pwt <anything>` fails inside the function, before any binary
   runs: `no such file or directory`.
4. `source ~/.zshrc` re-runs `eval "$(pwt shell-init)"`, which should
   regenerate the function from the correct binary. But `pwt` in that
   command substitution **is the broken function**, because functions
   beat PATH. The function fails, the substitution produces nothing,
   `eval ""` changes nothing, and the broken function survives its own
   repair.

That last step is the part worth remembering: a broken wrapper function
intercepts the very command that would replace it. You can re-source all
day.

## The escape

```
$ unfunction pwt        # zsh (bash: unset -f pwt)
$ source ~/.zshrc
$ pwt --version
pwt version 0.2.11
```

With the function gone, `pwt` resolves through PATH again, `shell-init`
runs from the real binary, and the eval installs a fresh function. To
see what you actually have before and after:

```
$ whence -a pwt          # zsh: every resolution, in precedence order
pwt                      # <- the function
/Users/you/.local/bin/pwt
$ type -a pwt            # bash equivalent
```

Terminal emulator is irrelevant, in case you wonder mid-debug like I
did: this is shell semantics, identical in iTerm, Terminal.app or a raw
tty.

## What the tool owes you

A user should never need to know the word `unfunction`. Two changes
shipped in pwt 0.2.12 because of this morning:

**The function heals itself.** It now checks the baked path at call time
and falls back to the first `pwt` on PATH when the path is gone, so a
stale function regenerates on the next source instead of deadlocking
behind itself. With no binary anywhere it exits 127 with instructions,
not a raw path error. Both branches have tests that generate the wrapper
from a symlink and delete it; both were red against the old code. Fish
never had the bug: its wrapper resolves via `command pwt` on every call,
which is the design this fix converges on.

**The doctor names the shadow.** The reason the npm copy existed at all
is the prequel: my shell had been running an npm-installed 0.2.8 while I
debugged "why doesn't the fix work" against a repo checkout carrying
0.2.11. An hour went to fixes that were correct all along. Now:

```
$ pwt doctor
⚠  Installation: the pwt on PATH is not the one running
    running:  ~/code/pwt/bin/pwt (v0.2.12)
    on PATH:  ~/.nvm/versions/node/v22.17.0/bin/pwt (v0.2.8)
    Your shell answers with the PATH one. List all: pwt self
```

And for the state where nothing local can be trusted, the rescue that
bypasses both lying layers, since `npx` is not intercepted by the
function and ignores your PATH's pwt entirely:

```
$ npx @jonasporto/pwt@latest doctor
```

## The general lesson

If your tool installs a shell function, that function will one day
outlive whatever it points at, on a machine you cannot see. Three rules
fall out of one morning:

- **Resolve at call time, or verify before use.** A baked path is a
  cache with no invalidation.
- **Never let the wrapper stand between the user and its own repair.**
  Test the specific loop: break the binary, then source the rc file, and
  assert the function comes back.
- **Give the diagnosis a command that works when everything is broken.**
  For an npm-published CLI, `npx pkg@latest doctor` costs nothing and
  cannot be shadowed.

`brew install jonasporto/pwt/pwt`, and if the one you already have is
acting strange, start with `pwt doctor`
([reference]({{ '/docs/commands/#doctor' | relative_url }})): which
install answers, whether something shadows it, and what to do about it.
