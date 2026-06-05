#!/usr/bin/env bash
# fetch-commits-github.sh
# Fetch commits from GitHub (personal + all orgs) for the current user, in parallel.
#
# Usage:
#   ./fetch-commits-github.sh [WEEK_DEF]
#
# Arguments:
#   $1  Week definition: mon-fri | mon-sun | last7  (default: mon-fri)
#
# Output:
#   /tmp/commits.json  — array of {sha, message, date, repo}
#                        filtered to current user only, pipeline noise excluded
#
# Prerequisites:
#   gh CLI authenticated; Python 3; jq

set -euo pipefail

GH_USER=$(gh api /user --jq '.login')
WEEK_DEF="${1:-mon-fri}"

echo "User:     $GH_USER"
echo "Week def: $WEEK_DEF"
echo ""

python3 - "$GH_USER" "$WEEK_DEF" <<'PYEOF'
import sys, json, subprocess, concurrent.futures, re
from datetime import date, timedelta

gh_user, week_def = sys.argv[1], sys.argv[2]

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
    r"^(UPD\.|Merge pull request \d+ from .+-[0-9a-f]{7,})",
    re.IGNORECASE,
)

# ---------------------------------------------------------------------------
# Collect repo list: personal + all orgs
# ---------------------------------------------------------------------------
def gh_api(path):
    r = subprocess.run(
        ["gh", "api", path, "--paginate"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        return []
    # gh api --paginate returns multiple JSON arrays concatenated; merge them
    results = []
    for chunk in r.stdout.strip().split("\n"):
        if not chunk:
            continue
        try:
            data = json.loads(chunk)
            if isinstance(data, list):
                results.extend(data)
            else:
                results.append(data)
        except Exception:
            pass
    return results

print("Collecting repos (personal + orgs)...")
repos = set()

for r in gh_api("/user/repos"):
    repos.add(r["full_name"])

for org in gh_api("/user/orgs"):
    for r in gh_api(f"/orgs/{org['login']}/repos"):
        repos.add(r["full_name"])

repo_list = sorted(repos)
print(f"Total repos: {len(repo_list)} — fetching with 8 workers...\n")

# ---------------------------------------------------------------------------
# Parallel commit fetch
# ---------------------------------------------------------------------------
def fetch_repo(full_name):
    try:
        r = subprocess.run(
            [
                "gh", "api",
                f"/repos/{full_name}/commits"
                f"?author={gh_user}&since={week_start}&until={week_end}&per_page=100",
                "--paginate",
            ],
            capture_output=True, text=True, timeout=30,
        )
        if r.returncode != 0:
            return []
        commits = []
        for chunk in r.stdout.strip().split("\n"):
            if not chunk:
                continue
            try:
                data = json.loads(chunk)
            except Exception:
                continue
            if not isinstance(data, list):
                continue
            for c in data:
                msg = (c.get("commit") or {}).get("message", "").split("\n")[0]
                if NOISE_RE.match(msg):
                    continue
                commits.append({
                    "sha":     c["sha"][:7],
                    "message": msg,
                    "date":    c["commit"]["author"]["date"],
                    "repo":    full_name,
                })
        return commits
    except Exception:
        return []

all_commits = []
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
    futures = {ex.submit(fetch_repo, r): r for r in repo_list}
    done = 0
    for fut in concurrent.futures.as_completed(futures):
        done += 1
        commits = fut.result()
        if commits:
            all_commits.extend(commits)
        if done % 20 == 0 or done == len(repo_list):
            print(f"  {done}/{len(repo_list)} repos scanned, {len(all_commits)} commits found", flush=True)

print(f"\nDone. Total commits: {len(all_commits)}")
with open("/tmp/commits.json", "w") as f:
    json.dump(all_commits, f, indent=2)
print("Output: /tmp/commits.json")
PYEOF
