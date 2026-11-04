# docs/ — index

Start with **[FINDINGS.md](FINDINGS.md)**, a digest of everything established so far: engine facts, the hook map, the design decisions in force, refuted approaches and open issues.

## Layout

```
docs/
├── README.md                  this index
├── FINDINGS.md                consolidated key findings (start here)
├── iteration-protocol.md      how to write iterations and review rounds
├── DetachedReticle.code-workspace   VS Code multi-root workspace (stays here: its paths are relative to docs/)
├── design/                    the current design, one topic per file
│   ├── architecture.md        tiers, per-frame math, components, per-weapon handling, build
│   ├── chase-smoothing.md     Option A power-law chase + Model A braking zone
│   └── convergence.md         parallax / hit-point convergence decision
├── research/                  reference material, kept current
│   ├── weapon-fire-flow.md    Phase 0 research (AGENTS.md cites this path)
│   └── noted-issues.md        proven mistakes; append-only "don't repeat" list
├── iterations/                append-only test logs
│   ├── 01-mvp.md              iterations 1–22 + assumptions ledger (closed)
│   ├── 02-polish.md           iterations 23–37 (active; next = 38)
│   └── 03-recoil.md           recoil iterations 1–6 (active; next = 7)
├── reviews/                   the open review round only
│   └── review-2026-11-03-round9.md   smart-weapon bisection plan (pending)
└── archive/                   superseded or one-off documents (see archive/README.md)
```

## Old path → new path

Older docs, reviews and commit messages cite the old paths. Use this table to find the files.

| Old path | New path |
|---|---|
| `docs/research/findings-mvp1-2.md` (earlier `findings.md`) | `docs/iterations/01-mvp.md` |
| `docs/research/findings-bugfixes.md` | `docs/iterations/02-polish.md` |
| `docs/research/findings-recoil.md` | `docs/iterations/03-recoil.md` |
| `docs/research/model-a-braking-zone.md` | `docs/design/chase-smoothing.md` |
| `docs/research/convergence-design.md` | `docs/design/convergence.md` |
| `docs/mvp.md` | merged into `docs/design/architecture.md`; original in `docs/archive/superseded/` |
| `docs/research/native-architecture.md` | merged into `docs/design/architecture.md`; original in `docs/archive/superseded/` |
| `docs/issue-analysis-and-iteration-plan.md` | `docs/archive/superseded/`; its §5 protocol moved to `docs/iteration-protocol.md` |
| `docs/review-*.md`, `docs/response-*.md` (rounds 1–8) | `docs/archive/reviews/` |
| `docs/review-2026-10-30-round7` (no extension) | `docs/archive/reviews/review-2026-10-30-round7.md` |
| `docs/review-2026-11-03-round9.md` | `docs/reviews/review-2026-11-03-round9.md` |

The iteration logs were moved without edits, so their entries still cite the old paths.
