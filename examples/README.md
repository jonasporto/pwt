# Demos

This folder holds VHS tapes and rendered GIFs for the README.

Structure:

```
examples/
  tapes/
    01-quickstart.tape
    02-use-symlink.tape
  gifs/
    00-overview.gif
    01-quickstart.gif
    02-use-symlink.gif
  videos/
    00-overview.mp4
```

## Requirements

- vhs (https://github.com/charmbracelet/vhs)
- git

## Record

Run from the repo root:

```
vhs examples/tapes/01-quickstart.tape
vhs examples/tapes/02-use-symlink.tape
```

The tapes use a temp HOME at /tmp/pwt-demo-home and delete it at the start.

If you add a new tape, keep the naming scheme and update the README demo list.

## Pwtfile.reference

A reference `Pwtfile` written as a catalogue of scenarios rather than a
working file: what to do when several worktrees of one project need the same
global resource. Each section states whether the resource should be
**derived** (ports, database names), **isolated** (databases, queues) or
**shared** (caches, package stores), and shows the strategy.

Read it with `pwt help pwtfile` open; copy the sections you need.
