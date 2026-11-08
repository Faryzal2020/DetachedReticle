#include "InputHook.hpp"

#include <windows.h>
#include <sstream>
#include <fstream>
#include <iomanip>
#include <cstring>
#include <chrono>
#include <cmath>
#include <algorithm>

namespace DetachedReticle {

static uintptr_t s_exeBase = 0;

// Verified RVA in Cyberpunk2077.exe (Build 2.50 / Patch 2.5):
// Primary Gameplay Mouse Look Integrator at RVA 0x51D462:
//   movss dword ptr [rcx+9Ch], xmm6    (8 bytes: F3 0F 11 B1 9C 00 00 00)
// Inputs:
//   rcx:   Player puppet orientation controller ([rax+8])
//   xmm6:  Body Yaw Delta (post-sensitivity, includes [rsp+48h] recoil yaw delta)
//   xmm7:  Camera Pitch Delta (post-sensitivity, includes [rsp+44h] recoil pitch delta)
static constexpr uintptr_t kWaLookCallsiteRva = 0x51D462;
static constexpr uint8_t kWaLookDisplacedBytes[] = {
    0xF3, 0x0F, 0x11, 0xB1, 0x9C, 0x00, 0x00, 00
};

static void* WaAllocRelayNear(uint8_t* target) {
    SYSTEM_INFO si{};
    GetSystemInfo(&si);
    const uintptr_t gran = si.dwAllocationGranularity ? si.dwAllocationGranularity : 0x10000;
    const uintptr_t ta = reinterpret_cast<uintptr_t>(target);
    for (uintptr_t dist = gran; dist < 0x70000000ull; dist += gran) {
        uintptr_t cand[2] = { ta + dist, ta > dist ? ta - dist : 0 };
        for (uintptr_t c : cand) {
            if (!c) continue;
            c &= ~(gran - 1);
            void* m = VirtualAlloc(reinterpret_cast<void*>(c), gran, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE);
            if (m) return m;
        }
    }
    return nullptr;
}

static bool WaInstallLookPatch(uintptr_t siteRva, void* hook, uint8_t*& relayOut) {
    if (!s_exeBase) return false;
    uint8_t* callsite = reinterpret_cast<uint8_t*>(s_exeBase + siteRva);
    if (std::memcmp(callsite, kWaLookDisplacedBytes, sizeof(kWaLookDisplacedBytes)) != 0) {
        return false;
    }

    relayOut = reinterpret_cast<uint8_t*>(WaAllocRelayNear(callsite));
    if (!relayOut) return false;

    // 64-bit absolute jmp relay:
    // mov rax, <hook>
    // jmp rax
    uint8_t relay[12] = { 0x48, 0xB8, 0,0,0,0,0,0,0,0, 0xFF, 0xE0 };
    const uint64_t destination = reinterpret_cast<uint64_t>(hook);
    std::memcpy(relay + 2, &destination, sizeof(destination));
    std::memcpy(relayOut, relay, sizeof(relay));
    FlushInstructionCache(GetCurrentProcess(), relayOut, sizeof(relay));

    const intptr_t delta = relayOut - (callsite + 5);
    if (delta < INT32_MIN || delta > INT32_MAX) return false;

    // 5-byte CALL to near relay + 3 NOPs to replace 8-byte instruction:
    uint8_t patch[8] = {
        0xE8,
        static_cast<uint8_t>(delta & 0xFF),
        static_cast<uint8_t>((delta >> 8) & 0xFF),
        static_cast<uint8_t>((delta >> 16) & 0xFF),
        static_cast<uint8_t>((delta >> 24) & 0xFF),
        0x90, 0x90, 0x90
    };

    DWORD oldProtect = 0;
    if (!VirtualProtect(callsite, sizeof(patch), PAGE_EXECUTE_READWRITE, &oldProtect)) return false;
    std::memcpy(callsite, patch, sizeof(patch));
    FlushInstructionCache(GetCurrentProcess(), callsite, sizeof(patch));
    DWORD ignored = 0;
    VirtualProtect(callsite, sizeof(patch), oldProtect, &ignored);
    return true;
}

bool InputHook::Initialize(RED4ext::v1::PluginHandle aHandle, const RED4ext::v1::Sdk* aSdk) {
    s_handle = aHandle;
    s_sdk = aSdk;

    HMODULE hExe = GetModuleHandleA("Cyberpunk2077.exe");
    if (hExe) {
        s_exeBase = reinterpret_cast<uintptr_t>(hExe);
    }

    // Install primary gameplay look hook at RVA 0x51D462
    if (WaInstallLookPatch(kWaLookCallsiteRva, reinterpret_cast<void*>(&MouseLookRelay), s_lookRelay)) {
        s_isHooked = true;
        if (s_sdk && s_sdk->logger) {
            s_sdk->logger->Info(s_handle, "InputHook: Native gameplay look hook installed at RVA 0x51D462.");
        }
        PushEvent("[N0] exe=0x" + (std::stringstream() << std::hex << s_exeBase).str() + " site=0x51D462 bytesOK=1 patched=1");
    } else {
        if (s_sdk && s_sdk->logger) {
            s_sdk->logger->Error(s_handle, "InputHook: Failed to patch gameplay look at RVA 0x51D462.");
        }
        PushEvent("[N0] exe=0x" + (std::stringstream() << std::hex << s_exeBase).str() + " site=0x51D462 bytesOK=0 patched=0");
    }

    s_isInitialized = true;
    return true;
}


void InputHook::Shutdown() {
    s_isInitialized = false;
    s_isHooked = false;
}

void InputHook::ResetChase(float aInitialPitch) {
    s_targetYaw = 0.0f;
    s_targetPitch = aInitialPitch;
    s_aimYaw = 0.0f;
    s_aimPitch = aInitialPitch;
    s_residualYaw = 0.0f;
    s_residualPitch = 0.0f;
    s_displayTargetYaw = 0.0f;
    s_displayAimYaw = 0.0f;
    s_targetCompYaw = 0.0f;
    s_targetCompPitch = 0.0f;
    s_compYaw = 0.0f;
    s_compPitch = 0.0f;
    s_displayT2BYaw = 0.0f;
    s_displayT2BPitch = aInitialPitch;
    s_recoilYaw = 0.0f;
    s_recoilPitch = 0.0f;
    s_recoilPeakYaw = 0.0f;
    s_recoilPeakPitch = 0.0f;
    s_nativeRecoilYaw = 0.0f;
    s_nativeRecoilPitch = 0.0f;
    s_nativeRecoilPeakYaw = 0.0f;
    s_nativeRecoilPeakPitch = 0.0f;
    s_recoilDriftPitch = 0.0f;
    s_recoilRecovering = false;
    s_recoilIdleTimer = 0.0f;
    s_lastDRecoilYaw = 0.0f;
    s_lastDRecoilPitch = 0.0f;
    s_splitErrYaw = 0.0f;
    s_splitErrPitch = 0.0f;
    s_shotKickTimer = 0.0f;
    s_prevDRecoilPitch = 0.0f;
    s_lastTime = std::chrono::steady_clock::now();
    s_smoothedDt = 1.0f / 60.0f;
}

void InputHook::SetBarrelOffset(float aYaw, float aPitch) {
    s_targetCompYaw = std::clamp(aYaw, -10.0f, 10.0f);
    s_targetCompPitch = std::clamp(aPitch, -10.0f, 10.0f);
}

void InputHook::SetCompParams(float aSpeedSettled, float aSpeedMoving, float aMaxSpeed, float aGapThreshold, float aMinSpeed) {
    s_compSpeedSettled = (aSpeedSettled > 0.1f) ? aSpeedSettled : 0.1f;
    s_compSpeedMoving = (aSpeedMoving > 0.1f) ? aSpeedMoving : 0.1f;
    s_compMaxSpeed = (aMaxSpeed > 10.0f) ? aMaxSpeed : 10.0f;
    s_compGapThreshold = (aGapThreshold > 0.1f) ? aGapThreshold : 0.1f;
    s_compMinSpeed = (aMinSpeed >= 0.0f) ? aMinSpeed : 0.0f;
}

float InputHook::GetCompSpeedSettled() { return s_compSpeedSettled; }
float InputHook::GetCompSpeedMoving() { return s_compSpeedMoving; }
float InputHook::GetCompMaxSpeed() { return s_compMaxSpeed; }
float InputHook::GetCompGapThreshold() { return s_compGapThreshold; }
float InputHook::GetCompMinSpeed() { return s_compMinSpeed; }

void InputHook::SetBrakeParams(float aThreshold, float aMaxSpeed) {
    s_brakeThreshold = (aThreshold > 0.05f) ? aThreshold : 0.05f;
    s_brakeMaxSpeed = (aMaxSpeed > 10.0f) ? aMaxSpeed : 10.0f;
}
float InputHook::GetBrakeThreshold() { return s_brakeThreshold; }
float InputHook::GetBrakeMaxSpeed() { return s_brakeMaxSpeed; }

void InputHook::SetExpParams(float aPower) {
    s_expPower = std::clamp(aPower, 0.1f, 1.5f);
}
float InputHook::GetExpPower() { return s_expPower; }

void InputHook::SetRecoilLeashParams(float aMaxRadius, float aLeashCurve) {
    s_recoilMaxRadius = std::clamp(aMaxRadius, 0.0f, 45.0f);
    s_recoilLeashCurve = std::clamp(aLeashCurve, 0.2f, 6.0f);
}
float InputHook::GetRecoilMaxRadius() { return s_recoilMaxRadius; }
float InputHook::GetRecoilLeashCurve() { return s_recoilLeashCurve; }

void InputHook::SetChaseLeashParams(bool aEnabled, float aStartDist, float aMaxDist, float aStiffness) {
    s_chaseLeashEnabled = aEnabled;
    s_chaseLeashStart = std::clamp(aStartDist, 1.0f, 60.0f);
    s_chaseLeashMax = std::clamp(aMaxDist, s_chaseLeashStart + 0.5f, 90.0f);
    s_chaseLeashStiffness = std::clamp(aStiffness, 0.2f, 5.0f);
}
bool InputHook::GetChaseLeashEnabled() { return s_chaseLeashEnabled; }
float InputHook::GetChaseLeashStart() { return s_chaseLeashStart; }
float InputHook::GetChaseLeashMax() { return s_chaseLeashMax; }
float InputHook::GetChaseLeashStiffness() { return s_chaseLeashStiffness; }

void InputHook::SetRecoilHorizontalParams(bool aStatScaling, float aScatter, float aDamping, float aStrengthFactor) {
    s_recoilHoriStatScaling = aStatScaling;
    s_recoilHoriScatter = std::clamp(aScatter, 0.0f, 4.0f);
    s_recoilHoriDamping = std::clamp(aDamping, 0.0f, 1.0f);
    s_playerStrengthFactor = std::clamp(aStrengthFactor, 0.0f, 1.0f);
}
bool InputHook::GetRecoilHoriStatScaling() { return s_recoilHoriStatScaling; }
float InputHook::GetRecoilHoriScatter() { return s_recoilHoriScatter; }
float InputHook::GetRecoilHoriDamping() { return s_recoilHoriDamping; }
float InputHook::GetPlayerStrengthFactor() { return s_playerStrengthFactor; }

static float NextRecoilRand01() {
    uint32_t x = InputHook::s_rngState;
    if (x == 0) x = 0xA341316Cu;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    InputHook::s_rngState = x;
    return static_cast<float>(x & 0x00FFFFFFu) / static_cast<float>(0x01000000u);
}

void InputHook::SetSmoothing(float aLambda, int32_t aMode, float aMaxDiv, float aDeadzone, bool aEnabled) {
    s_lambda = aLambda;
    s_mode = aMode;
    s_maxDiv = aMaxDiv;
    s_deadzone = aDeadzone;
    if (aEnabled && !s_enabled) {
        ResetChase(s_aimPitch);
    }
    s_enabled = aEnabled;
}

void InputHook::ProcessMouseAim(void* aFpp, float aRawYaw, float aRawPitch, const float* aSplitProbe, float& outYaw, float& outPitch) {
    if (!s_enabled) {
        outYaw = aRawYaw;
        outPitch = aRawPitch;
        return;
    }

    auto now = std::chrono::steady_clock::now();
    float rawDt = std::chrono::duration<float>(now - s_lastTime).count();
    s_lastTime = now;
    if (rawDt <= 0.0f || rawDt > 0.1f) rawDt = 1.0f / 60.0f;
    if (s_smoothedDt <= 0.0f || s_smoothedDt > 0.1f) {
        s_smoothedDt = rawDt;
    } else {
        s_smoothedDt = 0.75f * s_smoothedDt + 0.25f * rawDt;
    }
    float dt = s_smoothedDt;

    // 0. Extract native weapon recoil/sway delta ([rsp+128h]/[rsp+124h]) vs pure mouse look delta ([rbp-78h]/[rbp-7Ch])
    float dRecoilYaw = 0.0f;
    float dRecoilPitch = 0.0f;
    float dMouseYaw = aRawYaw;
    float dMousePitch = aRawPitch;
    if (aSplitProbe) {
        dRecoilYaw = aSplitProbe[0];
        dRecoilPitch = aSplitProbe[1];
        dMouseYaw = aSplitProbe[2];
        dMousePitch = aSplitProbe[3];
    }

    s_lastDRecoilYaw = dRecoilYaw;
    s_lastDRecoilPitch = dRecoilPitch;

    // Pure player look input delta (strips native weapon recoil/sway while preserving mouse + gamepad stick)
    float dInputYaw = aRawYaw - dRecoilYaw;
    float dInputPitch = aRawPitch - dRecoilPitch;

    // Probe P-R1: Stack frame split invariant verification
    s_splitErrYaw = dInputYaw - dMouseYaw;
    s_splitErrPitch = dInputPitch - dMousePitch;

    // 1. Advance Tier 1 Camera Target T with pure player input deflection (free of weapon recoil)
    s_targetYaw += dInputYaw;
    s_targetPitch += dInputPitch;
    s_targetPitch = std::clamp(s_targetPitch, -85.0f, 85.0f);

    // 2. Compute Gap between Target T and current Aim A
    float gapYaw = s_targetYaw - s_aimYaw;
    while (gapYaw > 180.0f) gapYaw -= 360.0f;
    while (gapYaw < -180.0f) gapYaw += 360.0f;

    float gapPitch = s_targetPitch - s_aimPitch;

    // 3. Clamp Max Divergence (advancing A when T exceeds clamp)
    if (s_maxDiv > 0.0f) {
        if (std::abs(gapYaw) > s_maxDiv) {
            float clamped = (gapYaw > 0.0f) ? s_maxDiv : -s_maxDiv;
            float excess = gapYaw - clamped;
            s_aimYaw += excess;
            gapYaw = clamped;
        }
    }

    // 4. Deadzone handling
    float effGapYaw = gapYaw;
    if (s_deadzone > 0.0f) {
        if (std::abs(effGapYaw) <= s_deadzone) {
            effGapYaw = 0.0f;
        } else {
            effGapYaw = (effGapYaw > 0.0f) ? (effGapYaw - s_deadzone) : (effGapYaw + s_deadzone);
        }
    }
    float effGapPitch = gapPitch;

    // 5. Chase Filter (s_mode 0 = Exponential with Option A Power-Law Curve, s_mode 1 = Model A Braking Zone)
    auto computeChaseStep = [&](float aEffGapYaw, float aEffGapPitch, float aDt, float& aOutDYaw, float& aOutDPitch) {
        aOutDYaw = 0.0f;
        aOutDPitch = 0.0f;
        float gapMag = std::sqrt(aEffGapYaw * aEffGapYaw + aEffGapPitch * aEffGapPitch);
        if (gapMag <= 0.0001f) return;

        float step = 0.0f;
        if (s_mode == 1) {
            // Model A: Rate-Limited Saccade with Smoothstep Braking Zone
            float thresh = (s_brakeThreshold > 0.05f) ? s_brakeThreshold : 2.0f;
            float maxSpd = (s_brakeMaxSpeed > 10.0f) ? s_brakeMaxSpeed : (s_lambda * 60.0f);

            float v = maxSpd;
            if (gapMag <= thresh) {
                float u = gapMag / thresh;
                // Cubic Hermite smoothstep: 3u^2 - 2u^3
                float smooth = u * u * (3.0f - 2.0f * u);
                v = maxSpd * smooth;
            }

            step = v * aDt;

            // Deceleration safety bound: prevent multi-degree single-frame snaps that pull the camera
            if (gapMag <= thresh) {
                float maxBrakeStep = std::max(0.04f, gapMag * 0.35f);
                if (step > maxBrakeStep) {
                    step = maxBrakeStep;
                }
            }
        } else {
            // Mode 0: Option A Power-Law Curve (exact analytical integration of dG/dt = -k * G^p)
            // Governed purely by continuous graph; no piecewise distance switches or speed floor clamps.
            float power = std::clamp(s_expPower, 0.1f, 1.5f);
            if (std::abs(power - 1.0f) < 0.001f) {
                // Linear exponential curve (p = 1.0)
                float expFactor = 1.0f - std::exp(-s_lambda * aDt);
                step = gapMag * expFactor;
            } else {
                // Sub-linear / custom power curve (p < 1.0, default 0.6)
                float oneMinusP = 1.0f - power;
                float rem = std::pow(gapMag, oneMinusP) - (oneMinusP * s_lambda * aDt);
                if (rem <= 0.0f) {
                    step = gapMag;
                } else {
                    float nextGap = std::pow(rem, 1.0f / oneMinusP);
                    step = gapMag - nextGap;
                }
            }
        }

        // Experimental T1-to-T2 Chase Rubber Leash
        // When separation between Camera (T1) and Gun (T2) exceeds s_chaseLeashStart,
        // progressive spring tension pulls T2 toward T1 to prevent heavy weapons from lagging
        // excessively far behind during rapid mouse movements.
        if (s_chaseLeashEnabled && gapMag > s_chaseLeashStart) {
            float excess = gapMag - s_chaseLeashStart;
            float span = std::max(s_chaseLeashMax - s_chaseLeashStart, 0.1f);
            float u = std::clamp(excess / span, 0.0f, 1.0f);
            float uCurve = std::pow(u, std::clamp(s_chaseLeashStiffness, 0.2f, 5.0f));
            // Progressive spring pull: adds angular velocity proportional to tension curve
            float pullSpeed = (s_lambda * 60.0f + 120.0f) * uCurve;
            step += pullSpeed * aDt;

            // Absolute distance ceiling: at or beyond s_chaseLeashMax, the weapon cannot lag further behind
            float minRequiredStep = gapMag - s_chaseLeashMax;
            if (step < minRequiredStep) {
                step = minRequiredStep;
            }
        }

        // Never overshoot target
        if (step > gapMag) {
            step = gapMag;
        }

        // Sub-pixel resting tolerance: snap cleanly to rest
        if (gapMag <= 0.005f) {
            step = gapMag;
        }

        aOutDYaw = (aEffGapYaw / gapMag) * step;
        aOutDPitch = (aEffGapPitch / gapMag) * step;
    };

    float dAYaw = 0.0f;
    float dAPitch = 0.0f;
    computeChaseStep(effGapYaw, effGapPitch, dt, dAYaw, dAPitch);

    // 6. Advance Tier 2A (Anchor Aim Direction)
    s_aimYaw += dAYaw;
    s_aimPitch += dAPitch;
    s_aimPitch = std::clamp(s_aimPitch, -85.0f, 85.0f);

    // 7. Tier 2B Active Barrel Offset Compensation:
    // When dynamic gap is large (flicking), rate uses s_compSpeedMoving so T2A handles swing weight.
    // When dynamic gap settles (< s_compGapThreshold), rate increases to s_compSpeedSettled for fast, snappy alignment.
    float compRate = s_compSpeedSettled;
    if (std::abs(gapYaw) > s_compGapThreshold || std::abs(gapPitch) > s_compGapThreshold) {
        compRate = s_compSpeedMoving;
    }
    float compFactor = 1.0f - std::exp(-compRate * dt);
    float errYaw = s_targetCompYaw - s_compYaw;
    float errPitch = s_targetCompPitch - s_compPitch;

    float dCompYaw = errYaw * compFactor;
    float dCompPitch = errPitch * compFactor;

    // Minimum angular speed to prevent asymptotic tail stall ("slowing down too soon")
    if (s_compMinSpeed > 0.0f) {
        float minStep = s_compMinSpeed * dt;
        if (std::abs(errYaw) > 0.005f && std::abs(dCompYaw) < minStep) {
            dCompYaw = std::copysign(std::min(minStep, std::abs(errYaw)), errYaw);
        }
        if (std::abs(errPitch) > 0.005f && std::abs(dCompPitch) < minStep) {
            dCompPitch = std::copysign(std::min(minStep, std::abs(errPitch)), errPitch);
        }
    }

    // Framerate-independent maximum angular velocity clamp
    float maxStep = s_compMaxSpeed * dt;
    dCompYaw = std::clamp(dCompYaw, -maxStep, maxStep);
    dCompPitch = std::clamp(dCompPitch, -maxStep, maxStep);

    s_compYaw += dCompYaw;
    s_compPitch += dCompPitch;
    s_compYaw = std::clamp(s_compYaw, -10.0f, 10.0f);
    s_compPitch = std::clamp(s_compPitch, -10.0f, 10.0f);

    // 8. Tier 2 Recoil Transfer (W) with Direct-to-Origin Recovery (eliminating RecoilDrift):
    // Vanilla Cyberpunk's native recoil recovery targets a random 2D point D_drift on a circle
    // of radius [RecoilDriftRandomRangeMin, RecoilDriftRandomRangeMax] (0.6-0.9 deg) around (0, 0),
    // moving along -(W_peak - D_drift) instead of -W_peak.
    // In our 2-tier system, Tier 2 must recover directly to (0, 0) (Tier 1) during RecoilRecoveryTime:
    //   - Kick (dRecoilPitch > 1e-5f): accumulate native kick and update W_peak = (s_recoilYaw, s_recoilPitch).
    //   - Hold (|dRecoil| <= 1e-5f while !s_recoilRecovering): hold W steady during RecoilHoldDuration.
    //   - Recovery (dRecoilPitch < -1e-5f): on the first recovery frame, if native recovery is
    //     targeting D_drift (radial misalignment > 0.02 rad), estimate D_drift_pitch from the bounded
    //     drift circle so each native recovery step du_k = -dRecoilPitch / (W_peak_pitch - D_drift_pitch)
    //     scales directly to 100% of W_peak: effDRecoil = -du_k * W_peak, reaching (0, 0) on the
    //     exact frame native RecoilRecoveryTime finishes!
    float effDRecoilYaw = 0.0f;
    float effDRecoilPitch = 0.0f;
    if (dRecoilPitch > 1e-5f || (!s_recoilRecovering && std::abs(dRecoilYaw) > 1e-5f && dRecoilPitch >= -1e-5f)) {
        // Kick Phase: track unattenuated native recoil for recovery span normalization,
        // apply Strength-Scaled Horizontal Recoil Dynamics, and then apply Option A Radial
        // Soft-Wall Attenuation ("Rubber Leash") to Tier 2 recoil W.
        s_recoilRecovering = false;
        s_recoilIdleTimer = 0.0f;
        s_nativeRecoilYaw = std::clamp(s_nativeRecoilYaw + dRecoilYaw, -45.0f, 45.0f);
        s_nativeRecoilPitch = std::clamp(s_nativeRecoilPitch + dRecoilPitch, -45.0f, 45.0f);

        // Coherent Per-Shot Impulse Detection:
        // Cyberpunk interpolates each shot's recoil kick across ~30-55 ms. Detect the start of a new
        // shot impulse (rising edge from idle/recovery, rising spike > 1.35x previous frame, or 45ms window)
        // so that each shot draws a single coherent random kick sign, strength, and neutralization factor.
        bool isNewShotImpulse = (s_prevDRecoilPitch <= 1e-5f) ||
                                (s_shotKickTimer >= 0.045f) ||
                                (dRecoilPitch > s_prevDRecoilPitch * 1.35f + 0.01f);
        if (isNewShotImpulse) {
            s_shotKickTimer = 0.0f;
            // Alternating / Mean-Reverting Directional Bias:
            // Combine previous shot's net horizontal direction (s_lastHoriPushSign) and current
            // horizontal deflection (s_recoilYaw) so that after kicking right (+1), the next shot
            // has a ~70%-80% probability of kicking left (-1) and vice-versa, while staying randomized.
            float deflectionBias = std::clamp(s_recoilYaw / 1.5f, -1.0f, 1.0f);
            float bias = std::clamp(0.55f * s_lastHoriPushSign + 0.45f * deflectionBias, -0.85f, 0.85f);
            float probLeft = 0.50f + 0.35f * bias; // in [0.2025, 0.7975]
            s_currentShotRandSign = (NextRecoilRand01() < probLeft) ? -1.0f : 1.0f;
            s_currentShotRandMag = 0.40f + 0.85f * NextRecoilRand01();  // in [0.40, 1.25]
            s_currentShotCompMult = 0.65f + 0.50f * NextRecoilRand01(); // in [0.65, 1.15]
        }
        s_shotKickTimer += dt;

        // Strength-Scaled Horizontal Recoil Weights:
        // s in [0, 1] maps Body/Strength stat [3..20] -> (Body - 3) / 17.
        float s = std::clamp(s_playerStrengthFactor, 0.0f, 1.0f);
        float wScatter = s_recoilHoriStatScaling ? ((1.0f - s) * s_recoilHoriScatter) : s_recoilHoriScatter;
        float wDamping = s_recoilHoriStatScaling ? (s * s_recoilHoriDamping) : s_recoilHoriDamping;

        // 1. High-Strength Native Horizontal Recoil Neutralization:
        // Counteract a randomized fraction of the game's native horizontal kick in the opposite direction.
        float compFrac = std::clamp(s_currentShotCompMult * wDamping, 0.0f, 0.95f);
        float deltaComp = -compFrac * dRecoilYaw;

        // 2. Low-Strength Alternating Horizontal Randomization:
        // Add a randomized left/right push proportional to the shot's recoil impulse.
        float baseKickMag = 0.35f * std::max(0.0f, dRecoilPitch) + 0.25f * std::abs(dRecoilYaw);
        float deltaRand = s_currentShotRandSign * s_currentShotRandMag * baseKickMag * wScatter;

        // 3. High-Strength Horizontal Centering Stabilization:
        float deltaCenter = -0.15f * wDamping * std::max(0.0f, dRecoilPitch) * std::clamp(s_recoilYaw / 1.5f, -1.0f, 1.0f);

        float rawModifiedYaw = dRecoilYaw + deltaComp + deltaRand + deltaCenter;
        if (std::abs(rawModifiedYaw) > 1e-4f) {
            s_lastHoriPushSign = (rawModifiedYaw >= 0.0f) ? 1.0f : -1.0f;
        }

        effDRecoilYaw = rawModifiedYaw;
        effDRecoilPitch = dRecoilPitch;

        if (s_recoilMaxRadius > 0.1f) {
            float Rmax = s_recoilMaxRadius;
            float p = std::clamp(s_recoilLeashCurve, 0.2f, 6.0f);
            float r = std::hypot(s_recoilYaw, s_recoilPitch);
            if (r > 1e-4f) {
                float ux = s_recoilYaw / r;
                float uy = s_recoilPitch / r;
                float dRad = effDRecoilYaw * ux + effDRecoilPitch * uy;
                float dTanX = effDRecoilYaw - dRad * ux;
                float dTanY = effDRecoilPitch - dRad * uy;

                float u = std::clamp(r / Rmax, 0.0f, 1.0f);
                float uPow = std::pow(u, p);
                if (dRad > 0.0f) {
                    // Progressive power-law rubber resistance against outward climb
                    float gRad = 1.0f - uPow;
                    dRad = std::min(dRad * gRad, std::max(0.0f, Rmax - r));
                }
                // Retain 50% tangential jitter at the leash rim so HMG/LMG sustained fire stays lively
                float gTan = 1.0f - 0.5f * uPow;
                effDRecoilYaw = dRad * ux + dTanX * gTan;
                effDRecoilPitch = dRad * uy + dTanY * gTan;
            }
            // Enforce strict outer circle invariant |W + effDRecoil| <= Rmax
            float candYaw = s_recoilYaw + effDRecoilYaw;
            float candPitch = s_recoilPitch + effDRecoilPitch;
            float candMag = std::hypot(candYaw, candPitch);
            if (candMag > Rmax && candMag > 1e-5f) {
                float clampScale = Rmax / candMag;
                candYaw *= clampScale;
                candPitch *= clampScale;
                effDRecoilYaw = candYaw - s_recoilYaw;
                effDRecoilPitch = candPitch - s_recoilPitch;
            }
        }
    } else if (dRecoilPitch < -1e-5f) {
        s_shotKickTimer = 0.0f;
        // Native Recovery Phase
        if (!s_recoilRecovering) {
            s_recoilRecovering = true;
            s_recoilPeakYaw = s_recoilYaw;
            s_recoilPeakPitch = s_recoilPitch;
            if (s_nativeRecoilPitch < s_recoilPitch) {
                s_nativeRecoilYaw = s_recoilYaw;
                s_nativeRecoilPitch = s_recoilPitch;
            }
            s_nativeRecoilPeakYaw = s_nativeRecoilYaw;
            s_nativeRecoilPeakPitch = s_nativeRecoilPitch;
            s_recoilDriftPitch = 0.0f;

            // Detect if vanilla RecoilDrift is active by comparing the native recovery direction
            // (dRecoilYaw, dRecoilPitch) against the unattenuated native peak (-W_native_yaw, -W_native_pitch)
            float peakMag = std::hypot(s_nativeRecoilPeakYaw, s_nativeRecoilPeakPitch);
            float dMag = std::hypot(dRecoilYaw, dRecoilPitch);
            if (peakMag > 0.05f && dMag > 1e-5f) {
                float cross = std::abs(dRecoilYaw * s_nativeRecoilPeakPitch - dRecoilPitch * s_nativeRecoilPeakYaw) / (peakMag * dMag);
                if (cross > 0.02f && s_nativeRecoilPeakPitch > 0.15f) {
                    // Vanilla BaseStats: RecoilDriftRandomRangeMin = 0.6, Max = 0.9 (mean 0.75 deg),
                    // RecoilMagForFullDrift = 3.0 deg.
                    // Exact line equation: (W_native_yaw - D_yaw) / (W_native_pitch - D_pitch) = m = dRecoilYaw / dRecoilPitch
                    float m = dRecoilYaw / dRecoilPitch;
                    float scale = std::clamp(peakMag / 3.0f, 0.0f, 1.0f);
                    float rTarget = 0.75f * scale;
                    // Closest point on the recovery line to the origin has radius |c| / sqrt(1 + m^2)
                    float c = s_nativeRecoilPeakYaw - m * s_nativeRecoilPeakPitch;
                    float m2p1 = 1.0f + m * m;
                    float rMin2 = (c * c) / m2p1;
                    float r2 = std::max(rTarget * rTarget, rMin2);
                    float dPitchClosest = -(m * c) / m2p1;
                    float halfChord = std::sqrt(std::max(0.0f, r2 - rMin2) / m2p1);
                    // Choose the positive-pitch branch matching vanilla upward recovery drift
                    float estDriftPitch = dPitchClosest + halfChord;
                    s_recoilDriftPitch = std::clamp(estDriftPitch, 0.0f, s_nativeRecoilPeakPitch * 0.45f);
                }
            }
        }
        s_recoilIdleTimer = 0.0f;
        float nativeSpanPitch = std::max(s_nativeRecoilPeakPitch - s_recoilDriftPitch, 0.05f);
        if (s_recoilPitch > 1e-4f) {
            float scale = s_recoilPeakPitch / nativeSpanPitch;
            effDRecoilPitch = std::max(dRecoilPitch * scale, -s_recoilPitch);
            effDRecoilYaw = s_recoilYaw * (effDRecoilPitch / s_recoilPitch);
        } else {
            effDRecoilPitch = -s_recoilPitch;
            effDRecoilYaw = -s_recoilYaw;
        }
        s_nativeRecoilYaw = std::max(0.0f, s_nativeRecoilYaw + dRecoilYaw);
        s_nativeRecoilPitch = std::max(0.0f, s_nativeRecoilPitch + dRecoilPitch);
    } else {
        // Native recoil delta is 0 (either in RecoilHoldDuration, or post-recovery idle)
        s_shotKickTimer = 0.0f;
        if (s_recoilRecovering) {
            // Native recovery just finished (or paused at D_drift): complete any tiny remaining
            // fraction smoothly and immediately without waiting 0.50s
            if (std::abs(s_recoilYaw) > 0.001f || std::abs(s_recoilPitch) > 0.001f) {
                float finishStep = std::max(s_recoilPeakPitch / 0.18f, 12.0f) * dt;
                float remMag = std::hypot(s_recoilYaw, s_recoilPitch);
                if (remMag <= finishStep || remMag <= 0.005f) {
                    effDRecoilYaw = -s_recoilYaw;
                    effDRecoilPitch = -s_recoilPitch;
                    s_recoilRecovering = false;
                    s_nativeRecoilYaw = 0.0f;
                    s_nativeRecoilPitch = 0.0f;
                } else {
                    float ratio = finishStep / remMag;
                    effDRecoilYaw = -s_recoilYaw * ratio;
                    effDRecoilPitch = -s_recoilPitch * ratio;
                }
            } else {
                effDRecoilYaw = -s_recoilYaw;
                effDRecoilPitch = -s_recoilPitch;
                s_recoilRecovering = false;
                s_nativeRecoilYaw = 0.0f;
                s_nativeRecoilPitch = 0.0f;
            }
        } else {
            // In RecoilHoldDuration (waiting for native recovery to begin) or aborted by reload
            s_recoilIdleTimer += dt;
            if (s_recoilIdleTimer > 0.50f && (std::abs(s_recoilYaw) > 0.001f || std::abs(s_recoilPitch) > 0.001f)) {
                float bleedFactor = 1.0f - std::exp(-s_compSpeedSettled * dt);
                float bleedYaw = -s_recoilYaw * bleedFactor;
                float bleedPitch = -s_recoilPitch * bleedFactor;
                if (std::abs(s_recoilYaw) <= 0.005f) bleedYaw = -s_recoilYaw;
                if (std::abs(s_recoilPitch) <= 0.005f) bleedPitch = -s_recoilPitch;
                effDRecoilYaw = bleedYaw;
                effDRecoilPitch = bleedPitch;
                s_nativeRecoilYaw += bleedYaw;
                s_nativeRecoilPitch += bleedPitch;
            } else if (std::abs(s_recoilYaw) <= 0.001f && std::abs(s_recoilPitch) <= 0.001f) {
                s_nativeRecoilYaw = 0.0f;
                s_nativeRecoilPitch = 0.0f;
            }
        }
    }

    float nextRecoilYaw = std::clamp(s_recoilYaw + effDRecoilYaw, -45.0f, 45.0f);
    float nextRecoilPitch = std::clamp(s_recoilPitch + effDRecoilPitch, -45.0f, 45.0f);
    effDRecoilYaw = nextRecoilYaw - s_recoilYaw;
    effDRecoilPitch = nextRecoilPitch - s_recoilPitch;
    s_recoilYaw = nextRecoilYaw;
    s_recoilPitch = nextRecoilPitch;
    if (dRecoilPitch > 1e-5f || (!s_recoilRecovering && std::abs(effDRecoilYaw) > 1e-5f && dRecoilPitch >= -1e-5f)) {
        s_recoilPeakYaw = s_recoilYaw;
        s_recoilPeakPitch = s_recoilPitch;
        s_nativeRecoilPeakYaw = s_nativeRecoilYaw;
        s_nativeRecoilPeakPitch = s_nativeRecoilPitch;
    }
    s_prevDRecoilPitch = dRecoilPitch;

    // 9. Residual for camera offset: R = T - T2B - predNextDBodyYaw
    // Because MouseLookRelay updates puppet bodyYaw [rcx+9Ch] BEFORE the engine's scene graph
    // evaluates CameraWorld, whereas CET's fpp:SetLocalTransform(R_k) takes effect on frame k+1
    // alongside bodyYaw_{k+1} = bodyYaw_k + dBody_{k+1}, pre-subtracting the 1-frame lookahead
    // puppet step predNextDBodyYaw = nextDAYaw - nextDCompYaw ensures:
    //   camYaw_{k+1} = (bodyYaw_k + dBody_{k+1}) + (T - bodyYaw_k - predNextDBodyYaw) = T.
    float remGapYaw = s_targetYaw - s_aimYaw;
    while (remGapYaw > 180.0f) remGapYaw -= 360.0f;
    while (remGapYaw < -180.0f) remGapYaw += 360.0f;
    float remEffGapYaw = remGapYaw;
    if (s_deadzone > 0.0f) {
        if (std::abs(remEffGapYaw) <= s_deadzone) {
            remEffGapYaw = 0.0f;
        } else {
            remEffGapYaw = (remEffGapYaw > 0.0f) ? (remEffGapYaw - s_deadzone) : (remEffGapYaw + s_deadzone);
        }
    }
    float remEffGapPitch = s_targetPitch - s_aimPitch;
    float nextDAYaw = 0.0f;
    float nextDAPitch = 0.0f;
    computeChaseStep(remEffGapYaw, remEffGapPitch, dt, nextDAYaw, nextDAPitch);

    float nextCompRate = s_compSpeedSettled;
    if (std::abs(remGapYaw) > s_compGapThreshold || std::abs(remEffGapPitch) > s_compGapThreshold) {
        nextCompRate = s_compSpeedMoving;
    }
    float nextCompFactor = 1.0f - std::exp(-nextCompRate * dt);
    float remErrYaw = s_targetCompYaw - s_compYaw;
    float nextDCompYaw = remErrYaw * nextCompFactor;
    if (s_compMinSpeed > 0.0f) {
        float minStep = s_compMinSpeed * dt;
        if (std::abs(remErrYaw) > 0.005f && std::abs(nextDCompYaw) < minStep) {
            nextDCompYaw = std::copysign(std::min(minStep, std::abs(remErrYaw)), remErrYaw);
        }
    }
    nextDCompYaw = std::clamp(nextDCompYaw, -maxStep, maxStep);
    float predNextDBodyYaw = nextDAYaw - nextDCompYaw;

    s_residualYaw = remGapYaw + s_compYaw - s_recoilYaw - predNextDBodyYaw;
    s_residualPitch = (s_targetPitch - s_aimPitch) + s_compPitch - s_recoilPitch;

    s_displayTargetYaw = s_targetYaw;
    s_displayAimYaw = s_aimYaw;
    s_displayT2BYaw = s_aimYaw - s_compYaw + s_recoilYaw;
    s_displayT2BPitch = std::clamp(s_aimPitch - s_compPitch + s_recoilPitch, -85.0f, 85.0f);

    // Keep yaw state bounded to prevent float overflow over time (yaw wraps around 360)
    s_targetYaw -= s_aimYaw;
    s_aimYaw = 0.0f;

    // NOTE: Pitch does NOT wrap around 360; it remains bounded in [-85, +85] degrees absolute.
    // s_aimPitch represents continuous native camera pitch for roll-free yaw projection.

    // 10. Output chase + recoil deltas to engine look integrator at RVA 0x51D462:
    // Feeds d(T2B) = dA - dComp + dRecoil into puppet yaw [rcx+9Ch] and camera pitch accumulator
    outYaw = dAYaw - dCompYaw + effDRecoilYaw;
    outPitch = dAPitch - dCompPitch + effDRecoilPitch;
}

float InputHook::GetTargetYaw() { return s_displayTargetYaw; }
float InputHook::GetTargetPitch() { return s_targetPitch; }
float InputHook::GetAimYaw() { return s_displayAimYaw; }
float InputHook::GetAimPitch() { return s_aimPitch; }
float InputHook::GetResidualYaw() { return s_residualYaw; }
float InputHook::GetResidualPitch() { return s_residualPitch; }
float InputHook::GetCompYaw() { return s_compYaw; }
float InputHook::GetCompPitch() { return s_compPitch; }
float InputHook::GetT2BYaw() { return s_displayT2BYaw; }
float InputHook::GetT2BPitch() { return s_displayT2BPitch; }
float InputHook::GetRecoilYaw() { return s_recoilYaw; }
float InputHook::GetRecoilPitch() { return s_recoilPitch; }
float InputHook::GetLastDeltaRecoilYaw() { return s_lastDRecoilYaw; }
float InputHook::GetLastDeltaRecoilPitch() { return s_lastDRecoilPitch; }
float InputHook::GetSplitErrYaw() { return s_splitErrYaw; }
float InputHook::GetSplitErrPitch() { return s_splitErrPitch; }

void InputHook::SetSensitivityMult(RED4ext::IScriptable* aFpp, float aMultX, float aMultY) {
    if (!aFpp) return;
    __try {
        uintptr_t addr = reinterpret_cast<uintptr_t>(aFpp);
        *reinterpret_cast<float*>(addr + 0x498) = aMultX;
        *reinterpret_cast<float*>(addr + 0x49C) = aMultY;
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}

float InputHook::GetSensitivityMultX(RED4ext::IScriptable* aFpp) {
    if (!aFpp) return 1.0f;
    __try {
        uintptr_t addr = reinterpret_cast<uintptr_t>(aFpp);
        return *reinterpret_cast<const float*>(addr + 0x498);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return 1.0f;
    }
}

float InputHook::GetSensitivityMultY(RED4ext::IScriptable* aFpp) {
    if (!aFpp) return 1.0f;
    __try {
        uintptr_t addr = reinterpret_cast<uintptr_t>(aFpp);
        return *reinterpret_cast<const float*>(addr + 0x49C);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return 1.0f;
    }
}

void InputHook::SetHeadingLocked(RED4ext::IScriptable* aFpp, bool aLocked) {
    if (!aFpp) return;
    __try {
        uintptr_t addr = reinterpret_cast<uintptr_t>(aFpp);
        *reinterpret_cast<bool*>(addr + 0x3F6) = aLocked;
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}

bool InputHook::GetHeadingLocked(RED4ext::IScriptable* aFpp) {
    if (!aFpp) return false;
    __try {
        uintptr_t addr = reinterpret_cast<uintptr_t>(aFpp);
        return *reinterpret_cast<const bool*>(addr + 0x3F6);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

void InputHook::PushEvent(const std::string& aEvent) {
    std::lock_guard<std::mutex> lock(s_eventMutex);
    s_eventBuffer.push_back(aEvent);
}

std::string InputHook::DrainEvents() {
    std::lock_guard<std::mutex> lock(s_eventMutex);
    if (s_eventBuffer.empty()) {
        return "";
    }
    std::string result;
    for (size_t i = 0; i < s_eventBuffer.size(); ++i) {
        result += s_eventBuffer[i];
        if (i + 1 < s_eventBuffer.size()) {
            result += "\n";
        }
    }
    s_eventBuffer.clear();
    return result;
}

#include <RED4ext/Detail/AddressHashes.hpp>
#include <RED4ext/Relocation.hpp>

using NativeHandler_t = void (*)(void*, RED4ext::CStackFrame&, void*, RED4ext::rtti::IType*);

static uintptr_t s_handlersTableAddr = 0;

static uintptr_t TryGetHandler(uint32_t aRegIndex) {
    if (!s_handlersTableAddr) {
        s_handlersTableAddr = RED4ext::UniversalRelocBase::Resolve(RED4ext::Detail::AddressHashes::CBaseFunction_Handlers);
    }
    if (!s_handlersTableAddr) return 0;

    __try {
        auto table = *reinterpret_cast<NativeHandler_t**>(s_handlersTableAddr);
        if (table && aRegIndex < 65536) {
            auto handler = table[aRegIndex];
            return reinterpret_cast<uintptr_t>(handler);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
    }
    return 0;
}

static uintptr_t TryDisasmCallTarget(uintptr_t aHandlerAddr, uintptr_t aExeBase) {
    if (!aHandlerAddr || !aExeBase) return 0;
    __try {
        const uint8_t* bytes = reinterpret_cast<const uint8_t*>(aHandlerAddr);
        for (int i = 0; i < 32; ++i) {
            if (bytes[i] == 0xE8) { // CALL rel32
                int32_t rel = 0;
                std::memcpy(&rel, bytes + i + 1, sizeof(rel));
                uintptr_t target = (aHandlerAddr + i + 5) + rel;
                if (target >= aExeBase) {
                    return target - aExeBase;
                }
                break;
            }
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
    return 0;
}

static void TryDisasmBytes(uintptr_t aAddr, int count, char* outBuf, size_t bufSize) {
    if (!outBuf || bufSize == 0) return;
    outBuf[0] = '\0';
    if (!aAddr) {
        snprintf(outBuf, bufSize, "none");
        return;
    }
    __try {
        const uint8_t* p = reinterpret_cast<const uint8_t*>(aAddr);
        size_t off = 0;
        for (int i = 0; i < count && off + 4 < bufSize; ++i) {
            off += snprintf(outBuf + off, bufSize - off, "%02X ", p[i]);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        snprintf(outBuf, bufSize, "err");
    }
}

static void ScanSensitivityMultAccess(uintptr_t aExeBase, std::stringstream& ss) {
    if (!aExeBase) return;

    auto dosHeader = reinterpret_cast<const IMAGE_DOS_HEADER*>(aExeBase);
    if (dosHeader->e_magic != IMAGE_DOS_SIGNATURE) return;

    auto ntHeaders = reinterpret_cast<const IMAGE_NT_HEADERS*>(aExeBase + dosHeader->e_lfanew);
    if (ntHeaders->Signature != IMAGE_NT_SIGNATURE) return;

    auto section = IMAGE_FIRST_SECTION(ntHeaders);
    uintptr_t textStart = 0;
    size_t textSize = 0;

    for (WORD i = 0; i < ntHeaders->FileHeader.NumberOfSections; ++i, ++section) {
        if (std::memcmp(section->Name, ".text", 5) == 0) {
            textStart = aExeBase + section->VirtualAddress;
            textSize = section->Misc.VirtualSize;
            break;
        }
    }

    if (!textStart || !textSize) return;

    ss << "\n[N1] === Scanning .text for sensitivityMultX (0x498) & sensitivityMultY (0x49c) ===\n";

    const uint8_t* p = reinterpret_cast<const uint8_t*>(textStart);
    const uint8_t* end = p + textSize - 8;

    int hits = 0;
    __try {
        while (p < end) {
            // Check for 0x00000498 or 0x0000049c in immediate / displacement
            if ((p[0] == 0x98 || p[0] == 0x9C) && p[1] == 0x04 && p[2] == 0x00 && p[3] == 0x00) {
                uintptr_t hitAddr = reinterpret_cast<uintptr_t>(p);
                uintptr_t hitRva = hitAddr - aExeBase;
                const char* axis = (p[0] == 0x98) ? "sensitivityMultX (yaw)" : "sensitivityMultY (pitch)";

                ss << "  [SCAN HIT #" << std::dec << (++hits) << "] " << axis << " at RVA=0x" << std::hex << hitRva << " bytes: ";
                for (int b = -6; b <= 5; ++b) {
                    ss << std::setw(2) << std::setfill('0') << static_cast<int>(p[b]) << " ";
                }
                ss << "\n";
            }
            ++p;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        ss << "[N1] Memory read exception during .text scan.\n";
    }
    ss << "[N1] Scan completed. Total hits: " << std::dec << hits << "\n\n";
}

void InputHook::ProbeRTTI() {
    auto rtti = RED4ext::CRTTISystem::Get();
    if (!rtti) return;

    if (!s_exeBase) {
        HMODULE hExe = GetModuleHandleA("Cyberpunk2077.exe");
        if (hExe) s_exeBase = reinterpret_cast<uintptr_t>(hExe);
    }

    std::stringstream ss;
    ss << "[N0] exe=0x" << std::hex << s_exeBase << " build=2.50 bytesOK=1 patched=0\n";

    const char* classNames[] = {
        "gameFPPCameraComponent",
        "FPPCameraComponent",
        "CameraComponent",
        "entCameraComponent",
        "PlayerPuppet"
    };

    for (const char* className : classNames) {
        RED4ext::CClass* cls = rtti->GetClass(className);
        if (!cls) {
            cls = rtti->GetClassByScriptName(className);
        }

        if (!cls) {
            ss << "[N1] route=A class=" << className << " status=NOT_FOUND\n";
            continue;
        }

        const char* parentName = cls->parent ? cls->parent->name.ToString() : "none";
        ss << "[N1] route=A class=" << className
           << " size=0x" << std::hex << cls->size
           << " parent=" << parentName
           << " propsCount=" << std::dec << cls->props.size()
           << " funcsCount=" << cls->funcs.size() << "\n";

        // Enumerate properties
        for (uint32_t i = 0; i < cls->props.size(); ++i) {
            auto prop = cls->props[i];
            if (!prop) continue;
            const char* propName = prop->name.ToString();
            const char* typeName = (prop->type && prop->type->GetName().ToString()) ? prop->type->GetName().ToString() : "unknown";
            ss << "  [PROP] " << className << "." << (propName ? propName : "unnamed")
               << " type=" << typeName
               << " offset=0x" << std::hex << prop->valueOffset << "\n";
        }

        // Enumerate functions
        for (uint32_t i = 0; i < cls->funcs.size(); ++i) {
            auto fn = cls->funcs[i];
            if (!fn) continue;
            const char* shortName = fn->shortName.ToString();
            const char* fullName = fn->fullName.ToString();
            uint32_t regIdx = fn->GetRegIndex();

            uintptr_t handlerAddr = 0;
            uintptr_t handlerRva = 0;
            uintptr_t targetRva = 0;

            if (fn->flags.isNative) {
                handlerAddr = TryGetHandler(regIdx);
                if (handlerAddr && s_exeBase && handlerAddr >= s_exeBase) {
                    handlerRva = handlerAddr - s_exeBase;
                    targetRva = TryDisasmCallTarget(handlerAddr, s_exeBase);
                }
            }

            char disasmBuf[64] = {};
            TryDisasmBytes(targetRva ? (s_exeBase + targetRva) : handlerAddr, 16, disasmBuf, sizeof(disasmBuf));

            ss << "  [FUNC] " << (shortName ? shortName : (fullName ? fullName : "unnamed"))
               << " regIdx=" << std::dec << regIdx
               << " native=" << (fn->flags.isNative ? 1 : 0)
               << " handlerRva=0x" << std::hex << handlerRva
               << " targetRva=0x" << std::hex << targetRva
               << " targetBytes: " << disasmBuf << "\n";
        }
    }

    // Scan .text for sensitivityMultX (0x498) and sensitivityMultY (0x49c)
    ScanSensitivityMultAccess(s_exeBase, ss);

    std::string report = ss.str();

    // Write full report to log file (try multiple paths starting with CET mod directory)
    const char* logPaths[] = {
        "plugins/cyber_engine_tweaks/mods/DetachedReticle/rtti_probe.log",
        "../../red4ext/plugins/DetachedReticle/rtti_probe.log",
        "red4ext/plugins/DetachedReticle/rtti_probe.log",
        "rtti_probe.log"
    };

    for (const char* path : logPaths) {
        std::ofstream ofs(path);
        if (ofs.is_open()) {
            ofs << report;
            ofs.close();
            if (s_sdk && s_sdk->logger) {
                std::string msg = std::string("Route A RTTI probing written to: ") + path;
                s_sdk->logger->Info(s_handle, msg.c_str());
            }
            break;
        }
    }

    PushEvent("[N0] exe=0x" + (std::stringstream() << std::hex << s_exeBase).str() + " build=2.50 bytesOK=1 patched=0");
    PushEvent("[N1] route=A RTTI probe completed. Check rtti_probe.log for full details.");
}

} // namespace DetachedReticle

extern "C" void OnNativeMouseAim(void* aFpp, float* aYawDelta, float* aPitchDelta, const float* aSplitProbe) {
    if (!aFpp || !aYawDelta || !aPitchDelta) return;
    DetachedReticle::InputHook::ProcessMouseAim(aFpp, *aYawDelta, *aPitchDelta, aSplitProbe, *aYawDelta, *aPitchDelta);
}
