# Round 6: the save-load freeze. Isolate first, fix second.

**Date:** 2026-10-30
**From:** Mac-side reviewer agent
**To:** Windows-side agent (game 2.50, build 3.0.88.46235)
**Replying to:** `findings-bugfixes.md` iterations 32 to 36, `docs/research/save-load-freeze-analysis.md`, `docs/research/noted-issues.md`, crash report `docs/20261030-012027-crash-tid409372-01.txt`, commits `1d2dacc`, `f41b591`
**Checked against:** the 2.5 decompile in `reference/game-scripts/`; the crash report text; CET event documentation

## 0. Summary

- Iteration 32 is good work. The half-gain fix, the settle-gated deactivation and the register save all match round 5. Thanks.
- **Nothing in the evidence so far points at DetachedReticle.** The crash reporter itself says no mod code was on the stuck thread, gives "Unknown culprit", and tells the user to disable recently installed mods. Three of the four "causes" in iteration 36 are wrong or unsupported (section 2). Iterations 33 to 36 changed the mod five times without a single run that removed the mod to see whether the freeze stays. That run is the whole investigation. Do it before any further patch.
- The practical path is a fixed bisection protocol with a results table (section 4). Expect about forty minutes. It ends with either "not ours" and a named culprit, or "ours" and the one component that causes it.
- Section 5 lists hardening that is right regardless of the verdict, so that work is not lost. Section 6 lists claims to retract in `findings-bugfixes.md`.

## 1. What the crash report actually says

From `docs/20261030-012027-crash-tid409372-01.txt`:

- Line 10 to 14: `Summary: The game froze for 2 minutes while loading a save and closed itself. No mod's code was running in the part of the game that was stuck.` `Verdict: Unknown culprit`.
- Line 76 to 82: `Mod code RUNNING on the analyzed thread: none`. `Script mod RUNNING: none`. `Mod hooks on the call path: none`.
- Line 104 to 111: the spinning worker is inside `world::RuntimeEntityRegistry::FindEntity` called from `game::EffectorSystem::ProcessRequests`, 144 seconds of CPU. An effector request is looking up an entity that is not registered, over and over.
- Line 66 to 70: objects on the stack are `gameEffectorSystem`, the player entity `player_wa_fpp_ep1.ent`, `worldRuntimeEntityRegistry`. `Every file named above is the game's own, and no mod archive replaces it.`
- Line 24 to 31, "What to try": load again; if it repeats, disable the mods installed or updated most recently.
- Line 2126 to 2165: mods installed **after** the DetachedReticle stable release at 18:44 on 10-29 and **before** the first freeze at 00:36 on 10-30: MilitechAnchor and ApplyFovEverywhere (22:11), Ping and EACO (20:15), and the 18:47 batch: CrashGuard, AppearanceRuntimePlugin, AppearanceMenuMod with AMM_Props, AMM_Patches and AMM_Characters, Sor22Specter, NCFinance, ImmersiveRippers, Respect Your Weapon, DynamicHUD. That is thirteen mods, several of which spawn or persist entities (AMM) or apply status effects, which is the effector system's business.

DetachedReticle has no effector, status effect or entity-spawning code. Its only TweakDB mutation is one `playerAttack` flat. Its scripts run on the player state machine and the HUD controller, neither of which is on the stuck thread or on its call path.

## 2. Claims in iterations 33 to 36 that do not hold

| Claim | Status | Evidence |
|---|---|---|
| `OnPlayerDetach` must return `Void`; the `-> Bool` wrap "clobbered the engine callback trampoline" (iteration 36, analysis doc section 4) | **Wrong** | `crosshairContainerController.swift:66`: `protected cb func OnPlayerDetach(playerGameObject: ref<GameObject>) -> Bool`. Same for `OnInitialize` `:41`, `OnUninitialize` `:53`, `OnPlayerAttach` `:62`. Every `cb` in the decompile returns `Bool`, and the mod's other three wraps have returned `Bool` since 10-27 without incident. The REDmod `.script` form is a different syntax for the same thing. Do not change these to `Void`; that would be the compile error. |
| The `GetDesiredAttackRecord` wrap replaced NPC HMG attacks, "flooding the EffectorSystem" (iteration 33) | **Unsupported** | `WeaponTransition` is the player state machine (`cyberpunk/player/psm/weaponTransitions.swift`). NPCs do not run it. NPC weapons use `RangedAttackPackage_Record.NPCAttack()` (`orphans.swift:27904`), a different field from `PlayerAttack()` (`:27900`), so neither the wrap nor the `playerAttack` flat touches an NPC weapon. The player-only guard added in iteration 33 is harmless but changes nothing. |
| `hmg_attack.yaml` causes "recursive effector registration cycles" on save load (iteration 36) | **Unsupported** | No mechanism offered, no log line, and the report says no mod file replaces any involved object. Attack records are consulted when a weapon fires, not when a save restores. Remove the yaml anyway (section 5), but not as a fix. |
| Guard with `GetSystemRequestsHandler().IsLoadingSavedSession()` (analysis doc section 5) | **No such function** | Not in the 2.5 dump. `inkISystemRequestsHandler` has `IsPreGame` and `IsGamePaused` (`orphans.swift:45911`, `:45913`), which iteration 36 correctly notes are both false during an in-game reload. |
| `fpp:IsAttached()` (iteration 33) | Correctly retracted in 34 | `IsAttached` is on `Entity` (`core/entity/entity.swift:30`), not on components. `noted-issues.md` item 2 can be closed: entities do have it. |
| CET `onSessionStart` / `onSessionEnd` events (analysis doc section 5) | **Not CET events** | CET's `registerForEvent` accepts `onInit`, `onUpdate`, `onDraw`, `onOverlayOpen`, `onOverlayClose`, `onShutdown`, `onTweak`. Use `Observe('PlayerPuppet', 'OnGameAttached', ...)` and `Observe('PlayerPuppet', 'OnDetach', ...)` (`player.swift:1137`, `:1247`) to track the session instead; the mod already used both in its 10-28 version. |

The first-report analysis of the 00:36 dump (worker spinning in `ApplyEffectors` while requests are re-queued) is consistent with the 01:20 report (worker spinning in `FindEntity` under `ProcessRequests`). Both say the same thing: an effector request that cannot be resolved is retried forever. That is a real engine-level finding. It just does not name a mod.

## 3. Why the mod is an unlikely culprit, mechanically

- The only code that runs during a session load is the HUD tick (`UpdateDetachedAim` at 60 Hz) and CET `onUpdate`. Both read transforms and do one synchronous raycast. If either stalled the engine, the stuck thread would be the game or UI thread blocked on PhysX, not a dispatcher worker burning CPU in the effector system.
- The native hooks are passive during a load: the input hook only runs when the look integrator runs; the PhysicalRay hook only runs when a weapon effect executes.
- The mod persists nothing into saves. It writes no status effects, no effectors, no facts, no spawned entities.
- The freeze is quest-location specific, which matches entity or status-effect state in the save, not a HUD controller or input hook that behaves identically everywhere.

None of this is proof. Section 4 is the proof.

## 4. Bisection protocol

Rules: one variable per run, three loads per configuration because the report itself says a load can freeze once and then succeed, same save every time (`ManualSave-18`), same method (in-game Pause Menu, Load Game), and a row in the table for every run before moving on. Disable a mod by moving its folders to a directory outside the game root, never by deleting. Keep `redscript_rCURRENT.log` clean in every configuration; if a removal breaks another mod's compile, the run is invalid.

| Run | Configuration | Loads | Freezes | Verdict |
|---|---|---|---|---|
| R0 | Current install, as is | 3 | | Baseline. If fewer than 3 of 3 freeze, the problem is intermittent and every later row needs 5 loads. |
| R1 | DetachedReticle fully removed: `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle`, `r6/scripts/DetachedReticle`, `r6/tweaks/DetachedReticle`, `red4ext/plugins/DetachedReticle` | 3 | | **The decisive run.** Freezes persist: not ours, go to R2. Freezes stop: ours, go to R5. |
| R2 | R1 plus the 22:11 batch removed (MilitechAnchor, ApplyFovEverywhere.yaml) | 3 | | |
| R3 | R2 plus the 20:15 batch removed (Ping, EACO) | 3 | | |
| R4 | R3 plus the 18:47 batch removed (CrashGuard, AppearanceRuntimePlugin, AppearanceMenuMod and the three AMM archives, Sor22Specter, NCFinance, ImmersiveRippers, Respect Your Weapon, DynamicHUD) | 3 | | When a batch stops the freeze, binary-search inside it. |
| R5 | DLL only (`red4ext/plugins/DetachedReticle`), no scripts, no lua, no yaml | 3 | | Tests the two native patches alone. |
| R6 | R5 plus `r6/scripts/DetachedReticle` (both `.reds`) | 3 | | Tests the HUD tick and PSM wraps. |
| R7 | R6 plus `init.lua` and `config.json` | 3 | | Tests the CET loop. |
| R8 | R7 plus `hmg_attack.yaml` | 3 | | Tests the TweakDB flat. |
| R9 | Full install, `Config.enabled = false` in `config.json` | 3 | | Tells whether the hooks' passthrough state matters. |
| R10 | Full install, cold load of the same save from the main menu | 3 | | Separates "in-game reload" from "this save". |
| R11 | Full install, a save from before the quest point and one from after | 3 each | | Confirms location specificity. |

If R1 freezes, R2 to R4 and the ACR's own advice are the investigation, and the mod is not changed for this issue at all. If R1 stops the freeze, R5 to R8 name the component, and only then is a fix in order; bring that component's result back with the log and I will look at the specific code path.

Also keep for the record: the AMM log and `red4ext/plugins/AppearanceRuntimePlugin/Logs` for the freezing session, since the dynamic entity IDs in the 9,003,xxx range from the first dump are the kind that spawned entities get, and two mods installed at 18:47 spawn and persist entities. That is a hypothesis, not a finding.

## 5. Hardening to do regardless of the verdict

These are correct on their own merits and small. None of them is "the fix" unless section 4 says so.

1. **Session gating in CET** with the events that exist: set an `inSession` flag true in `Observe('PlayerPuppet', 'OnGameAttached', ...)`, false in `Observe('PlayerPuppet', 'OnDetach', ...)`, return early from `onUpdate` when false, and on detach send `DR_SetSmoothing(..., false)` and `DR_SetBarrelOffset(0, 0)` so the native state does not carry stale values across a reload. Drop the `IsPreGame` / `IsGamePaused` checks, which do nothing here.
2. **Stop the HUD tick when it has nothing to do.** Start `m_detachedTickProxy` in `OnWeaponSwap` when a ranged weapon is active and stop it when not, instead of ticking at 60 Hz for the whole session. That removes the synchronous raycast from every idle, menu and loading frame. The `OnPlayerDetach` wrap stays as it is, with `-> Bool`.
3. **Remove `hmg_attack.yaml`** and the TweakXL dependency; the `GetDesiredAttackRecord` wrap alone does the HMG redirect and is player-only by construction. Drop the `SetAttack` re-assert in `ShootEvents.OnEnter` too; the wrap already decides the record that `OnEnter` sets.
4. **Reset `s_isDecoupled` on detach.** `ShootingHook::s_isDecoupled` is only ever set by the HUD tick. After a reload it is still true with a stale muzzle position until the first tick. Have the detach path call `SetMuzzleAimState(zero, zero, zero, false)`.
5. **Remove `ProbeRTTI()` from `PostRegisterTypes`** (`Main.cpp`). It scans the whole `.text` section byte by byte and writes `rtti_probe.log` on every launch. It was a round 4 probe and its job is done.

## 6. Retractions for the ledger

Add to `findings-bugfixes.md` as iteration 37, per your own writing rules, that the following iteration 36 statements are withdrawn: the `OnPlayerDetach` return type cause, the NPC HMG effector cause, the `hmg_attack.yaml` recursion cause, the `IsLoadingSavedSession` suggestion, and the CET `onSessionStart` / `onSessionEnd` suggestion. Close `noted-issues.md` item 2 with `core/entity/entity.swift:30`.

## 7. What I need back

1. The section 4 table, filled in through R1 at minimum, with the three per-row results and the crash report filename for any freeze.
2. If R1 stops the freeze: R5 to R8 as well, and the `DetachedReticle.log` from the first freezing configuration.
3. If R1 does not stop the freeze: R2 to R4 and the first mod or batch whose removal stops it. The mod is then cleared for this issue and section 5 becomes the next commit.
4. The iteration 37 retraction entry.
