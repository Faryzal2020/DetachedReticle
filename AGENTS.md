# AGENTS.md — Cyberpunk 2077 Decoupled Aim Mod

Instructions for AI coding agents working in this repository. Read this file fully before doing anything, then read `docs/FINDINGS.md`.

---

## 0. Ground truth (human: keep current; agent: treat as fact)

| Item | Value |
|---|---|
| `<ModName>` | `DetachedReticle` |
| `<GAME_ROOT>` | `E:\Cyberpunk 2077` (the Windows test machine) |
| Game build | `2.50 (Build 3.0.88.46235)`. The native RVAs only work on this build. |
| Branch of record | `testing`. It will overwrite `main`; never merge `main` into it. |
| State (2026-11-04) | MVP 1 and MVP 2 done; polish and recoil work done. Open items: `docs/FINDINGS.md` §7. |

---

## 1. What the mod does

The camera's aim direction is **decoupled** from the weapon's physical orientation, in **first person only**. It is not a third-person or TPS mod; third person is out of scope (owner decision, 2026-11-04).

| Goal | State |
|---|---|
| The camera reticle (center diamond) shows where the camera looks and moves only with the mouse | Done |
| A second reticle shows where the gun physically points | Done: a widget projected from the muzzle trace |
| The weapon turns toward the camera aim point with weight and a slight delay, framerate-independently | Done: the native chase (Option A power law) |
| Shots leave the muzzle and travel along the barrel | Done for hitscan. The HMG is remapped to hitscan. Other projectile weapon types have only been partly tested. |
| Recoil kicks the gun, not the camera | Done: recoil goes to Tier 2, with drift-free recovery and a rubber leash |

### Model (details in `docs/design/architecture.md`)

- **T1, camera:** raw mouse, instant.
- **T2A:** a smoothed chase of T1.
- **T2B, physical body heading:** `T2A − C + W` (C = barrel-offset compensation, W = recoil).
- **T3, gun reticle:** follows T2B through vanilla animation.

The mod never moves the gun mesh. It feeds vanilla's own look integrator a smoothed mouse delta, then counter-rotates the camera by the residual, so the camera stays on T1.

### Design decisions (resolved; the reasons are in `docs/FINDINGS.md` §5)

| Question | Decision |
|---|---|
| Parallax / convergence | Converge on the hit point with a slow integral screen trim (±3°) that only runs when settled. `docs/design/convergence.md` |
| Smoothing model | Option A: the continuous power law `dG/dt = −k·G^p` (k 22, p 0.6), solved in closed form. Model A braking is kept for reference only (too stiff). `docs/design/chase-smoothing.md` |
| Obstruction | No special handling. The gun reticle shows the muzzle trace's hit point, whatever the camera sees. |
| NPCs | Untouched: every hook checks for the player. |
| Excluded contexts | Melee, unarmed and dual wielding are vanilla. Scanning is confirmed fine. Vehicle combat is untested. |
| Smart weapons | Keep the chase only: no Tier 2B, no gun reticle, ray hook off, vanilla smart crosshair at center. The current bug is on hold (FINDINGS §7). |
| Compatibility | Script patches are `@wrapMethod` / `@addMethod` / `@addField` only, with no `@replaceMethod`. Native patches are three callsite patches; they check the bytes first and refuse to patch on any other build. |

---

## 2. How it got here (history)

| Phase | Outcome | Record |
|---|---|---|
| 0, Research | The fire pipeline, the muzzle transform, reticle feasibility | `docs/research/weapon-fire-flow.md` |
| 1, Feasibility | Script can draw the dual reticle. Neither the hitscan ray nor the arm rig can be redirected from script; a RED4ext plugin is required. Approved by the owner. | `docs/archive/reviews/` rounds 1–2 |
| MVP 1 (2026-10-28) | Freelook plus barrel ballistics: PhysicalRay callsite patch | `docs/iterations/01-mvp.md` #1–#9 |
| MVP 2 (2026-10-29) | Chase the mouse: look-integrator patch at `0x51D462`. Teleport was rejected. | `docs/iterations/01-mvp.md` #10–#22 |
| Polish | Roll fix, Tier 2B compensation, holster continuity, HMG, stance gates | `docs/iterations/02-polish.md` #23–#37 |
| Recoil | Recoil moved to Tier 2, drift-free recovery, leash, LMG gate | `docs/iterations/03-recoil.md` #1–#6 |

**Current mode:** iterate. One change per numbered iteration, recorded per `docs/iteration-protocol.md`. For a new feature that needs a new hook site or a big design change, write it up in `docs/` and get the owner's approval first.

---

## 3. Repository layout

The repo mirrors the game directory, so the tracked mod folders **are** the release.

```
/
├── AGENTS.md  README.md  .gitignore  CMakeLists.txt
├── docs/                      # see docs/README.md (FINDINGS, design, iterations, reviews, archive)
├── bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/
│   ├── init.lua               # activation, Tier 2B target/trim, camera residual, settings UI, logging
│   └── config.json            # default settings (rewritten by the in-game UI)
├── r6/
│   ├── scripts/DetachedReticle/
│   │   ├── DetachedReticle.reds   # module DetachedReticle: aim system, dual reticle, muzzle feed
│   │   └── NativeBridge.reds      # native func declarations for the DLL
│   └── tweaks/DetachedReticle/hmg_attack.yaml   # HMG → hitscan attack (TweakXL)
├── red4ext/plugins/DetachedReticle/DetachedReticle.dll   # tracked build of src/
├── src/                       # RED4ext plugin source (Main.cpp, Hooks/*)
│
├── reference/                 # NOT tracked: game-scripts/ (2.5 decompile), read-only
└── dist/                      # NOT tracked: release zips
```

### Workspace roots (`docs/DetachedReticle.code-workspace`)

The repo itself, plus `<GAME_ROOT>\red4ext\plugins`, `<GAME_ROOT>\tools\redmod` and `<GAME_ROOT>\bin\x64\plugins\cyber_engine_tweaks`. All of them are read-only except the repo.

---

## 4. Source of truth

Use these in priority order:

1. **Vanilla scripts:**
   - `reference/game-scripts/`: the 2.5 decompile, from the Codeberg fork `flibdev/cyberpunk` @ `17c62d0`. Files use `.swift`; native-only classes are in `orphans.swift`.
   - On the Windows machine, also the REDmod sources in `<GAME_ROOT>\tools\redmod\scripts\` (`.script`).

   The two can differ in line numbers and sometimes in bodies. Say which one you cite.
2. Dependency script folders (TweakXL, CET API) for their own APIs.
3. `docs/FINDINGS.md`, the iteration logs and `docs/research/noted-issues.md`, for the **empirical** engine behavior the dump can't show: RVAs, field offsets, stack slots.
4. `reference/wiki/` and <https://wiki.redmodding.org/>, for language rules (append `.md` to a page URL for Markdown).
5. Your own memory. Lowest priority; never sufficient alone.

**Regenerating the dump** after a game patch:

```
redscript-cli decompile -i "<GAME_ROOT>\r6\cache\final.redscripts" -o reference\game-scripts
```

Check the flags with `redscript-cli --help` first; or use the upstream mirror's tag for the new patch. Then update §0.

---

## 5. Rules

### Truthfulness (most important)

- **Never invent** class names, methods, fields, enums, TweakDB records, RVAs, offsets or engine behavior. Every script symbol must be found in the dump or in a dependency, and you must quote the file path. Every native fact must cite the iteration that measured it.
- If you can't find something, say so. Never guess a plausible name.
- Label every claim **verified** (in the dump), **empirical** (measured in game or in disassembly), **inferred** or **unknown**. Don't write "100% sure".
- `native` functions: you can see the signature, not the behavior.
- Before proposing anything, check `docs/research/noted-issues.md` and FINDINGS §6 (refuted approaches). Do not retry a refuted approach without new evidence.

### redscript

- Swift-like syntax, but not Swift. Known traps, all listed in `noted-issues.md`:
  - use `func`, not `function`/`export`
  - compare enums with `Equals()` / `EnumInt()`
  - `Cast<StatsObjectID>`
  - `array<ref<...>>` for class element types
  - `cb` wraps keep `-> Bool`
  - only wrap methods the class declares itself
- Use **`@wrapMethod`**, `@addMethod` and `@addField`. **No `@replaceMethod`** unless nothing else works, and then justify it in a comment.
- Check `<GAME_ROOT>\r6\scripts\` for other mods patching the same methods.
- Keep patches small. Don't copy vanilla blocks into the repo.
- New self-contained classes go in `module DetachedReticle`.

### Native plugin

- Every patch site is build-specific. Byte-check before patching, refuse on a mismatch, and log the refusal in `red4ext\logs\DetachedReticle.log`.
- All body and pitch rotation goes through the look-integrator hook. **Never** use `Teleport` to turn the puppet.
- The relay must save every volatile register and keep the stack 16-byte aligned.
- Keep the tracked DLL built from the committed `src/`. A DLL built from uncommitted source invalidated a test session (iteration 34).

### Never regress the core

The following must stay true after every change:

- The camera follows only the mouse, with no wobble.
- The body and gun chase with weight.
- Bullets leave the muzzle along the barrel.
- Passthrough mode is byte-for-byte vanilla.

After any large edit, confirm that the `Decoupled Aim ACTIVE` log line appears and that `rYaw` is non-zero. Iteration 31 shipped an inert mod.

### Safety and scope

- **Never modify** anything under `reference/`.
- **Never write** into `<GAME_ROOT>` outside an explicit deploy step the owner has approved.
- **Do not commit** game files, decompiled CDPR scripts, extracted assets or archives. Short citation snippets in docs are fine.
- Don't add dependencies without asking. Every required dependency must be in `README.md`.
- Don't touch `.gitignore` without asking. Its whitelist style is deliberate.
- Nothing is committed or pushed unless the owner asks.

### Working style

- Ask before big design decisions: new hook sites, smoothing models, scope changes.
- Keep responses concrete: file paths, symbol names, short diffs.
- Flag changes that could break other mods or save games.
- Record work per `docs/iteration-protocol.md`. In short:
  - iteration logs are append-only
  - write the entry as untested before testing
  - one variable per iteration
  - log reverted attempts too
  - proven mistakes go in `noted-issues.md`

---

## 6. Dependencies

| Dependency | Needed for | Required? |
|---|---|---|
| redscript 0.5.32+ | Compiling `.reds` | Yes |
| RED4ext 1.25+ (tested on 1.31.0) | Loading the native plugin: ballistics, look integrator, RTTI bridge | Yes |
| Cyber Engine Tweaks 1.38+ | `init.lua`: activation, camera residual, settings, logging. The mod does not run without it. | Yes (runtime) |
| TweakXL | `r6/tweaks/DetachedReticle/hmg_attack.yaml` (HMG hitscan remap) | Yes while that file ships. README doesn't list it yet (open item). |
| Native Settings UI | In-game settings menu | Optional |
| Codeware | Not used by the current scripts | No |
| ArchiveXL | No assets | No |
| RED4ext.SDK `5246e65`, MSVC v143, CMake ≥ 3.22, MASM | Building the DLL | Build only |
| WolvenKit | Inspecting entities, inkwidgets, game effects | Dev only |

---

## 7. Testing and debugging

| What | Where |
|---|---|
| Compile errors | `<GAME_ROOT>\r6\logs\redscript_rCURRENT.log`. Compile time only; it closes before gameplay. |
| Runtime telemetry (shots, chase, T2B, recoil, probes) | `<GAME_ROOT>\bin\x64\plugins\cyber_engine_tweaks\mods\DetachedReticle\DetachedReticle.log`, written by CET `io.open`. Enable `debugLogging` for the per-frame lines. |
| Native plugin load and patch status | `<GAME_ROOT>\red4ext\logs\DetachedReticle.log` |
| CET errors | `<GAME_ROOT>\bin\x64\plugins\cyber_engine_tweaks\` logs |

- `FTLog` does **not** reach disk at runtime. Bridge script telemetry through `DetachedAimSystem` into the CET log.
- The game's working directory is `bin\x64`. Relative paths in the DLL resolve from there.
- **After every game update:**
  1. Regenerate the dump.
  2. Re-find and re-verify all three RVAs and the `gameFPPCameraComponent` offsets (FINDINGS §4).
  3. Re-check every wrapped method.
  4. Update §0 and the tested version in `README.md`.

---

## 8. Release

- A release is a zip of the tracked mod folders (`bin/`, `r6/`, `red4ext/`) plus `README.md`, built into `dist/`.
- It contains **only** mod files: no `reference/`, `docs/`, `src/`, dumps or logs.
- The README must state:
  - the exact game build
  - every required dependency
  - what happens on other builds (the plugin refuses to patch and logs it)
  - gameplay changes (HMG rounds become hitscan with the medium exploding-bullet effect)
