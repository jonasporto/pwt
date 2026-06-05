#!/usr/bin/env bash
set -u

usage() {
    cat <<'EOF'
Usage: scripts/test.sh [options] [test-files-or-dirs...]

Run pwt's BATS suite. By default, test files run in parallel while tests inside
each file stay serial and use the real pwt binary.

Options:
  -j, --jobs N    Number of test files to run concurrently
  --serial        Run through plain `bats` with no parallelism
  -h, --help      Show this help

Environment:
  PWT_TEST_JOBS   Default job count when -j/--jobs is omitted
EOF
}

cpu_count() {
    if command -v getconf >/dev/null 2>&1; then
        getconf _NPROCESSORS_ONLN 2>/dev/null && return
    fi
    if command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu 2>/dev/null && return
    fi
    echo 4
}

default_jobs() {
    local cpus
    cpus=$(cpu_count)
    if ! [[ "$cpus" =~ ^[0-9]+$ ]] || [ "$cpus" -lt 1 ]; then
        cpus=4
    fi

    # Git-heavy integration tests get slower if the machine is oversubscribed.
    if [ "$cpus" -gt 8 ]; then
        echo 8
    else
        echo "$cpus"
    fi
}

collect_tests() {
    local arg
    if [ "$#" -eq 0 ]; then
        set -- tests
    fi

    for arg in "$@"; do
        if [ -d "$arg" ]; then
            find "$arg" -maxdepth 1 -type f -name '*.bats' -print
        elif [ -f "$arg" ]; then
            printf '%s\n' "$arg"
        else
            echo "Test path not found: $arg" >&2
            return 1
        fi
    done | sort -u
}

run_one() {
    local file="$1"
    local output_dir="${PWT_TEST_OUTPUT_DIR:?}"
    local safe_name
    safe_name=$(printf '%s' "$file" | sed 's#[^A-Za-z0-9_.-]#_#g')

    local output_file="$output_dir/$safe_name.out"
    local status_file="$output_dir/$safe_name.status"
    local time_file="$output_dir/$safe_name.time"

    local start end elapsed status
    start=$(date +%s)
    bats "$file" >"$output_file" 2>&1
    status=$?
    end=$(date +%s)
    elapsed=$((end - start))

    printf '%s\n' "$status" > "$status_file"
    printf '%s\n' "$elapsed" > "$time_file"

    if [ "$status" -eq 0 ]; then
        printf 'ok %s (%ss)\n' "$file" "$elapsed"
    else
        printf 'not ok %s (%ss)\n' "$file" "$elapsed"
    fi

    return "$status"
}

if [ "${1:-}" = "__run_one" ]; then
    shift
    run_one "$1"
    exit $?
fi

jobs="${PWT_TEST_JOBS:-}"
serial=false
tests=()
test_arg_count=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        -j|--jobs)
            if [ -z "${2:-}" ]; then
                echo "Error: $1 requires a number" >&2
                exit 2
            fi
            jobs="$2"
            shift 2
            ;;
        --serial)
            serial=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            while [ "$#" -gt 0 ]; do
                tests+=("$1")
                test_arg_count=$((test_arg_count + 1))
                shift
            done
            ;;
        *)
            tests+=("$1")
            test_arg_count=$((test_arg_count + 1))
            shift
            ;;
    esac
done

if ! command -v bats >/dev/null 2>&1; then
    echo "bats not installed. Install with: brew install bats-core" >&2
    exit 127
fi

if [ "$serial" = true ]; then
    if [ "$test_arg_count" -eq 0 ]; then
        exec bats tests/
    fi
    exec bats "${tests[@]}"
fi

if [ -z "$jobs" ]; then
    jobs=$(default_jobs)
fi
if ! [[ "$jobs" =~ ^[0-9]+$ ]] || [ "$jobs" -lt 1 ]; then
    echo "Error: jobs must be a positive integer" >&2
    exit 2
fi

test_list=$(mktemp "${TMPDIR:-/tmp}/pwt-tests.XXXXXX")
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/pwt-test-output.XXXXXX")
trap 'rm -f "$test_list"; rm -rf "$output_dir"' EXIT

if [ "$test_arg_count" -eq 0 ]; then
    collect_tests > "$test_list"
else
    collect_tests "${tests[@]}" > "$test_list"
fi
if [ "$?" -ne 0 ]; then
    exit 2
fi

test_count=$(wc -l < "$test_list" | tr -d ' ')
if [ "$test_count" -eq 0 ]; then
    echo "No .bats files found" >&2
    exit 2
fi

echo "Running $test_count BATS files with $jobs parallel jobs"

start=$(date +%s)
PWT_TEST_OUTPUT_DIR="$output_dir" xargs -n 1 -P "$jobs" "$0" __run_one < "$test_list"
xargs_status=$?
end=$(date +%s)
elapsed=$((end - start))

failed=0
while IFS= read -r status_file; do
    status=$(cat "$status_file")
    if [ "$status" -ne 0 ]; then
        failed=$((failed + 1))
    fi
done < <(find "$output_dir" -type f -name '*.status' -print)

echo ""
echo "Finished in ${elapsed}s"

if [ "$failed" -gt 0 ] || [ "$xargs_status" -ne 0 ]; then
    echo ""
    echo "Failures:"
    while IFS= read -r status_file; do
        status=$(cat "$status_file")
        [ "$status" -eq 0 ] && continue

        base="${status_file%.status}"
        echo ""
        echo "===== ${base##*/} ====="
        cat "$base.out"
    done < <(find "$output_dir" -type f -name '*.status' -print | sort)
    exit 1
fi

exit 0
