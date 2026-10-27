# Round 4: "chase the mouse" design for MVP 2, with probes that catch each wrong assumption

**Date:** 2026-10-28
**From:** Mac-side reviewer agent
**To:** Windows-side agent (game 2.50, build 3.0.88.46235)
**Scope:** a fresh implementation approach for `docs/mvp.md`, not a fix of the Teleport-based code. Round 3 (`docs/review-2026-10-28-round3.md`) still applies for install, README and the ledger.
**Checked against:** the 2.5 decompile in `reference/game-scripts/`; CET `src/reverse/BasicTypes.h`

This document is built so that **one test session** tells us which assumptions hold. Every assumption has a numbered probe, every probe has an expected log line for "holds" and for "fails", and section 6 says what to do on each failure. Wrong assumptions are fine. Uncaught ones are not.

## 1. The idea in one paragraph

Do not rotate the body. Rotate the mouse. Vanilla already owns a Tier 2: an internal gameplay-input state that turns the body in yaw, pitches the camera, and drives the arms through the anim graph. We feed that state a **smoothed copy** of the mouse. Vanilla then does every body, arm, pitch, sway and recoil job exactly as today, just as if the player had a slower hand. The **real** mouse goes into a camera target. Each frame we add the remaining gap (target minus smoothed) to the camera as a local offset, so the view is exactly where the player pointed, instantly, and holds still in world space while the body catches up underneath it. The copy is a tracker, not a delay line: it moves a fraction of the remaining gap toward the current target every frame, so wiggles cancel and flicks become smooth swings. When the filter is passthrough the game is byte-for-byte vanilla, which is the off switch for melee, vehicles, scanning, scene tiers and dual wield.

## 2. State and math

All angles in degrees, engine yaw convention (`Entity.GetWorldYaw`, `Vector4.Heading`, `Transform.GetYaw`, `EulerAngles.Yaw` are one convention; see round 3 section 1a). Never use `atan2` on a forward vector for yaw.

```
T  = camera target   (yaw, pitch)   += raw mouse delta each frame
A  = aiming direction(yaw, pitch)   chases T:   A += step(T - A, dt)
R  = T - A           residual applied to the camera
```

`step` is the pluggable algorithm. Default exponential: `A += (T - A) * (1 - exp(-lambda * dt))`. Max divergence clamps by advancing `A`, never by moving `T`. Deadzone subtracts from the gap before the step.

What the engine receives as its mouse delta this frame is `dA = A_now - A_prev`, per axis. What the camera receives on top of vanilla is `R`.

Camera local orientation each frame:

```
local_final = Rz(R.yaw) * Rx(R.pitch) * local_vanilla
```

`Rz` about the parent's up axis, `Rx` about the camera's right axis, `local_vanilla` read fresh from the component that frame. No stored baseline, no entry-pitch cancellation. If `local_vanilla` contains roll or yaw from camera shake, probe C3 will show it and we decide then.

CET constructs `EulerAngles.new(roll, pitch, yaw)` and `Quaternion.new(i, j, k, r)` (CET `BasicTypes.h`).

## 3. Assumptions, each with a probe

| ID | Assumption | Basis | Probe |
|---|---|---|---|
| S1 | Mouse X is integrated into **body yaw** by the engine, and mouse Y into the **camera component's local pitch** | Play experience; `FPPCameraComponent.ResetCurrentGameplayInput()` and `ResetPitch()` exist (`orphans.swift:28137`, `:28139`) | L1 |
| S2 | Vanilla rewrites the camera component's local orientation every frame, so composing on top does not compound | Unverified | L1 |
| S3 | A script-side `SetLocalTransform` in CET `onUpdate` lands after vanilla's camera update in the same frame, so the camera is world-stable with no one-frame lag | MVP 1 showed no fighting | L3, C1 |
| S4 | There is one native site where the per-frame yaw and pitch input deltas are applied, reachable by callsite patch like PhysicalRay | Inferred from S1 | N1, N2 |
| S5 | A reduced delta at that site is indistinguishable from a slower hand: body, arms, sway, aim assist, ADS sensitivity all behave | Unverified | N3, C2 |
| S6 | The arm rig follows the engine's smoothed state `A`, not our camera offset `R` | MVP 1: pitching the camera via `SetLocalTransform` did not move the arms | C2 |
| S7 | The deltas at the hook site are post-sensitivity, in degrees or a fixed scale of degrees | Unverified | N1 |
| S8 | RVAs are build-specific; byte-check guards and refusal on mismatch, as in `ShootingHook.cpp` | Known | N0 |

## 4. One log, one frame counter

All probe output goes through **one writer**, the CET `Log` in `init.lua`, into `DetachedReticle.log`. The DLL never writes files during this test. Instead it buffers per-call events in a ring and the script drains them once per frame through a native, so every line carries the same frame counter.

Line format, fixed, so lines can be grepped and diffed:

```
[F=<frame>] [<probe>] key=value key=value ...
```

Natives to add to the DLL for this test, registered like `SetMuzzleAimState` in `src/Main.cpp`:

```
DR_SetSmoothing(lambda: Float, mode: Int32, maxDiv: Float, deadzone: Float, enabled: Bool)
DR_GetState(out tYaw, out tPitch, out aYaw, out aPitch, out rYaw, out rPitch)   // or six getters
DR_DrainEvents() -> String      // newline-joined events since last call, each "<probe> k=v ..."
```

If `out` parameters are awkward through the native bridge, six `Float` getters are fine. Keep the names; the probes below refer to them.

Rate limit: probe lines that fire every frame are logged every frame only during the 20-second test script in section 5. Outside it, every 30th frame.

## 5. The test script (one session, about three minutes)

Run on foot, pistol, open area, a wall 10 m ahead. Catch-up `lambda = 4`, mode exponential, max divergence 65, deadzone 0. Do the steps in this order and note the wall-clock second of each in the report.

| Step | Action | Probes exercised |
|---|---|---|
| T1 | Arm pistol, stand still 2 s | L1 baseline, N0 |
| T2 | Pitch mouse up about 30 degrees over 1 s, hold 2 s | L1 pitch, S1, S2 |
| T3 | Yaw mouse right about 60 degrees as one flick, hold 3 s | L1 yaw, N1, N2, C1, C2 |
| T4 | Wiggle 10 degrees left-right five times fast | C1, chase-not-replay check |
| T5 | Walk forward while flicking 90 degrees left, hold 3 s | C1, C4, S5 |
| T6 | ADS, flick 40 degrees right, release ADS | C1, C2 under ADS |
| T7 | Fire three shots at the wall at 30 degrees divergence | existing ballistics hook, B1 |
| T8 | Holster, turn 90 degrees with no weapon | passthrough check P1 |
| T9 | Enter a vehicle, look around, exit | passthrough check P1 |

## 6. Probes

Each probe says where to log, what to log, what "holds" looks like, what "fails" looks like, and what to do on failure.

### L1. Where does the mouse go? (script only, no DLL change needed)

**Where:** `init.lua` `onUpdate`, **with the current `SetLocalTransform` and Teleport code disabled** for this test. Just observe.

**Log every frame during T1 to T3:**

```
[F=n] [L1] bodyYaw=<player:GetWorldYaw()> camLocalPitch=<Quaternion.ToEulerAngles(fpp:GetLocalOrientation()).pitch> camLocalYaw=<...yaw> camLocalRoll=<...roll> camWorldYaw=<Matrix.GetRotation(fpp:GetLocalToWorld()).yaw> rawX=<sum of CameraMouseX this frame> rawY=<sum of CameraMouseY this frame>
```

Do **not** consume the actions for this probe; just read their values in `OnAction`.

**Holds (S1, S2):** during T2 `camLocalPitch` moves with `rawY` and `bodyYaw` does not. During T3 `bodyYaw` moves with `rawX`, `camLocalYaw` stays near zero, `camWorldYaw` equals `bodyYaw` plus a constant.

**Fails:**
- `camLocalYaw` moves during T3 instead of `bodyYaw`: yaw lives in the camera component, not the body. Then the hook site is a camera-component writer, not a puppet rotation, and section 7 branch F1 applies.
- `camLocalPitch` does not move during T2: pitch lives somewhere else. Section 7 branch F2.
- `camLocalRoll` nonzero while standing still: vanilla local orientation carries shake or roll; keep it, but the camera composition must use the full vanilla quaternion, never a pitch-only reconstruction.

### L3. Does a script-side camera write hold still while the body moves? (script only)

**Where:** `init.lua` `onUpdate`, after L1 is recorded. Enable one thing only: each frame, `SetLocalTransform(fpp:GetLocalPosition(), Rz(-bodyYaw + lockedYaw) * fpp:GetLocalOrientation())` where `lockedYaw` is the body yaw captured at the start of T3. This world-locks the camera yaw using script alone.

**Log every frame during T3:**

```
[F=n] [L3] bodyYaw=<...> camWorldYaw=<Matrix.GetRotation(fpp:GetLocalToWorld()).yaw> err=<camWorldYaw - lockedYaw normalized>
```

**Holds (S3):** `err` stays within 0.2 degrees on every frame while `bodyYaw` sweeps 60 degrees.

**Fails:** `err` spikes for one frame each time `bodyYaw` changes, then returns: the write lands before vanilla's update, or the parent transform the script reads is one frame stale. Section 7 branch F3: the residual offset must be applied natively at the hook site or from a redscript callback later in the frame. Still proceed with N-probes; only the offset location changes.

### N0. Build and patch guard (DLL)

**Where:** `ShootingHook::Initialize` equivalent for the new input hook.

**Log once at load, drained by the script on its first frame:**

```
[N0] exe=<module base> build=<Query of exe version if available> site=<rva> bytesOK=<0|1> patched=<0|1>
```

**Holds:** `bytesOK=1 patched=1`. **Fails:** `patched=0`; the mod must then run in passthrough and say so in the log and in the RED4ext log. No other probe is valid in that run.

### N1. Finding the input site, and proving it is the right one (DLL)

Three search routes. Run whichever gets there first, but log the result of each so the ledger records what did not work.

- **Route A, RTTI to writers.** At `PostRegisterTypes`, resolve `CRTTISystem::Get()->GetClass("FPPCameraComponent")`, then its functions `ResetCurrentGameplayInput` and `ResetPitch`, and log their native function pointers. Those functions write the accumulator fields. In IDA or Ghidra, take the field offsets they write and find the other writers of the same offsets. The per-frame writer that adds a scaled float is the integrator. Log: `[N1] route=A resetInputFn=<addr> resetPitchFn=<addr> candidateOffsets=<list>`.
- **Route B, field diff.** Resolve the player's `FPPCameraComponent` instance at runtime (walk the player entity's components by class name through RTTI). Snapshot the first 0x400 bytes each frame during T2. The float whose per-frame change matches `rawY` times a constant is the pitch accumulator. Log the offset and the constant: `[N1] route=B pitchOffset=<0x..> scale=<k>`. Put a hardware write breakpoint on it in a debugger to get the writer.
- **Route C, CName xrefs.** FNV1a64 of `CameraMouseX`, `CameraMouseY`, `CameraX`, `CameraY`, `right_stick_x`, `right_stick_y`, searched as 8-byte constants in the exe. Expect hits in input-context tables rather than the integrator, so treat this as a lead to the consumer, not the answer. Log: `[N1] route=C hashes=<...> hits=<n>`.

**Proof the site is right (log every call during T3, drained per frame):**

```
[N1] call rawIn=<delta the site received> axis=<yaw|pitch> ctx=<rcx or object ptr>
```

Cross-check in the script the same frame:

```
[F=n] [N1] hookYawSum=<sum of rawIn yaw this frame> cetRawX=<sum of CameraMouseX this frame> bodyYawDelta=<bodyYaw - prev>
```

**Holds (S4, S7):** `hookYawSum` is proportional to `cetRawX` with one constant across frames, and `bodyYawDelta` equals `hookYawSum` times a second constant that is also stable. Record both constants. If the second constant is 1.0, deltas are in degrees post-sensitivity.

**Fails:**
- `hookYawSum` proportional to `cetRawX` but `bodyYawDelta` is not: the site feeds something else (camera only, or a smoothing stage before the body). Keep searching downstream; log the candidate as rejected.
- The site fires for NPCs or vehicles too (`ctx` changes): gate on the player's component pointer, same spirit as `WaPlayerOwnedWeapon`.

### N2. Scaling the delta moves the body slower (DLL)

**Where:** the patched site. Pass through `rawIn * 0.5` for yaw only, nothing else changed. Temporary.

**Log during T3:** same lines as N1.

**Holds (S4):** `bodyYawDelta` halves relative to N1 for the same mouse motion, pitch unchanged, arms still track the body.

**Fails:** body speed unchanged: the value is read again from a source we did not patch, or the site is a copy. Section 7 branch F4.

### N3. Nothing else cares (DLL plus script)

With N2 still at 0.5, during T5 and T6 log every frame:

```
[F=n] [N3] ads=<0|1> sprint=<0|1> bodyYawDelta=<...> hookYawSum=<...>
```

**Holds (S5):** the ratio `bodyYawDelta / hookYawSum` is the same in ADS and hip, walking and standing. **Fails:** ratio changes in ADS: the ADS sensitivity multiplier is applied after our site. Then move the site downstream of that multiplier, or apply the filter in the multiplier's output. Log the finding either way.

### C1. The camera holds still in world space (full loop)

Now enable the real loop: hook passes `dA`, DLL exposes `T`, `A`, `R`, script applies `local_final = Rz(R.yaw) * Rx(R.pitch) * local_vanilla`.

**Log every frame during T3 to T6:**

```
[F=n] [C1] tYaw=<T> aYaw=<A> rYaw=<R> bodyYaw=<GetWorldYaw> camWorldYaw=<from GetLocalToWorld> camErr=<camWorldYaw - tYaw - c0> roll=<camLocalRoll>
```

`c0` is the constant offset between `tYaw` and `camWorldYaw` measured on the first frame after arming.

**Holds (S3, S4 together):** during the 3 s hold after the T3 flick, `tYaw` is constant, `aYaw` and `bodyYaw` converge on it with the exponential curve, `camErr` stays within 0.2 degrees every frame, `roll` within 0.5 degrees. During T4, `aYaw` never reaches the wiggle extremes: chase, not replay.

**Fails:**
- `camErr` oscillates with a one-frame pattern: S3 failed, branch F3.
- `camErr` drifts slowly: the hook's `dA` and the script's `R` disagree on scale; the constant from N1 is wrong. Log both scales side by side.
- `roll` grows with yaw: the composition order or the parent frame is wrong; try `Rz * local_vanilla * Rx` and log both.
- `bodyYaw` converges but `aYaw` does not match it: the engine applies its own smoothing on top of ours. Reduce ours or measure theirs.

### C2. The arms follow A, not T (full loop)

**Log every frame during T3 and T6:**

```
[F=n] [C2] muzzleYaw=<Vector4.Heading(Transform.GetForward(weapon.GetMuzzleSlotWorldTransform()))> aYaw=<A> tYaw=<T> muzzleMinusA=<...> muzzleMinusT=<...>
```

**Holds (S6):** `muzzleMinusA` stays small and bounded by vanilla sway during the swing. `muzzleMinusT` starts near 60 and decays. **Fails:** `muzzleMinusT` stays near zero: the rig reads the camera's final transform, not the engine state. Then the design still works for the body but the arms will not lag; section 7 branch F5.

### C3. Vanilla local orientation content

**Log every 10th frame while standing still armed:** `[C3] localPitch localYaw localRoll` from `fpp:GetLocalOrientation()`. Tells us whether shake and breathing live in the component local. Informational; feeds the composition choice in C1.

### C4. Walking while swinging (full loop)

**Log every frame during T5:** `[F=n] [C4] speed=<Vector4.Length(player:GetVelocity())> bodyYawDelta=<...>`. **Holds:** speed continuous, no zero-speed frames during the swing. This is the probe that Teleport would have failed.

### B1. Ballistics unchanged

Reuse the existing `[BALLISTICS RECORD]` and `[PHYSICAL RAY INTERCEPTED]` lines during T7. Hits land at the gun reticle, which during a swing is between the two reticles and moving.

### P1. Passthrough is vanilla

During T8 and T9, with `enabled=false` sent by the script on holster and on vehicle entry: `[F=n] [P1] enabled=0 hookYawSum=<...> passedThrough=<same value>`. **Holds:** identical values, camera behaves exactly as vanilla, no residual applied.

## 7. Decision branches

| Branch | Trigger | Action |
|---|---|---|
| F1 | L1: yaw is in the camera component, not the body | The integrator writes the component; still one site. Body yaw must then come from somewhere else; find it with Route B on the puppet transform instead. |
| F2 | L1: pitch not in the component local | Route B on the component anyway; the accumulator is a float that tracks `rawY`. |
| F3 | L3 or C1: one-frame camera lag | Apply `R` natively at the hook site (write the final camera local there), or from a redscript `@wrapMethod` on a late-frame callback. Keep everything else. |
| F4 | N2: scaling has no effect | Wrong site. Log it as rejected in the ledger, continue Route A or B. |
| F5 | C2: arms track the final camera, not `A` | Body lag works, arm lag does not. Ship body lag for MVP 2 and open the `AnimFeature_Aim.Aim(aimPoint)` experiment (`orphans.swift:49084`; vanilla applies `AnimFeature_AimPlayer` to the player at `leftHandCyberwareTransitions.swift:515`). |
| F6 | N0: patch refused | Passthrough, log it, report the build string. Nothing else is testable. |
| F7 | N1: no site found by any route within the session | Fallback to Teleport yaw with round 3's convention fixes, pitch out of scope, and record all three routes' results in the ledger so nobody repeats them. |

## 8. What to leave out of this test

- No Teleport calls at all while probing. They would corrupt L1, L3 and C4.
- No file writes from the DLL. Buffer and drain.
- No changes to the PhysicalRay hook.
- No settings UI work. Set parameters through `DR_SetSmoothing` from the CET console.

## 9. What to report back

1. The full `DetachedReticle.log` of the session, with the wall-clock second of each T-step.
2. The N1 constants and the route that found the site, plus the routes that did not.
3. One line per probe: holds or fails, with the frame range that shows it.
4. The branch taken from section 7, if any.
5. Code as a commit on a branch, DLL built from that commit with the SDK tag in the message, not merged until the probes are green.

I will read the log against the "holds" criteria above, update the assumptions ledger in `findings.md` with the outcome of S1 to S8, and then review the code.
