# OmniChat — Claude Code Agent Setup Guide

## Prerequisites

1. **Claude Code** installed and authenticated (`claude` CLI available)
2. **Xcode 16+** installed
3. **Git** configured
4. **Apple Developer account** (for iCloud entitlements and App Store)

---

## Step 1: Initialize the Project

```bash
mkdir -p ~/Projects/OmniChat
cd ~/Projects/OmniChat
git init
```

## Step 2: Copy the Scaffold Files

Copy all the scaffold files into your project root:

```
~/Projects/OmniChat/
├── .claude/
│   └── agents/
│       ├── pm.md           ← Project Manager agent
│       ├── core.md         ← Core/infrastructure agent
│       ├── ui.md           ← UI/frontend agent
│       ├── qa.md           ← QA/testing agent
│       └── devops.md       ← DevOps/build agent
├── CLAUDE.md               ← Project-level Claude Code config
├── MASTER_PLAN.md          ← Full project specification
├── AGENTS.md               ← Shared task board
└── SETUP_GUIDE.md          ← This file
```

## Step 3: Verify Agents Are Registered

Open Claude Code in the project directory:

```bash
cd ~/Projects/OmniChat
claude
```

Then run:
```
/agents
```

You should see all 5 agents listed:
- **pm** — Project Manager
- **core** — Core infrastructure
- **ui** — UI/frontend
- **qa** — QA/testing
- **devops** — DevOps/build

## Step 4: Start Development

### Option A: Single Session (Simplest)

Run Claude Code and let it auto-delegate to agents:

```bash
cd ~/Projects/OmniChat
claude
```

Then tell Claude:
```
Read MASTER_PLAN.md and AGENTS.md. Start with Phase 0 — use the devops agent 
to set up the Xcode project, then proceed through each phase using the 
appropriate agents. Use the pm agent to coordinate.
```

Claude will automatically delegate tasks to the appropriate subagents based on their descriptions.

### Option B: Explicit Agent Invocation

You can explicitly request specific agents:

```
> Use the pm agent to initialize AGENTS.md and assign Phase 0 tasks
> Use the devops agent to create the Xcode project and configure capabilities
> Use the core agent to implement the SwiftData models
> Use the ui agent to build the ChatView
> Use the qa agent to write tests for the provider adapters
```

### Option C: Parallel Sessions (Most Efficient)

Open multiple Claude Code sessions in separate terminal tabs, each focused on a different agent:

**Terminal 1 — PM:**
```bash
cd ~/Projects/OmniChat
claude
> Use the pm agent to manage the project. Read MASTER_PLAN.md and coordinate work.
```

**Terminal 2 — Core:**
```bash
cd ~/Projects/OmniChat
claude
> Use the core agent. Check AGENTS.md for assigned tasks and start implementing.
```

**Terminal 3 — UI:**
```bash
cd ~/Projects/OmniChat
claude
> Use the ui agent. Check AGENTS.md for assigned tasks and start implementing.
```

**Terminal 4 — QA:**
```bash
cd ~/Projects/OmniChat
claude
> Use the qa agent. Monitor AGENTS.md for completed modules and write tests.
```

**Important for parallel sessions:**
- Each session operates on the same Git repo
- Agents coordinate via `AGENTS.md` — always pull/read it before starting work
- Agents commit with prefixes: `[pm]`, `[core]`, `[ui]`, `[qa]`, `[devops]`
- Keep an eye on merge conflicts — resolve them promptly

---

## How Agent Coordination Works

### Task Board (AGENTS.md)
This is the single source of truth for task assignments:

```markdown
| Task ID | Description | Agent | Status | Blockers | Notes |
|---------|-------------|-------|--------|----------|-------|
| TASK-1.1 | SwiftData Models | core | IN PROGRESS | — | — |
| TASK-2.1 | ContentView | ui | BLOCKED | TASK-1.1 | Needs data models |
```

### Workflow
1. **PM agent** reads MASTER_PLAN.md, populates AGENTS.md with phase tasks
2. **Each agent** checks AGENTS.md, claims their tasks, marks "IN PROGRESS"
3. **On completion**, agent commits code and marks task "DONE" in AGENTS.md
4. **If blocked**, agent updates AGENTS.md with blocker and moves to next task
5. **PM agent** monitors progress, resolves blockers, gates phase transitions

### File Ownership
Each agent has exclusive ownership of specific directories (defined in their agent files). This prevents conflicts:

| Agent | Owns |
|-------|------|
| core | `Core/`, `Shared/Models/`, `Shared/Extensions/` |
| ui | `App/`, `Features/`, `Shared/DesignSystem/`, `Resources/` |
| qa | `OmniChatTests/`, `OmniChatUITests/` |
| devops | `.xcodeproj`, `Info.plist`, `.entitlements`, `scripts/` |
| pm | `AGENTS.md`, `README.md`, docs only |

---

## Phase Progression

The project follows 12 phases (Phase 0–11). See MASTER_PLAN.md for full details.

**Quick reference:**
1. **Phase 0**: Project setup (devops leads)
2. **Phase 1**: Core data & provider layer (core leads)
3. **Phase 2**: Chat UI foundation (ui leads)
4. **Phase 3**: Provider configuration UI (ui leads, core supports)
5. **Phase 4**: Advanced chat features (ui leads)
6. **Phase 5**: Personas & system prompts (ui + core)
7. **Phase 6**: iCloud sync & polish (all agents)
8. **Phase 7**: Ollama & custom providers (core leads)
9. **Phase 8**: Token tracking & usage dashboard (core + ui)
10. **Phase 9**: OAuth integration (core leads)
11. **Phase 10**: Polish, testing & App Store (all agents)
12. **Phase 11**: Ads integration (devops + ui) — LAST STEP

---

## Agent Teams vs Subagents — Two Modes of Operation

This scaffold supports **both** Claude Code coordination models. Understanding the difference is key:

### Subagents (`.claude/agents/*.md`)
- Run **within a single Claude Code session**
- The main session delegates to a subagent → subagent works → returns results to main session
- Subagents **cannot talk to each other** — only report back to the parent
- Each subagent gets its own context window (doesn't pollute main conversation)
- Great for: focused tasks, sequential workflows, single-developer use

**How to use:** Just tell Claude which agent to invoke:
```
> Use the core agent to implement the SSE parser
```

### Agent Teams (experimental, enabled via settings.json)
- Multiple **independent Claude Code instances** running simultaneously
- A team lead coordinates, spawns teammates, assigns tasks
- Teammates **can message each other directly** — no round-trip through lead
- Shared task list with status tracking
- Great for: parallel development, large features, cross-layer work

**How to use:** The feature is already enabled in `.claude/settings.json`. Tell Claude to create a team:
```
> Create an agent team for OmniChat Phase 1. Spawn teammates:
> - "core-models" working on SwiftData models (use the core agent instructions)
> - "core-network" working on networking and SSE parser (use the core agent instructions)  
> - "core-providers" working on Anthropic and OpenAI adapters (use the core agent instructions)
> Have them coordinate: core-providers depends on core-network finishing the SSE parser.
```

### Which to Use When

| Scenario | Use | Why |
|----------|-----|-----|
| Quick focused task | Subagent | Low overhead, fast |
| Sequential phase work | Subagent | Tasks have dependencies |
| Parallel independent modules | Agent Team | Real parallelism, direct coordination |
| Cross-layer feature (UI + Core) | Agent Team | Frontend/backend teammates message each other |
| Code review from multiple angles | Agent Team | Security + performance + tests in parallel |
| Single terminal, casual work | Subagent | Simpler setup |

### Agent Teams Configuration

The scaffold includes `.claude/settings.json` with Agent Teams enabled:
```json
{
  "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": true
}
```

Alternatively, set the environment variable:
```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

**Display modes** (for tmux users):
- **auto** (default): Split panes if in tmux, in-process otherwise
- **split panes**: Each teammate gets its own tmux pane — best for 3+ teammates
- **in-process**: All in one terminal, use Shift+Up/Down to switch views

**Recommended setup for OmniChat development:**
```bash
# Start a tmux session for split pane view
tmux new -s omnichat
cd ~/Projects/OmniChat
claude
```

Then instruct Claude to create a team based on the current phase. The subagent definitions in `.claude/agents/` serve double duty — their system prompts and ownership rules apply whether invoked as subagents or as teammates in an Agent Team.

### Example: Full Phase 1 with Agent Teams

```
Read MASTER_PLAN.md and AGENTS.md. Create an agent team called "phase-1" for Phase 1 work.

Spawn these teammates:
1. "data-layer" — Implement SwiftData models and DataManager (TASK-1.1, TASK-1.4). 
   Follow the core agent rules from .claude/agents/core.md.
2. "networking" — Implement HTTPClient, SSEParser (TASK-1.5, TASK-1.4).
   Follow the core agent rules from .claude/agents/core.md.
3. "anthropic" — Implement AnthropicAdapter (TASK-1.6). Depends on networking finishing SSEParser.
   Follow the core agent rules from .claude/agents/core.md.
4. "openai" — Implement OpenAIAdapter (TASK-1.7). Depends on networking finishing SSEParser.
   Follow the core agent rules from .claude/agents/core.md.

Use Sonnet for all teammates. Coordinate dependencies: anthropic and openai should wait 
for networking to finish the SSE parser before starting their streaming implementation.
Update AGENTS.md as tasks complete.
```

---

## Tips

- **Always have agents read MASTER_PLAN.md first** — it's the project bible
- **Use the PM agent** when things get complex or agents need coordination
- **Run builds frequently**: `xcodebuild -scheme OmniChat -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`
- **QA agent should test early** — don't wait for the entire phase
- **Git commit often** with the proper prefix so you can track which agent did what
- For **complex provider work** (streaming, SSE parsing), give the core agent MASTER_PLAN.md Appendix A as reference — it has exact API formats
