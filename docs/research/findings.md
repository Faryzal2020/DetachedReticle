- "Vector4.Normalize3()" causes crash at startup; wrong method name
- require("ffi") causes crash

#iteration 1
- error: Redscript failed to parse and compile ShootEvents.OnEnter on startup.
- error cause: 
  - Line 396 declared `protected export function OnEnter(...)`: redscript syntax does not have `export` and uses `func`, not `function`.
  - Lines 541 & 573 used empty argument syntax `, , true` in `TriggerSingleBroadcast`, which is illegal syntax in redscript.
  - Lines 493 & 494 passed references directly to `EffectData.SetVariant` without `ToVariant(...)`.
  - Line 467 used `new Vector4(...)`, but `Vector4` is a struct (value type), not a class.
  - Lines 542 & 582 used non-existent `Equals(...)` helper on enums instead of `==`.
- fix:
  - Changed method signature to `protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void`.
  - Declared `emptyInvestigateData: stimInvestigateData` and passed it to `TriggerSingleBroadcast` calls.
  - Wrapped `attackObj` and `statMods` with `ToVariant(...)` in `EffectData.SetVariant`.
  - Replaced `new Vector4(...)` with `Vector4(...)`.
  - Replaced `Equals(...)` with `==`.
(user test timestamp: 2026-10-27 22:15:12 +0700)

#iteration 2
- error: `[NO_MATCHING_OVERLOAD] At r6\scripts\DetachedReticle\DetachedReticle.reds:424:21: muzzleFxScale = statsSystem.GetStatValue(weapon.GetEntityID(), ...); arguments passed to 'GetStatValue' do not match any of the overloads: 1st argument: expected 'StatsObjectID', given 'EntityID'`
- error cause: Redscript is strictly typed and does not implicitly coerce `EntityID` to `StatsObjectID` when invoking `StatsSystem.GetStatValue` or `StatPoolsSystem.GetStatPoolValue`.
- fix: Wrapped all entity ID parameters with `Cast<StatsObjectID>(...)` across lines 424, 428, 538, 550, 581, and 583.
(user test timestamp: pending user verification)