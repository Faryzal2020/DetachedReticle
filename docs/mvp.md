### The Three-Tier System

| Tier | Component | Role | Driven By |
|---|---|---|---|
| **Tier 1** | **Camera Reticle** | *The Leader (Intended Aim Point)*: where the player's eyes are looking in 3D space. | Mouse input (instant, crisp, responsive). |
| **Tier 2** | **Aiming Direction** | *The Chained Anchor*: the reference heading of the character's body and base upper-body rig. | **Chained to Tier 1** via the weighting/smoothing algorithm. |
| **Tier 3** | **Gun Reticle** | *The Physical Muzzle*: where the barrel physically points and where bullets originate. | **Linked to Tier 2** naturally via vanilla skeletal animations, weapon sway, breathing, recoil, and resting/ready transitions. |

Because Tier 3 is already linked to Tier 2 via vanilla animations, we don't need to manually manipulate the physical weapon barrel or fake weapon sway. All we need to do is **chain Tier 2 (Aiming Direction) to Tier 1 (Camera Reticle)**.

MVP will be regarded as success if the camera doesn't wobble, doesn't move by anything except player's mouse. and the Aiming Direction should be detached from camera but still follows the camera with some delay and lag (adjustable). Shooting the gun will make the bullet went to the gun reticle, not aiming direction, not camera reticle.
The method for attaching Aiming direction to Camera reticle is tricky and none of recent implementations and assumptions are working. Assumptions that are not working need to be tracked so it wont be repeated.

---

### How the Chaining Algorithm Works

In our current freelook MVP:
- The mouse changes the camera gaze $\mathbf{Q}_{\text{cam}}$ immediately.
- The angular difference between the camera gaze and the aiming direction is:
  $$\Delta_{\text{aim}} = (\text{yawLag},\ \text{pitchLag})$$
- Currently, $\Delta_{\text{aim}}$ is held frozen (pure freelook).

In the **chained MVP**:
On every frame $\Delta t$, the Aiming Direction rotates toward the Camera Reticle using a weighted smoothing model:

$$\mathbf{Q}_{\text{aim}}(t + \Delta t) = \text{Slerp}\left(\mathbf{Q}_{\text{aim}}(t),\ \mathbf{Q}_{\text{cam}}(t),\ 1 - e^{-\lambda \cdot \Delta t}\right)$$

where $\lambda$ is the **tracking weight / catch-up speed**:
1. When you glance or move the mouse, the **Camera Reticle moves instantly**.
2. The **Aiming Direction smoothly rotates to catch up** with realistic inertia and mass.
3. The **Gun Reticle naturally lags behind**, swinging smoothly toward the camera reticle with the weapon's natural hand sway and weight.
4. When you stop moving the mouse, the Aiming Direction catches up, and the Gun Reticle smoothly settles onto the target.

---

