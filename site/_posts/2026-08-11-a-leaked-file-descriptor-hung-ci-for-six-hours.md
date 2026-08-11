---
title: "A leaked file descriptor hung our CI for six hours (five times in a row)"
description: "Debugging a kcov coverage job that sat silent until GitHub's 6-hour timeout: node's spawn() only controls fds 0–2, and one daemon kept a trace pipe open."
featured: true
---

pwt's coverage job hung until GitHub Actions' six-hour default timeout in
**every single run** since the job was added. No error, no failing test — the
log just stopped after one specific test and sat there burning a runner.

This is the kind of bug worth writing down, because every ingredient is
reusable: how `bats` waits for output, how `kcov` traces bash, and how easy it
is to leak a file descriptor into a daemon.

## The symptom

The suite (~840 [bats](https://github.com/bats-core/bats-core) tests) passed
everywhere — Linux, macOS, `set -u`, minimal containers. Only the coverage job
hung, and always at the same place: the first test that starts pwt's gateway,
a small node proxy that gives every Git worktree a stable URL. Six hours
later, the runner's cleanup listed the orphans: a `node` process, a `python3`
fixture server, and one `kcov`.

## Three facts that make the hang

**1. `bats` waits on pipes, not just children.** When a test runs under
`bats`, its output is captured through pipes. Anything that inherits the write
end of those pipes — including a daemon that outlives the test — keeps the
pipe open, and the reader keeps waiting. pwt already solves this for its
background jobs: daemons are launched through a small perl
`fork` + `setsid` helper that closes every inherited descriptor above stderr
before `exec`.

**2. `kcov` traces bash through a pipe of its own.** For bash coverage, kcov
runs the script with a DEBUG-trap engine that reports executed lines through
an extra file descriptor. That descriptor is invisible to your code, but it
is in the process's fd table like any other — and children inherit it.

**3. `node`'s `spawn()` only controls fds 0–2.** The gateway daemon was
spawned from a node one-liner with `detached: true` and
`stdio: ["ignore", out, out]`. That configures stdin, stdout, stderr —
nothing else. Every descriptor above 2 leaks into the detached child.

Put together: under coverage, pwt runs wrapped by kcov, so its fd table
contains kcov's trace pipe. The test starts the gateway; node's `spawn()`
hands the daemon that pipe; pwt exits; kcov keeps reading a pipe whose write
end is now owned by a daemon that never exits. `bats` waits for kcov, the
job waits for `bats`, and GitHub kills everything at hour six.

The perl-launched daemons never had this problem — closing fds 3..max was
already their job. The gateway was the one daemon launched a different way.

## The fix

Launch the gateway through the same perl daemonizer as every other daemon:

```
my $pid = fork();
if ($pid == 0) {
    setsid();
    open(STDIN,  "<",  "/dev/null");
    open(STDOUT, ">>", $log);
    open(STDERR, ">&STDOUT");
    my $max = POSIX::sysconf(&POSIX::_SC_OPEN_MAX) || 256;
    POSIX::close($_) for 3 .. $max;
    exec("node", $script) or die "exec failed: $!";
}
```

One daemonizer, one place to get fd hygiene right.

## What we hardened afterwards

- **`timeout-minutes` on every job.** A hang should cost minutes, not six
  hours of a runner. GitHub's default job timeout is 360 minutes; almost no
  job deserves it.
- **`timeout(1)` around the coverage run itself**, so a future hang still
  merges and uploads whatever coverage was collected before the cap.
- **Daemons must close inherited fds** — not just detach. `setsid` +
  redirecting stdio is not enough; the descriptors you did not know you had
  are the ones that bite.

If you manage Git worktrees for parallel development (human or agent-driven),
that gateway — one stable URL routing to whichever worktree you're testing —
is part of [pwt](https://github.com/jonasporto/pwt). `brew install
jonasporto/pwt/pwt` or `npm i -g @jonasporto/pwt`.
