# Full Diagnostic Report: In-Game Save Load Freeze & Watchdog Timeout

**Date:** 2026-10-30  
**Game Version:** Cyberpunk 2077 v2.50 (Build `3.0.88.46235`)  
**Investigated Incident:** 120-second Watchdog Freeze during in-game save loading (Crash ID `20261030-003604-401112-406300`)  
**Target Save Context:** `ManualSave-18` / `AutoSave-16` (`q003_after_deal_shootout` at observer position `[-865, 2211, 62]`)

---

## 1. Executive Summary

When loading a save from in-game (Pause Menu -> Load Game), the game freezes indefinitely on the loading screen and terminates after exactly 120 seconds via an engine Watchdog breakpoint (`EXCEPTION_BREAKPOINT` at `CWatchdogThread::OnCheckStatus+0xA6` in [`engineWatchdog.cpp(224)`](file:///E:/Cyberpunk%202077/bin/x64/Cyberpunk2077.exe)).

Detailed disassembly, crash log analysis, and live memory inspection of the process minidump (`Cyberpunk2077.dmp`) revealed:
1. **The GameThread (`TID 397708`) is NOT deadlocked on a mutex.** It is parked in `gsm::State_SessionLoading::ProcessTick` waiting for asynchronous engine dispatcher jobs to flush (`job::prv::Dispatcher::FlushCounter`).
2. **Worker thread `redDispatcher10` (`TID 401756`) was trapped in a 100% CPU infinite loop.** Out of 133 threads in the process, 132 were asleep in standard NT kernel waits; `redDispatcher10` consumed **142.3 seconds of CPU time** inside [`game::EffectorSystem::ApplyEffectors`](file:///E:/Cyberpunk%202077/bin/x64/Cyberpunk2077.exe).
3. **Previous fixes in Iterations 33–35 failed to prevent the freeze** because:
   - `srh.IsGamePaused()` and `srh.IsPreGame()` are **both `false`** while the game is inside `State_SessionLoading`. As a result, neither the Lua `onUpdate` loop nor the Redscript UI ticks were actually silenced during save transitions.
   - Redscript's `OnPlayerDetach` wrapper had a signature mismatch (`-> Bool` instead of `-> Void`), breaking event propagation during player destruction.
   - The TweakXL override in [`hmg_attack.yaml`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/r6/tweaks/DetachedReticle/hmg_attack.yaml) globally mutated `Attacks.ExplodingBulletHMG` in TweakDB, causing recursive effector registration cycles when world entities (e.g. Maelstrom HMG enemies in `q003_after_deal_shootout`) restored their weapons during session load.

---

## 2. Detailed Log Findings

### 2.1 Advanced Crash Reporter (`20261030-003604-crash-tid406300-01.txt`)
- **Path:** [`20261030-003604-crash-tid406300-01.txt`](file:///E:/Cyberpunk%202077/bin/x64/plugins/AdvancedCrashReporter/reports/20261030-003604-crash-tid406300-01.txt)
- **Faulting Code:** `Cyberpunk2077.exe + 0x2FB8E16` (`CWatchdogThread::OnCheckStatus+0xA6`)
- **Engine State at Freeze:**
  ```text
  Game/LoadingStage                      = WaitingForUpdate...
  Game/SessionDesc/IsLoadingSavedSession = true
  Game/SessionDesc/WorldName             = 03_night_city
  Streaming/LastObserverPosition         = [-865, 2211, 62]
  SystemUpdate/UpdateTickGroup           = {G}PreBuckets
  SystemUpdate/DebugName                 = [U]/EffectorSystem/Tick
  ```
- **Thread Timing:**
  - Total process uptime: 232 seconds.
  - Thread `401756` (`redDispatcher10`) CPU time: **142,327 ms** (~61% of total process life, 100% core utilization for over two continuous minutes).
  - All other 15 dispatcher worker threads consumed under 20 seconds total.

### 2.2 Cyber Engine Tweaks Log (`cyber_engine_tweaks.log` & `DetachedReticle.log`)
- **Path:** [`DetachedReticle.log`](file:///E:/Cyberpunk%202077/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/DetachedReticle.log)
- Initialized successfully at `00:32:54`:
  ```text
  [2026-10-30 00:32:54] [DetachedReticle] Initializing Decoupled Aiming System v2.0.0 | Enabled=true | Speed=6.0 | Deadzone=0.0 deg | MaxDiv=65.0 deg | Algorithm=exponential | T2BSettling=8.0 | T2BMaxSpd=240 deg/s
  [2026-10-30 00:32:54] [DetachedReticle] [SETTINGS] NativeSettings tab '/detachedReticle' successfully initialized.
  ```
- **Crucial Observation:** After `00:32:54`, CET logged zero errors. However, because CET lacked `onSessionStart` / `onSessionEnd` handlers, `onUpdate` continued executing 60 times per second through the entire loading screen, querying `Game.GetPlayer()`, calling `fpp:SetLocalTransform()`, and pushing deltas into `InputHook`.

### 2.3 Redscript Compiler Log (`redscript_rCURRENT.log`)
- **Path:** [`redscript_rCURRENT.log`](file:///E:/Cyberpunk%202077/r6/logs/redscript_rCURRENT.log)
- Redscript compilation completed cleanly with zero syntax errors.
- However, Redscript does not emit runtime warnings when a `@wrapMethod` on an engine event (`protected event OnPlayerDetach`) specifies a mismatched return type (`-> Bool` vs `-> Void`). The trampoline clobbered the expected return stack.

---

## 3. Minidump Heap & Disassembly Reconstruction

Analyzing the minidump at [`Cyberpunk2077-20261030-003604-401112-406300\Cyberpunk2077.dmp`](file:///C:/Users/fary2/AppData/Local/REDEngine/ReportQueue/Cyberpunk2077-20261030-003604-401112-406300/Cyberpunk2077.dmp):

### 3.1 Stack of the Spinning Worker Thread (`TID 401756`)
```text
[RSP+0x0000]: Cyberpunk2077.exe + 0x2723FD  (REDengine Pool Allocator)
[RSP+0x00F8]: Cyberpunk2077.exe + 0x270246  (Buffer Reallocator)
[RSP+0x0128]: Cyberpunk2077.exe + 0x4296E7  (game::EffectorSystem::ResizeBuffer)
[RSP+0x01C8]: Cyberpunk2077.exe + 0x21942C8  (EnqueueEffectorRequest)
[RSP+0x01D8]: Cyberpunk2077.exe + 0x2194205
[RSP+0x0238]: Cyberpunk2077.exe + 0x2193F00
[RSP+0x02A8]: Cyberpunk2077.exe + 0x21938B0  (game::EffectorSystem::ApplyEffectors Loop)
[RSP+0x0328]: Cyberpunk2077.exe + 0x4CB8D4  (game::EffectorSystem::ProcessRequests)
[RSP+0x0398]: Cyberpunk2077.exe + 0x4BA7B8  (helper::CallUpdateFn)
[RSP+0x03D8]: Cyberpunk2077.exe + 0x4BA5F3  (TaskExecutor)
[RSP+0x0458]: Cyberpunk2077.exe + 0x2735E3  (job::prv::DispatcherThread::DoWorkLoop)
```

### 3.2 The Infinite Loop Mechanism
1. In [`Cyberpunk2077.exe + 0x4CB8D4`](file:///E:/Cyberpunk%202077/bin/x64/Cyberpunk2077.exe), `game::EffectorSystem::ProcessRequests` is called as part of tick group `{G}PreBuckets` during session loading.
2. It passes the effector request queue (located at `gameEffectorSystem + 0x94`) to `ApplyEffectors` at RVA `0x21937BF`.
3. `ApplyEffectors` runs a while loop:
   ```x86asm
   0x21937F5: cmp  dword ptr [rbx+10h], 0    ; Check if request count == 0
   0x21937F9: je   0x21938B9                 ; Exit loop if empty
   0x21937FF: mov  eax, [rbx+14h]            ; Read head index
   0x219380B: call 0x2193AF0                 ; Pop 48-byte request struct
   0x2193822: dec  dword ptr [rbx+10h]        ; Decrement count
   0x2193836: call 0x2193DB0                 ; Apply effector
   0x21938B4: jmp  0x21937F5                 ; Loop back unconditionally!
   ```
4. When `0x2193DB0` is called for requests belonging to `PlayerPuppet` (`entityID = 1`) and the loaded scene entities (`9003197..9003201`), it invokes `0x2193F00` -> `0x2194260`.
5. `0x2194260` **inserts new requests back into the same effector queue** while `ApplyEffectors` is iterating over it.
6. The queue never reaches count 0; instead, it repeatedly doubles its capacity (allocating up to 425 entries) while pinning `redDispatcher10` at 100% CPU until Watchdog timeout aborts the engine.

---

## 4. Root Cause Breakdown: Why Previous Fixes Failed

| Previous Attempt | What Was Done | Why It Did Not Prevent The Freeze |
|---|---|---|
| **Iteration 33** | Added `player.IsAttached()` and `weapon.IsAttached()` checks in Redscript and CET. | During `State_SessionLoading`, the existing player entity remains "attached" until the session transition finishes. The checks evaluated to `true`. |
| **Iteration 34** | Fixed CET `fpp:IsAttached()` runtime crash. | Fixed the Lua error, allowing the script to execute cleanly, but did not stop execution during loading screens. |
| **Iteration 35** | Added `srh.IsGamePaused()` and `srh.IsPreGame()` checks to `UpdateDetachedAim()` and `onUpdate`. | **Both functions return `false` during save loading!** `IsPreGame()` is only true in the main menu; `IsGamePaused()` is false because `State_SessionLoading` unpauses the game loop. |
| **Iteration 35** | Added `OnPlayerDetach` in [`DetachedReticle.reds`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/r6/scripts/DetachedReticle/DetachedReticle.reds). | Declared as `protected cb func OnPlayerDetach(playerGameObject: ref<GameObject>) -> Bool`. Vanilla [`crosshairContainerController.script:53`](file:///e:/Cyberpunk%202077/tools/redmod/scripts/cyberpunk/UI/weapons/crosshairs/crosshairContainerController.script#L53) defines it as `event OnPlayerDetach(...) -> Void`. Mismatching the signature corrupts event callbacks. |
| **Pending Vector** | [`hmg_attack.yaml`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/r6/tweaks/DetachedReticle/hmg_attack.yaml) active in game directory. | Rewrote `Attacks.ExplodingBulletHMG.playerAttack` to `Attacks.ExplodingBulletMediumEffect` in global TweakDB. Triggers complex `BulletMediumExplosion` GLP and effector creation when restoring weapons on entities in `q003_after_deal_shootout`. |

---

## 5. Required Corrective Actions (Iteration 36)

To completely eliminate the save-load freeze:

1. **Gate CET with Session Lifecycle Events:**
   In [`bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua):
   - Listen to `onSessionStart` and `onSessionEnd`.
   - Set `DetachedReticle.isSessionActive = true` on `onSessionStart`.
   - Set `DetachedReticle.isSessionActive = false` on `onSessionEnd` and cleanly reset all native camera overrides.
   - At the very top of `onUpdate`, add:
     ```lua
     if not DetachedReticle.isSessionActive then return end
     ```

2. **Fix Redscript Crosshair Container Event Signatures:**
   In [`r6/scripts/DetachedReticle/DetachedReticle.reds`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/r6/scripts/DetachedReticle/DetachedReticle.reds):
   - Correct `OnInitialize`, `OnPlayerAttach`, `OnPlayerDetach`, and `OnUninitialize` to return `Void`:
     ```swift
     @wrapMethod(gameuiCrosshairContainerController)
     protected cb func OnPlayerDetach(playerGameObject: ref<GameObject>) -> Void {
         this.UninitDetachedReticle();
         wrappedMethod(playerGameObject);
     }
     ```
   - In `UpdateDetachedAim()`, guard with `player.IsAttached()`, `weapon.IsAttached()`, and check if `GameInstance.GetSystemRequestsHandler().IsLoadingSavedSession()` or similar session state is active.

3. **Neutralize Redundant HMG Tweak Override:**
   - Remove or delete [`r6/tweaks/DetachedReticle/hmg_attack.yaml`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/r6/tweaks/DetachedReticle/hmg_attack.yaml) from both the repository and `E:\Cyberpunk 2077\r6\tweaks\DetachedReticle\`.
   - In [`DetachedReticle.reds`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/r6/scripts/DetachedReticle/DetachedReticle.reds), remove `weapon.SetAttack(t"Attacks.ExplodingBulletMediumEffect")` and avoid mutating attack records during save restoration. Native PhysicalRay callsites in [`ShootingHook.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/ShootingHook.cpp) already handle muzzle redirection directly.
