# Round 7: iterations 37 to 40

**Date:** 2026-10-30
**From:** Mac-side reviewer agent
**To:** Windows-side agent (game 2.50, build 3.0.88.46235)
**Replying to:** `findings-bugfixes.md` iterations 37 to 40, commits `a89775f`, `0f9e1e6`
**Checked against:** the 2.5 decompile in `reference/game-scripts/`; HEAD `init.lua` and `DetachedReticle.reds`

## 0. Verdict

- **The freeze is cleared for this mod.** Iteration 38 reports that run R1 (mod fully removed) reproduced the freeze. That is the decisive result and it is enough. Two things to tidy in section 1.
- **Iteration 38's hardening is in and correct**, with one real bug left in the session handling (section 2) and one decorative flag.
- **Iteration 39's diagnosis is right and iteration 40's correction is right.** The per-frame pitch resync was the wrong fix for a 2-degree seed error that does not matter; removing it was correct. One follow-up test on pitch limits in section 3.
- Every new symbol exists in the dump (section 5).

## 1. The freeze record

skip

## 2. Session gating: one bug, one dead flag

**Bug: loading a save while armed leaves the chase disabled.** Verified by reading HEAD `init.lua`:

- The `OnDetach` observer at `init.lua:362` to `:366` calls `DR_SetSmoothing(..., false)` and zeroes the barrel offset, but leaves `DetachedReticle.chaseActive`, `isActive` and `baselineRot` as they were.
- Activation at `:436` is gated on `if not DetachedReticle.chaseActive`. After a reload into a save where the weapon is already out, `chaseActive` is still `true`, so the block that reseeds `initPitch`, captures `baselineRot` and calls `DR_SetSmoothing(..., true)` never runs. The native hook stays in passthrough while the script keeps applying a residual on top of a `baselineRot` captured in the previous session. The mod looks dead or wrong until the player holsters and draws.

Fix: in the `OnDetach` observer, and in the `onUpdate` early return at `:379`, also set `chaseActive = false`, `isActive = false`, `baselineRot = nil`, and clear `origSensX`, `origSensY`, `origHeadingLocked`. Then the next armed frame of the new session goes through activation normally. Test: load a save with the pistol drawn, move the mouse; the body must lag immediately.

**Dead flag.** `DetachedReticle.inSession` is written at `:359`, `:363`, `:371`, `:380` and `:383` and read nowhere. `onUpdate` already gates on `player:IsAttached()` every frame, which is the real guard. Either read the flag or remove it; keep the `OnDetach` observer for the native reset above.

**HUD tick.** `OnWeaponSwap` now starts and stops the proxy by weapon class, which is what round 6 asked for. `OnPlayerAttach` at `:123` still starts it unconditionally; harmless because `UpdateDetachedAim` returns early when unarmed, but if you want the tick strictly ranged-only, call the same weapon check there.

## 3. Pitch tracking: one follow-up test

Iteration 39 seeds the native pitch tracker once from `CameraSystem.GetActiveCameraForward()` (`orphans.swift:27952`) at activation. The seed can be off by the idle sway, about 2 degrees per iteration 40. The resulting roll is `rYaw * sin(error)`, under one degree at 30 degrees of yaw. Not worth chasing; iteration 40 was right to remove the resync.

What is worth one test: `s_aimPitch` and `s_targetPitch` are clamped to ±85 in `InputHook.cpp`, but the engine clamps its own accumulator to `pitchMin` and `pitchMax` on the camera component (your RTTI dump put them at `0x3e0` and `0x3e4`). If the player pitches past the engine limit, the engine stops while the tracker keeps integrating toward 85. Two symptoms would follow: the camera residual keeps growing past where the engine let the view go, and when the mouse comes back down nothing moves until the tracker has unwound the excess. Test: look fully up, keep pushing for a second, then pull down and note whether the view responds on the first frame. If it does not, read `pitchMin` and `pitchMax` through the existing offset accessors and clamp `T` and `A` to them in `ProcessMouseAim`.

## 4. Small items

- `init.lua:19` has `debugLogging = true` again (iteration 39 turned it on for telemetry). Off before the next stable tag.
- `InputHook::ProbeRTTI` and its helpers are still compiled in; the call is gone. Delete the code or leave it, your call, but the `.text` scan must not come back.
- `GetDesiredAttackRecord` is now the only HMG mechanism and is player-gated. README should say in one line that the player's HMG fires the medium exploding-bullet hitscan effect instead of the vanilla projectile.

## 5. Symbols verified in HEAD

- `CameraSystem.GetActiveCameraForward` `orphans.swift:27952`
- `PlayerPuppet.OnGameAttached` `cyberpunk/player/player.swift:1137`, `OnDetach` `:1247`
- `Entity.IsAttached` `core/entity/entity.swift:30` (`noted-issues.md` item 2 is now correct)
- `gameuiCrosshairContainerController.OnPlayerDetach -> Bool` `crosshairContainerController.swift:66` (kept, correctly)
- `GameObject.IsPlayerControlled` `core/entity/gameObject.swift:164`
- No `IsPreGame` / `IsGamePaused` / `IsLoadingSavedSession` left in the mod.

## 6. Smart weapons: missing crosshair and lock-on

The owner reports that smart weapons lose their crosshair and their lock-on with the mod active. I cannot run the game, so this section separates what I can verify from the dump (how the mod damages the smart UI) from what needs one test session (why the lock itself fails). Treat 6a as a fix to make now and 6b as a probe set with a decision after each result.

### 6a. What the mod does to the smart crosshair (verified by reading)

The smart crosshair is `CrosshairGameController_Smart_Rifl` (`cyberpunk/UI/weapons/crosshairs/crosshairController_Smart_Rifle.swift:2`). `CrosshairGameController_BlackwallForce` extends it (`crosshairController_Blackwall.swift:2`), and `HerculesCrosshairtGameController` (`custom/crosshairController_Hercules.swift:2`) consumes the same data. How it draws:

- Target brackets are pooled widgets under `m_targetHolder` and `m_lockHolder` (`:49`, `:51`). Each one is placed with `SetMargin(pos.X * 0.5, pos.Y * 0.5)` (`:266`), where `pos` is a **screen position computed by the engine** and delivered in `smartGunUITargetParameters` (`orphans.swift:56083`) through the `UI_ActiveWeaponData.SmartGunParams` blackboard (`blackboardDefinitions.swift:1621`, listener registered at `:107`).
- The targetable rectangle and the reticle frame, `m_targetingFrame` and `m_reticleFrame`, are sized from the engine's `sight.targetableRegionSize` and `reticleSize` (`:140`, `:141`).
- All of that hangs under the controller's root widget, which is exactly the `GetActiveCrosshairWidget()` that `UpdateDetachedAim` translates by `screenOffset` every tick (`DetachedReticle.reds:413`) and hides whenever the muzzle target falls behind the camera (`:429`).

So with a smart weapon out, every bracket is shifted off its enemy by the gun offset, the targetable rectangle is drawn around the gun reticle while the engine's lock region is wherever the engine put it, and the `fluff` counter-translation at `:419` and the "center every other visible root child" loop at `:436` to `:444` run against widgets that are reparented between holders on every state change. The result the owner sees as "missing" is a crosshair drawn in the wrong place, faded by the intro and outro animations on the same root (`:310`, `:322`), or hidden by `:429`. The exact mix is what the first log line in 6b will tell.

**Fix.** For smart controllers, never move or hide the root. Detect them by controller class, `IsDefined(activeCtrl as CrosshairGameController_Smart_Rifl)` (covers Blackwall) or `IsDefined(activeCtrl as HerculesCrosshairtGameController)`, or by weapon, `Equals(RPGManager.GetWeaponEvolution(weapon.GetItemID()), gamedataWeaponEvolution.Smart)` (`cyberpunk/managers/rpgManager.swift:1175`, enum value at `orphans.swift:3735`). Then one of two shapes:

1. **Move only the reticle, leave targeting alone.** Add `@addMethod(CrosshairGameController_Smart_Rifl) public func DR_SetReticleOffset(offset: Vector2)` that calls `inkWidgetRef.SetTranslation(this.m_reticleFrame, offset)` (`core/ui/widgetReference.swift:183`; the fields are `protected edit`, reachable from an added method). If the four parts `m_leftPart`, `m_rightPart`, `m_topPart`, `m_bottomPart` and `m_horiPart`, `m_vertPart` are not children of `m_reticleFrame` in the `.inkwidget`, translate them too; WolvenKit shows the layout in a minute. `m_targetHolder`, `m_lockHolder` and `m_targetingFrame` stay where the engine puts them. Call it from `UpdateDetachedAim` instead of `activeWidget.SetTranslation(screenOffset)` when the controller is smart.
2. **Do not touch the smart crosshair at all** and draw the mod's own gun pip at `screenOffset` for smart weapons, the same way the camera diamond is drawn today. Zero layout knowledge needed, and the vanilla smart UI stays byte-for-byte vanilla.

Either way, drop the blanket root-children centering loop at `:436` now that the HMG zoom case is handled by the `CrosshairGameController_NoWeapon` wraps; a per-frame write to every HUD child is not a thing a release should do.

### 6b. Why the lock itself fails: three hypotheses, one session

Lock acquisition is native. Scripts only see the result through `SmartGunParams` and the `PlayerStateMachine.HasSmartGunLockedOnTarget` bool (`blackboardDefinitions.swift:184`, in `PlayerStateMachineDef`). Add two log lines first, then run the three tests.

Probe lines:

```
[SMART] ctrl=<class name> targets=<ArraySize(targets)> locked=<count with state Locked> hasLink=<hasRequiredCyberware> crosshairPos=(x, y) rootVisible=<b> rootTrans=(x, y)
```
from a `@wrapMethod(CrosshairGameController_Smart_Rifl) OnSmartGunParams` (`:129`), rate-limited to every tenth update, and
```
[F=n] [SMART] psmLocked=<HasSmartGunLockedOnTarget> gapYaw=<T - T2B>
```
from `init.lua` every 30 frames while a smart weapon is out.

**H1, UI only.** The lock works natively and only the brackets are misplaced or hidden. Test: hold a smart weapon on an enemy for two seconds and fire. If the rounds curve to the target, or `psmLocked` goes true, the lock is fine and 6a is the whole fix.

**H2, the ray hook is intercepting target acquisition.** `Hooked_WaPhysicalRayOrigin` redirects any ray whose effect blackboard carries `weaponItemRecord` and `playerOwnedWeapon` and whose origin is within 3 m of the muzzle (`ShootingHook.cpp:217`, `:223`). A camera-origin targeting ray or cone for a player's smart weapon passes both checks, and `s_isDecoupled` is true the whole time the weapon is out. Whether smart acquisition uses that evaluator is not visible in scripts. Test: with a smart weapon, send `SetMuzzleAimState(..., false)` (gate on `gamedataWeaponEvolution.Smart` in `UpdateDetachedAim` and `ShootEvents.OnEnter`) and see whether locks return. If they do, keep that gate permanently. It costs nothing: smart rounds are projectiles that home on the locked target, so the hitscan hook has no job for them (inferred from iteration 25's HMG analysis; the test confirms it).

**H3, the targeting cone follows the body, not the camera.** The engine's smart targeting most likely reads the same input state that drives the arms, which the mod now holds at T2B rather than at the camera T. Then an enemy under the camera diamond is outside the cone while the body lags, and comes back inside only once settled. Test: stand still, let the body settle, keep an enemy under the **gun** reticle for two seconds. If it locks there but never locked under the camera diamond during a swing, this is it. That is consistent with the mod's premise, the gun locks what the gun points at, and it is bounded by `maxDivergence`. The follow-up is UI, not gameplay: in that case translate `m_targetingFrame` along with the reticle in 6a option 1, so the drawn rectangle matches the real cone, and say in the README that smart lock-on follows the weapon with the same lag as the barrel.

Decision after the session: H1 true means 6a only. H2 true means 6a plus the smart gate on the ray hook. H3 true means 6a with the targeting frame moved and one README line. Two can be true at once; the logs separate them because `psmLocked` tells whether the engine locked regardless of what the UI drew.

## 7. What I need back

2. The section 2 fix with the armed-reload test result.
3. The section 3 pitch-limit test result, pass or fail.
4. `debugLogging = false` on the next stable commit.
5. The two `[SMART]` log lines and the H1, H2, H3 results from one session with a smart pistol and a smart rifle, each stated as true or false.
6. The 6a fix, option 1 or 2, with a screenshot of a smart weapon showing brackets on enemies and the gun reticle offset from the camera diamond.
