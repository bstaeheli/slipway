# Agent Development Kit: Design

Date: 2026-10-29
Status: draft, awaiting user approval

Markers used in this document:

- No marker: the user decided this.
- **(our call)**: a default chosen during the design conversation. The user has not explicitly confirmed it, and it may be changed.
- **Left to the builder**: open by design; the builder decides.

## 1. Intent and why

The user wants to develop software with coding agents the way two talks at Directions EMEA 2026 (Paris) suggested:

- **"Ready, Spec, Go! What Could Possibly Go Wrong?"** by Vjekoslav Babić. This talk is the main source. Its points:
  - Spec-driven development, kept lightweight.
  - A project "constitution" that every agent reads first.
  - Specs state intent only and expire once built.
  - Separate code and test lanes, each validated against the spec.
  - A review loop after every producing step.
  - The human stands only at the two ends of the pipeline (slides 27, 30, 33 to 35, 37).
  - His own tooling ("fianchetto") is Claude-specific.
- **"Coding with agents: what actually works"**, an AL / Business Central panel deck. It contains questions only. Its themes:
  - Context files.
  - Small tasks.
  - Estimation that counts review and fix time.
  - Recovery from wrong paths.
  - Compile/publish/test loops.
  - Keeping some work away from agents.
  - Sharing practices across a team.

A concrete failure motivates this. The user tried to build a Matrix to Threema bridge with agents, and it failed for two reasons:

- They gave too many prescriptions about *how*, which made the result precise but wrong.
- The topic was far too large for one run.

All three symptoms appeared:

- The agent went in circles.
- The code did not run.
- The user lost the overview.

The kit must prevent exactly these three things.

## 2. Users, tools, languages

- **Users:** the user works alone for now. Later they want to share the practice with their team, so the kit must be shareable without the user's help.
- **Tools, all three equally:**
  - Claude Code.
  - GitHub Copilot in VS Code (agent mode).
  - GitHub Copilot CLI.
- **Languages:**
  - Work: AL apps for Business Central.
  - Private: FHEM (Perl), Python, Rust and others.
  - The kit is language-neutral. Anything language-specific lives in each project.

## 3. Goals, non-goals, anti-goals

### Goals

- **Same process everywhere.** One way of working, regardless of tool or language.
- **Big work cut small.** Large topics are cut into small slices. Each slice runs on its own and is tested.
- **Summaries only.** The user reads summaries only, never specs or code (except rarely).
- **Rare stops.** The agent stops only when it is truly blocked and has nothing else to do.
- **Trust from checks.** Trust in the result comes from automated tests and independent reviews, not from the user reading code.
- **Install once.** The kit is installed once per machine and never copied into projects.

### Non-goals

- Fully unattended "autopilot" or "judge" modes like Babić's. These may come later. Nothing in the first version depends on them **(our call)**.
- Replacing Superpowers inside Claude Code. The kit builds on Superpowers as a template (see section 10).
- Shared hook logic across tools. Hook formats differ per tool, so each tool gets its own small hook or deny-rule file (see section 8).
- Full autonomy in Copilot in the first version. Full autonomy comes first in Claude Code only (see section 7).

### Anti-goals (failure even if it works)

- **Ceremony for small work.** A small change must not trigger a spec, a plan and three reviews.
- **Token explosion.** Review loops, context loading and model size must stay proportionate (see section 9a). Every rule, review and artifact must justify its cost (Babić's "agentic economy": every instruction sends an invoice).
- **Frequent interruptions.** The agent must not keep asking the user things it could decide or defer.
- **Doctored tests.** These must never happen. The user considers them out of the question. The kit enforces this twice:
  - A hard rule: never weaken, skip or delete tests to make them pass, and never conceal failures.
  - An independent check: the test lane is written against the spec without seeing the code, and the final cross-review compares tests against the spec.

## 4. Installation model

**Model.** This repository (`agent-development-kit`) is the single source of truth. It is installed once per machine at user level. Projects receive only outputs, never kit files.

### Research findings (verified 2026-10-29)

Locally installed versions: Claude Code 2.1.306, Copilot CLI 1.0.48, VS Code 1.144.0.

| Location | Claude Code | Copilot CLI | VS Code Copilot |
|---|---|---|---|
| `~/.claude/skills` | yes | no | yes |
| `~/.copilot/skills` | no | yes | yes |
| `~/.agents/skills` | no (inferred) | yes | yes |
| `~/.claude/agents` | yes | no | yes |
| `~/.copilot/agents` | no | yes | yes |
| User instructions | `~/.claude/CLAUDE.md`, `~/.claude/rules/` | `~/.copilot/copilot-instructions.md`, `~/.copilot/instructions/` | both sets |
| Hooks | `~/.claude/settings.json` | `~/.copilot/hooks/` | `~/.copilot/hooks/` (preview) |
| Project `AGENTS.md` | yes, only if no `CLAUDE.md` exists | yes | yes |
| Plugins, Claude format | yes | yes (legacy manifest path) | yes |
| Subagents | yes | yes | yes |

All three tools support the open Agent Skills format (`SKILL.md` with `name` and `description` frontmatter). In all three, a skill is invoked automatically by its description and also by `/name`.

### Install layout (our call, derived from the research)

1. **Skills.** The repo holds `skills/<name>/SKILL.md`. Each skill is symlinked into both `~/.claude/skills/<name>` and `~/.agents/skills/<name>`. Together these two folders cover all three tools.
   - Do not also link into `~/.copilot/skills`. VS Code reads all three folders and would see duplicates.
   - Per-skill links leave existing third-party skills in those folders untouched. `~/.agents/skills` already holds 21 other skills.
2. **Rules.** The repo holds one rules file. It is symlinked to:
   - `~/.claude/rules/adk.md`
   - `~/.copilot/instructions/adk.instructions.md`

   The user's existing `~/.claude/CLAUDE.md` is not modified.
3. **Subagent definitions.** Optional, same symlink approach. Copilot expects the `*.agent.md` naming.
4. **Frontmatter.** Use portable fields only: `name`, `description`, and where needed `disable-model-invocation`. Avoid Claude-only features such as `!cmd` injection and `context: fork`.
5. **Hooks and deny rules.** These are tool-specific.
   - They are required for the customer-environment ban wherever a tool supports them (see section 8).
   - For everything else they are optional.
   - The instruction in the rules file remains the fallback where a tool has no technical block.
6. **Installer.** The kit ships an install script for macOS, Linux and Windows, with a matching uninstall and update path. This is a user decision.

   Details (our call):

   - **Scripts:**
     - `install.sh` in POSIX sh, for macOS and Linux.
     - `install.ps1`, for Windows PowerShell 5.1 and PowerShell 7.
   - **Idempotent.** Running it again changes nothing that is already correct.
   - **Scope.** It touches only the kit's own links. It never touches other skills or the user's existing `CLAUDE.md` and instruction files.
   - **Reporting.** It reports what it changed.
   - **Windows links:**
     - Directories link through junctions, which need neither admin rights nor Developer Mode.
     - Single files, such as the rules file, use a symlink when allowed, otherwise a hard link.
     - If neither works, it copies the file and warns that updates need a re-run.
   - **Windows user-level paths:** `%USERPROFILE%\.claude`, `%USERPROFILE%\.copilot`, `%USERPROFILE%\.agents`.
   - **Tests.** The install scripts must be tested on all three operating systems. How is left to the builder, for example a CI matrix.
7. **Team distribution (later).** The repo also carries a Claude-format plugin marketplace manifest. Claude Code, Copilot CLI and VS Code can all install it. For the user's own machine, symlinks remain preferred because edits take effect immediately.

### Verify first (unverified, must be tested before relying on them)

- Do Copilot CLI and VS Code follow symlinked skill directories?
- On Windows, do Copilot (CLI and VS Code) and Claude Code follow junctions?
- How does VS Code de-duplicate a skill found in several user folders?
- Does Claude Code really not read `~/.agents/skills`? (Currently inferred, not documented.)
- Does VS Code's Copilot harness read hooks from `~/.claude/settings.json`?

If symlinks are not followed, fall back to copying from the install script, and re-run it on update.

## 5. What lives in a project

**Opt-in.** The kit is active only in projects that contain `docs/agents/`.

- The global rules file says this first.
- In any other project, the kit does nothing.
- The bootstrap step creates `docs/agents/`.

Projects contain only outputs. All project files are in English, per the user's global rule.

```
AGENTS.md                  short: points to docs/agents/, lists project overrides
docs/agents/
  constitution/
    brief.md               what the project is, for whom, goals
    tech-stack.md          languages, frameworks, build/test/publish commands
    invariants.md          what must never break
    vocabulary.md          domain terms
    environments.md        allowlist of permitted publish targets
  status.md                slices: done / active / parked; blocker list for the user
  lessons.md               lessons from postmortems
  specs/<slug>.md          active specs only
  brainstorm/<slug>.md     conversation record so a later session can resume
```

- **No `CLAUDE.md` in projects.** Claude Code then reads `AGENTS.md` natively. Copilot reads `AGENTS.md` too.
- **Roadmap and personas** are not created by default. The kit describes both:
  - Roadmap: direction and planned stages.
  - Personas: who uses the product, with which goals.

  The agent creates them itself once the project needs them, for example when several stages are planned or several user groups become visible.
- **Done specs are deleted.** Babić calls them "archaeology": the code is the truth and git holds the history. Agents never read old specs.
- **No separate "how the product works today" document (our call).** The code is the truth.
- **Overrides.** Project overrides (for example "merge only by a human") go in `AGENTS.md`.
- **Bootstrap.** This step creates `docs/agents/` and so opts the project in.
  - For existing projects (for example a ten-year-old AL app), it drafts the constitution from the existing code and repository.
  - The user only confirms the draft.

## 6. Workflow

### Front end (the user is present)

1. **Conversation.**
   - The user describes the problem, not the solution.
   - The agent asks, challenges assumptions, explores alternatives and surfaces contradictions.
   - It reads the constitution first and keeps a record in `brainstorm/<slug>.md`.
   - This is the only step with full user participation.
2. **Routing.** The agent picks one of three paths:
   - **do-it:** small or UI changes. No spec. Implement, test, summarize.
   - **bugfix:** a reproduction test first, then the fix. This is the only place where test-first is mandatory.
   - **spec:** only for work that binds the architecture, carries business logic, or spans parts that must ship in order.

### Spec path (autonomous from here)

3. **Spec.**
   - States intent: what the change must and must not do, plus acceptance criteria.
   - Never covers how it is built, layout or wording. Anything left unsaid is the implementer's call.
   - The user receives a few-line summary, not the spec.
4. **Design.** Produces three artifacts:
   - Context: the relevant knowledge.
   - Graph: the affected code structure.
   - Acceptance: concrete acceptance checks.
5. **Plan.** Execution plan. It is a transient artifact, per Babić's dashed outline.
6. **Slicing.**
   - Cut the work into small slices. Each slice is independently runnable and testable.
   - Record the slices and their order in `status.md`.
   - This is the main defense against the Matrix-Threema failure.

Steps 3 to 6 each have a review loop. The reviewer returns findings to the producer until the review is clean. Reviewers flag violations and never invent new obligations. Upstream decisions are trusted and not re-debated.

### Per slice

7. **Fresh session or subagent** per slice, so context stays small.
8. **Contracts.** Derive signatures, data shapes and error cases from the spec, then review them. The contracts produce a code skeleton.
9. **Two parallel lanes, run by separate agents:**
   - **Code lane:** builds on the contracts using context and graph, then is reviewed.
   - **Test lane:** builds from the acceptance criteria, context and contracts, without seeing the implementation, then is reviewed.
   - **Lane isolation (our call):** the test lane is kept away from the code by instruction only. The final cross-review enforces it. No worktree isolation, to avoid ceremony and cost.
10. **Run tests.** This happens after both lane reviews. Use fast loops:
    - AL: `al-runner`, which avoids publishing to a sandbox.
    - Rust: `cargo test`.
    - Others: the commands listed in `tech-stack.md`.
11. **Analyze failure.**
    - Decide who is wrong: code, test or spec.
    - A code or test fault goes back to that lane.
    - A spec fault becomes a parked question for the user.
12. **Give-up rule.** After repeated failure on the same problem, stop that slice:
    - Write an honest note in `status.md`.
    - Park the slice.
    - Continue with other independent slices.

    The exact limit is left to the builder.

Strict TDD is not required. Tests and code are developed in parallel and both are validated against the spec.

### Back end

13. **Cross-review per slice.** Three comparisons, all asking "do they tell the same story?":
    - code against spec
    - tests against spec
    - code against tests
14. **One PR per slice.**
    - Each slice is a small PR that can be merged immediately (see section 8).
    - Parked slices block nothing.
    - Interim progress is recorded in `status.md`.
15. **One summary per spec, at the end.** It covers:
    - what was built
    - what was tested and the results
    - what is open or parked
    - which decisions the agent made on its own
    - any model-tier escalations
16. **Postmortem.**
    - Record lessons in `lessons.md`, which future sessions read.
    - Delete the spec after its last slice has merged.

## 7. Human role and stopping

- The human owns the product, takes part in the conversation, reads summaries and confirms constitution drafts. The human stands only at the two ends of the pipeline.
- **The agent stops only on a hard problem**, when it is blocked and has no other work left. Typical cases:
  - A Bitwarden or 1Password confirmation, for example for code signing.
  - An SSH login to a remote machine.
- **Handling blocks:**
  - A blocked slice is parked, and the agent continues with other work.
  - Blockers are collected as a list in `status.md`, so the user gets one batch instead of single interruptions.
- **Secrets stay with the user.** The agent never queries a password manager itself and never bypasses a confirmation.
- **Notification.** How the user is notified when the agent finally stops is left to the builder. It may differ per tool.
- **Autonomy per tool.**
  - Full autonomy comes first in Claude Code only.
  - In Copilot (VS Code and CLI), the user may start each slice manually, for example by typing "continue". This is acceptable.
  - The flow resumes from `status.md`, so any new session can pick up where the last one stopped.

## 8. Permissions

- **Allowed:**
  - `git push`.
  - Opening pull requests.
  - Publishing to local development environments.
- **Merge:** the agent merges each slice's PR itself. A project can override this in `AGENTS.md`.
- **Strictly forbidden:** publishing to customer environments and deleting anything on them.
- **Environment allowlist (our call).** Each project lists its permitted publish targets in `environments.md`, for example a local Docker container or al-runner.
  - Any target that is not listed counts as a customer environment and is forbidden.
  - Reason: an agent cannot reliably tell a customer environment from its name.

### Technical enforcement

- **Allowlist templates.** The kit ships permission allowlist templates per tool, so unattended runs work without constant permission prompts.
- **Hard block.** Where a tool supports it, the kit also ships a hard technical block (a deny rule or a hook) against publishing to or deleting on customer environments.
- **Fallback.** Where a tool has no such mechanism, the instruction in the rules file is the fallback.

### Git platforms

- **Platforms in use:**
  - Private: Forgejo (self-hosted and codeberg.org) and GitHub.
  - Business: GitHub and Azure DevOps.
- **MCP servers.** The respective platform MCP servers should be available to the agents.
- **Detection.** The platform is detected from the git remote.
- **PRs and merges** go through that platform's MCP server.
- **No PR capability.** If the repository has no PR capability at all, the agent merges locally.
- **Setup docs (our call).** The kit lists the required MCP server per platform, with setup notes per tool.
- **Missing MCP server (our call).** A missing MCP server for the detected platform is a blocker reported in `status.md`, not a silent fallback.

## 9. Rules for agents

These go in the kit's rules file and apply to every project.

**Freedoms.** The agent may:

- choose its approach and make technical decisions
- select tools
- refactor
- design tests and verification
- challenge assumptions
- adapt plans

**Prohibitions.** The agent must never:

- violate the constitution
- contradict explicit requirements
- break established contracts
- compromise security or privacy
- silently change intended behavior
- weaken, skip or delete tests to make them pass
- conceal failures or uncertainty
- publish to or delete on customer environments

**Principles:**

- Constrain the outcomes, not the intelligence.
- Engineer reliability, not predictability.
- Every rule, review and artifact must justify its cost.
- In projects with `docs/agents/`, kit skills take precedence over overlapping skills from other plugins (our call, see section 10).

## 9a. Model and context economy

The user requires that the orchestrator use only as large a model and as much context as necessary. This requirement is the main defense against the token-explosion anti-goal.

1. **Lean orchestrator.**
   - The orchestrator routes and delegates.
   - It keeps only summaries and file pointers in its own context.
   - It never holds file dumps or full transcripts.
2. **Smallest tier that works.** Each step or subagent uses the smallest model tier that does the job reliably:
   - **Large tier:** judgment-heavy steps: brainstorm, spec, design, review, failure analysis.
   - **Mid tier:** well-specified execution: code lane, test lane, mechanical edits.
   - **Small tier:** trivial tasks: status updates, formatting, searching.
3. **Escalate only after failure.**
   - A step moves to a larger tier only after it has failed at the smaller one.
   - Every escalation is recorded in the summary to the user.
4. **Fresh, minimal context per subagent (progressive disclosure).** Each subagent starts fresh and receives only what it needs:
   - its spec slice
   - the relevant contracts
   - the relevant parts of the constitution

**Portability.** The tiers are abstract and portable: large, mid and small. Mapping each tier to a concrete model per tool is left to the builder, for example through:

- the `model:` frontmatter of a Claude Code subagent
- the model field of a Copilot `.agent.md`

**Unverified.** Whether each tool honors per-agent model selection must be checked before relying on it, especially Copilot CLI and VS Code.

## 10. Relation to Superpowers

- The user already uses Superpowers in Claude Code (brainstorming, writing-plans, subagent-driven-development and others), plus Caveman and Ponytail.
- The kit builds on Superpowers as a template. It ships its own tool-neutral skills for every step, with its own storage locations under `docs/agents/`.
- The kit has no dependency on Superpowers. It must work in Copilot, where Superpowers is not installed.
- **Precedence (our call).** In projects that have `docs/agents/`, kit skills take precedence. The kit's rules file says so explicitly, so that two brainstorming skills do not fire at once in Claude Code.

## 11. Left to the builder

- The exact skill names and how many skills there are. Steps may be merged where separate skills would add ceremony.
- File templates for constitution documents, specs, `status.md` and `lessons.md`.
- Review-loop limits and the give-up threshold.
- How subagents are dispatched per tool, including a fallback to sequential runs if a tool cannot run lanes in parallel.
- How the user is notified of the batched blocker list.
- Mapping the abstract model tiers (large/mid/small) to concrete models per tool, after verifying per-agent model selection support (section 9a).
- The installer implementation and the plugin manifest.
- How the kit is tested. Every change ships with tests, validated against this document before shipping. The tests should at least cover:
  - the installer's links
  - the frontmatter's portability
  - the opt-in behavior: the kit does nothing without `docs/agents/`
  - the customer-environment block
- **Dry run per tool (our call).**
  - Automated for Claude Code and Copilot CLI, on a small sample project.
  - A short manual check for VS Code.
