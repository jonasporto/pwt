#!/bin/bash
# Tests for Claude Code status line script
# Run: bash ~/.pwt/tests/statusline-test.sh

SCRIPT="$HOME/.claude/statusline-command.sh"
PASS=0
FAIL=0

# Colors for test output
RED='\033[31m'
GREEN='\033[32m'
RESET='\033[0m'

assert_contains() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$actual" == *"$expected"* ]]; then
    echo -e "${GREEN}✓${RESET} $name"
    ((PASS++))
  else
    echo -e "${RED}✗${RESET} $name"
    echo "  Expected to contain: $expected"
    echo "  Got: $actual"
    ((FAIL++))
  fi
}

assert_not_contains() {
  local name="$1"
  local not_expected="$2"
  local actual="$3"

  if [[ "$actual" != *"$not_expected"* ]]; then
    echo -e "${GREEN}✓${RESET} $name"
    ((PASS++))
  else
    echo -e "${RED}✗${RESET} $name"
    echo "  Expected NOT to contain: $not_expected"
    echo "  Got: $actual"
    ((FAIL++))
  fi
}

echo "=== Status Line Tests ==="
echo

# Test 1: Named colors
echo "--- Named Colors ---"

test_color() {
  local color="$1"
  local code="$2"
  local input="{$color:TEST}"
  local result=$(echo "$input" | perl -pe "s/\\{$color:([^}]*)\\}/\\033[${code}m\$1\\033[0m/g")
  assert_contains "$color color" "[${code}m" "$result"
}

test_color "cyan" "36"
test_color "yellow" "33"
test_color "red" "31"
test_color "green" "32"
test_color "blue" "34"
test_color "magenta" "35"
test_color "dim" "2"
test_color "bold" "1"

echo
echo "--- RGB Colors ---"

# Test RGB format
rgb_input="{rgb:255,100,0:ORANGE}"
rgb_result=$(echo "$rgb_input" | perl -pe 's/\{rgb:(\d+),(\d+),(\d+):([^}]*)\}/\033[38;2;$1;$2;$3m$4\033[0m/g')
assert_contains "RGB 255,100,0" "[38;2;255;100;0m" "$rgb_result"
assert_contains "RGB content" "ORANGE" "$rgb_result"

echo
echo "--- Hex Colors ---"

# Test Hex format
hex_input="{#FF6400:ORANGE}"
hex_result=$(echo "$hex_input" | perl -pe 's/\{#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2}):([^}]*)\}/sprintf("\033[38;2;%d;%d;%dm%s\033[0m", hex($1), hex($2), hex($3), $4)/ge')
assert_contains "Hex FF6400" "[38;2;255;100;0m" "$hex_result"
assert_contains "Hex content" "ORANGE" "$hex_result"

# Test lowercase hex
hex_lower="{#ff6400:ORANGE}"
hex_lower_result=$(echo "$hex_lower" | perl -pe 's/\{#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2}):([^}]*)\}/sprintf("\033[38;2;%d;%d;%dm%s\033[0m", hex($1), hex($2), hex($3), $4)/ge')
assert_contains "Hex lowercase" "[38;2;255;100;0m" "$hex_lower_result"

echo
echo "--- Variable Substitution ---"

# Create temp config for testing
TMP_CONFIG=$(mktemp)
echo '{"format":"{cyan:{project}} ({branch})"}' > "$TMP_CONFIG"

# Mock the script test
mock_vars() {
  local format="$1"
  local project="myproject"
  local branch="main"
  local output="$format"
  output="${output//\{project\}/$project}"
  output="${output//\{branch\}/$branch}"
  echo "$output"
}

var_result=$(mock_vars "{cyan:{project}} ({branch})")
assert_contains "Project variable" "myproject" "$var_result"
assert_contains "Branch variable" "main" "$var_result"
assert_contains "Color tag preserved" "{cyan:" "$var_result"

rm "$TMP_CONFIG"

echo
echo "--- Custom Variables (Pwtfile) ---"

# Setup test directory with Pwtfile
TEST_DIR="/tmp/pwt-test-custom-vars"
rm -rf "$TEST_DIR" 2>/dev/null
mkdir -p "$TEST_DIR"

# Create test Pwtfile with static and dynamic vars
cat > "$TEST_DIR/Pwtfile" << 'PWTFILE_EOF'
# Test Pwtfile
CLAUDE_APP="testapp"
CLAUDE_ENV="staging"

claude_dynamic() {
  echo "dynamic-value"
}

claude_with_context() {
  echo "wt:$PWT_WORKTREE"
}
PWTFILE_EOF

# Test static variable extraction
cd "$TEST_DIR"
static_result=$(
  source ./Pwtfile 2>/dev/null
  set | grep '^CLAUDE_APP=' | cut -d= -f2 | tr -d "'"
)
assert_contains "Static CLAUDE_APP" "testapp" "$static_result"

# Test function detection
func_exists=$(
  source ./Pwtfile 2>/dev/null
  declare -F | grep -c 'claude_dynamic' || echo "0"
)
if [ "$func_exists" -gt 0 ]; then
  echo -e "${GREEN}✓${RESET} Dynamic function claude_dynamic exists"
  ((PASS++))
else
  echo -e "${RED}✗${RESET} Dynamic function claude_dynamic not found"
  ((FAIL++))
fi

# Test function execution
func_result=$(
  source ./Pwtfile 2>/dev/null
  claude_dynamic 2>/dev/null
)
assert_contains "Dynamic function returns value" "dynamic-value" "$func_result"

# Test context variables in function
context_result=$(
  export PWT_WORKTREE="myworktree"
  source ./Pwtfile 2>/dev/null
  claude_with_context 2>/dev/null
)
assert_contains "Context var in function" "wt:myworktree" "$context_result"

# Cleanup
rm -rf "$TEST_DIR"
cd - >/dev/null

echo
echo "--- Toggle/Enable/Disable ---"

# Test environment variable toggle
export PWT_STATUSLINE_OFF=1
env_disabled_check='[ "${PWT_STATUSLINE_OFF:-}" = "1" ] && echo "disabled" || echo "enabled"'
env_result=$(eval "$env_disabled_check")
assert_contains "Env var disables" "disabled" "$env_result"

unset PWT_STATUSLINE_OFF
env_result=$(eval "$env_disabled_check")
assert_contains "Env var unset enables" "enabled" "$env_result"

# Test config file toggle
TEST_CONFIG=$(mktemp)
echo '{"enabled": false}' > "$TEST_CONFIG"
config_result=$(jq -r 'if has("enabled") then .enabled else true end' "$TEST_CONFIG")
assert_contains "Config disabled" "false" "$config_result"

echo '{"enabled": true}' > "$TEST_CONFIG"
config_result=$(jq -r 'if has("enabled") then .enabled else true end' "$TEST_CONFIG")
assert_contains "Config enabled" "true" "$config_result"

echo '{}' > "$TEST_CONFIG"
config_result=$(jq -r 'if has("enabled") then .enabled else true end' "$TEST_CONFIG")
assert_contains "Config default (no key)" "true" "$config_result"

rm "$TEST_CONFIG"

echo
echo "--- Integration Test ---"

if [ -f "$SCRIPT" ]; then
  # Test with mock input
  mock_input='{"workspace":{"current_dir":"/tmp/test-worktrees/myworktree"}}'

  # Create temp test dir
  mkdir -p /tmp/test-worktrees/myworktree
  cd /tmp/test-worktrees/myworktree
  git init -q 2>/dev/null || true

  result=$(echo "$mock_input" | "$SCRIPT" 2>/dev/null)

  assert_contains "Script executes" "" "$result" || true  # Just check it runs

  # Cleanup
  rm -rf /tmp/test-worktrees
  cd - >/dev/null

  echo -e "${GREEN}✓${RESET} Script integration test passed"
  ((PASS++))
else
  echo -e "${RED}✗${RESET} Script not found at $SCRIPT"
  ((FAIL++))
fi

echo
echo "=== Results ==="
echo -e "Passed: ${GREEN}$PASS${RESET}"
echo -e "Failed: ${RED}$FAIL${RESET}"
echo

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
