#!/usr/bin/env bash
# fetch-commits-ado.sh
# Fetch current-week commits from Azure DevOps (cross-project) for the current user.
#
# Usage:
#   ./fetch-commits-ado.sh [PROJECT1,PROJECT2,...]
#
# Arguments:
#   $1  Optional comma-separated project names to scan.
#       Leave empty to scan ALL projects (warning: 100+ projects can take 5–10 min).
#
# Output:
#   /tmp/commits.json  — array of {sha, message, date, project, repo}
#
# Prerequisites:
#   az CLI + azure-devops extension, logged in
#   jq

set -euo pipefail

ORG=$(az devops configure --list --output json 2>/dev/null \
  | jq -r '.[] | select(.name=="organization") | .value')
AUTHOR=$(az account show --query 'user.name' -o tsv 2>/dev/null)
WEEK_START=$(date -v-Mon +%Y-%m-%dT00:00:00Z 2>/dev/null \
  || date -d "last Monday" +%Y-%m-%dT00:00:00Z)   # macOS / Linux fallback
WEEK_END=$(date +%Y-%m-%dT23:59:59Z)

echo "Org:    $ORG"
echo "Author: $AUTHOR"
echo "Range:  $WEEK_START → $WEEK_END"
echo ""

# Determine project list
USER_PROJECTS="${1:-}"
if [ -n "$USER_PROJECTS" ]; then
  PROJECTS=$(echo "$USER_PROJECTS" | tr ',' '\n')
  echo "Scanning $(echo "$PROJECTS" | wc -l | tr -d ' ') project(s): $USER_PROJECTS"
else
  PROJECTS=$(az devops project list --org "$ORG" --output json 2>/dev/null \
    | jq -r '.value[].name')
  echo "Scanning ALL projects ($(echo "$PROJECTS" | wc -l | tr -d ' ') total) — this may take a while..."
fi

> /tmp/commits_raw.ndjson

while IFS= read -r project; do
  REPOS=$(az repos list --org "$ORG" --project "$project" --output json 2>/dev/null \
    | jq -r '.[] | .id + "\t" + .name' 2>/dev/null)
  [ -z "$REPOS" ] && continue

  echo "  → $project"
  while IFS=$'\t' read -r repo_id repo_name; do
    az devops invoke \
      --org "$ORG" \
      --area git \
      --resource commits \
      --route-parameters "project=$project" "repositoryId=$repo_id" \
      --query-parameters "searchCriteria.authorAlias=$AUTHOR" \
                         "searchCriteria.fromDate=$WEEK_START" \
                         "searchCriteria.toDate=$WEEK_END" \
                         '$top=100' \
      --output json 2>/dev/null | \
      jq --arg p "$project" --arg r "$repo_name" \
        '.value[]? | {sha: .commitId[:7], message: (.comment | split("\n")[0]), date: .author.date, project: $p, repo: $r}' \
      >> /tmp/commits_raw.ndjson
  done <<< "$REPOS"
done <<< "$PROJECTS"

jq -s '.' /tmp/commits_raw.ndjson > /tmp/commits.json
echo ""
echo "Done. Total commits: $(jq 'length' /tmp/commits.json)"
echo "Output: /tmp/commits.json"
