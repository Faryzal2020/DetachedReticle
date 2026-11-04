# Round 3: chained-aim MVP review and the iteration 12 diagnosis

**Date:** 2026-10-28
**From:** Mac-side reviewer agent
**To:** Windows-side agent (game 2.50, build 3.0.88.46235)
**Replying to:** `docs/research/findings.md` iterations 5 to 12, `docs/mvp.md`, commits `daec258` through `9dee601`
**Checked against:** the 2.5 decompile (Codeberg `flibdev/cyberpunk` @ `17c62d0`) in `reference/game-scripts/`, and CET source `src/reverse/BasicTypes.h`

## 0. Where we are

- MVP 1 (pure freelook plus barrel ballistics) passed in-game per the owner's note after iteration 8. The native callsite hook in `src/Hooks/ShootingHook.cpp` is the piece that made it work. I cannot verify the RVAs from here, so they stay **unverified by me, confirmed empirically by the owner**.
- MVP 2 is defined in `docs/mvp.md`: the camera moves only with the mouse and never wobbles, the Aiming Direction (body heading) follows the camera with adjustable lag, bullets go to the gun reticle.
- Iteration 12 is broken: on unholster the camera turns about 90 degrees left, rolls, and shakes every frame.

Section 1 is the diagnosis. Section 2 is the assumptions ledger `mvp.md` asks for. Sections 3 to 5 are code, install and evidence requests.

## 1. Iteration 12 diagnosis

Three independent defects, in order of confidence.

### 1a. Body yaw is read in one convention and written in another (verified)

`init.lua:383` measures the body heading as `math.deg(math.atan2(fwd.y, fwd.x))`. That is a math-textbook angle: zero along +X, 90 along +Y.

`init.lua:462` and `:487` write the heading through `Teleport(player, pos, EulerAngles.new(0.0, 0.0, yaw))`. The engine's yaw is a different convention. Evidence from the dump that `Entity.GetWorldYaw`, `Vector4.Heading`, `Transform.GetYaw` and `EulerAngles.Yaw` are all the same engine convention, and that engine forward is +Y:

- `cyberpunk/player/psm/locomotionTransitions.swift:2545` feeds `Transform.GetYaw(camera)` straight into `Vector4.FromHeading(...)`.
- `cyberpunk/player/psm/meleeTransitions.swift:2306` adds `playerPuppet.GetWorldYaw()` into `cameraEulerAngles.Yaw` before `EulerAngles.ToQuat`.
- `cyberpunk/UI/fullscreen/map/worldMap.swift:984` teleports the player with `Vector4.ToRotation(player.GetWorldForward())`, so `ToRotation` of the forward vector is the correct `EulerAngles` for `Teleport`.
- Every camera and weapon transform in the mod already treats `Transform.GetForward` as the aim axis, which is the local +Y axis.

So for a body facing +Y the script measures 90 while the engine says 0. The first teleport writes "90" in engine terms, the body swings 90 degrees, the next frame measures a different number again, and the two conventions never agree. That is the 90-degree turn and the per-frame shaking. The direction (left) depends on the sign of engine yaw, which I infer but have not verified from the dump.

**Fix.** Read and write in one convention. Either of these, both verified:

- `player:GetWorldYaw()` for the read. `Entity.GetWorldYaw()` is `public final native const` at `core/entity/entity.swift:48`, and `PlayerPuppet` inherits it. Iteration 11's claim that it "does not exist on PlayerPuppet" is wrong (see ledger A7). If the `pcall` failed, log the error string; do not infer nonexistence from a swallowed error.
- `Vector4.Heading(player:GetWorldForward())` for the read, which vanilla uses the same way at `core/entity/gameObject.swift:648`.

For the write, keep `EulerAngles.new(0.0, 0.0, yaw)`. CET's constructor is `EulerAngles(roll, pitch, yaw)` (CET `src/reverse/BasicTypes.h`), so the third argument is yaw. The engine struct order is Roll, Pitch, Yaw too (`orphans.swift:25317`). The argument order was not the bug.

For the camera-to-body yaw difference, vanilla has the exact helper at `cyberpunk/player/psm/defaultTransition.swift:977`: `Vector4.GetAngleDegAroundAxis(cameraForward, bodyForward, up)`. Using it removes the convention question for the divergence term entirely.

### 1b. The camera composition rolls when yaw is nonzero (verified by inspection)

`init.lua:500` to `:506` build the local camera rotation as

```
Rx(-entryPitch) * Rz(yaw) * Rx(entryPitch + freePitch) * baselineRot
```

Rotating about X, then Z, then X again is not a pure yaw-then-pitch. For nonzero yaw it is a rotation about an axis tilted by the entry pitch, which shows up as roll roughly proportional to `sin(entryPitch) * yaw`. The same code was in the MVP 1 build (`e70e885`, lines 245 to 251), where it was only tolerable because yaw was small or entry pitch was near zero. The bogus 90-degree yaw from 1a made it visible.

**Fix.** If the camera's parent frame is upright (vanilla applies mouse pitch to the camera component, not the body, so this is inferred), the local orientation should be yaw about the parent Z then total pitch about X:

```
targetRot = qYaw(relativeYaw) * qPitch(freePitch) * baselineRot
```

with no `entryNativePitch` terms at all, since `baselineRot` already holds the pitch at arming. Keep the existing `quatMultiply` argument order, which worked for pure yaw in MVP 1.

**Test.** With `freePitch` held at zero, look 90 degrees left and log `Matrix.GetRotation(fpp:GetLocalToWorld()).Roll` (`orphans.swift:26875`, `:17203`). It must stay within a degree of zero. If it does not, the parent frame is not upright and we need to measure it instead of assuming.

### 1c. Pitch divergence drags the body in yaw (verified by inspection)

`init.lua:449` folds pitch into `divergenceMag`, and `:456` to `:462` apply the resulting pull factor to **yaw** via `Teleport`. The body cannot pitch, so a camera pitched 70 degrees with no yaw difference still exceeds `maxDivergence` and the body gets yanked in yaw by a step computed from pitch. Use yaw-only divergence for anything that rotates the body. Pitch needs its own actuator (see open question Q2).

## 2. Assumptions ledger

`mvp.md` asks that failed assumptions be tracked so they are not repeated. Here is the ledger as I read it from `findings.md` and the code, with status against the dump. Please move this into `findings.md` and keep it current.

| # | Assumption | Status | Evidence |
|---|---|---|---|
| A1 | `ShootEvents.OnEnter` is where the bullet is fired, so suppressing its calls stops the camera ray | **Refuted** (iteration 8) | Mode 1 suppressed everything in `OnEnter` and the bullet still fired. The ray comes from native `SetTriggerDown` to `gameEffectObjectProvider_PhysicalRay`. |
| A2 | `EffectPreAction_PreAttack.Process` overrides of `position`/`forward`/`raycastEnd` redirect the ray | **Refuted** (iterations 5 to 7) | Blackboard writes did not move the hitscan ray. |
| A3 | `weapon.ShootStraight(true)` redirects along the barrel | **Refuted**, and harmful | Disables spread (iteration 9). Removed. |
| A4 | `AI_ShootForwards`, `StartContinuousAttack`, `CreateEffectStatic(n"weaponShoot")` from script fire along a given vector for the player | **Refuted** (iterations 6 to 8) | All modes hit the camera reticle. |
| A5 | `TriggerWeaponEffects(..., Shoot)` generates the camera-converging tracer | **Refuted** | Suppressing it did not change where the bullet hit (iteration 8). |
| A6 | Native callsite patch of the PhysicalRay input evaluator redirects origin and direction | **Confirmed empirically** by owner (iteration 8), unverified by me | Build-specific RVAs; the hook checks `E8` and the call target before patching. |
| A7 | `GetWorldYaw` does not exist on `PlayerPuppet` | **Refuted** | `core/entity/entity.swift:48`, inherited by `PlayerPuppet`. |
| A8 | `math.atan2(fwd.y, fwd.x)` equals engine yaw | **Refuted** (iteration 12) | Section 1a. |
| A9 | `EulerAngles.new(0, 0, yaw)` sets yaw | **Confirmed** | CET `BasicTypes.h`: `EulerAngles(roll, pitch, yaw)`. |
| A10 | `Rx(-p) * Rz(yaw) * Rx(p + free) * baseline` is a pure yaw plus pitch | **Refuted** | Section 1b. |
| A11 | Per-frame `TeleportationFacility.Teleport` is a viable way to rotate the player body | **Untested** | It does rotate the puppet (iteration 12 proves it moves). Vanilla uses it only for one-shot relocation (`fastTravelSystem.swift:691`, `vehicles.swift:1418`, `portal.swift:111`). Side effects on locomotion, physics and animation while walking are unknown. See Q1. |
| A12 | The anim graph makes the gun follow the camera pitch set through `SetLocalTransform` | **Appears refuted** by MVP 1 | The gun stayed fixed while the camera pitched. Needs an explicit yes or no. See Q2. |
| A13 | `redscript_rCURRENT.log` and `FTLog` can show runtime telemetry | **Refuted** (iteration 5) | File logging via CET `io.open` and the native hook's `ofstream` is what works. |
| A14 | Bare `Vector4(...)` and `EulerAngles` struct construction compile on redscript 0.5.32 | **Confirmed** by compile logs | Still convert the remaining one at `DetachedReticle.reds:511` for consistency. |

## 3. Open questions that block MVP 2 design

**Q1. Is per-frame Teleport acceptable, and is there an alternative?** Please measure, not assert: walk forward while the body catches up over 60 degrees and report stutter, velocity loss, footstep audio, and whether `gameTeleportEvent` or any quest/prevention hooks fire. The dump offers no entity orientation setter other than `Teleport` (`orphans.swift:33922`). `Transform.SetOrientation` and friends (`core/math/xform.swift:47`) only edit a struct. So Teleport may be the only script-side actuator for body yaw, in which case the measurement decides whether we live with it or move body rotation into the DLL.

**Q2. What actuates Aiming Direction pitch?** The body cannot pitch, and A12 suggests the anim graph ignores our camera pitch. Two candidates, both unknown behavior until tested:

- Vanilla camera parameters. `DefaultTransition.SetGameplayCameraParameters` (`cyberpunk/player/psm/defaultTransition.swift:1192`) builds an `AnimFeature_CameraGameplay` (`orphans.swift:42106`) with `upperbody_pitch_weight`, `upperbody_yaw_weight`, `is_pitch_off`, `is_yaw_off`, read from TweakDB `player.cameraDefault.*`, `player.cameraTakedowns.*`, `player.cameraFinishers.*`, `player.cameraGrapple.*`, and applies it with `SetAnimationParameterFeature(n"CameraGameplay", ...)` (`orphans.swift:42558`). The field names say the graph has a notion of how much the upper body follows camera yaw and pitch, and a switch to turn each off. What the graph does with them is not visible in scripts. Cheap experiment: in CET read `TweakDB:GetFlat("player.cameraDefault.upperbody_yaw_weight")` and the other five, log them, then apply a modified feature on the player and watch the arms. Record the result in the ledger either way.
- Let mouse Y through to vanilla and offset the camera locally by the lag. This gives up "nothing but the mouse moves the camera" only if vanilla adds its own pitch motion; test whether it does.

**Q3. Does the hook's spread rotation hold under ADS and for tech charge?** Iteration 9 rotates the pellet cone from camera frame to barrel frame. One screenshot each for a shotgun hip-fire, shotgun ADS, and a charged tech weapon at 30 degrees divergence.

## 4. Code findings against HEAD

| # | Where | Finding |
|---|---|---|
| C1 | `DetachedReticle.reds:426` | `@replaceMethod(ShootEvents.OnEnter)` is no longer justified. The body is now vanilla plus `SetMuzzleAimState`, `RecordShot` and a log. Nothing is suppressed, so the comment at `:419` describing suppression is stale. Convert to `@wrapMethod`: compute the muzzle state, call `SetMuzzleAimState`, then `wrappedMethod(stateContext, scriptInterface)`. This drops about 150 copied vanilla lines, which AGENTS.md forbids, and restores compatibility with other mods wrapping `OnEnter`. |
| C2 | `DetachedReticle.reds:298`, `:525` | `LogChannel` is back. It is not in the vanilla dump; it depends on a third-party `Logs.reds` the end user will not have, and `findings.md` says it was replaced. Use `FTLog` or write through the aim system to the CET log, which is already the working channel. |
| C3 | `DetachedReticle.reds:511` | One bare `Vector4(...)` left; the rest use `new`. |
| C4 | `init.lua:383` | Section 1a. |
| C5 | `init.lua:500` to `:506` | Section 1b. |
| C6 | `init.lua:449` to `:467` | Section 1c. |
| C7 | `init.lua` holster path | On holster the camera is restored but the body is left wherever catch-up stopped, and `intendedWorldYaw` is reset to the body yaw on the next arm. Fine for MVP, but state it in the README. |
| C8 | `src/Hooks/ShootingHook.cpp:118` | `LogRayRedirection` opens and writes a file on every evaluated ray, so one shotgun shot does up to twelve file opens on the game thread. Gate it behind a flag that the script or a config can turn off before release. |
| C9 | `src/Hooks/AnimationHook.cpp` | Still a no-op that logs "Setting up AnimationHook". Either remove the log line or the whole hook until it has a job, so the RED4ext log does not claim a feature that does not exist. |
| C10 | `src/Main.cpp:12` | Author string is `Antigravity & User`. Pick the author you want in the plugin metadata and keep it stable; it is what RED4ext shows users. |

## 5. Install completeness (owner's requirement)

The README is now wrong in the opposite direction from last time. It says RED4ext is not required and lists only `bin/` and `r6/`. HEAD cannot run that way: `r6/scripts/DetachedReticle/NativeBridge.reds` declares `native func SetMuzzleAimState`, which only `DetachedReticle.dll` registers, and the ballistics live in that DLL. Without the DLL the scripts fail validation at startup or the first call crashes, and MVP item 4 does not exist.

The owner has said the repo must contain everything an end user installs, including the DLL. So:

1. **Commit the DLL** at `red4ext/plugins/DetachedReticle/DetachedReticle.dll`. This needs a `.gitignore` whitelist line `!/red4ext/plugins/DetachedReticle/DetachedReticle.dll` below the `*.dll` rule. The owner's requirement is the approval AGENTS.md asks for; note it in the commit message.
2. **Build provenance.** Pin `GIT_TAG` in `CMakeLists.txt` to a RED4ext.SDK tag or commit instead of `master`. Put the SDK commit, MSVC version and game build in the README and in the commit that adds the binary. The author string in the binary must match `Main.cpp`.
3. **README rewrite.** Requirements: game 2.50 build 3.0.88.46235 exactly (the RVAs are build-specific and the hook refuses to patch other builds, so say what the user will see in `red4ext/logs` when that happens), RED4ext, redscript 0.5.32 or later, CET 1.38 or later, NativeSettings optional. Copy steps for `bin/`, `r6/` and `red4ext/`. Current behavior and known gaps. Remove the "RED4ext is not required" note and the dead telemetry formats.
4. **Config file.** `config.json` is tracked and gets rewritten by `SaveConfig` on every slider move, so the repo copy will churn. Either ship it as `config.default.json` and create `config.json` on first run, or add it to `.gitignore` after the owner agrees.

## 6. What I need back, in order

1. The 1a fix (`GetWorldYaw` or `Heading`) plus a five-second log excerpt showing body yaw and intended yaw converging with no sign flips.
2. The 1b roll test result (roll within one degree at 90 degrees yaw, zero pitch).
3. The ledger moved into `findings.md`, with A7 corrected.
4. Q1 measurements and the Q2 experiment result, whatever they are.
5. C1, C2 and the section 5 install commit, with the DLL and its provenance.

When those are in, I will re-verify the final `.reds` and `init.lua` symbols against the dump and sign off on MVP 2 from my side. The owner signs off on the in-game result.
