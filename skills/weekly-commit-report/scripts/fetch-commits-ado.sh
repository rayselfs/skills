#!/usr/bin/env bash
# fetch-commits-ado.sh
# Fetch commits from Azure DevOps for the current user, in parallel.
#
# Usage:
#   ./fetch-commits-ado.sh [PROJECTS] [WEEK_DEF]
#
# Arguments:
#   $1  Comma-separated project names (e.g. "OPS,vad-ops"). Empty = all projects.
#   $2  Week definition: mon-fri | mon-sun | last7  (default: mon-fri)
#
# Output:
#   /tmp/commits.json  — array of {sha, message, date, project, repo}
#                        filtered to current user only, pipeline noise excluded
#
# Prerequisites:
#   az CLI + azure-devops extension, logged in; Python 3; jq

set -euo pipefail

ORG=$(az devops configure --list 2>/dev/null \
  | awk -F' = ' '/organization/{print $2}' | tr -d ' ')
ORG="${ORG_OVERRIDE:-$ORG}"
AUTHOR=$(az account show --query 'user.name' -o tsv 2>/dev/null)
PROJECTS="${1:-}"
WEEK_DEF="${2:-mon-fri}"

echo "Org:      $ORG"
echo "Author:   $AUTHOR"
echo "Week def: $WEEK_DEF"
echo ""

python3 - "$ORG" "$AUTHOR" "$WEEK_DEF" "$PROJECTS" <<'PYEOF'
import sys, json, subprocess, concurrent.futures, re
from datetime import date, timedelta

org, author, week_def, projects_arg = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

# ---------------------------------------------------------------------------
# Date range
# ---------------------------------------------------------------------------
today = date.today()
mon = today - timedelta(days=today.weekday())

if week_def == "mon-fri":
    start, end = mon, mon + timedelta(days=4)
elif week_def == "mon-sun":
    start, end = mon, mon + timedelta(days=6)
elif week_def == "last7":
    end, start = today, today - timedelta(days=7)
else:
    print(f"ERROR: unknown week_def '{week_def}'. Use mon-fri, mon-sun, or last7", file=sys.stderr)
    sys.exit(1)

week_start = f"{start.isoformat()}T00:00:00Z"
week_end   = f"{end.isoformat()}T23:59:59Z"
print(f"Range:    {week_start} → {week_end}\n")

# ---------------------------------------------------------------------------
# Pipeline noise patterns to exclude
# ---------------------------------------------------------------------------
NOISE_RE = re.compile(
    r"^(UPD\.|Merge pull request \d+ from .+-[0-9a-f]{7,} into )",
    re.IGNORECASE,
)

# ---------------------------------------------------------------------------
# Project list
# ---------------------------------------------------------------------------
if projects_arg:
    projects = [p.strip() for p in projects_arg.split(",") if p.strip()]
else:
    r = subprocess.run(
        ["az", "devops", "project", "list", "--org", org, "--output", "json"],
        capture_output=True, text=True,
    )
    projects = [p["name"] for p in json.loads(r.stdout).get("value", [])]

print(f"Scanning {len(projects)} project(s): {', '.join(projects)}")

# ---------------------------------------------------------------------------
# Collect repo list
# ---------------------------------------------------------------------------
repo_list = []
for project in projects:
    r = subprocess.run(
        ["az", "repos", "list", "--org", org, "--project", project, "--output", "json"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        continue
    try:
        repos = json.loads(r.stdout)
    except Exception:
        continue
    for repo in repos:
        repo_list.append((project, repo["id"], repo["name"]))

print(f"Total repos: {len(repo_list)} — fetching with 16 workers...\n")

# ---------------------------------------------------------------------------
# Parallel commit fetch
# ---------------------------------------------------------------------------
def fetch_repo(args):
    project, repo_id, repo_name = args
    try:
        r = subprocess.run(
            [
                "az", "devops", "invoke",
                "--org", org,
                "--area", "git",
                "--resource", "commits",
                "--route-parameters", f"project={project}", f"repositoryId={repo_id}",
                "--query-parameters",
                f"searchCriteria.fromDate={week_start}",
                f"searchCriteria.toDate={week_end}",
                "$top=500",
                "--output", "json",
            ],
            capture_output=True, text=True, timeout=30,
        )
        if r.returncode != 0:
            return []
        data = json.loads(r.stdout)
        commits = []
        for c in data.get("value", []):
            # Client-side author filter (searchCriteria.authorAlias is unreliable)
            author_email = (c.get("author") or {}).get("email", "")
            if author_email.lower() != author.lower():
                continue
            msg = c["comment"].split("\n")[0]
            # Filter pipeline noise
            if NOISE_RE.match(msg):
                continue
            commits.append({
                "sha":     c["commitId"][:7],
                "message": msg,
                "date":    c["author"]["date"],
                "project": project,
                "repo":    repo_name,
            })
        return commits
    except Exception:
        return []

all_commits = []
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as ex:
    futures = {ex.submit(fetch_repo, r): r for r in repo_list}
    done = 0
    for fut in concurrent.futures.as_completed(futures):
        done += 1
        commits = fut.result()
        if commits:
            all_commits.extend(commits)
        if done % 25 == 0 or done == len(repo_list):
            print(f"  {done}/{len(repo_list)} repos scanned, {len(all_commits)} commits found", flush=True)

print(f"\nDone. Total commits: {len(all_commits)}")
with open("/tmp/commits.json", "w") as f:
    json.dump(all_commits, f, indent=2)
print("Output: /tmp/commits.json")
PYEOF
