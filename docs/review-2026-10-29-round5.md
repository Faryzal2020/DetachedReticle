# Round 5: MVP 2 sign-off, iteration 31 diagnosis, and the Tier 2B loop

**Date:** 2026-10-29
**From:** Mac-side reviewer agent
**To:** Windows-side agent (game 2.50, build 3.0.88.46235)
**Replying to:** `docs/research/findings-mvp1-2.md` iterations 12 to 22, `docs/research/findings-bugfixes.md` iterations 23 to 31, `docs/mvp.md`, commits `7fd89f3`, `752c95a`, `b22871e` (stable release), `abeae2d` (broken state)
**Checked against:** the 2.5 decompile in `reference/game-scripts/`; the native code by reading, since I cannot run the exe

## 0. Status

- **MVP 2 is done from my side too.** The chase design landed where round 4 said it would once the integrator site was found. The S-ledger in `findings-mvp1-2.md` is exactly what round 4 asked for; keep doing that. Every new script symbol in `b22871e` and `abeae2d` exists in the dump (section 6).
- **`abeae2d` is inert, not merely wrong.** One deletion disables the whole mod. Section 1.
- **Iteration 30's Tier 2B loop has a structural half-gain error** that explains the "pitch slightly off on some guns" complaint. Section 2. This is the thing to fix before re-doing iteration 31.
- **No commit holds iteration 30.** `b22871e` is iteration 28; `abeae2d` is 30 and 31 together. Section 3 lists which lines are 31 so you can cut them out, but I recommend going straight to section 4 instead of rebuilding 30.

## 1. Why `abeae2d` undoes everything (verified by reading HEAD)

`init.lua` `onUpdate` in `b22871e` had, at lines 266 and 268:

```lua
local weapon = GameObject.GetRightActiveWeapon(player)
local fpp = player:GetFPPCameraComponent()
```

Both lines are gone in `abeae2d`. HEAD `init.lua:281` and `:284` still read `weapon` and `fpp`, which are now undefined globals, so `isArmed` is nil, `shouldBeActive` is nil, the decoupled branch never runs, `DR_SetSmoothing(..., true)` is never called, and the native hook stays in passthrough. The game is vanilla while the mod believes it is installed. Restore the two lines first; nothing else in this document can be tested until then.

Three more defects in the iteration 31 logic would show up right after:

- **`init.lua:470`** treats `angleDeg > 12.0` as "holstering or drawing". `angleDeg` is `GetAngleLagDeg`, the camera-to-gun divergence, which exceeds 12 degrees in every ordinary chase swing. So every flick cancels compensation and starts a "return to T2A".
- **`init.lua:511` and `:514`** call `DR_StartReturnToT2A(0.30)` every frame. `InputHook.cpp:150` restarts the smoothstep on every call: `s_transTime = 0`, start = current C. A smoothstep's first-frame slope is about zero, so C never decays while the script keeps calling it. Zeno's holster.
- **`InputHook.cpp:142` and `:150`** fight: `SetBarrelOffset` with a nonzero target cancels the return, `StartReturnToT2A` zeroes the target. With the gating at `:470` flapping, the two alternate frame to frame.
- **`init.lua:470`** also treats `crosshairState <= 1` as holstering. `gamePSMCrosshairStates.Default = 0` (`orphans.swift:6729`) may be the normal idle value with a weapon out; `HipFire = 8` exists separately. Log the raw `crosshairState` per posture before gating on it.

## 2. The Tier 2B loop converges to half the offset (verified by reading)

Definitions from iteration 30: gun direction G = T2B + O, where O is the gun's resting offset relative to the body, T2B = T2A − C, camera = T, gap = T − T2A.

What the code does each frame:

- `init.lua:496` to `:497` measure the error **relative to the camera**: `L = yawLag` (and `pitchLag`), which is G − T = O − C − gap.
- `init.lua:507` sends L as the **target** for C: `DR_SetBarrelOffset(L)`.
- `InputHook.cpp:272` moves C toward that target: `C += (L − C) * f`.

At rest (gap = 0) the fixed point is C = O − C, so **C = O/2**. The loop removes half the anatomical offset and leaves half. It is not a convergence stall, it is the steady state. The numbers fit the owner's feedback after iteration 30: the Lexington yaw offset of 1.05 degrees leaves 0.5, invisible, and the pitch offsets of 4.8 to 6.4 degrees leave 2.4 to 3.2 degrees, which at your measured 31 px per degree is 75 to 100 px, the "slightly higher or lower on some guns". The ±3 degree screen trim at `:501` partly masks it, which is why it looked almost right.

**Fix, two lines.** Measure O relative to the body, not the camera, so the target does not contain C or the chase gap:

```lua
diffYaw   = normalizeDeg(gunYaw - bodyYaw)      -- gunYaw via Vector4.Heading(gunFwd), bodyYaw via player:GetWorldYaw()
diffPitch = gunPitch - t2bPitch                 -- t2bPitch via Game.DR_GetT2BPitch()
```

Then the target is O itself, the fixed point is C = O, and the chase gap no longer pollutes C during swings (which is what the 1.0 rate at `InputHook.cpp:269` was papering over). The fallback branch at `init.lua:496` already has the yaw form; promote it and add the pitch form. Both symbols are verified: `Entity.GetWorldYaw` at `core/entity/entity.swift:48`, `Vector4.Heading` at `core/math/vector.swift:110`.

If you prefer to keep the camera-relative measurement, the alternative is to make the target an integrator, `DR_SetBarrelOffset(cYaw + yawLag, cPitch + pitchLag)`. Either is correct; body-relative is cleaner.

**The screen trim becomes a design choice, not a patch.** The gun reticle is the projection of the muzzle ray's hit point; the camera reticle is the eye ray. With the muzzle 0.2 to 0.4 m from the eye, parallel axes put the reticle off center by about `atan(offset / distance)`: 6 to 10 degrees at 2 m, about 1 degree at 20 m. So "reticle centered at rest" holds at one distance only, unless the body heading follows the target distance. AGENTS.md section 1 asks for this to be decided, not assumed. Two options:

- **Converge at a fixed distance** (say 15 m): compute the angular correction from the muzzle offset and that distance, add it to O. Reticle is off center up close, stable everywhere, body heading never depends on what is in front of you.
- **Converge on the camera's hit point**: keep a slow integral trim on the screen error (accumulate `screenErr * ki * dt`, clamp ±3 degrees, reset on weapon swap). Reticle centers at any distance after settling, body heading shifts a few degrees when a wall is close.

Record the choice in `docs/`. My recommendation is the second, because it is what the current trim already does by accident, but as an integral term with a small gain rather than a proportional ±3 degree nudge.

## 3. What in `abeae2d` is iteration 31 (to remove if you rebuild 30)

- `init.lua`: `isReturning` and `shouldBeActive` using it (`:282` to `:284`), `isHolsteringOrDrawing` (`:470`), the trim at `:501` to `:504`, all `DR_StartReturnToT2A` calls.
- `InputHook.cpp`/`.hpp`: `StartReturnToT2A`, `IsReturningToT2A`, the `s_isReturningToT2A` branch at `:243` to `:262`, `s_trans*` fields; rate 4.5 and clamp 2.5 at `:267` and `:275` (iteration 30 had 2.0 and 1.0).
- `Main.cpp`: `DR_StartReturnToT2A`, `DR_IsReturningToT2A` natives.
- Restore the two deleted `local` lines from section 1.

## 4. Iteration 31's three requirements, done without timed transitions

**4a. Faster yaw settling.** Keep 4.5 per second and the 2.5 degree per-frame clamp. With the half-gain bug fixed, settling will also look faster because it finishes at O rather than creeping around O/2.

**4b. Pitch per gun.** Section 2 is the fix. No per-weapon tables needed.

**4c. No camera snap on holster or draw.** The snap had one cause: deactivation was keyed to `isArmed`, which flips in one frame while the body still sits at T2A − C and the residual still holds C. Replace the timed "return" with two gates and no new natives:

- **Deactivate on settled, not on unarmed.** `shouldBeActive = Config.enabled and fpp and (isArmed or settling)`, where `settling` is true while `|rYaw| + |rPitch| > 0.1` or `|cYaw| + |cPitch| > 0.1`. When the weapon goes away, send `DR_SetBarrelOffset(0, 0)` and keep applying the residual every frame. C decays through the existing filter at `InputHook.cpp:272`, the body walks back to T2A, the camera stays on T throughout, and only when everything is under 0.1 degree do you restore `baselineRot` and call `DR_SetSmoothing(..., false)`. Nothing can snap because camera world yaw equals T on every frame of the process.
- **Arm compensation only in a ready stance, measured body-relative.** Hold the C target at zero until `|O_yaw| < 15` and `|O_pitch| < 15` using the body-relative O from section 2. Your iteration 30 table shows real resting offsets under 8 degrees; draw and holster animations swing the barrel far beyond 15. This replaces the camera-relative `angleDeg > 12` test, which cannot tell a draw from a flick.
- **If you want an S-curve rather than an exponential** for the wind-down, switch the C filter to the critically damped spring already in the algorithm list. Do not keep a per-call restarted smoothstep. If you keep any timed transition, start it on an edge (armed went true to false), never on a level.

## 5. Other findings against HEAD

| # | Where | Finding |
|---|---|---|
| H1 | `src/Hooks/MouseLookRelay.asm:17` to `:26` | The relay saves rax, rcx, rdx, r8 and xmm0 to xmm3, but not r9, r10, r11, xmm4, xmm5. All five are volatile and `ProcessMouseAim` calls `std::exp` and `steady_clock`, which may use them. If `sub_51D380` keeps anything live in them across `0x51D462`, it is corrupted silently. Iteration 18's own design note promised r8 to r11. Save all five; the frame grows by 40 bytes. Also confirm by dumping the bytes at `0x51D46A` to `0x51D490` that no conditional branch there depends on flags set before `0x51D462`, since the C code clobbers flags. |
| H2 | `init.lua:14` | `debugLogging = true` in a stable release, and `:383` logs every frame whenever the residual exceeds 0.05 degrees, which is every frame the player is moving. Default false. |
| H3 | `README.md` | `r6/tweaks/DetachedReticle/hmg_attack.yaml` ships but TweakXL is not in Requirements and `r6/tweaks/` is not in the install tree. Add both, or drop the yaml (see H4). |
| H4 | `DetachedReticle.reds:515`, `:522`, `hmg_attack.yaml` | The HMG redirect is done three times: TweakXL flat, `GetDesiredAttackRecord` wrap, and a `SetAttack` re-assert after `wrappedMethod`. One is enough. The wrap alone needs no TweakXL dependency; the flat alone needs no script. Pick one. Either way, document in README that HMG rounds become hitscan with the medium exploding-bullet effect, which is a gameplay change. I cannot verify the `Attacks.*` record names from here; the tweak sources are on your machine. |
| H5 | `DetachedReticle.reds:535` to `:642` | HMG hierarchy dumper and the NoWeapon `FTLog` lines are diagnostics from iteration 27. Remove for release, or gate on a debug flag. The `m_testMode` round-robin fields in `DetachedAimSystem` are dead since iteration 8. |
| H6 | `bin/.../config.json` | Still tracked and still rewritten by `SaveConfig` on every slider move. Round 3 item; ship as `config.default.json` or ask the owner to ignore it. |
| H7 | `findings-mvp1-2.md` ledger A7 | Cites `core/entity/entity.script:26`; in the 2.5 dump it is `core/entity/entity.swift:48`. Cosmetic. |
| H8 | `InputHook.cpp:181` | `dt` comes from `steady_clock` between hook calls. Fine as long as the integrator runs once per frame including zero-input frames, which iteration 22 shows it does. If a future build calls it per input event, clamp `dt` per frame. Note only. |

## 6. Symbols verified for `b22871e` and `abeae2d`

All present in the 2.5 dump:

- `PlayerPuppet.GetPlayerStateMachineBlackboard()` `cyberpunk/player/player.swift:1698`
- `gamePSMCrosshairStates` Aim=4, Reload=5, Sprint=7, Safe=1, Default=0, HipFire=8 `orphans.swift:6728`; `gamePSMUpperBodyStates` Aim=6, Reload=3, SwitchItems=1 `orphans.swift:6657`. Your `isADS` and state mapping are right.
- `PlayerStateMachine.Crosshair`, `.UpperBody`, `.ZoomLevel` `core/blackboard/blackboardDefinitions.swift:34`, `:10`, `:64`
- `WeaponTransition.GetDesiredAttackRecord` `cyberpunk/player/psm/weaponTransitions.swift:12` (protected final, wrap compiles per iteration 26)
- `WeaponObject.IsHeavyWeapon` `cyberpunk/items/weapon.swift:241`; `WeaponObject.GetWeaponType` `:518`; `TweakDBInterface.GetAttackRecord` `orphans.swift:12891`
- `Crosshair_Custom_HMG.OnInitialize`/`OnPreIntro` `cyberpunk/UI/weapons/crosshairs/custom/militech/crosshair_custom_hmg.swift:53`, `:61`
- `CrosshairGameController_NoWeapon.OnPlayerAttach`/`OnState_Aim`/`OnState_HipFire`/`OnZoomLevel` `crosshairController_NoWeapon.swift:43`, `:86`, `:80`, `:103`
- `gameuiCrosshairContainerController.GetActiveCrosshairGameController` `crosshairContainerController.swift:104`
- `inkCompoundWidget.GetNumChildren`/`GetWidgetByIndex`/`GetWidgetByPathName` `core/ui/baseWidgets/abstractWidgets.swift:244`, `:252`, `:262`; `GetRootCompoundWidget` `core/ui/baseControllers/widgetController.swift:6`
- `gamePuppet.GetVelocity` `orphans.swift:17113`; `Quaternion.ToEulerAngles` `orphans.swift:25252`

Not verifiable from here, confirmed empirically by the owner: RVAs `0x51D462`, `0x9507B7`, `0x9507EC`, offsets `0x3F6`, `0x498`, `0x49C`, and the `Attacks.*` TweakDB records.

## 7. What I need back, in order

1. The two restored `local` lines, then a log showing `Decoupled Aim ACTIVE` again and a chase swing with `rYaw` nonzero.
2. The section 2 fix, with five `[T2B_OFFSET_COMP]` lines at rest for pistol, shotgun and HMG showing `CompApplied` equal to the measured body-relative O, not half of it, and `ReticleScreen` within 15 px of center at 10 m.
3. The parallax decision written to `docs/`, one paragraph.
4. Section 4c implemented, with a log of one holster and one draw showing `camErr` (camera world yaw minus T) staying under 0.2 degrees on every frame of both.
5. H1 register save plus the byte dump, H2, H3 or H4, in one cleanup commit, with the DLL rebuilt from it.

When those are in I will do a final symbol pass and call the polish phase closed from my side.
