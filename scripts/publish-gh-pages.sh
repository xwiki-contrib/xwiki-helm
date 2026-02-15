#!/bin/bash
set -e

# Configuration
# These environment variables are available in the GitHub Actions context
REPO_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
PAGES_BRANCH="gh-pages"
CHARTS_DIR=".cr-release-packages"
INDEX_DIR="gh-pages-repo"
GITHUB_PAGES_URL="https://$(echo "$GITHUB_REPOSITORY" | cut -d'/' -f1).github.io/$(echo "$GITHUB_REPOSITORY" | cut -d'/' -f2)/"

echo "Starting GitHub Pages publication..."
echo "Repository: $GITHUB_REPOSITORY"
echo "Pages URL: $GITHUB_PAGES_URL"

# Clone gh-pages branch
echo "Cloning $PAGES_BRANCH branch..."
rm -rf "$INDEX_DIR"
git clone --branch "$PAGES_BRANCH" --single-branch --depth 1 "$REPO_URL" "$INDEX_DIR" || {
    echo "Branch $PAGES_BRANCH not found. Creating it..."
    mkdir -p "$INDEX_DIR"
    cd "$INDEX_DIR"
    git init
    git checkout -b "$PAGES_BRANCH"
    git remote add origin "$REPO_URL"
    cd ..
}

# Copy charts
echo "Indexing charts in $CHARTS_DIR..."
# The version is passed in the .releaserc.json environment, but we can extract it or assume standard tagging.

# Semantic release tag format: xwiki-helm-${nextRelease.version}
# URL: https://github.com/${GITHUB_REPOSITORY}/releases/download/xwiki-helm-${VERSION}/${CHART_NAME}-${VERSION}.tgz

# We need to run helm repo index on the local charts dir, but with --url pointing to GitHub.
# We merge with the existing index.yaml from gh-pages.

# Copy existing index.yaml to CHARTS_DIR for merging
if [ -f "$INDEX_DIR/index.yaml" ]; then
  cp "$INDEX_DIR/index.yaml" "$CHARTS_DIR/index.yaml"
fi

# Get the tag (assuming nextRelease.version is available or we parse it from the filename)
# Actually, semantic-release ensures the version in Chart.yaml is correct at this point.
VERSION=$(grep '^version:' charts/xwiki/Chart.yaml | awk '{print $2}')
TAG="xwiki-helm-$VERSION"
RELEASE_URL="https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG"

echo "Using Release URL: $RELEASE_URL"

# Update index in CHARTS_DIR
helm repo index "$CHARTS_DIR" --url "$RELEASE_URL" --merge "$CHARTS_DIR/index.yaml"

# Move ONLY index.yaml back to INDEX_DIR
mv "$CHARTS_DIR/index.yaml" "$INDEX_DIR/"

# Push changes
cd "$INDEX_DIR"
echo "Committing and pushing changes..."
if [ -z "$(git status --porcelain)" ]; then
  echo "No changes to commit."
else
  git config user.name "$GITHUB_ACTOR"
  git config user.email "$GITHUB_ACTOR@users.noreply.github.com"
  git add index.yaml
  git commit -m "Update Helm repository index for $TAG [skip ci]"
  git push "$REPO_URL" "$PAGES_BRANCH"
  echo "Successfully pushed to $PAGES_BRANCH"
fi