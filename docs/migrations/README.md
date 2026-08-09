# State migrations

pwt keeps its state on disk (`~/.pwt`). When that layout changes, existing
installs must be converted. This directory defines how that happens — the
process is the same for every future change, so both people and AI agents can
follow it without reading the implementation.

## What is versioned

The **state schema**, not the pwt release. `~/.pwt/state-version` holds a
single integer. A release may contain zero or many migrations; a migration is
always a step between two schema versions.

| Schema | Introduced by | Guide |
|---|---|---|
| 1 | (implicit — no `state-version` file) | — |
| 2 | next release (unreleased) | [001-v1-to-v2.md](001-v1-to-v2.md) |

An install on schema N applies every migration from N+1 upward, in order,
until it reaches the version the binary expects. Downgrades are not
supported: recovery is by restoring the `.v1.bak`-style backups a migration
leaves behind.

## The contract

Every migration provides four operations. `pwt state migrate` drives them; nothing
else may write state during a migration.

| Operation | Must do | Must never do |
|---|---|---|
| `describe` | One paragraph: what moves where, and why | — |
| `check` | Dry run: count inputs, report what *would* convert and what would be skipped, exit non-zero if the source is unreadable | Modify anything |
| `up` | The transform, then leave every source file in place as `<name>.vN.bak` | Delete a source; declare success on partial output |
| `verify` | Check that **each** input record landed, naming any that did not | Compare raw counts (state legitimately gains records created after the migration); assume success because no command errored |

Three rules, each learned from a real failure:

1. **Never silence the parser.** `jq ... 2>/dev/null` hid an abort that
   dropped 8 of 10 projects while the migration reported success. Capture
   stderr, check the exit status, and abort without touching state.
2. **Type-guard every level.** Real installs accumulate malformed entries.
   One bad record must be skipped and *named*, never allowed to truncate the
   run.
3. **Check, don't trust.** `verify` exists because "no error" is not
   evidence. Verify per record, not by totals: on the first real run a raw
   count mismatched simply because a worktree created *after* the migration
   marker was a legitimate extra file.

## Running a migration

Migration is automatic on the first command after an upgrade. To do it
deliberately — recommended when the install is large or shared:

```bash
pwt state migrate --status  # current schema, target schema, pending steps
pwt state migrate --check   # dry run: what would change, with counts
pwt state migrate           # apply pending migrations
pwt state migrate --verify  # re-run the checks against the migrated state
```

`--check` never modifies anything, so it is always safe to run first.

### Before migrating a large install

```bash
cp -R ~/.pwt ~/.pwt.backup-$(date +%Y%m%d)   # cheap insurance
pwt state migrate --check                    # read the counts and skips
```

### If something looks wrong afterwards

Sources are kept as `*.vN.bak`. To roll back to the previous schema:

```bash
rm ~/.pwt/state-version
find ~/.pwt -name '*.v1.bak' | while read -r f; do mv "$f" "${f%.v1.bak}"; done
```

Then pin the older pwt release. `pwt doctor` lists leftover `.bak` files so
they are not forgotten.

## For AI agents

- Check `~/.pwt/state-version` before parsing state directly; refuse or
  degrade on an unexpected value rather than guessing.
- `pwt state migrate --check --porcelain` emits JSON (`from`, `to`, `pending`,
  per-step `converts`/`skips`) — prefer it over scraping the human output.
- Never migrate a user's state without being asked. Run `--check`, report
  the counts, and let the human decide.
- Exit codes follow the CLI convention: 0 ok, 1 error, 2 usage, 6 missing
  dependency (a migration may need a tool such as `jq` for a one-time parse).

## Authoring a new migration

1. Create `docs/migrations/NNN-vX-to-vY.md` from the shape of the existing
   guide: what changes, why, the check output, rollback steps, and what
   external consumers must update.
2. Implement the four operations in `lib/pwt/migrations/NNN-vX-to-vY.sh`
   as `migration_NNN_describe/check/up/verify`.
3. Add a row to the table above and bump the target schema in `bin/pwt`.
4. Write regression tests with a fixture containing **malformed data**, not
   only the happy path — that is the case that has actually bitten us.
5. Update `docs/state-v2-contract.md` (or its successor) so the contract
   documents the new layout.
