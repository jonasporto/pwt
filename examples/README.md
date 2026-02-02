# Demos

This folder holds VHS tapes and rendered GIFs for the README.

Structure:

```
examples/
  tapes/
    01-quickstart.tape
    02-use-symlink.tape
    03-status-tui.tape
  gifs/
    01-quickstart.gif
    02-use-symlink.gif
    03-status-tui.gif
```

## Requirements

- vhs (https://github.com/charmbracelet/vhs)
- git, jq

## Record

Run from the repo root:

```
vhs examples/tapes/01-quickstart.tape
vhs examples/tapes/02-use-symlink.tape
vhs examples/tapes/03-status-tui.tape
```

The tapes use a temp HOME at /tmp/pwt-demo-home and delete it at the start.

If you add a new tape, keep the naming scheme and update the README demo list.
