#!/usr/bin/env bash
# fetch-commits-github.sh
# Fetch current-week commits from GitHub (personal + all orgs) for the current user.
#
# Usage:
#   ./fetch-commits-github.sh
#
# Output:
#   /tmp/commits.json  — array of {sha, message, date, repo}
#
# Prerequisites:
#   gh CLI, authenticated (`gh auth status`)
#   jq

set -euo pipefail

GH_USER=$(gh api /user --jq '.login')
WEEK_START=$(date -v-Mon +%Y-%m-%dT00:00:00Z 2>/dev/null \
  || date -d "last Monday" +%Y-%m-%dT00:00:00Z)   # macOS / Linux fallback
WEEK_END=$(date +%Y-%m-%dT23:59:59Z)

echo "User:  $GH_USER"
echo "Range: $WEEK_START → $WEEK_END"
echo ""

# Collect personal repos + all org repos
gh api /user/repos --paginate --jq '.[].full_name' > /tmp/gh_repos.txt

echo "Fetching org repos..."
gh api /user/orgs --paginate --jq '.[].login' | while read -r org; do
  gh api "/orgs/$org/repos" --paginate --jq '.[].full_name' >> /tmp/gh_repos.txt
done
sort -u /tmp/gh_repos.txt -o /tmp/gh_repos.txt

TOTAL_REPOS=$(wc -l < /tmp/gh_repos.txt | tr -d ' ')
echo "Scanning $TOTAL_REPOS repos..."
echo ""

> /tmp/commits_raw.ndjson

while IFS= read -r repo; do
  RESULT=$(gh api "/repos/$repo/commits?author=$GH_USER&since=$WEEK_START&until=$WEEK_END" \
    --paginate \
    --jq '.[] | {sha: .sha[:7], message: (.commit.message | split("\n")[0]), date: .commit.author.date, repo: "'"$repo"'"}' \
    2>/dev/null || true)

  if [ -n "$RESULT" ]; then
    echo "  → $repo"
    echo "$RESULT" >> /tmp/commits_raw.ndjson
  fi
done < /tmp/gh_repos.txt

jq -s '.' /tmp/commits_raw.ndjson > /tmp/commits.json
echo ""
echo "Done. Total commits: $(jq 'length' /tmp/commits.json)"
echo "Output: /tmp/commits.json"
