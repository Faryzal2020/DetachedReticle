This document provides findings that are proven to be causing issues. This document is not the place for noting down the solution, only known mistakes.

- fpp is a gameFPPCameraComponent (an entIComponent), not an entity (entEntity).
- In REDengine / CET, components (entIComponent) do not have an IsAttached() method; calling it throws a runtime nil method exception. Entities (entEntity / GameObject / PlayerPuppet / WeaponObject) DO have IsAttached() (verified in reference/game-scripts: core/entity/entity.swift:30: public native func IsAttached() -> Bool).