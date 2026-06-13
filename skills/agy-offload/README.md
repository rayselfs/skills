# agy-offload

Delegates token-heavy bulk reading and codebase analysis to agy CLI (Gemini backend), preserving Claude subscription budget.

## What it does

Routes analysis-heavy tasks (3+ files, whole-project overviews, architecture reviews) through `agy` CLI instead of consuming Claude tokens directly. The sub-agent runs `agy --print` and returns the full output.

## Install

```bash
npx skills add rayselfs/skills --skill agy-offload
```

## When it triggers

**Keywords:** analyze / investigate / look into / summarize / 調查 / 分析 / 看一下 / 幫我看看

**Quantitative:** 3+ files · 2+ modules · file > 300 lines · whole-project overview · architecture review

## Usage

Main agent delegates via:

```typescript
task(
  category="unspecified-high",
  load_skills=["agy-offload"],
  prompt=`
    project_path: /absolute/path/to/project
    Analyze the authentication flow across src/auth/ and src/middleware/.
    Return: key file paths, function names, data flow summary.
  `
)
```

## Prerequisites

`agy` CLI installed at `~/.local/bin/agy`.

## Files

```
agy-offload/
├── SKILL.md    # Agent instructions
└── README.md   # This file
```
