# Demos

This folder holds VHS tapes and their rendered GIFs and MP4s. The README
embeds the GIFs; the site (site/assets/demos/) uses the MP4s.

Structure:

```
examples/
  tapes/
    00-overview.tape
    01-quickstart.tape
    02-use-symlink.tape
    03-ports.tape
    04-jobs-wait.tape
  gifs/       # one .gif per tape
  videos/     # one .mp4 per tape
```

## Requirements

- vhs (https://github.com/charmbracelet/vhs)
- git

## Record

Run from the repo root:

```
for t in examples/tapes/*.tape; do rm -rf /tmp/pwt-demo-home; vhs "$t"; done
```

The tapes use a temp HOME at /tmp/pwt-demo-home and delete it at the start.
Every command a tape shows must exit 0: dry-run the storyline in a shell
first, because a recording that films an error ships that error to the
landing page. After re-recording, copy the MP4s to site/assets/demos/ and
regenerate the poster JPGs (see the site repo history for the ffmpeg line).

If you add a new tape, keep the naming scheme and update the README demo list.

## Pwtfile.reference

A reference `Pwtfile` written as a catalogue of scenarios rather than a
working file: what to do when several worktrees of one project need the same
global resource. Each section states whether the resource should be
**derived** (ports, database names), **isolated** (databases, queues) or
**shared** (caches, package stores), and shows the strategy.

Read it with `pwt help pwtfile` open; copy the sections you need.
