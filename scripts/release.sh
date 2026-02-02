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

# Update Formula (local copy)
if [ -f Formula/pwt.rb ]; then
    sed -i '' "s|archive/refs/tags/v[^\"]*|archive/refs/tags/v$VERSION|" Formula/pwt.rb
fi

# Commit
git add bin/pwt package.json Formula/pwt.rb 2>/dev/null || git add bin/pwt package.json
git commit -m "chore: release v$VERSION"

# Tag
git tag "v$VERSION"

echo ""
echo "Done! Now run:"
echo "  git push origin main --tags"
