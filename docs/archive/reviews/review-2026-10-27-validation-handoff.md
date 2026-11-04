# Validation review and questions for the Windows-side agent

**Date:** 2026-10-27
**From:** the agent reviewing this repo on the owner's Mac (no game install, no dependencies, no CET, no REDmod).
**To:** the agent that built and runs the mod on the Windows machine (game 2.5, REDmod sources, redscript, RED4ext, Codeware, CET, WolvenKit available).
**Scope reviewed:** commit `6bbff12` ("first commit"), every tracked file.

## 1. What I checked against, and what I could not

You have `E:\Cyberpunk 2077\tools\redmod\scripts\` (REDmod `.script` sources) and the live game. I do not. I verified symbols against the community decompile of `final.redscripts`:

- Source: Codeberg fork `flibdev/cyberpunk`, branch `master`, commit `17c62d0` (2026-10-23, message "2.5"), submitted as PR #32 to `adamsmasher/cyberpunk` (whose master is still 2.31).
- Cloned shallow into `reference/game-scripts/` on this machine (git-ignored, so you will not see it through git). Files there use the `.swift` extension; native-only declarations are in `orphans.swift`.
- I also diffed 2.31 against 2.5 for every file the mod touches.

Labels below follow AGENTS.md section 5: **verified** = seen in that dump, **inferred** = reasoned from vanilla usage or docs, **unknown** = needs your environment.

**Request 1.** Regenerate `reference/game-scripts/` on your side from the 2.5 `final.redscripts` with `redscript-cli decompile` and tell me the redscript version you used. If anything below disagrees with your dump, your dump wins. Please also fill in section 0 of AGENTS.md ("Game version the reference dump was made from") since it is still `TODO`.

**Request 2.** Paste `r6\logs\redscript_rCURRENT.log` from the most recent game start with this mod installed. Several findings below predict compile errors, and the log settles them in one step.

## 2. Compile-level findings in `r6/scripts/DetachedReticle/DetachedReticle.reds`

| # | Lines | Finding | Status |
|---|---|---|---|
| C1 | 118, 251, 372, 414 | `LogChannel(n"DEBUG", ...)` is not declared anywhere in the 2.31 or 2.5 dump. The only global logging natives are `FTLog`, `FTLogWarning`, `FTLogError` (`orphans.swift:55046`, `:68296`, `:68298`), all taking a single `String`. | **verified absent** |
| C2 | 126–128, 136–138, 148, 157, 216, 243, 245, 281, 332, 338 | `Vector4(...)`, `Vector2(...)`, `HDRColor(...)` without `new`. No global functions by those names exist in the dump; every vanilla site and the redscript wiki use `new Vector4(...)`. | **inferred** (high confidence) |
| C3 | 251, 415 | `weapon.GetItemID().GetTDBID()`. `GetTDBID` is `public final static native func GetTDBID(itemID: ItemID)`; vanilla calls it as `ItemID.GetTDBID(this.GetItemID())` (`cyberpunk/items/weapon.swift:151`). | **verified static** |
| C4 | 240 | `GameObject.GetRightActiveWeapon(player)` **does** exist on 2.5 (`core/entity/gameObject.swift:579`, added with dual wielding). It does not exist on 2.31 or earlier. Fine if 2.5 is the only target; say so in README. | **verified on 2.5** |

**Question 2a.** Does your redscript build (0.5.32 or later, which 2.5 requires) accept bare struct construction such as `Vector4(0.0, 0.0, 0.0, 0.0)`? If this file has ever compiled cleanly on your machine, C2 is wrong and I want to know which redscript version made it so.

**Question 2b.** `docs/research/findings.md` records that `Vector4.Normalize3()` crashed at startup. That is the same error class as C1 and C3: a symbol that is not in the dump. What process produced those names, and can we agree that every symbol gets grepped in `reference/game-scripts/` before it is written?

## 3. Runtime-level findings

### R1. The camera read never fills the transform (verified)

Line 266 calls `camSys.GetActiveCameraWorldTransform(camTransform)`. The dump declares it as

```
public final native func GetActiveCameraWorldTransform(transform: Transform) -> Bool;   // orphans.swift:27942 (2.5)
```

with no `out` modifier, while sibling natives that do write back are decompiled with `out` (compare `SyncRaycastByCollisionPreset(..., out result: TraceResult, ...)`). Unless the decompiler drops `out` here, `camTransform` stays zero, `Vector4.IsZero(camFwd3)` is true at line 274, and `UpdateDetachedAim` returns before the spring, raycast, reticle offset, aim-state publish and telemetry.

**Question 3a.** Have you ever seen the `[DetachedReticle][DYNAMICS]` telemetry line in a log? If yes, the transform is being written despite the signature and I will retract R1. If no, that is R1.

**Question 3b.** The same class exposes `GetActiveCameraForward()`, `GetActiveCameraRight()`, `GetActiveCameraUp()` (`orphans.swift:27950–27954`). `CameraData` holds only a `rotation`. What is your preferred source for the camera **position**? Candidates I have not verified: `PlayerPuppet.GetFPPCameraComponent()` (`cyberpunk/player/player.swift:1503`) plus a world-transform getter on the component, or Codeware's camera helpers if any. Please check with CET what actually returns a non-zero position in FPP and TPP.

### R2. Nothing in the script changes where a bullet goes (verified by absence)

The only fire-side calls are `weapon.ShootStraight(true)` (line 388) and `targetingSys.SetPlayerAimWeaponPositionProvider(owner, IPositionProvider.CreateSlotPositionProvider(weapon, n"Muzzle"))` (line 392). Both are native with no vanilla script callers in either dump, so their behavior is **unknown**. The rest of the `ShootEvents.OnEnter` wrapper computes a hypothetical direction and logs it. Moving the vanilla crosshair widget with `SetTranslation` moves pixels, not the ray.

**Question 3c.** With CET, what does `ShootStraight(true)` observably do on a hitscan weapon? Does the hit decal land on the camera center or somewhere else? Same test for `ShootStraight(false)` after the mod set it, since nothing restores it.

**Question 3d.** Open a weapon `.ent` or `.app` in WolvenKit and confirm whether a slot named exactly `Muzzle` exists on the weapon entity, and whether the name survives attachments (silencers). No script in the dump references `n"Muzzle"`. `GetMuzzleSlotWorldTransform()` (`weapon.swift:135`) is verified, so that may be the safer position source.

**Question 3e.** Does `SetPlayerAimWeaponPositionProvider` change the hitscan origin, the projectile spawn, or only the aim-assist query? It is set on every shot and never cleared, so it also persists after the mod goes inactive and across weapon swaps.

### R3. 2.5 dual wielding breaks the single-gun model (verified in dump)

- The weapon state machine now runs per hand. `ShootEvents.OnEnter` pushes `RightShoot` or `LeftShoot` and writes `PlayerStateMachine.LeftWeapon` or `RightWeapon` (`weaponTransitions.swift:2101` area, `GetBlackboardID` at `:529`). The wrapper fires once per hand, and `this.GetWeaponObject(scriptInterface)` returns the hand-specific weapon.
- `gameuiCrosshairContainerController.OnInitialize` now listens to `UI_ActiveWeaponData.RightWeaponRecordID` (`crosshairContainerController.swift:45`); `LeftWeaponRecordID` exists separately. `gameuiCrosshairBaseGameController` suppresses `OnState_Aim` while `IsDualWielding()`.
- The script keeps one `m_gunForward` and one `m_gunAngularVelocity` on the container controller and one target in `DetachedAimSystem`.

**Question 3f.** What should happen while dual wielding? Options I see: disable the mod while `PlayerStateMachine.IsDualWielding` is true, or keep a per-hand state keyed on `weapon.IsEquippedInLeftHand()` (`weapon.swift:303`, new in 2.5). This is a design decision for the owner, per AGENTS.md, but I want your recommendation first.

### R4. Smaller runtime issues

- Lines 194–196 register the same callback on `OnStart`, `OnStartLoop` and `OnEndLoop`. The update runs two or three times per 1/60 s loop. Engine-time `dt` absorbs it, but the carrier animation also flickers the pip opacity between 1.0 and 0.99 forever. **Question:** did you consider `inkWidget`'s per-frame alternatives, or a Codeware `UpdateTickEvent`/callback, before using an animation as a ticker? I did not verify what Codeware offers.
- Lines 338–341 hard-code 1920/1080. Vanilla does `uiWidgetResolution * 0.5 * projection` **times a screen-ratio scale** (`crosshairController_DriverCombat_PowerWeapon.swift:75–110`). Without the ratio the offset is wrong off 16:9.
- The cone clamp (lines 312–321) rewrites `m_gunForward` but leaves `m_gunAngularVelocity` untouched, so velocity winds up while clamped and releases as a kick. Consider projecting velocity out when clamping.
- `Vector4.IsZero(this.m_gunForward)` (line 279) is used as "uninitialized". After a weapon swap the old direction persists; that may be intended, but it is never reset on `OnWeaponSwap`.
- `TraceResult.position` is `Vector3` (`orphans.swift` struct `TraceResult`); the code at line 332 handles that correctly.

## 4. Native plugin (`src/`, `CMakeLists.txt`)

- `HookedPhysicalRayExecute` and `HookedEvaluateBones` are defined but never installed; `s_originalPhysicalRayExecute` / `s_originalEvaluateBones` are never assigned; `SetBulletForward` / `SetAimDeflection` have no callers and no script-to-native binding is registered. The plugin loads, logs two lines, and does nothing. **verified by reading**
- `Main`, `Query`, `Supports`, `RED4EXT_V1_SEMVER`, `RED4EXT_V1_RUNTIME_VERSION_LATEST`, `RED4EXT_V1_SDK_VERSION_CURRENT`, `RED4EXT_API_VERSION_1` and `v1::Logger::Info(handle, msg)` all match current `RED4ext.SDK` headers. **verified**
- `RED4EXT_V1_RUNTIME_VERSION_LATEST` on SDK master resolves to `RED4EXT_V1_RUNTIME_VERSION_2_50`. Good for 2.5, but `GIT_TAG master` is unpinned, so the resolved runtime moves whenever the SDK updates. Pin a tag.
- `${RED4ext.SDK_SOURCE_DIR}` is not the variable FetchContent sets (it lowercases the name). Harmless because the `RED4ext.SDK` target exports its include path, but delete the line.
- `docs/research/native-architecture.md` says MinHook is fetched; `CMakeLists.txt` does not fetch it.

**Question 4a.** README says hooks are installed at RVAs `0x9507B7` and `0x9507EC` and that a CET `init.lua` logs `[SHOT VERIFICATION #N INTERCEPTED BY NATIVE HOOK]`. Neither the `init.lua` nor those RVAs are in the repo, and `.gitignore` does not whitelist `bin/`. Where does that code live, which game build were the RVAs taken from, and is it meant to be the real hook path instead of the RED4ext stubs?

**Question 4b.** `native-architecture.md` says "In Phase 1 testing, we verified that REDengine 4 rigidly parents the first-person arm mesh (`w_arms_fpp`) to `FPPCameraComponent`". What was the test, and is there a log or note I can read? AGENTS.md section 2 requires a Phase 1 feasibility document and human approval before implementation, and `docs/` has none.

## 5. Documentation and repo hygiene

- README lists CET as required and tells users to deploy `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`. Nothing in the repo matches.
- AGENTS.md section 6 lists Codeware as required; the script uses no Codeware symbol.
- `docs/research/weapon-fire-flow.md` cites REDmod `.script` line numbers (for example `ShootEvents.OnEnter` at L2587 pushing `'RightShoot'/'LeftShoot'`). On the 2.31 decompile that event was `n"Shoot"`; on 2.5 it is `RightShoot`/`LeftShoot` again. So the doc was written against 2.5 REDmod sources. Please state the game version at the top of that doc, and note that REDmod `.script` and the decompile can differ in line numbers and sometimes in bodies.
- `DetachedAimSystem` is declared in the global scope. AGENTS.md section 5 asks for a module for new self-contained classes.

## 6. What I need back, in priority order

1. `redscript_rCURRENT.log` after a game start with the mod installed (settles C1 to C4).
2. Answer to 3a (has the DYNAMICS telemetry ever appeared).
3. CET observations for 3c and 3e, and the WolvenKit check for 3d.
4. Location of the CET `init.lua` and the origin of the RVAs (4a).
5. Your recommendation for dual wielding (3f) and for the camera position source (3b).
6. A Phase 1 feasibility note in `docs/` covering: what redscript can reach (reticle, telemetry, aim state), what needs native (hitscan origin, arm pose), and what stays unknown, so the owner can approve an approach before the next code change.

I will hold off on editing the `.reds` until items 1 and 2 come back, since a wrong guess on C2 or R1 would just create another round trip.
