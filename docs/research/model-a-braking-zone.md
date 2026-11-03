# Model A: Rate-Limited Saccade with Smoothstep Braking Zone

**Date:** 2026-11-03  
**Status:** Implemented (Feature Branch `feature/model-a-braking-zone`)  
**Scope:** Cyberpunk 2077 Decoupled Aim Mod (`DetachedReticle`)  
**Design Reference:** `docs/research/convergence-design.md`, `src/Hooks/InputHook.cpp`, `init.lua`

---

## 1. Intent & Motivation

In the baseline version of `DetachedReticle`, physical aim chase from camera gaze ($T1$) to weapon orientation ($T2A$) was driven exclusively by a first-order exponential decay filter:

$$\frac{dA}{dt} = \lambda \cdot (T - A)$$

While exponential smoothing is framerate-independent and prevents overshoot, it suffers from a fundamental human-feel drawback: **the asymptotic tail**.

Because velocity is strictly proportional to remaining distance ($v \propto \text{gap}$), speed drops off continuously from the very first frame of motion. By the time the weapon gets within $2^\circ$ of the camera crosshair, speed has already dropped by $> 90\%$. The reticle then spends the vast majority of its total travel time creeping through the last few degrees ("tail crawl"), making the weapon feel sluggish to settle onto target after a flick.

### Design Goal
1. **Maintain high, constant cruising speed** throughout large mouse flicks.
2. **Delay deceleration until the weapon is close to the target** (e.g. within $2.0^\circ$).
3. **Decelerate rapidly and smoothly** within that braking window using a zero-acceleration boundary curve (Hermite smoothstep), eliminating both abrupt snapping and asymptotic creeping.
4. **Preserve the Exponential model** as an instant toggle for players who prefer traditional passive sway.

---

## 2. Mathematical Formulation

Model A splits the chase into two distinct kinematic phases based on the 2D Euclidean angular distance between camera gaze and physical aim:

$$\text{gapMag} = \sqrt{\text{effGapYaw}^2 + \text{effGapPitch}^2}$$

### Phase 1: Cruising Phase ($\text{gapMag} > \theta_{\text{brake}}$)
When the weapon is farther than the braking threshold $\theta_{\text{brake}}$ (default $2.0^\circ$), it travels at constant maximum angular speed $\omega_{\max}$ along the normalized 2D direction vector:

$$v = \omega_{\max}$$
$$\Delta A = \omega_{\max} \cdot \Delta t \cdot \frac{\vec{\text{gap}}}{\text{gapMag}}$$

*(If $\Delta A > \text{gapMag}$, $\Delta A$ is clamped to $\text{gapMag}$ to prevent overshoot).*

### Phase 2: Smoothstep Braking Phase ($0.02^\circ < \text{gapMag} \le \theta_{\text{brake}}$)
Inside the braking window, the distance is normalized:

$$u = \frac{\text{gapMag}}{\theta_{\text{brake}}} \in (0, 1]$$

A cubic Hermite smoothstep curve calculates the velocity scaling factor:

$$S(u) = 3u^2 - 2u^3$$
$$v = \omega_{\max} \cdot S(u)$$

Because $\frac{dS}{du} = 6u - 6u^2$:
- At $u = 1$ (entering the braking zone): $S(1) = 1$ and $\frac{dS}{du} = 0$, producing a seamless $C^1$-continuous transition from constant cruising speed into deceleration.
- At $u = 0$ (arriving at target): $S(0) = 0$ and $\frac{dS}{du} = 0$, ensuring the deceleration comes to rest with zero jerk.

### Phase 3: Sub-Pixel Resting Snap ($\text{gapMag} \le 0.02^\circ$)
At $\le 0.02^\circ$ (sub-pixel scale on 1080p/1440p displays), the remaining gap is closed immediately:

$$\Delta A = \vec{\text{gap}}$$

This cuts off infinitesimal floating-point remainder steps, ensuring crisp, definitive resting stability with zero jitter.

---

## 3. Motion Profile Comparison

```
Velocity
  ^
  |        [ Cruise at Max Speed: 360 deg/s ]
  |  ____________________________________________
  |                                              \
  |                                               \ [ Smoothstep Brake Zone ]
  +------------------------------------------------+----------> Distance to T1
                                                   0   (e.g. 2.0°)
```

| Metric | Mode 0: Exponential Decay | Mode 1: Model A (Braking Zone) |
|---|---|---|
| **Speed at $20^\circ$ gap** | Peak ($20 \lambda \approx 120^\circ/\text{s}$) | Cruising speed ($\omega_{\max} = 360^\circ/\text{s}$) |
| **Speed at $2^\circ$ gap** | Decelerated by $90\%$ ($12^\circ/\text{s}$) | **100% cruising speed ($360^\circ/\text{s}$)** |
| **Speed at $1^\circ$ gap** | $6^\circ/\text{s}$ (crawl) | $180^\circ/\text{s}$ (active braking) |
| **Settling Feel** | Soft, trailing, slow finish | **Crisp, snappy, definitive stop** |
| **Best Used For** | Heavy cinematic weapons, slow sway | Snappy, competitive gunplay |

---

## 4. Implementation Details

### Native C++ Plugin (`DetachedReticle.dll`)
1. **[`InputHook.hpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.hpp):**
   - Added `s_brakeThreshold` (default `2.0f` deg) and `s_brakeMaxSpeed` (default `360.0f` deg/s).
   - Added declarations for `SetBrakeParams`, `GetBrakeThreshold`, `GetBrakeMaxSpeed`.
2. **[`InputHook.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.cpp):**
   - Implemented `s_mode` branching in `ProcessMouseAim`:
     - `s_mode == 0`: Exponential decay filter.
     - `s_mode == 1`: Model A rate-limited saccade with smoothstep braking zone.
   - Implemented `SetBrakeParams`, `GetBrakeThreshold`, `GetBrakeMaxSpeed`.
3. **[`Main.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Main.cpp):**
   - Registered `DR_SetBrakeParams(threshold: Float, maxSpeed: Float)`, `DR_GetBrakeThreshold() -> Float`, and `DR_GetBrakeMaxSpeed() -> Float` in REDengine RTTI.

### CET Lua Script (`init.lua`) & Config (`config.json`)
1. **Configuration:** Added `brakeThreshold: 2.0`, `brakeMaxSpeed: 360.0`, and default `smoothingMode: "braking"`.
2. **`SyncSmoothing()` Helper:** Automatically syncs mode integer (`"braking"` $\to 1$, `"exponential"` $\to 0$) and brake parameters to the native DLL on activation and whenever options change.
3. **ImGui Overlay & NativeSettings:**
   - Added `Braking (Model A)` option to the Catch-Up Algorithm radio/dropdown menu.
   - Added interactive sliders for `Braking Zone` ($0.5^\circ$ to $10.0^\circ$) and `Max Cruise Speed` ($60^\circ/\text{s}$ to $1200^\circ/\text{s}$).
4. **Console API:**
   - `DetachedReticle.SetSmoothingMode("braking")` / `DetachedReticle.SetSmoothingMode("exponential")`
   - `DetachedReticle.SetBrakeThreshold(degrees)`
   - `DetachedReticle.SetBrakeMaxSpeed(degPerSec)`

---

## 5. Tuning Guide

- **Fast & Snappy (Default Recommended):**
  - Algorithm: `Braking (Model A)`
  - Braking Zone: `2.0 deg`
  - Max Cruise Speed: `360 deg/s`
- **Ultra-Aggressive / Competitive:**
  - Algorithm: `Braking (Model A)`
  - Braking Zone: `1.2 deg`
  - Max Cruise Speed: `500 deg/s`
- **Heavy / Cinematic (Alternative):**
  - Algorithm: `Exponential`
  - Catch-up Speed: `5.0`
