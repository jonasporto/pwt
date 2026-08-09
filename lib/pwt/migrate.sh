#!/bin/bash
# ============================================
# pwt migrate module
# Inspect and apply state schema migrations
# ============================================
#
# The process every migration follows is documented in docs/migrations/README.md.
# Each migration provides describe / check / up / verify; this module drives
# them and is the only supported way to run one deliberately.
#
# Dependencies from bin/pwt: state_version_read, migrate_state_v1,
# state_version_write, json_escape, pwt_error, PWT_STATE_VERSION, PWT_DIR.

[[ -n "${_PWT_MIGRATE_LOADED:-}" ]] && return 0
_PWT_MIGRATE_LOADED=1

# Current schema of this install (1 means "pre-versioning")
_migrate_current_version() {
	local v
	v=$(state_version_read)
	printf '%s' "${v:-1}"
}

# --- migration 001: v1 JSON -> v2 key=value ---

migration_001_describe() {
	echo "JSON state becomes flat key=value files (one per record), removing"
	echo "jq from the runtime. See docs/migrations/001-v1-to-v2.md."
}

# Dry run. Prints one line per source; sets the _MIG_* counters so callers can
# reuse them for JSON output. Never modifies anything.
migration_001_check() {
	_MIG_META_RECORDS=0
	_MIG_META_CONVERTS=0
	_MIG_META_SKIPS=0
	_MIG_SKIP_NAMES=""
	_MIG_CONFIGS=0
	_MIG_JOBS=0
	_MIG_TRASH=0

	if [ -f "$PWT_DIR/meta.json" ]; then
		if ! command -v jq >/dev/null 2>&1; then
			pwt_error "Error: this migration needs jq once to read $PWT_DIR/meta.json"
			return "$EXIT_DEPENDENCY"
		fi
		if ! jq -e . "$PWT_DIR/meta.json" >/dev/null 2>&1; then
			pwt_error "Error: $PWT_DIR/meta.json is not readable JSON"
			return "$EXIT_ERROR"
		fi

		# Guard the type at every level: `to_entries` on a non-object aborts
		# jq, and the old `|| echo 0` swallowed that - the very mistake rule #1
		# in docs/migrations/README.md warns about, left in the command users
		# are told to read before migrating.
		#
		# "records" must equal converts + skips (rule #3), so it counts both
		# the sub-entries of well-formed projects AND the top-level entries
		# that are not projects at all; the latter are skips too.
		_MIG_META_RECORDS=$(jq -r '
            [ (.[] | select(type == "object") | to_entries[]),
              (to_entries[] | select((.value | type) != "object")) ] | length
        ' "$PWT_DIR/meta.json" 2>/dev/null || echo 0)
		_MIG_META_CONVERTS=$(jq -r '
            [ .[] | select(type == "object") | to_entries[]
              | select((.value | type) == "object") ] | length
        ' "$PWT_DIR/meta.json" 2>/dev/null || echo 0)
		_MIG_SKIP_NAMES=$(jq -r '
            to_entries[] | .key as $p | .value |
            if type != "object" then $p
            else (to_entries[] | select((.value | type) != "object") | "\($p)/\(.key)")
            end
        ' "$PWT_DIR/meta.json" 2>/dev/null || true)
		[ -n "$_MIG_SKIP_NAMES" ] && _MIG_META_SKIPS=$(printf '%s\n' "$_MIG_SKIP_NAMES" | grep -c .)
	fi

	local f
	for f in "$PWT_DIR"/projects/*/config.json; do
		[ -f "$f" ] && _MIG_CONFIGS=$((_MIG_CONFIGS + 1))
	done
	for f in "$PWT_DIR"/jobs/*.json; do
		[ -f "$f" ] && _MIG_JOBS=$((_MIG_JOBS + 1))
	done
	for f in "$PWT_DIR"/trash/*.json; do
		[ -f "$f" ] && _MIG_TRASH=$((_MIG_TRASH + 1))
	done

	return 0
}

migration_001_up() {
	# Same guard the startup path uses: with nothing legacy on disk there is
	# nothing to convert, and migrate_state_v1 would demand jq (and claim to
	# have found v1 state) on a brand-new install.
	if ! _legacy_state_present; then
		return 0
	fi
	migrate_state_v1
}

# Post-migration check: every convertible record must exist on disk.
migration_001_verify() {
	local problems=0

	# Check that each convertible record LANDED, rather than comparing raw
	# counts: state/ legitimately also holds worktrees created after the
	# migration marker, so "more files than records" is not an error.
	if [ -f "$PWT_DIR/meta.json.v1.bak" ] && command -v jq >/dev/null 2>&1; then
		local expected=0 found=0 missing="" project wt
		while IFS=$'\t' read -r project wt; do
			[ -n "$project" ] && [ -n "$wt" ] || continue
			expected=$((expected + 1))
			if [ -f "$PWT_DIR/state/$project/$wt.meta" ]; then
				found=$((found + 1))
			else
				missing="${missing}${missing:+, }$project/$wt"
			fi
		done < <(jq -r '
            to_entries[] | .key as $p | .value | select(type == "object") |
            to_entries[] | select((.value | type) == "object") |
            [$p, .key] | @tsv
        ' "$PWT_DIR/meta.json.v1.bak" 2>/dev/null)

		if [ -n "$missing" ]; then
			pwt_error "Missing after migration: $missing"
			echo "  Recover them from $PWT_DIR/meta.json.v1.bak" >&2
			problems=$((problems + 1))
		else
			echo "  ✓ worktrees: $found/$expected converted"
		fi
	fi

	# grep -c prints 0 AND exits 1 when there is no match, so a `|| echo 0`
	# here would emit "0\n0" and break the numeric test below.
	local leftovers
	leftovers=$(find "$PWT_DIR" -name '*.json' -not -name '*.v1.bak' \
		-not -path "$PWT_DIR/cache/*" 2>/dev/null | wc -l | tr -d ' ')
	if [ "${leftovers:-0}" -gt 0 ]; then
		echo "  ⚠ $leftovers legacy .json file(s) still present (harmless, but unmigrated)"
	fi

	if [ "$(_migrate_current_version)" != "$PWT_STATE_VERSION" ]; then
		pwt_error "state-version is $(_migrate_current_version), expected $PWT_STATE_VERSION"
		problems=$((problems + 1))
	else
		echo "  ✓ state-version: $PWT_STATE_VERSION"
	fi

	[ "$problems" -eq 0 ] || return "$EXIT_ERROR"
	return 0
}

# --- driver ---

_migrate_print_check() {
	local from="$1"
	echo "Pending: $from → $PWT_STATE_VERSION (migration 001)"
	echo ""
	migration_001_describe
	echo ""
	echo "Dry run — nothing was modified:"
	if [ -f "$PWT_DIR/meta.json" ]; then
		printf '  %-22s %4s records → %s worktrees, %s skipped\n' \
			"meta.json" "$_MIG_META_RECORDS" "$_MIG_META_CONVERTS" "$_MIG_META_SKIPS"
	fi
	[ "${_MIG_CONFIGS:-0}" -gt 0 ] && printf '  %-22s %4s files\n' "projects/*/config.json" "$_MIG_CONFIGS"
	[ "${_MIG_JOBS:-0}" -gt 0 ] && printf '  %-22s %4s files\n' "jobs/*.json" "$_MIG_JOBS"
	[ "${_MIG_TRASH:-0}" -gt 0 ] && printf '  %-22s %4s files\n' "trash/*.json" "$_MIG_TRASH"

	if [ -n "${_MIG_SKIP_NAMES:-}" ]; then
		echo ""
		echo "Would skip (malformed legacy entries, kept in meta.json.v1.bak):"
		printf '  %s\n' $_MIG_SKIP_NAMES
	fi
	echo ""
	echo "Apply with: pwt state migrate     Guide: docs/migrations/001-v1-to-v2.md"
}

_migrate_print_check_json() {
	local from="$1"
	printf '{\n'
	printf '  "from": %s,\n  "to": %s,\n' "$from" "$PWT_STATE_VERSION"
	printf '  "pending": ["001-v1-to-v2"],\n'
	printf '  "steps": [\n'
	printf '    {"id":"001-v1-to-v2","meta_records":%s,"converts":%s,"skips":%s,' \
		"${_MIG_META_RECORDS:-0}" "${_MIG_META_CONVERTS:-0}" "${_MIG_META_SKIPS:-0}"
	printf '"configs":%s,"jobs":%s,"trash":%s,"skipped_entries":[' \
		"${_MIG_CONFIGS:-0}" "${_MIG_JOBS:-0}" "${_MIG_TRASH:-0}"
	local first=true entry
	for entry in ${_MIG_SKIP_NAMES:-}; do
		[ "$first" = true ] || printf ','
		first=false
		printf '"%s"' "$(json_escape "$entry")"
	done
	printf ']}\n  ]\n}\n'
}

cmd_migrate() {
	local action="apply" porcelain=false

	while [ $# -gt 0 ]; do
		case "$1" in
		--status) action="status" ;;
		--check | -n | --dry-run) action="check" ;;
		--verify) action="verify" ;;
		--porcelain | --json) porcelain=true ;;
		-h | --help)
			echo "Usage: pwt state migrate [--status|--check|--verify] [--porcelain]"
			echo ""
			echo "Inspect and apply pwt state schema migrations."
			echo ""
			echo "Options:"
			echo "  --status     Show current and target schema, and pending steps"
			echo "  --check      Dry run: what would change, with counts (never writes)"
			echo "  --verify     Re-check counts against already-migrated state"
			echo "  --porcelain  JSON output (--status and --check)"
			echo ""
			echo "Migration also happens automatically on the first command"
			echo "after an upgrade. Guides: docs/migrations/"
			echo ""
			echo "'pwt migrate' is accepted as an alias; 'pwt state migrate'"
			echo "is canonical (schema migrations belong to the state subsystem)."
			return 0
			;;
		*)
			pwt_error "Unknown option: $1"
			echo "Usage: pwt state migrate [--status|--check|--verify] [--porcelain]" >&2
			return "$EXIT_USAGE"
			;;
		esac
		shift
	done

	local from
	from=$(_migrate_current_version)

	case "$action" in
	status)
		if [ "$porcelain" = true ]; then
			printf '{"from":%s,"to":%s,"pending":[' "$from" "$PWT_STATE_VERSION"
			[ "$from" -lt "$PWT_STATE_VERSION" ] && printf '"001-v1-to-v2"'
			printf ']}\n'
		else
			echo "Schema:  $from → $PWT_STATE_VERSION"
			if [ "$from" -ge "$PWT_STATE_VERSION" ]; then
				echo "Pending: none (up to date)"
			else
				echo "Pending: 001-v1-to-v2"
				echo ""
				echo "Preview with: pwt state migrate --check"
			fi
		fi
		;;
	check)
		if [ "$from" -ge "$PWT_STATE_VERSION" ]; then
			if [ "$porcelain" = true ]; then
				printf '{"from":%s,"to":%s,"pending":[],"steps":[]}\n' "$from" "$PWT_STATE_VERSION"
			else
				echo "Schema $from is current — nothing to migrate."
			fi
			return 0
		fi
		migration_001_check || return $?
		if [ "$porcelain" = true ]; then
			_migrate_print_check_json "$from"
		else
			_migrate_print_check "$from"
		fi
		;;
	verify)
		echo "Verifying schema $(_migrate_current_version)..."
		migration_001_verify || return $?
		echo "State verified."
		;;
	apply)
		if [ "$from" -ge "$PWT_STATE_VERSION" ]; then
			echo "Schema $from is current — nothing to migrate."
			return 0
		fi
		migration_001_up || return "$EXIT_ERROR"
		state_version_write
		echo ""
		migration_001_verify || return $?
		;;
	esac

	return 0
}
