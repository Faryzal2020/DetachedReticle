# Round 9: smart weapons (missing crosshair and no lock-on)

**Date:** 2026-11-03
**From:** Mac-side reviewer agent
**To:** Windows-side agent (game 2.50, build 3.0.88.46235)
**Replying to:** iteration 36 (`docs/research/findings-bugfixes.md`) and the owner's report on `testing` HEAD `adb2218` ("stable - non functioning smart gun")
**Checked against:** `testing` HEAD: `init.lua`, `DetachedReticle.reds`, `src/Hooks/*.cpp`; the 2.5 dump in `reference/game-scripts/`; `docs/research/noted-issues.md`; round 7 §6.

## 0. Verdict

- **Owner decision (2026-11-03): smart weapons keep the chase, nothing else.** The 3D gun and hands still lag the camera, Tier 1 to Tier 2A, exactly as for other guns. Smart weapons get no Tier 2B, no gun reticle and no camera pip, and the vanilla smart crosshair stays at screen centre, untouched. Fully excluding smart weapons from the chase is **off the table**.
- **That is already the shape of iteration 36.** It turns off the gun reticle, the camera pip, Tier 2B and the ray hook, and leaves the mouse chase and the camera residual writes running (section 2). So the job is not to cut more out. It is to find which part of the chase, or which UI write, breaks the native smart system, and fix that part while keeping the chase.
- **New owner observation (2026-11-03), and it changes the target.** With a smart weapon out, the screen shows the **regular gun reticle**, not the square smart one. The smart crosshair is not "hidden" or "misplaced": it is **never there**, and a regular crosshair takes its place. Earlier attempts treated the regular reticle as correct and tried to re-add lock-on as a separate feature. That was the wrong target. The first goal is to get the vanilla smart crosshair spawned again (section 1b).
- **Nobody has found the root cause yet.** The repo has no log line, no probe result and no control test for smart weapons. Round 7's `[SMART]` probes and H1 to H3 tests were never run. Every attempt since then was a guess, and the reverted attempts were never written up as iterations. So we don't know what was tried or what it broke.
- **I have a likely explanation for why earlier fixes "brought back old bugs" (inferred).** If smart weapons are fully excluded from the chase, every swap from a smart weapon to a normal one re-activates the chase. That activation seeds pitch from `aimSys:GetCameraForward()` (`init.lua:419-437`). The smart branch has just zeroed that value (`DetachedReticle.reds:304`), so the seed is 0. That is the known pitch-seed failure (`noted-issues.md`: "Seeding the native pitch tracker from `aimSys:GetCameraForward()` fails…"), and it shows up as the roll after drawing a weapon. The same zero seed already happens today whenever the chase starts with a smart weapon drawn from holster. Fix F0 (section 4) applies whatever the bisection says.
- **Next step:** one bisection session with no code changes, plus one small probe (section 3). The result picks the fix. Please don't write another fix before that session.

---

## 1. How the vanilla smart crosshair works (verified in the dump)

- The crosshair is `CrosshairGameController_Smart_Rifl` (`cyberpunk/UI/weapons/crosshairs/crosshairController_Smart_Rifle.swift:2`). It draws **only what the engine publishes**. In `OnPreIntro` (`:105-108`) it registers `OnSmartGunParams` on `UI_ActiveWeaponData.SmartGunParams` (`core/blackboard/blackboardDefinitions.swift:1621`). Each update sizes `m_targetingFrame` and `m_reticleFrame` from `smartData.sight` (`:134-150`) and places one bracket per entry in `smartData.targets` (`ProcessData`, `:264-278`).
- The payload is native: `smartGunUIParameters` (`orphans.swift:56104`) carries `targets`, `sight` (`center`, `targetableRegionSize`, `reticleSize`, `orphans.swift:57708`), `crosshairPos` and `hasRequiredCyberware`. No script in the dump writes `SmartGunParams`. Target acquisition and locking are native and invisible to us. Scripts only see the result, plus `PlayerStateMachine.HasSmartGunLockedOnTarget` (`blackboardDefinitions.swift:184`, in `PlayerStateMachineDef`).
- If `SmartGunParams` never arrives, the frames are never sized and no brackets appear. **That one cause would produce both symptoms**, a missing crosshair and no lock-on. This is the main hypothesis (H-native). It is inferred, and the probe in section 3 confirms or rejects it.
- The root starts invisible: `gameuiCrosshairBaseGameController.OnInitialize` sets opacity 0 when the controller is not active (`crosshairBaseControllers.swift:58-63`). The intro animation then fades it to 1 (`crosshairController_Smart_Rifle.swift:301-311`). Visibility per stance comes from `OnState_*` (`crosshairBaseControllers.swift:229-263`). The smart controller overrides `OnState_Aim` without calling super, so it stays visible in ADS (`crosshairController_Smart_Rifle.swift:363`).
- Smart weapons need a Smart Link. The item stat is `ItemRequiresSmartLink` (`rpgManager.swift:2479-2484`), the player stat is `HasSmartLink` (`player.swift:3130`), and the UI shows "firmware offline" when `!hasRequiredCyberware` (`crosshairController_Smart_Rifle.swift:144-149`). What the native lock does without the cyberware is **unknown**. That makes the control test in section 3 mandatory: a character without a Smart Link would show this bug with the mod uninstalled too.
- **A free, independent observable:** the HUD weapon roster also listens to `SmartGunParams` (`cyberpunk/UI/weapons/weaponRoster.swift:250, 338-348`) and toggles its own "smart link firmware online/offline" badge. The mod never touches the roster. If that badge appears with a smart weapon out, the engine is publishing `SmartGunParams`, and the fault is in the crosshair UI.

## 1b. The regular reticle on a smart weapon: what picks the crosshair

- **The crosshair is chosen natively, from TweakDB.** Each item record has `Item_Record.Crosshair() -> Crosshair_Record` (`orphans.swift:15319` class, `:15331` method), and `Crosshair_Record` holds only `WidgetResourcePath()` (`orphans.swift:61940`). No script in the dump reads `Crosshair()`, `GetCrosshairRecord` or a `Crosshairs.*` ID, and no script swaps crosshairs. The container picks the active one through private natives (`crosshairContainerController.swift:102, 104`). So a regular reticle on a smart weapon means one of these (all inferred, ranked):
  1. **The weapon's `crosshair` flat points at a regular crosshair.** Possible causes: another installed mod (a TweakXL/REDmod tweak or an archive that edits crosshairs or smart weapons), or this particular weapon is meant to use one. The flat `<item>.ignoreSmartCrosshair` exists for that purpose (`weaponRoster.swift:725-727`).
  2. **The engine decides at spawn time that this weapon is not smart-enabled** and falls back to a regular crosshair, for example because of the Smart Link state (`HasSmartLink` / `ItemRequiresSmartLink`, section 1). Whether the engine does this is unknown: the smart controller has its own "firmware offline" visuals (`crosshairController_Smart_Rifle.swift:148`), which suggests it is designed to show without the link.
  3. **Something in this mod interferes with crosshair spawning.** The candidates are the four wraps on `gameuiCrosshairContainerController` (`DetachedReticle.reds:117-148`) and the extra canvas the mod adds to the container's root (`:202`), since the native container manages crosshair widgets under that root. The per-frame camera writes (section 2, rows a to c) are much less likely: the crosshair is picked when the weapon is equipped, not every frame.
- **The owner's theory, that lock-on comes from the reticle, can't be checked from scripts. It is the right working assumption.** On the script side, the smart controller only reads `SmartGunParams`. It never writes to a blackboard or to targeting (whole file read, `crosshairController_Smart_Rifle.swift`). But `gameuiCrosshairBaseGameController` is a native class (`crosshairBaseControllers.swift:2`), and whether the native smart handler only runs while a smart crosshair is active is unknown. Either way, the reticle and the lock most likely depend on the same upstream decision. Getting the square reticle back is the right first target, and lock-on should be retested only after that.
- **Cheap checks, in the CET console, smart weapon in hand, no code change:**
  - `TDBID.ToStringDEBUG(TweakDBInterface.GetItemRecord(ItemID.GetTDBID(GameObject.GetRightActiveWeapon(Game.GetPlayer()):GetItemID())):Crosshair():GetID())`, which is the crosshair record the engine should spawn (`GetItemRecord` `orphans.swift:13303`, `GetID` `:14322`). Compare it with a regular rifle's.
  - `TweakDB:GetFlat(<weapon TDBID> .. ".ignoreSmartCrosshair")` (CET API, not in the dump).
  - Write down which smart weapon (record ID) is being tested, and whether the square reticle shows on **other** smart weapons.
  - List every other mod that ships TweakDB edits or `r6/scripts` touching crosshairs, weapons or `Crosshairs.*` (`<GAME_ROOT>\r6\tweaks\`, `r6\scripts\`, `archive\pc\mod\`, `mods\`).

## 2. What the mod still does while a smart weapon is out (verified by reading)

| # | What | Where | Effect on smart |
|---|---|---|---|
| a | `isArmed` includes smart weapons, so the CET chase stays active | `init.lua:360, 375` | The puppet (A / T2B) lags the camera (T). The camera is held at T by rewriting `fpp` local orientation every frame (`init.lua:486`). Only Tier 2B is bypassed (`init.lua:654`). |
| b | The chase seed reads `aimSys:GetCameraForward()`, which the smart branch has zeroed | `init.lua:419-437`, `DetachedReticle.reds:303-305` | Drawing a smart weapon from holster always seeds pitch 0. Inferred: so would any future "exclude smart from chase" that re-activates on swap. |
| c | On every chase activation, raw writes to `fpp+0x3F6` (headingLocked) and `+0x498/+0x49C` (sensitivity) | `InputHook.cpp:291-325`, called from `init.lua:442-448` | The offsets can't be checked against the dump. This runs for every weapon. Listed only so the bisection covers it. |
| d | The reds tick forces `activeWidget.SetVisible(true)` 60 times a second | `DetachedReticle.reds:300` | This overrides vanilla hiding in Safe, Sprint, Reload, Scanning and GrenadeCharging (`crosshairBaseControllers.swift:237-263`). It is a real regression, but it shows the crosshair, it doesn't hide it, so it doesn't explain "missing". |
| e | The ray hook is installed at load, but gated off for smart weapons | `ShootingHook.cpp:206, 271`, `DetachedReticle.reds:306, 478-479` | Effectively inert for smart weapons. Round 7's H2 no longer applies. |
| f | The HMG tweak and the `GetDesiredAttackRecord` wrap | `hmg_attack.yaml`, `DetachedReticle.reds:529-533, 537-547` | They only fire on `IsHeavyWeapon()` (`weapon.swift:241`) or `Wea_HeavyMachineGun`. Not smart weapons. |

So the only mod paths that still differ from vanilla for a smart weapon are (a) to (d), plus the two load-time code patches.

## 3. One test session: probe + bisection

### 3.1 Probe (small reds + Lua change, logging only)

`FTLog` does not reach disk at runtime (`noted-issues.md`). Bridge the probe through `DetachedAimSystem` the same way the ballistics record already works (`init.lua:785-807`):

- `@addField(DetachedAimSystem)` counters: `m_smartCalls: Int32`, `m_smartTargets: Int32`, `m_smartLocked: Int32`, `m_smartHasLink: Bool`, `m_smartRegion: Vector2`, `m_smartRootVis: Bool`, `m_smartRootOpacity: Float`, `m_smartPreIntro: Int32`.
- `@wrapMethod(CrosshairGameController_Smart_Rifl) protected cb func OnSmartGunParams(argParams: Variant) -> Bool`: call `wrappedMethod(argParams)` first, then increment `m_smartCalls` and copy `ArraySize(data.targets)`, the number of targets with `Equals(state, gamesmartGunTargetState.Locked)`, `hasRequiredCyberware`, `sight.targetableRegionSize`, `this.m_rootWidget.IsVisible()` (`abstractWidgets.swift:36`) and `GetOpacity()` (`:157`). Keep the `-> Bool` return (`noted-issues.md`, cb wraps).
- `@wrapMethod(CrosshairGameController_Smart_Rifl) protected cb func OnPreIntro() -> Bool`: increment `m_smartPreIntro`. This tells whether the controller was ever activated.
- In the smart branch of `UpdateDetachedAim` (`DetachedReticle.reds:297`), store the active crosshair's identity in `DetachedAimSystem` as two `String` fields: `NameToString(this.GetActiveCrosshairGameController().GetClassName())` (the same call the `[DYNAMICS]` telemetry already compiles with, `:463-464`) and `NameToString(activeWidget.GetName())`. Also store the expected record, `TDBID.ToStringDEBUG(TweakDBInterface.GetItemRecord(ItemID.GetTDBID(weapon.GetItemID())).Crosshair().GetID())`. This answers section 1b directly. A smart weapon should report `CrosshairGameController_Smart_Rifl` (or a subclass). Given the owner's report, expect a regular controller class and `preIntro=0`.
- In `init.lua`, every 30 frames while a smart weapon is out, log:
  `[SMART] ctrl=<class> widget=<name> xhairRecord=<id> calls=<delta since last line> preIntro=<n> targets=<n> locked=<n> hasLink=<b> region=(x,y) rootVis=<b> rootOpacity=<f> psmLocked=<HasSmartGunLockedOnTarget> playerSmartLink=<GetStatValue(player, HasSmartLink)> chase=<DetachedReticle.chaseActive>`

Reading the probe:
- `calls=0` with `preIntro>0` → the engine isn't publishing (H-native).
- `calls=0` with `preIntro=0` → the smart crosshair controller never activated. This is the expected result given the owner's report. `ctrl` and `xhairRecord` then tell whether the engine was told to spawn a regular crosshair (the record is wrong: another mod or the weapon itself), or was told to spawn a smart one and spawned something else (spawning failed: this mod or the engine). See section 1b.
- `calls>0` and `targets>0` but nothing on screen → UI problem: check `rootVis` and `rootOpacity`.
- `calls>0`, `targets>0`, `locked=0` while an enemy sits in the box for 2 s → the lock itself fails. Compare `psmLocked`.

### 3.2 Bisection (no code changes between steps; same save, same smart weapon, same enemy)

"Works" means: **the square smart reticle is on screen** after drawing the weapon (re-draw it at each step, because the crosshair is picked at equip time), then lock-on is checked on an enemy. Section 1b makes steps 3 and 4 the likeliest places for it to come back; steps 2 and 2b are kept because they are cheap.

| Step | Configuration | If smart works here |
|---|---|---|
| 0 | CET console: player `HasSmartLink` stat, the section 1b crosshair-record check, the weapon roster badge; try a second smart weapon | — (if `HasSmartLink = 0` or the record already points at a regular crosshair, do step 4 first) |
| 1 | Everything installed (baseline) | — (should reproduce) |
| 2 | ImGui "Enable Decoupled Aim" **off** (`Config.enabled = false`: no chase, no `fpp` writes, no T2B) | Cause is the chase / camera path, rows (a) to (c) → do step 2b |
| 2b | Enabled again, but in `config.json` set `catchUpSpeed: 1000` and `maxDivergence: 0.5` (both loaded unclamped, `init.lua:104, 106`; the native clamp only needs `s_maxDiv > 0`, `InputHook.cpp:192`). Every chase code path still runs, but A ≈ T, so there is almost no lag | Works here → the **lag itself** breaks smart targeting → **F1-lag**. Still broken → the **writes themselves** break it, whatever the lag → **F1-write** |
| 3 | Step 2 + move `r6/scripts/DetachedReticle/` out of the game folder | Cause is the reds UI: row (d), the container wraps, or the added canvas → fix **F2**, then **F3** if F2 alone doesn't bring the square back |
| 4 | Everything removed (DLL, reds, tweak, CET mod) | Cause is a load-time patch or the tweak; next split: remove only `hmg_attack.yaml`, then only the DLL |
| — | Still broken at step 4 | Not this mod: the save (Smart Link) or another mod. List other mods that wrap crosshair or weapon classes in `<GAME_ROOT>\r6\scripts\` |

Step 3 note: with the reds folder removed, `aimSys` is nil, and every `init.lua` access is already inside `pcall`, so CET stays alive. Keep `Config.enabled = false` for that step anyway, so there is only one variable.

Put the probe numbers for steps 1 to 3 in the iteration entry (the probe disappears at steps 3 and 4, which is expected).

## 4. Fixes, one per bisection outcome

All fixes keep the owner's design: chase on for smart weapons, T2B off, vanilla crosshair at centre.

**F0, ship it in every case:** seed the chase pitch from the rendered camera, not from `aimSys`. Use `Game.GetCameraSystem():GetActiveCameraForward()` (`orphans.swift:27952`). `init.lua:505` already reads it for the P1 probe. Replace the `aimSys:GetCameraForward()` block at `init.lua:419-434` with that read, using the same `atan2(z, xy)`. Pass criterion: `[SEED] pitchErr` within ±0.2° right after (i) drawing from holster, and (ii) a smart → normal swap. This is main's iteration 39/40 lesson (round 8 §4). It was never ported to `testing`.

Also, in the smart branch, stop zeroing `aimSys` (`DetachedReticle.reds:303-305`). Pass the real `camFwd3` and `isDetached = false`, so any consumer that reads the camera forward gets a valid vector. With F0 in place, nothing depends on this any more, but a zero vector there has already caused one bug.

**F1-lag, step 2b works (the lag is what breaks it).** Inferred meaning: the native smart system aims from the body/weapon (A), while the camera and the centred crosshair are at T. Script cannot move the native lock cone; no script symbol in the dump reaches it (section 1). What we can do while keeping the owner's design:
1. Read the probe while swinging and while settled. If locks work once settled (`calls>0`, `locked>0`) and only fail mid-swing, that is round 7's H3. It is consistent with the design ("the gun locks what the gun points at"), and it is bounded by the lag. Then the only change is a **faster catch-up for smart weapons**: a separate `smartCatchUpSpeed` passed to `DR_SetSmoothing` while a smart weapon is out (`init.lua:438`). Tune it in game until locks feel vanilla during normal aiming. The crosshair stays centred as the owner wants. The drawn targeting box can differ from the real lock box only during fast swings.
2. If nothing locks even once fully settled (residual ≈ 0), the lag explanation does not hold, because settled A = T. Treat it as F1-write.
3. Making the native lock cone follow the camera instead of the body would need reverse-engineering the native smart targeting (RED4ext). Feasibility unknown. Only open that if the owner finds the lag in item 1 unacceptable.

**F1-write, step 2b still broken (the writes break it, whatever the lag).** Split the chase path once more, one variable per run, with temporary debug flags in `init.lua` (off by default, removed afterwards):
- `dbgSkipRawFppWrites`: skip `DR_SetHeadingLocked` and `DR_SetSensitivityMult` (`init.lua:442-448`), i.e. the raw `fpp+0x3F6/+0x498/+0x49C` writes (`InputHook.cpp:291-325`). Those offsets cannot be checked against the dump.
- `dbgSkipFppTransform`: skip `fpp:SetLocalTransform` (`init.lua:486`) while a smart weapon is out. With 2b's near-zero lag, the camera barely moves without it, so this run is safe to play.
Whichever flag restores smart targeting is the cause. If it is the raw writes, verify the field offsets on 2.5 (WolvenKit/RTTI dump of `gameFPPCameraComponent`) before changing anything. If it is the transform write, report it before designing a fix: the residual is how the chase keeps the camera at T, so that one needs a design discussion, not a quick patch.

**F2, reds UI is the cause:** in the smart branch (`DetachedReticle.reds:297-308`), stop touching the vanilla widget. Drop `activeWidget.SetVisible(true)` and call `SetTranslation(0, 0)` only once, on the transition into smart (an `@addField` bool), not every tick. If that is not enough, also skip `UpdateDetachedAim` in the `OnWeaponSwap` wrap (`:141`) when the new weapon is smart. Row (d)'s Safe/Sprint/Reload regression is fixed either way. Do the `SetVisible(true)` removal whatever the bisection says: "vanilla crosshair" means the vanilla `OnState_*` hiding must work too.

**F3, step 3 brings the square back but F2 doesn't.** Split the reds container changes, one per run: (i) don't add the `CameraCrosshairFreelookCenter` canvas to the container root (`DetachedReticle.reds:202`); attach it to a separate HUD layer instead, or skip creating it while testing. (ii) Remove the `UpdateDetachedAim` call from the `OnWeaponSwap` wrap (`:141`) and leave the swap to the tick. (iii) Remove the `OnPlayerAttach` wrap's tick restart (`:123-131`). Keep whichever change restores the smart crosshair, and record the others as "no effect".

**F4, the square is missing even at step 4 (mod fully removed).** This mod is not the cause. Check the crosshair record (section 1b) and the other mods, and confirm that the character has a Smart Link. Report back before changing anything in this repo.

**Not an option any more:** treating smart weapons as unarmed for the chase (round 9's first draft, F1). The owner wants the gun and hands decoupled for smart weapons too.

## 5. Process

- Every attempt goes in as an iteration, **including reverted ones** (`findings-bugfixes.md` rules: "Fixes for a wrong implementation in an iteration = next iteration"). The smart attempts after iteration 36 left no trace. Please backfill **iteration 37** with what was tried, what it fixed, and what regressed (camera roll? jitter? snap on swap?). Any proven failure goes in `noted-issues.md`. That record is what stops the next attempt from repeating them.
- Change one variable per iteration. F0 can ship together with F2 or a F1 fix, because it touches a different path (the activation seed). Record them as two numbered changes in one entry, with separate pass criteria.
