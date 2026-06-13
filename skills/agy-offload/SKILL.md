---
name: agy-offload
description: Delegates token-heavy bulk reading and codebase analysis to the agy CLI (Gemini backend), preserving Claude subscription budget. Use when task involves 3+ files, 2+ modules, files > 300 lines, whole-project overview, architecture review, or keywords: analyze / investigate / look into / summarize / 調查 / 分析 / 看一下 / 幫我看看.
metadata:
  author: rayselfs
---

# agy Offload

You are a sub-agent. Your job: run the delegated analysis through `agy` CLI and return the full output.

## When to Use / When NOT to Use

**Use:** 3+ files · 2+ modules · file > 300 lines · whole-project overview · architecture review · keywords: analyze / investigate / summarize / 調查 / 分析

**Do NOT use:** single-file edits · grep/symbol lookup · first-attempt bug fixes · tasks already in context

## Working Directory (CRITICAL)

`agy` reads from its cwd. Without an explicit path it analyzes the wrong directory.

**Caller must include `project_path` in the task prompt:**

```
project_path: /absolute/path/to/project
```

**Sub-agent:** extract `project_path` → run bash with `workdir` set to that path.

## Execution

```bash
agy --dangerously-skip-permissions --print "<prompt>" --model "<model>"
```

**Never pre-read files and paste contents into the prompt.** agy has its own filesystem access — doing so bloats the context and causes `signal: killed`.

## Model Selection

| Task | Model |
|------|-------|
| Summarize / list / extract types / read configs | `Gemini 3.5 Flash (Low)` |
| Codebase analysis, cross-file investigation | `Gemini 3.5 Flash (Medium)` ← **DEFAULT** |
| 50+ files, complex data flow, multi-module | `Gemini 3.5 Flash (High)` |
| Architecture review, design patterns, API spec | `Gemini 3.1 Pro (Low)` |
| Deep architecture critique, security analysis | `Gemini 3.1 Pro (High)` |
| Hard debug, complex logic, multi-step inference | `Claude Sonnet 4.6 (Thinking)` |
| Cryptic bugs, novel architecture | `Claude Opus 4.6 (Thinking)` |
| Second opinion when Gemini results seem off | `GPT-OSS 120B (Medium)` |

## Error Handling

| Symptom | Action |
|---------|--------|
| Non-zero exit | Report stderr verbatim — do not retry silently |
| No output after 5 min | Report timeout — suggest running `agy` interactively |
| `signal: killed` | Prompt was too large — ask caller to reduce scope |

## Caller Pattern

```typescript
task(
  category="unspecified-high",
  load_skills=["agy-offload"],
  prompt=`
    project_path: /Users/name/projects/myapp
    Analyze the authentication flow across src/auth/ and src/middleware/.
    Find how tokens are validated and where session state is managed.
    Return: key file paths, function names, data flow summary.
  `
)
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| No `project_path` in prompt | agy analyzes wrong cwd — always pass absolute path |
| Pasting file contents into prompt | Causes `signal: killed` — proxy the question directly |
| Asking agy to edit/write files | This pattern is analysis-only — agy is read here |
| Skipping agy because "task seems small" | If trigger conditions are met, use agy. No exceptions. |
