# Security Policy

## Supported versions

pwt is a small tool with a single active line: fixes land on the latest
release. If you are on an older version, upgrade before reporting.

## Reporting a vulnerability

Please **do not** open a public issue for a security problem.

Use GitHub's private reporting — *Security* → *Report a vulnerability* on
https://github.com/jonasporto/pwt — which opens a confidential thread with
the maintainer.

Include what you can: the pwt version (`pwt --version`), your OS and shell,
the commands involved, and the smallest reproduction you have. You should get
an acknowledgement within a week.

## Scope

pwt is a local developer tool. It runs git, allocates ports for local dev
servers, and **executes project-provided `Pwtfile` scripts** as your user.

Some things follow from that design and are not vulnerabilities:

- A Pwtfile runs arbitrary shell code. Treat a repository's Pwtfile exactly
  like its build scripts: only run pwt in repositories you trust.
- Background job logs under `~/.pwt/jobs/` contain whatever your dev server
  printed, which may include secrets your app logged.
- State under `~/.pwt/` is plain text, readable by your user.

Things that **are** in scope: command injection through worktree, branch or
project names; a path that escapes `worktrees_dir` or `~/.pwt`; leaking
credentials into state files, logs or command lines; and privilege issues in
the installer.
