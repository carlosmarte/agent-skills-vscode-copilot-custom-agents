# Devin Multi-Agent System (MAS) Scaffolding Execution Plan

## 1. Architectural Objective
Implement a deterministic, Multi-Agent System (MAS) scaffolding strategy using Devin. Because Devin currently lacks native semantic parsing for standalone `SKILL.md` files, this plan utilizes a **Router + Standard Operating Procedure (SOP)** pattern. This enforces strict architectural rules—specifically for <RepoRoot>/<RepoProject> environments and hyper-observability—before any code is written.

---

## 2. Directory Structure Setup
Begin by establishing the agent cognitive layer at the repository root (<RepoRoot>). This separates human documentation from AI execution parameters.

```text
<RepoRoot>/<RepoProject>
├── AGENTS.md                  # The AI Router & Root Directives
└── .agents/
    ├── skills/*               # Reusable agent capabilities, workflows, and task-specific instructions
    ├── templates/*            # Standardized prompts, file layouts, and response/document scaffolds
    ├── commands/*             # Named agent actions or slash-style commands for repeatable operations
    ├── scripts/*              # Helper scripts used by agents for automation, validation, or setup
    └── rules/*                # Project-specific constraints, policies, coding standards, and guardrails
```

# SYSTEM DIRECTIVE: WIKI & RUNTIME MEMORY PERSISTENCE

Devin, you must immediately update your internal Wiki, Knowledge Base, and central memory with the following permanent rules:

1. **Central Agent Repository Designation:** Acknowledge and record that this repository is the definitive, central source of truth for all Agent Files (Skills, Commands, Agents, and Rules).
2. **Progressive Runtime Loading:** Rather than attempting a heavy, synchronous initialization of all configurations upfront, you must load these assets dynamically and incrementally as needed by the execution context:
   * **Phase 1 (Discovery on Session Start):** Scan `AGENTS.md` and build an index of the available skill files in the `.agents/skills/` directory to mapping out your capabilities map. 
   * **Phase 2 (Lazy-Loading on Demand):** When a specific task matches a tool's trigger, pull that specific `[skill-name].md` file into active runtime context right before execution.
   * **Phase 3 (Post-Flight Validation):** Load defensive programming and testing constraints *after* code generation but *before* executing validation suites to audit the output against the target quality gate.
3. **Knowledge Base Sync:** Continuously index the file paths, triggers, and constraints of all `.agents/skills/*.md` files into your persistent Wiki so these capabilities remain instantly discoverable and globally available without requiring manual user prompting.
