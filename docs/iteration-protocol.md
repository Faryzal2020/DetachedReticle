# Iteration & Review Protocol

How work gets recorded in this repo. It collects the "Findings Writing Rules" from the iteration logs, the test protocol from the archived `issue-analysis-and-iteration-plan.md` (§5), and the process notes from review rounds 8 and 9.

## 1. Who writes what

| Who | Writes | Where |
|---|---|---|
| Windows agent (has the game, builds and tests) | One entry per attempt | `iterations/02-polish.md` (general; the next entry is **38**) or `iterations/03-recoil.md` (recoil; the next entry is **7**) |
| Windows agent | Proven mistakes, without their fixes | `research/noted-issues.md` |
| Mac reviewer (has the 2.5 dump, no game) | A reply to the latest iterations | `reviews/review-<YYYY-MM-DD>-round<N>.md` (the next round is **10**) |
| Either | Design decisions | `design/*.md` |
| Either, at milestones | The digest | `FINDINGS.md` |

`iterations/01-mvp.md` is closed (iterations 1 to 22). Iteration numbers on `testing` continue from its own history, not from `main`'s (owner decision, 2026-11-02).

## 2. Iteration log rules

1. Continue from the last entry. Never renumber.
2. Write the change as an **untested** entry *before* testing it. The next entry records the test result and what changed because of it.
3. Never edit or delete a past entry, except to fix a pure typo. A wrong fix is corrected in the next entry, which says what was wrong.
4. Log every attempt, **including reverted ones.** The smart-weapon attempts after iteration 36 left no trace, and that cost a review round (R9 §5).
5. Change **one variable** per iteration. Unrelated paths may share an entry if they get separate numbered changes and separate pass criteria.
6. Define pass/fail before testing, as a number or a concrete behavior.
7. Cite log lines verbatim (timestamp, frame number, values). If a claim rests on a log, the log lines go into the entry.
8. Label claims **verified** (seen in the dump), **empirical** (measured), **inferred** or **unknown**. Don't write "100% sure" (R8 §4).

### Template

```markdown
# iteration <N>
- date: YYYY-MM-DD HH:MM +0700
- status: untested | tested-pass | tested-fail
- previous_iteration_results: <observations + verbatim log lines>
- target_goal / hypothesis: <what is believed, and its label>
- changes_made:
  1. `<file>`: `<symbol / line>`: <exact change>
- expected_outcome: <pass criterion>
- test_procedure:
  1. <weapon, stance, action>
  2. <log lines to inspect>
```

## 3. Hard rules (from AGENTS.md and past failures)

- Grep every symbol in `reference/game-scripts/` before using it. Never guess a name.
- Don't use `Teleport` to turn the puppet. All rotation goes through the native look integrator.
- Never regress the core MVP: instant camera freelook, a body that chases with lag, muzzle ballistics.
- After any large edit, confirm the `Decoupled Aim ACTIVE` log line and a non-zero `rYaw`. Iteration 31 shipped an inert mod.
- Keep the repo DLL, the game-folder DLL and `src/` in sync. Iteration 34 found a deployed DLL built from uncommitted source.

## 4. Review rounds

- The Mac reviewer verifies each new symbol against the dump, diagnoses from the code and the dump, and labels every claim.
- One file per round, in `reviews/`. When the next round supersedes it, move it to `archive/reviews/`.
- Nothing is committed unless the owner asks.
