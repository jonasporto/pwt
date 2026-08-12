---
title: "A leaked file descriptor hung our CI for six hours (five times in a row)"
description: "A coverage job sat silent until GitHub's 6-hour timeout. The cause: one file descriptor leaked into a daemon."
featured: true
image:
  path: /assets/covers/card-fd.png
  width: 1200
  height: 630
---

pwt's coverage job hit GitHub Actions' six-hour default timeout in **every
single run** since the job was added. No error, no failing test. The log
just stopped after one specific test and sat there burning a runner.

The cause turned out to be one leaked file descriptor. This post is the
debugging story, because every ingredient is reusable: how `bats` waits for
output, how `kcov` traces bash, and how easy it is to hand a daemon a pipe
you did not know you had.

## The symptom

The suite (~840 [bats](https://github.com/bats-core/bats-core) tests)
passed everywhere: Linux, macOS, `set -u`, minimal containers. Only the
coverage job hung, and always at the same place: the first test that starts
pwt's gateway, a small node proxy that gives every Git worktree a stable
URL. Six hours later, the runner's cleanup listed the orphans. A `node`
process, a `python3` fixture server, and one `kcov`.

That orphan list was the tell. Those are exactly the processes of the
gateway test.

## Three facts that make the hang

**Fact 1: `bats` waits on pipes, not just children.** A test's output is
captured through pipes. Anything that inherits the write end and outlives
the test keeps the pipe open, and the reader keeps waiting. pwt already
solves this for its background jobs: daemons go through a small perl
`fork` + `setsid` launcher that closes every inherited descriptor above
stderr before `exec`.

**Fact 2: `kcov` traces bash through a pipe of its own.** For bash
coverage, kcov runs the script with a DEBUG-trap engine that reports
executed lines through an extra file descriptor. Your code never sees it,
but it sits in the fd table like any other. Children inherit it.

**Fact 3: node's `spawn()` only controls fds 0-2.** The gateway daemon was
spawned from a node one-liner with `detached: true` and
`stdio: ["ignore", out, out]`. That configures stdin, stdout, stderr, and
nothing else. Every descriptor above 2 leaks into the detached child.

Chain them: under coverage, pwt runs wrapped by kcov, so its fd table
contains kcov's trace pipe. The test starts the gateway. node's `spawn()`
hands the daemon that pipe. pwt exits, kcov keeps reading a pipe whose
write end now belongs to a daemon that never exits, `bats` waits for kcov,
and GitHub kills the job at hour six.

The perl-launched daemons never had this problem. Closing fds 3..max was
already their job. The gateway was the one daemon launched a different way.
That is why tests 18 and 19 (background jobs) passed and test 21 (gateway)
hung.

## The fix

Launch the gateway through the same perl launcher as every other daemon:

```perl
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

One launcher, one place to get fd hygiene right. After the fix the coverage
run completed on its own, 840 of 841 tests green under instrumentation.

## What we hardened afterwards

- **`timeout-minutes` on every job.** A hang should cost minutes, not six
  hours of a runner. GitHub's default job timeout is 360 minutes. Almost no
  job deserves it.
- **`timeout(1)` around the coverage run itself**, so a future hang still
  merges and uploads whatever was collected before the cap.
- **Daemons must close inherited fds, not just detach.** `setsid` plus
  redirecting stdio is not enough. The descriptors you did not know you had
  are the ones that bite.

> Debugging a hang like this with an AI agent? Give it the orphan-process
> list from the runner's cleanup log first. It named every process involved
> here, and turned a six-hour mystery into an fd-table question.
{: .hint}

The gateway that started all this (one stable URL routing to whichever
worktree you're testing) is part of
[pwt](https://github.com/jonasporto/pwt), a Git worktree manager for
parallel development: `brew install jonasporto/pwt/pwt`.
