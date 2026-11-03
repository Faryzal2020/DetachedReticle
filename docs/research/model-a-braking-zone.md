# Dual-Model Decoupled Aim: Model A (Braking Zone) & Exponential (Option 1 Tail-Cutter)

**Date:** 2026-11-03  
**Status:** Implemented (Feature Branch `feature/model-a-braking-zone`)  
**Scope:** Cyberpunk 2077 Decoupled Aim Mod (`DetachedReticle`)  
**Design Reference:** `docs/research/convergence-design.md`, `src/Hooks/InputHook.cpp`, `init.lua`

---

## 1. Intent & Motivation

In the baseline version of `DetachedReticle`, physical aim chase from camera gaze ($T1$) to weapon orientation ($T2A$) was driven exclusively by a first-order exponential decay filter:

$$\frac{dA}{dt} = \lambda \cdot (T - A)$$

While exponential smoothing is framerate-independent and prevents overshoot, it suffers from a fundamental human-feel drawback: **the asymptotic tail**.

Because velocity is strictly proportional to remaining distance ($v \propto \text{gap}$), speed drops off continuously from the very first frame of motion. By the time the weapon gets within $1^\circ\text{--}2^\circ$ of the camera crosshair, speed has already dropped by $> 90\%$. The reticle then spends the vast majority of its total travel time creeping through the last few degrees ("tail crawl"), making the weapon feel sluggish to settle onto target after a flick.

---

## 2. Model Implementations

### Mode 1: Model A — Rate-Limited Saccade with Smoothstep Braking Zone

Model A splits the chase into two distinct kinematic phases based on the 2D Euclidean angular distance between camera gaze and physical aim:

$$\text{gapMag} = \sqrt{\text{effGapYaw}^2 + \text{effGapPitch}^2}$$

1. **Cruising Phase ($\text{gapMag} > \theta_{\text{brake}}$):**
   When the weapon is farther than the braking threshold $\theta_{\text{brake}}$ (default $2.0^\circ$), it travels at constant maximum angular speed $\omega_{\max}$ along the normalized 2D direction vector:
   $$v = \omega_{\max}$$
   $$\text{step} = \omega_{\max} \cdot \Delta t$$

2. **Smoothstep Braking Phase ($0.02^\circ < \text{gapMag} \le \theta_{\text{brake}}$):**
   Inside the braking window, the distance is normalized $u = \frac{\text{gapMag}}{\theta_{\text{brake}}} \in (0, 1]$.
   A cubic Hermite smoothstep curve calculates the velocity scaling factor:
   $$S(u) = 3u^2 - 2u^3$$
   $$v = \omega_{\max} \cdot S(u)$$
   $$\text{step} = v \cdot \Delta t$$

   > [!IMPORTANT]
   > **Camera-Pull Prevention (Multi-Frame Deceleration Bound):**  
   > If $\omega_{\max} \cdot \Delta t$ is large (e.g. $6.0^\circ/\text{frame}$ at 60 FPS), clamping `step = gapMag` would cause the weapon to snap the entire remaining $1.5^\circ\text{--}2.0^\circ$ into the target in a single frame. Because the player camera is attached to the puppet body, this sudden 1-frame body delta causes a visible 1-frame camera jerk/pull due to sub-frame tick phase skew between native input and CET's `onUpdate`.  
   > To prevent this, the per-frame step inside the braking zone is bounded by:
   > $$\text{maxBrakeStep} = \max(0.04^\circ,\; \text{gapMag} \cdot 0.35)$$
   > This guarantees the deceleration is smoothly distributed across 5 to 8 frames, completely eliminating camera pull.

3. **Sub-Pixel Resting Snap ($\text{gapMag} \le 0.02^\circ$):**
   At $\le 0.02^\circ$ (sub-pixel scale), the remaining gap is closed immediately to eliminate infinitesimal floating-point remainder steps.

---

### Mode 0: Exponential Model (Option 1: Minimum Speed Floor / Tail-Cutter)

For players who prefer the natural, organic curve of exponential smoothing, **Option 1** eliminates the sluggish asymptotic tail while preserving 100% of the natural exponential feel during mouse swings:

1. **Exponential Swing Phase:**
   $$\text{expStep} = \text{gapMag} \cdot (1 - e^{-\lambda \Delta t})$$
2. **Speed Floor Phase:**
   When the gap shrinks and exponential velocity drops below the configured floor `expMinSpeed` (default $12.0^\circ/\text{s}$), the step is clamped to:
   $$\text{minStep} = \text{expMinSpeed} \cdot \Delta t$$
   $$\text{step} = \max(\text{expStep},\; \min(\text{minStep},\; \text{gapMag}))$$
3. **Behavior:**
   - Wide flicks move with natural, organic exponential deceleration.
   - Once inside the final $1.0^\circ\text{--}2.0^\circ$, instead of crawling for 30+ frames, the weapon finishes the remaining distance at a steady, crisp $12.0^\circ/\text{s}$ ($\approx 0.20^\circ/\text{frame}$ at 60 FPS), taking only $\sim 5$ frames to land cleanly on target.
   - Setting `expMinSpeed = 0.0` restores pure vanilla exponential decay.

---

## 3. Motion Profile Comparison

```
Velocity
  ^
  |        [ Model A: Cruise at Max Speed ]
  |  ____________________________________________
  |                                              \
  |                                               \ [ Smoothstep Multi-Frame Decel ]
  +------------------------------------------------+----------> Distance to T1
                                                   0   (e.g. 2.0°)
```

```
Velocity
  ^
  | [ Exponential Option 1: Natural Exponential Decay ]
  | \
  |  \
  |   \
  |    \__________ [ Steady expMinSpeed Floor (e.g. 12 deg/s) ]
  |               \ [ Clean Rest ]
  +----------------+-------------------------------------------> Distance to T1
                   0 (e.g. 1.0°)
```

| Metric | Pure Exponential (Old) | Exponential + Option 1 (`expMinSpeed = 12`) | Model A (Braking Zone) |
|---|---|---|---|
| **Speed at $20^\circ$ gap** | $\approx 120^\circ/\text{s}$ | $\approx 120^\circ/\text{s}$ (100% identical) | Cruising speed ($360^\circ/\text{s}$) |
| **Speed at $2^\circ$ gap** | $12^\circ/\text{s}$ | $12^\circ/\text{s}$ | High speed ($\sim 180^\circ/\text{s}$) |
| **Speed at $0.5^\circ$ gap** | $3^\circ/\text{s}$ (crawling) | **$12^\circ/\text{s}$ (crisp approach)** | Controlled multi-frame decel |
| **Frames to settle final $1^\circ$** | $> 30$ frames | **$\sim 5$ frames** | $\sim 5\text{--}7$ frames |
| **Settling Feel** | Sluggish, soft crawl | **Natural swing + decisive finish** | **Saccadic flick + snappy brake** |

---

## 4. Configuration & Dedicated Parameters

### Native RTTI APIs (`DetachedReticle.dll`)
- `DR_SetSmoothing(lambda: Float, mode: Int32, maxDiv: Float, deadzone: Float, enabled: Bool)`
- `DR_SetBrakeParams(threshold: Float, maxSpeed: Float)`
- `DR_GetBrakeThreshold() -> Float`
- `DR_GetBrakeMaxSpeed() -> Float`
- `DR_SetExpParams(minSpeed: Float)`
- `DR_GetExpMinSpeed() -> Float`

### Config & CET Options (`config.json` & `init.lua`)
- **`smoothingMode`:** `"exponential"` or `"braking"`
- **Model A Parameters:**
  - `brakeThreshold`: Distance from camera gaze where deceleration begins ($0.5^\circ$ to $10.0^\circ$, default: `2.0 deg`).
  - `brakeMaxSpeed`: Cruising speed outside braking zone ($60^\circ/\text{s}$ to $1200^\circ/\text{s}$, default: `360 deg/s`).
- **Exponential Model Parameters:**
  - `catchUpSpeed`: Chase rate constant $\lambda$ ($0.0$ to $30.0$, default: `6.0`).
  - `expMinSpeed`: Minimum speed floor ($0.0$ to $30.0^\circ/\text{s}$, default: `12.0 deg/s`).

### CET Console Commands
- `DetachedReticle.SetSmoothingMode("exponential")` / `DetachedReticle.SetSmoothingMode("braking")`
- `DetachedReticle.SetExpMinSpeed(12.0)`
- `DetachedReticle.SetBrakeThreshold(2.0)`
- `DetachedReticle.SetBrakeMaxSpeed(360.0)`
