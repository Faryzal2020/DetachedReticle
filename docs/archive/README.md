# archive/

These documents are no longer current. They stay here for history, unedited, so their internal links still use the old paths (see the path table in `../README.md`). Everything still worth knowing from them is in `../FINDINGS.md`.

## reviews/

The answered review rounds between the Mac reviewer and the Windows agent.

| File | Topic | Absorbed into |
|---|---|---|
| `review-2026-10-27-validation-handoff.md` | Round 1: first-commit validation (compile issues, ballistics, dual wield) | FINDINGS §3.1, §5 |
| `response-2026-10-27-validation-handoff.md` | Windows reply to round 1. **Caution:** its "EffectPreAction_PreAttack redirects the ray" claim was later refuted (MVP#5–#8). | FINDINGS §6 |
| `review-2026-10-27-round2.md` | MVP 1 acceptance bar, install completeness | FINDINGS §1 |
| `review-2026-10-28-round3.md` | Iteration 12 diagnosis (yaw convention, gimbal roll), first assumptions ledger | FINDINGS §3.3, §6; ledger in `iterations/01-mvp.md` |
| `review-2026-10-28-round4-chase-design.md` | The "chase the mouse" design and probe plan that produced MVP 2 | FINDINGS §2, `design/architecture.md` |
| `review-2026-10-29-round5.md` | MVP 2 sign-off, the half-gain bug, holster continuity, cleanup items H1–H8 | FINDINGS §5, §7 |
| `review-2026-10-30-round7.md` | First smart-weapon analysis (H1–H3). Round 6 was never filed. | Superseded by `reviews/review-2026-11-03-round9.md` |
| `review-2026-11-02-round8.md` | Validation of the WASD jitter / misalignment pre-analysis | FINDINGS §3.3, §6, §7 |

## superseded/

| File | Replaced by |
|---|---|
| `mvp.md` | `design/architecture.md` §1–2 |
| `native-architecture.md` | `design/architecture.md` §3, §5. Its Phase 1 claim (the arm mesh rigidly parented to the camera) and the AnimationHook plan were overtaken by MVP#13–#22. |
| `issue-analysis-and-iteration-plan.md` | Diagnosis: round 8 and iterations 33–35. Protocol: `iteration-protocol.md`. |
