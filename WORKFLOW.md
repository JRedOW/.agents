# Workflow

The rule is simple: **Claude Code plans, OpenCode implements.** Never build in Claude Code, never plan a big feature in OpenCode. The bridge between the two windows is the ticket list on the issue tracker (source of truth) plus a `/handoff` doc that captures session context which specs and ADRs do not already record.

## One-time setup

- [ ] Run `/setup-matt-pocock-skills` in Claude Code. The "with issue" paths assume whatever tracker this configures (GitHub Issues or local `.scratch/` files). Until this is done, only work the two "no issue" paths.

## Which path am I on?

Two questions decide everything: does a written issue exist, and is the job large?

| Issue exists? | Large? | Path |
|---|---|---|
| No  | Yes | [Path 1: Large, no issue](#path-1-large-no-issue) |
| Yes | Yes | [Path 2: Large, with issue](#path-2-large-with-issue) |
| Yes | No  | [Path 3: Small, with issue](#path-3-small-with-issue) |
| No  | No  | [Path 4: Small, no issue](#path-4-small-no-issue) |

**Large** means more than one ticket, or more than one session of work. **Small** means one ticket, one session.

```mermaid
flowchart TD
    START(["Something to build or fix"]) --> Q1{"Does a written issue exist?"}
    Q1 -- yes --> Q2{"Large?"}
    Q1 -- no --> Q3{"Large?"}
    Q2 -- yes --> P2["Path 2: Large with issue"]
    Q2 -- no --> P3["Path 3: Small with issue"]
    Q3 -- yes --> P1["Path 1: Large, no issue"]
    Q3 -- no --> P4["Path 4: Small, no issue"]
```

## Path 1: Large, no issue

```mermaid
flowchart TD
    subgraph CC ["Claude Code: planning"]
        ENTRY{"Foggy, greenfield, or too big for one session?"} -- yes --> WF["/wayfinder: charts decision tickets on the tracker and resolves them one at a time, producing decisions, not deliverables. Never for a well-scoped feature."]
        ENTRY -- no --> GRILL
        WF -->|"when the way is clear: it hands off, it does not build"| GRILL["/grill-with-docs: interviews you until the idea is sharp, and leaves a paper trail: GLOSSARY.md and ADRs."]
        GRILL --> PROTO{"Does a design question need code to answer?"} -- "yes: state, business logic, or a UI to see" --> HP["/handoff out, open a fresh session in a separate directory, run /prototype, then /handoff back what you learned, and reference it from the original thread."]
        PROTO -- "no" --> SPEC["/to-spec: turns the conversation into a spec."]
        HP --> SPEC
        SPEC --> TICKETS["/to-tickets: splits the spec into tracer-bullet tickets, each declaring its blocking edges."]
        TICKETS --> HYG["Context hygiene: keep planning in one unbroken context window. Do not compact or clear until after /to-tickets. Near the smart zone of roughly 150k tokens, /compact at the nearest phase boundary."]
    end
    HYG --> BRIDGE
    subgraph OC ["OpenCode: implementation"]
        BRIDGE["The tickets are the source of truth, so OpenCode reads tickets, not a summary. Write a /handoff doc only for session context not already captured in specs, ADRs, or tickets, and reference those by path."] --> IMPL["Pick any ticket whose blockers are done. Run /implement on it with the review override in your prompt: finish with /ponytail-review instead of /code-review. It uses /tdd where possible at pre-agreed seams, typechecks regularly, runs the full test suite once at the finish, and commits to the current branch."]
        IMPL --> REVIEW["/ponytail-review after each change. Fix the findings before the next ticket."]
        REVIEW --> DONE{"All tickets done?"}
        DONE -->|"not yet"| CLEAR["/clear, then pick the next ticket. Each ticket is self-contained."]
        CLEAR --> IMPL
        DONE -- yes --> FINAL["/ponytail-review over the branch"] --> CODE["/code-review: checks the diff against coding standards and the originating spec."] --> PRB["/pr: the smallest visual that shows the change, before and after evidence it works, and a one-way or two-way door call."] --> RETRO["/retro: turns every finding into an environment change, a coding standard, an automated check, or a steering file."]
        ALT["Alternative: instead of driving tickets by hand, /implement-spec builds the whole spec in one orchestrated run, with implementer subagents working the ready frontier in parallel onto one integration branch."] -.->|"if you would rather orchestrate"| IMPL
    end
```

## Path 2: Large, with issue

```mermaid
flowchart TD
    RAW["Raw incoming issue: bug report or feature request you did not write for yourself."] --> TRIAGE["/triage: moves issues through triage roles and produces agent-ready issues."]
    TRIAGE --> SKIP["Never triage tickets that /to-tickets produced: they are already agent-ready."] -.-> MERGE
    TRIAGE --> MERGE["Then follow Path 1 in full: /wayfinder if foggy, otherwise /grill-with-docs, then /to-spec and /to-tickets. Implementation is identical and lives inside the Path 1 chart."]
```

## Path 3: Small, with issue

```mermaid
flowchart TD
    subgraph CC ["Claude Code: planning"]
        READ["Read the issue: it already says what to do and why, so do not re-plan it."] --> UNCLEAR{"Is the issue unclear, or hiding a design decision?"}
        UNCLEAR -- "yes" --> BRIEF["A brief /grill-with-docs, to sharpen only what is unclear."]
        BRIEF --> PLAN["Write a short plan, or a /handoff doc if the reasoning is not obvious from the issue."]
        UNCLEAR -- "no" --> PLAN
        PLAN --> GROWN{"Do you need more than one ticket?"}
    end
    GROWN -->|"yes: stop, switch to Path 2"| P2(["Path 2"])
    GROWN -->|"no"| IMPL
    subgraph OC ["OpenCode: implementation"]
        IMPL["/implement in one context, no /clear, driving /tdd for the behaviour."] --> REVIEW["/ponytail-review, and fix the findings."] --> PR{"Need a PR?"}
        PR -- "yes" --> PRB["/pr"] --> CLOSE(["Update or close the issue. /retro is optional here."])
        PR -- "no" --> CLOSE
    end
```

## Path 4: Small, no issue

```mermaid
flowchart TD
    subgraph CC ["Claude Code: planning"]
        SHARP{"In a repo, and want the ADR trail?"} -- "yes" --> GD["A short /grill-with-docs."]
        SHARP -- "no" --> GM["/grill-me: stateless, saves nothing locally, for when no working directory is involved."]
        GD --> PLAN["Write a short plan, or a /handoff doc."]
        GM --> PLAN
        PLAN --> GROWN{"More than one ticket?"}
    end
    GROWN -- "yes: switch to Path 1" --> P1(["Path 1"])
    GROWN -- "no" --> IMPL
    subgraph OC ["OpenCode: implementation"]
        IMPL["A single concrete behaviour? Drive /tdd alone. Otherwise run /implement."] --> REVIEW["/ponytail-review."] --> PR{"Need a PR?"}
        PR -- "yes" --> PRB["/pr"] --> DONE(["Done."])
        PR -- "no" --> DONE
    end
```

## Escalation

```mermaid
flowchart LR
    SMALL["Working small path 3 or 4"] --> GROW{"Grew past one ticket?"}
    GROW -- no --> CONTINUE["Keep going"]
    GROW -- yes --> ESC["Stop, switch to the matching large path<br>path 3 becomes path 2, path 4 becomes path 1"]
```

## Bugs: something broken, throwing, or slow

```mermaid
flowchart TD
    BUG["A bug, an intermittent flake, or a regression between two known-good states."] --> DIAG["/diagnosing-bugs"]
    DIAG --> LOOP{"Do you have a tight feedback loop: one command that already goes red on this exact bug?"}
    LOOP -- "no" --> BUILD["Build the loop first. No theorising without it."]
    BUILD --> LOOP
    LOOP -- "yes" --> RED["Write a regression test that fails: /tdd"] --> FIX["Fix until green."] --> REVIEW["/ponytail-review."] --> RETRO["/retro, in the same session: what would have prevented this bug?"]
    RETRO --> SEAM{"No good seam in the code to lock this down?"} -- "yes" --> ICA["/improve-codebase-architecture"]
```

## Upkeep

```mermaid
flowchart LR
    IDLE["A spare moment, no feature work running"] --> HEAP
    subgraph HEAP ["Upkeep"]
        A["/improve-codebase-architecture: surfaces deepening opportunities. Picking one generates an idea you take into Path 1."]
        B["/ponytail-audit: one-shot whole-repo quality report. Changes nothing."]
        C["/ponytail-debt: lists every shortcut comment as a ledger of deferred limits."]
    end
```

## The review rule

```mermaid
flowchart TD
    CHANGE["A change is ready for review"] --> WHERE{"Where are we in the build?"}
    WHERE -- "per change, on every path" --> PONY["/ponytail-review: correctness, risk, scale, missing tests, speed, and leanness. Closes with a verdict: ship, or fix which findings first."]
    WHERE -- "branch or PR level, on the large paths only" --> BOTH["/ponytail-review, then /code-review: checks the diff against the coding standards and the originating spec."]
```

## The retro loop

```mermaid
flowchart TD
    RETRO["/retro, in the session it looks back on, before you clear it"] --> KIND{"What was the finding?"}
    KIND -- "a mechanical mistake" --> CHECK["Becomes a deterministic check"]
    KIND -- "a judgement call" --> STANDARD["Becomes a coding standard for /code-review"]
    KIND -- "navigation or tooling pain" --> ENV["Becomes a steering file, pointer, or tooling change"]
    CHECK --> NEXT(["The next build starts from a better environment"])
    STANDARD --> NEXT
    ENV --> NEXT
```
