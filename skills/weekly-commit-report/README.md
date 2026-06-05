# weekly-commit-report

Generate a weekly work report from your git commits — grouped by theme, not listed one-by-one.

## What it does

Fetches this week's commits from **GitHub** or **Azure DevOps**, groups them by intent (Features, Fixes, Infrastructure, Docs/Refactor), writes cohesive narrative summaries, and produces a report in `.pptx`, Markdown, or HTML.

## Install

```bash
npx skills add rayselfs/skills --skill weekly-commit-report
```

## Prerequisites

| Tool | Required for | Install |
|------|-------------|---------|
| `gh` CLI + auth | GitHub path | [cli.github.com](https://cli.github.com) |
| `az` CLI + azure-devops ext | ADO path | `brew install azure-cli && az extension add --name azure-devops` |
| `jq` | Both paths | `brew install jq` |
| Python 3.x | PPTX output only | system or `brew install python3` |

## Usage

Tell your AI assistant any of:

- "幫我做 weekly report，從 Azure DevOps 抓這週的 commit"
- "Generate a weekly commit summary from GitHub as pptx"
- "What did I work on this week? Make a pptx."
- "Weekly standup prep from my ADO commits"

## Output formats

| Format | Notes |
|--------|-------|
| `.pptx` | From scratch, or modify your existing template with `{{PLACEHOLDER}}` markers |
| Markdown | Clean `.md` file, Confluence/GitHub-friendly |
| HTML | Inline CSS only, email-friendly |

## Template placeholders (PPTX)

Add these text markers to your `.pptx` template slides:

| Placeholder | Replaced with |
|-------------|---------------|
| `{{SUMMARY}}` | Executive summary paragraph |
| `{{WEEK}}` | Week number |
| `{{YEAR}}` | Year |
| `{{STATS}}` | "N commits across N repos" |
| `{{CATEGORY_Features}}` | Narrative for Features group |
| `{{CATEGORY_Infrastructure}}` | Narrative for Infrastructure group |

## Related skills

| Skill | Required for |
|-------|-------------|
| `gh-cli` ([github/awesome-copilot](https://github.com/github/awesome-copilot)) | GitHub path auth & CLI reference |
| `azure-devops-cli` | ADO path auth & query syntax |

## Files

```
weekly-commit-report/
├── SKILL.md                          # Agent instructions
└── scripts/
    ├── fetch-commits-github.sh       # Fetch from GitHub (cross-org)
    ├── fetch-commits-ado.sh          # Fetch from Azure DevOps (cross-project)
    └── pptx-generator.py             # Generate / modify .pptx
```
