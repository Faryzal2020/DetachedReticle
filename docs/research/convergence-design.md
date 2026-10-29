# Parallax and Convergence Design Decision

**Date:** 2026-10-29  
**Scope:** Cyberpunk 2077 Decoupled Aim Mod (`DetachedReticle`)  
**Design Reference:** `AGENTS.md` Section 1, `docs/review-2026-10-29-round5.md` Section 2

---

## 1. Context & The Parallax Problem

In Cyberpunk 2077's first-person perspective, weapon muzzle slots are displaced by approximately $0.2\text{ m}$ to $0.4\text{ m}$ laterally and vertically from the camera eye position. 
- The **camera crosshair** (Tier 1) represents the eye ray into world space.
- The **weapon reticle** (Tier 2B) represents the physical muzzle projection.
- If the weapon barrel is aligned strictly parallel to the player body/aim heading, the angular parallax between the eye ray and the muzzle ray varies with engagement distance according to $\theta \approx \arctan(\text{offset} / \text{distance})$:
  - At $2\text{ m}$ (point-blank): $\approx 6^\circ\text{ to }10^\circ$ separation ($\sim 180\text{--}300\text{ px}$).
  - At $15\text{ m}$ (medium range): $\approx 1^\circ$ separation ($\sim 30\text{ px}$).
  - At $50\text{ m}$ (long range): $< 0.3^\circ$ separation ($< 10\text{ px}$).

---

## 2. Decision: Dynamic Hit-Point Convergence via Slow Integral Screen-Trim

Per `AGENTS.md` section 1, DetachedReticle adopts **Option B: Dynamic Hit-Point Convergence via Slow Integral Screen-Trim**.

### Implementation Architecture:
1. **Body-Relative Anatomical Anchor (Primary Fixed Point $C = O$):**  
   The primary Tier 2B compensation loop operates strictly relative to the puppet body heading and actuation pitch:
   $$\text{diffYaw} = \text{normalizeDeg}(\text{gunYaw} - \text{bodyYaw})$$
   $$\text{diffPitch} = \text{gunPitch} - \text{t2bPitch}$$
   This removes the weapon's static rig offset ($O$) so the barrel aligns with the physical body look vector regardless of mouse motion.
2. **Slow Integral Screen Trim (Settled Rest Only):**  
   To eliminate distance-dependent parallax without executing expensive trace raycasts in the input loop, a slow integral term accumulates pixel error when the player is fully resting in a ready firing stance:
   $$\text{trimYaw} = \text{clamp}\left(\text{trimYaw} + \text{scrX} \cdot k_i \cdot \Delta t, -3.0^\circ, +3.0^\circ\right)$$
   $$\text{trimPitch} = \text{clamp}\left(\text{trimPitch} - \text{scrY} \cdot k_i \cdot \Delta t, -3.0^\circ, +3.0^\circ\right)$$
   where $k_i = 0.005\text{ deg}/(\text{px} \cdot \text{s})$.
3. **Motion Isolation:**  
   During dynamic mouse swings ($\text{rawGap} \ge 0.10^\circ$), the integral trim is **frozen**. Dynamic chase dynamics ($T1 \to T2A$) operate with 100% physical weight and zero closed-loop drag toward screen center.
4. **State Cleanup:**  
   Trim values reset to zero upon weapon swap or when holstered.
