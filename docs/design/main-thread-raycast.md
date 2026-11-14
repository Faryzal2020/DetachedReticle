# Main-Thread Raycast Separation (Draft)

- **Status:** Draft — awaiting owner approval (no code edited yet).
- **Date:** 2026-11-12
- **Game build:** 2.50 (Build 3.0.88.46235)
- **Triggering evidence:** Two PhysX crashes back-to-back in Dogtown (`q301_q302_rescue_myers`):
  1. `2026-11-12 05:37:09` (`20261112-053709-crash-tid133688-01.txt`) — `redDispatcher12` (TID `133688`, main thread `137568`), single-weapon `Items.Preset_Borg4a_Legendary`:
     `OnDetachedReticleTick` -> `UpdateDetachedAim` -> `SyncRaycastByCollisionPreset` -> `PhysX3_x64.dll +0xD8959` (`physx::Sq::AABBPruner::updateObjectsAfterManualBoundsUpdates+0x79`, reading `[RAX+RCX*4]` at `0x2535F4A0DF0`, `RCX=0xD7D6B140`).
  2. `2026-11-12 06:21:54` (`20261112-062154-crash-tid139360-01.txt`) — `redDispatcher7` (TID `139360`, main thread `140936`), dual-wielding `Items.MicroMG_Crafting_Recipe_Legendary`:
     `OnDetachedReticleTick` -> `UpdateDetachedAim` -> `UpdateDualWieldAim` -> `SyncRaycastByCollisionPreset` -> `PhysX3_x64.dll +0xDDEDD` (`physx::Sq::AABBTree::refitMarkedNodes+0x12D` <- `AABBPruner::refitUpdatedAndRemoved` <- `AABBPruner::commit` <- `SceneQueryManager::flushUpdates`, reading `[RDI+RCX*8]` at `0x18022049CE8`, `RCX=0x2FFFFFFFD`).

---

## 1. Root Cause

1. **Worker-thread execution of UI animation callbacks (verified):**
   `StartDetachedReticleTick()` (`r6/scripts/DetachedReticle/DetachedReticle.reds:426-453`) loops an infinite 60 Hz `inkAnimTransparency` proxy and binds `OnDetachedReticleTick` to `inkanimEventType.OnStartLoop`. `ink::anim::Instance::FireCallbacks` executes inside `job::prv::DispatcherThread::DoWorkLoop` (`redDispatcher7` / `redDispatcher12`), off the main thread.
2. **PhysX scene-query flush inside `SyncRaycastByCollisionPreset` (verified):**
   `SpatialQueriesSystem::SyncRaycastByCollisionPreset` enters `physics::PhysXScene::SyncRaycast` -> `physx::NpSceneQueries::raycast` -> `physx::NpSceneQueries::multiQuery<PxRaycastHit>`, which calls `physx::Sq::SceneQueryManager::flushUpdates()` -> `AABBPruner::commit()` / `updateObjectsAfterManualBoundsUpdates` / `AABBTree::refitMarkedNodes`.
3. **Concurrent PhysX bounds mutation race (inferred):**
   Calling `SyncRaycastByCollisionPreset` every tick from an `inkAnim` worker job (`redDispatcher*`) flushes and refits PhysX's scene-query `AABBTree` / `AABBPruner` concurrently with main-thread / simulation updates adding, moving, and destroying bodies (especially heavy during `face_damaged_spidertank` / `destroy_all_drones`).

---

## 2. Current `SyncRaycastByCollisionPreset` Callsites

In `r6/scripts/DetachedReticle/DetachedReticle.reds`:

| Path | Lines | Execution Context |
|---|---|---|
| `UpdateDetachedAim` (ADS static/dynamic, hipfire static) | L633, L636, L653 | `OnDetachedReticleTick` -> **`redDispatcher*` worker thread** (crashed `05:37:09`) |
| `UpdateDualWieldAim` (Right & Left static/dynamic) | L932, L935, L987, L990 | `OnDetachedReticleTick` -> **`redDispatcher*` worker thread** (crashed `06:21:54`) |
| `ShootEvents.OnEnter` (Dual L1106/1109, ADS L1154/1157, `RecordShot` debug raycast L1190) | L1106, L1109, L1154, L1157, L1190 | Weapon state-machine transition (thread `unknown`) |

---

## 3. Proposed Design: Main-Thread Aim & Raycast, UI-Only Reticle Projection

Split world/PhysX calculation cleanly from `inkWidget` projection without adding any new native hooks or modifying `DetachedReticle.dll`.

### 3.1 Main-thread driver (`init.lua` -> `DetachedAimSystem`)

CET's `registerForEvent("onUpdate", ...)` (`bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua:850`) runs on `CRunningState::OnTick` on the **Main Thread** (confirmed in `cyber_engine_tweaks.log`: `Main thread function CRunningState::OnTick hook complete!`). `onUpdate` already resolves `DetachedReticle.DetachedAimSystem` every frame (L1320, L1783).

Add a single main-thread entry point on `DetachedAimSystem` in `DetachedReticle.reds`:

- `public func UpdateWorldAim(player: ref<PlayerPuppet>, dt: Float) -> Void`
- Called once per frame from `init.lua` `onUpdate` when `player` is defined (before Tier 2B / telemetry reads, or right after `SetAdsRecoilHoriMult` / `SetDualStabilizeWeight` are pushed).
- Guard inside `UpdateWorldAim` / `init.lua` against pause/overlay if `delta <= 0.0` (while keeping `dt` clamped to `[0.0001, 0.2]` fallback `1/60`, matching existing behavior).

Inside `DetachedAimSystem.UpdateWorldAim(player, dt)` (running on **Main Thread**):

1. Handle unarmed / melee / smart-weapon passthrough state resets and call `SetMuzzleAimState(...)`.
2. For regular weapons (single-hand):
   - Read `CameraSystem.GetActiveCameraWorldTransform`, `weapon.GetMuzzleSlotWorldTransform()`, `PlayerStateMachine` ADS flags, and `DR_GetRecoilYaw()`.
   - Run the ADS `World Static` + `World Dynamic` or hipfire/HMG `World Static` `SyncRaycastByCollisionPreset` calls here on the Main Thread.
   - Pass `staticOnly = true` on `n"World Static"` calls (`SyncRaycastByCollisionPreset(start, end, n"World Static", trace, true)`).
   - Store world aim results on `DetachedAimSystem`: `m_gunForward`, `m_targetPoint`, `m_muzzlePos`, `m_cameraPos`, `m_cameraForward`, `m_muzzleRelCam`, `m_angleLagDeg`, `m_yawLagDeg`, `m_pitchLagDeg`, `m_isDetachedActive`.
   - Call `SetMuzzleAimState(muzzlePos, aimFwd, camFwd3, true)`.
3. For dual-wielding (`GameObject.IsDualWielding(player)`):
   - Measure Right & Left barrel transforms, call `UpdateDualBaseOffsets(...)` once per main-thread tick (instead of on the UI callback thread).
   - Run Right and Left `World Static` (`staticOnly = true`) + `World Dynamic` `SyncRaycastByCollisionPreset` calls here on the Main Thread.
   - Store both hands' results on `DetachedAimSystem`:
     - Right: via `SetAimState(...)` (`m_targetPoint` = `rightTargetPt`, `m_gunForward` = `rightAimFwd`, `m_muzzlePos` = `rightMuzzlePos`, `m_angleLagDeg` = `rAngleDeg`, `m_yawLagDeg` = `rEffYaw`, `m_pitchLagDeg` = `rEffPitch`)
     - Left: add `m_leftTargetPoint` alongside `m_leftGunForward`, `m_leftMuzzlePos`.

### 3.2 Worker-thread UI callback (`OnDetachedReticleTick` -> Projection & Widgets Only)

In `gameuiCrosshairContainerController`:

- **Remove all `SpatialQueriesSystem` / `SyncRaycastByCollisionPreset` calls** from `UpdateDetachedAim()` and `UpdateDualWieldAim()`.
- **Remove** `UpdateDualBaseOffsets(...)`, `SetMuzzleAimState(...)`, and `OnWeaponSwap`'s synchronous `UpdateDetachedAim()` world-raycast side effects.
- Have `OnDetachedReticleTick` (`UpdateDetachedAim` / `UpdateDualWieldAim`) act purely as a **HUD projection step**:
  - Read `aimSys.IsDetachedActive()`, `aimSys.GetTargetPoint()`, `aimSys.GetMuzzlePos()`, `aimSys.GetCameraForward()` (and `aimSys.GetLeftTargetPoint()` when dual-wielding).
  - Run `this.ProjectWorldToScreen(...)` (which is an `inkHUDGameController` method) to position `activeWidget` (+ `fluff` counter-translation), `m_cameraCrosshair`, and `m_leftCrosshair`.
  - Write back only `m_screenOffset` / `m_muzzleScreen` / `m_leftScreenOffset` to `DetachedAimSystem` for `init.lua`'s Tier 2B screen trim (`scrX`, `scrY`) and logging.

### 3.3 `ShootEvents.OnEnter` Convergence & Telemetry Raycasts

Because `ShootEvents.OnEnter` fires on weapon fire transitions (exact worker vs. main-thread affinity unverified):

- **Option A (Recommended — Zero off-tick raycasts anywhere):**
  In `ShootEvents.OnEnter`, instead of calling `SyncRaycastByCollisionPreset` (L1106/1109, L1154/1157, L1190), read the latest Main-Thread world hit point from `DetachedAimSystem` (`aimSys.GetTargetPoint()` for right/single hand, `aimSys.GetLeftTargetPoint()` for left hand). Re-compute convergence from the live fire-instant muzzle (`Vector4.Normalize(cachedTargetPt - liveMuzzlePos)`), fall back to `effGunFwd` if dot <= 0.2 or cached point is invalid, and pass `cachedTargetPt` to `aimSys.RecordShot(...)` (eliminating L1190's redundant debug trace completely).
- **Option B (Conservative fallback):**
  Keep `ShootEvents.OnEnter` convergence traces only if live mouse-flick divergence between `onUpdate` and shot frame matters empirically, while still removing L1190's `RecordShot` debug raycast. (Less preferred until `ShootEvents.OnEnter` thread affinity is known, since if it runs on `redDispatcher*`, it shares the same PhysX race risk.)

---

## 4. Files Touched (When Approved)

| File | Summary of changes |
|---|---|
| `r6/scripts/DetachedReticle/DetachedReticle.reds` | Add `m_leftTargetPoint` + `UpdateWorldAim(player, dt)` to `DetachedAimSystem`; move all `SyncRaycastByCollisionPreset` calls (and `UpdateDualBaseOffsets` / `SetMuzzleAimState`) out of `gameuiCrosshairContainerController` into `UpdateWorldAim`; pass `staticOnly = true` for `World Static`; simplify `OnDetachedReticleTick` to projection + `inkWidget` updates; reuse cached `targetPoint`/`leftTargetPoint` in `ShootEvents.OnEnter` (Option A). |
| `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua` | Call `aimSys:UpdateWorldAim(player, delta)` on the Main Thread inside `onUpdate` before reading lag/screen offsets and computing Tier 2B. |
| `src/` / `DetachedReticle.dll` | **No changes required.** |

---

## 5. Verification Plan

1. Verify compilation with zero redscript errors in `<GAME_ROOT>\r6\logs\redscript_rCURRENT.log`.
2. Verify core MVP invariants in `DetachedReticle.log` (`Decoupled Aim ACTIVE`, non-zero `rYaw`, `BALLISTICS RECORD` trajectory matches reticle).
3. Stress-test the exact crash reproducer (`q301_q302_rescue_myers` — Chimera boss fight + `destroy_all_drones`) with both single weapon (`Preset_Borg4a_Legendary`) and dual-wielding (`MicroMG_Crafting_Recipe_Legendary`), confirming zero `PhysX3_x64.dll` / `SyncRaycastByCollisionPreset` faults.
4. Regression-check regular hipfire, ADS convergence, HMG, LMG, melee/unarmed/smart passthrough, and dual-wielding T3 stabilization + per-hand ballistics.

