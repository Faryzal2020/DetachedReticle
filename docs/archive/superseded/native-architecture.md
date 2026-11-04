# Native RED4ext Plugin Architecture — DetachedReticle

## 1. Overview & Project Purpose
In Phase 1 testing, we verified that REDengine 4 rigidly parents the first-person arm mesh (`w_arms_fpp`) to [`FPPCameraComponent`](file:///e:/Cyberpunk%202077/tools/redmod/scripts/core/components/cameraComponent.script#L24). Manipulating [`FPPCameraComponent`](file:///e:/Cyberpunk%202077/tools/redmod/scripts/core/components/cameraComponent.script#L24) in script causes the entire arm and gun mesh to rotate with the camera, which created feedback oscillations and swung the weapon ahead of the turn rather than lagging behind.

To decouple the physical weapon orientation from the camera view:
1. **The camera view** remains 100% freelook-controlled by the player's mouse at screen center $(0, 0)$.
2. **The 3D weapon and arm mesh** are rotated independently in world/model space during REDengine's native animation evaluation pass.
3. **Hitscan bullet rays** (`PhysicalRay::Execute`) are redirected along the weapon's decoupled muzzle vector so shots physically strike the off-center crosshair.

---

## 2. Project Layout
```
DetachedReticle/
├── CMakeLists.txt              # CMake C++20 build definition (fetches RED4ext.SDK & MinHook)
├── src/
│   ├── Main.cpp                # RED4ext plugin entry points (Query, Supports, Main)
│   └── Hooks/
│       ├── AnimationHook.hpp   # Intercepts bone matrix evaluation for RightForeArm/Weapon
│       ├── AnimationHook.cpp
│       ├── ShootingHook.hpp    # Intercepts PhysicalRay::Execute hitscan raycast
│       └── ShootingHook.cpp
├── r6/
│   └── scripts/DetachedReticle/
│       └── DetachedReticle.reds # ScriptableSystem providing telemetry and 2D crosshairs
└── red4ext/
    └── plugins/DetachedReticle/
        └── DetachedReticle.dll  # Compiled native plugin binary
```

---

## 3. Required Build Toolchain
* **Compiler**: Microsoft Visual C++ (MSVC) v143 (Visual Studio 2022) with C++20 standard support.
* **Build System**: CMake $\ge 3.22$.
* **SDK**: `RED4ext.SDK` v2.5.0 (compatible with RED4ext v1.31.0 on Cyberpunk 2077 v2.2+).
* **Hooking Engine**: MinHook v1.3.3.

### How to Install C++ Build Tools (if not yet installed)
Open the **Visual Studio Installer** on your system:
1. Select **Modify** on `Visual Studio Community 2022`.
2. Check the workload **"Desktop development with C++"** (includes MSVC v143, CMake tools for Windows, and Windows 10/11 SDK).
3. Click **Modify** to complete installation.

### Building with CMake
```powershell
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```
The output DLL will be produced at:
`build/Release/DetachedReticle.dll` and deployed to `E:\Cyberpunk 2077\red4ext\plugins\DetachedReticle\DetachedReticle.dll`.
