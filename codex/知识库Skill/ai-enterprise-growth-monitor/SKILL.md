---
name: ai-enterprise-growth-monitor
description: Track and apply GitHub knowledge about enterprise AI delivery, AI application implementation, short-video operations, and customer acquisition. Use when Codex needs to update or consult the local AI delivery/growth knowledge base, review the daily GitHub learning digest, or turn new AI/project/creator-growth patterns into practical delivery playbooks.
---

# AI Enterprise Growth Monitor

## Purpose

Use this skill to keep a local, practical knowledge base for:

- Enterprise AI application delivery and implementation projects
- Agent, RAG, MCP, workflow automation, and evaluation patterns
- Short-video operations, creator workflows, content automation, and growth loops
- Customer acquisition, lead generation, sales automation, and funnel experiments

The knowledge base lives in this skill folder. Prefer the newest digest first, then use the index and dated notes for historical context.

## Quick Workflow

1. Read `references/latest-digest.md` for the newest GitHub learning run.
2. Read `knowledge/index.md` to see accumulated patterns and prior daily notes.
3. If the user asks for delivery advice, transform findings into concrete SOPs, checklists, prompts, implementation plans, or experiments.
4. If the user asks to refresh the knowledge base manually, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Code\codex\知识库Skill\ai-enterprise-growth-monitor\scripts\update-github-knowledge.ps1"
```

## Operating Rules

- Treat GitHub findings as leads, not facts. Prefer primary repo docs, releases, examples, and commit messages.
- Prioritize reusable implementation knowledge over news-like chatter.
- When a finding is relevant to the user's work, convert it into:
  - delivery implication
  - project checklist
  - reusable prompt or SOP
  - risk or validation note
- Keep enterprise implementation and growth operations connected: AI tools matter most when they improve delivery speed, quality, retention, or acquisition.

## Knowledge Files

- `references/watchlist.json`: editable GitHub sources, search topics, and relevance keywords.
- `references/latest-digest.md`: latest daily generated digest.
- `knowledge/index.md`: accumulated local knowledge index.
- `knowledge/YYYY-MM-DD-github-ai-knowledge.md`: dated daily digests.
- `raw/`: raw JSON snapshots from GitHub API calls.
- `logs/update.log`: automation run log.

## Scheduling

The local Windows scheduled task is named `Codex-GitHub-AI-Knowledge-03`. It runs daily at 03:00 local Windows time and executes `scripts/update-github-knowledge.ps1`.

Each run writes a digest where every monitored repository and discovery result includes:

- `使用功能`: what the project can be used for
- `作用`: how it helps enterprise AI delivery, short-video operations, customer acquisition, or Codex Skill growth

After updating the local D-drive knowledge base, the script syncs the tracked skill files into `D:\Code\ai-office-training\codex\知识库Skill\ai-enterprise-growth-monitor`, commits any changes, and pushes them to `origin/main`. Runtime logs and raw API snapshots stay local.

To inspect the task:

```powershell
Get-ScheduledTask -TaskName "Codex-GitHub-AI-Knowledge-03"
```

To run it immediately:

```powershell
Start-ScheduledTask -TaskName "Codex-GitHub-AI-Knowledge-03"
```

## Customizing Sources

Edit `references/watchlist.json` when the user names specific projects, repos, or priorities. Add:

- exact repositories under `repositories`
- discovery searches under `search_queries`
- terms that imply high relevance under `priority_keywords`

Use `GITHUB_TOKEN` or `GH_TOKEN` in the environment if rate limits become a problem.
