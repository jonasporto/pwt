#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/release.sh 0.2.0

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 0.2.0"
    exit 1
fi

# Remove 'v' prefix if provided
VERSION="${VERSION#v}"

echo "Releasing v$VERSION..."

# Update bin/pwt
sed -i '' "s/^PWT_VERSION=.*/PWT_VERSION=\"$VERSION\"/" bin/pwt

# Update package.json
jq --arg v "$VERSION" '.version = $v' package.json > tmp.json && mv tmp.json package.json

# Update README version badge (scripts/check enforces the match)
sed -i '' "s/version-[0-9.]*-green/version-$VERSION-green/" README.md

# Update the man page header, which shipped a stale version for months
# because nothing tied it to a release (scripts/check enforces it now)
sed -i '' "s/^\.TH PWT 1 \(\"[^\"]*\"\) \"pwt [0-9.]*\"/.TH PWT 1 \1 \"pwt $VERSION\"/" man/pwt.1

# Update Formula (local copy)
if [ -f Formula/pwt.rb ]; then
    sed -i '' "s|archive/refs/tags/v[^\"]*|archive/refs/tags/v$VERSION|" Formula/pwt.rb
fi

# Commit. README and man carry the version too: they were edited above but
# never staged, which is why the badge and the man header drifted for
# months while every release looked clean.
git add bin/pwt package.json README.md man/pwt.1
git add Formula/pwt.rb 2>/dev/null || true
git commit -m "chore: release v$VERSION"

# Tag
git tag "v$VERSION"

echo ""
echo "Done! Now run:"
echo "  git push origin main --tags"
