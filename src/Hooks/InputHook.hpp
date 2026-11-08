#pragma once

#include <RED4ext/RED4ext.hpp>
#include <string>
#include <mutex>
#include <vector>
#include <chrono>

namespace DetachedReticle {

class InputHook {
public:
    static bool Initialize(RED4ext::v1::PluginHandle aHandle, const RED4ext::v1::Sdk* aSdk);
    static void Shutdown();

    // RTTI Inspection & Probing (Route A)
    static void ProbeRTTI();

    // Script Bridge APIs
    static void SetSmoothing(float aLambda, int32_t aMode, float aMaxDiv, float aDeadzone, bool aEnabled);
    static float GetTargetYaw();
    static float GetTargetPitch();
    static float GetAimYaw();
    static float GetAimPitch();
    static float GetResidualYaw();
    static float GetResidualPitch();

    // Tier 2B Active Barrel Offset Compensation & Recoil Transfer Telemetry
    static void SetBarrelOffset(float aYaw, float aPitch);
    static float GetCompYaw();
    static float GetCompPitch();
    static float GetT2BYaw();
    static float GetT2BPitch();
    static float GetRecoilYaw();
    static float GetRecoilPitch();
    static float GetLastDeltaRecoilYaw();
    static float GetLastDeltaRecoilPitch();
    static float GetSplitErrYaw();
    static float GetSplitErrPitch();
    static void SetCompParams(float aSpeedSettled, float aSpeedMoving, float aMaxSpeed, float aGapThreshold, float aMinSpeed);
    static float GetCompSpeedSettled();
    static float GetCompSpeedMoving();
    static float GetCompMaxSpeed();
    static float GetCompGapThreshold();
    static float GetCompMinSpeed();

    // Model A: Braking Zone Chase Parameters
    static void SetBrakeParams(float aThreshold, float aMaxSpeed);
    static float GetBrakeThreshold();
    static float GetBrakeMaxSpeed();

    // Option A: Continuous Power-Law Curve Parameters
    static void SetExpParams(float aPower);
    static float GetExpPower();

    // Tier 2 Recoil Rubber Leash (Option A Radial Soft-Wall Attenuation) Parameters
    static void SetRecoilLeashParams(float aMaxRadius, float aLeashCurve);
    static float GetRecoilMaxRadius();
    static float GetRecoilLeashCurve();

    // Experimental T1-to-T2 Chase Rubber Leash Parameters
    static void SetChaseLeashParams(bool aEnabled, float aStartDist, float aMaxDist, float aStiffness);
    static bool GetChaseLeashEnabled();
    static float GetChaseLeashStart();
    static float GetChaseLeashMax();
    static float GetChaseLeashStiffness();

    // Tier 2 Strength-Scaled Horizontal Recoil Dynamics Parameters
    static void SetRecoilHorizontalParams(bool aStatScaling, float aScatter, float aDamping, float aStrengthFactor);
    static bool GetRecoilHoriStatScaling();
    static float GetRecoilHoriScatter();
    static float GetRecoilHoriDamping();
    static float GetPlayerStrengthFactor();

    // Sensitivity Mult Direct Memory Access (offsets 0x498, 0x49C on gameFPPCameraComponent)
    static void SetSensitivityMult(RED4ext::IScriptable* aFpp, float aMultX, float aMultY);
    static float GetSensitivityMultX(RED4ext::IScriptable* aFpp);
    static float GetSensitivityMultY(RED4ext::IScriptable* aFpp);

    // Heading Lock Direct Memory Access (offset 0x3F6 on gameFPPCameraComponent)
    static void SetHeadingLocked(RED4ext::IScriptable* aFpp, bool aLocked);
    static bool GetHeadingLocked(RED4ext::IScriptable* aFpp);

    // Event Buffer
    static void PushEvent(const std::string& aEvent);
    static std::string DrainEvents();

    // State Variables
    static inline float s_lambda{ 22.0f };
    static inline int32_t s_mode{ 0 }; // 0: exp, 1: linear, 2: spring, 3: power
    static inline float s_maxDiv{ 65.0f };
    static inline float s_deadzone{ 0.0f };
    static inline bool s_enabled{ false };

    // Chase Target (T) and Aim Direction (A = T2A, Actuated = T2B)
    static inline float s_targetYaw{ 0.0f };
    static inline float s_targetPitch{ 0.0f };
    static inline float s_aimYaw{ 0.0f };
    static inline float s_aimPitch{ 0.0f };
    static inline float s_residualYaw{ 0.0f };
    static inline float s_residualPitch{ 0.0f };
    static inline float s_displayTargetYaw{ 0.0f };
    static inline float s_displayAimYaw{ 0.0f };

    // Tier 2B Compensation State (C)
    static inline float s_targetCompYaw{ 0.0f };
    static inline float s_targetCompPitch{ 0.0f };
    static inline float s_compYaw{ 0.0f };
    static inline float s_compPitch{ 0.0f };
    static inline float s_displayT2BYaw{ 0.0f };
    static inline float s_displayT2BPitch{ 0.0f };

    // Tier 2 Native Recoil Offset State (W) & Split Probe Telemetry
    static inline float s_recoilYaw{ 0.0f };
    static inline float s_recoilPitch{ 0.0f };
    static inline float s_recoilPeakYaw{ 0.0f };
    static inline float s_recoilPeakPitch{ 0.0f };
    static inline float s_nativeRecoilYaw{ 0.0f };
    static inline float s_nativeRecoilPitch{ 0.0f };
    static inline float s_nativeRecoilPeakYaw{ 0.0f };
    static inline float s_nativeRecoilPeakPitch{ 0.0f };
    static inline float s_recoilDriftPitch{ 0.0f };
    static inline bool s_recoilRecovering{ false };
    static inline float s_recoilIdleTimer{ 0.0f };
    static inline float s_lastDRecoilYaw{ 0.0f };
    static inline float s_lastDRecoilPitch{ 0.0f };
    static inline float s_splitErrYaw{ 0.0f };
    static inline float s_splitErrPitch{ 0.0f };

    // Tier 2 Recoil Rubber Leash Parameters
    static inline float s_recoilMaxRadius{ 7.0f };   // Degrees: max recoil distance from center reticle (0 = unlimited)
    static inline float s_recoilLeashCurve{ 1.5f };  // Power-law resistance exponent as recoil approaches s_recoilMaxRadius

    // Experimental T1-to-T2 Chase Rubber Leash State & Parameters
    static inline bool s_chaseLeashEnabled{ true };
    static inline float s_chaseLeashStart{ 20.0f };   // Degrees: distance where rubber leash tension begins pulling T2
    static inline float s_chaseLeashMax{ 60.0f };     // Degrees: maximum separation distance where leash is fully taut
    static inline float s_chaseLeashStiffness{ 0.6f };// Tension ramp exponent (default: 0.6)

    // Tier 2 Strength-Scaled Horizontal Recoil Dynamics State & Parameters
    static inline bool s_recoilHoriStatScaling{ true }; // Scale scatter/damping with player Body/Strength stat [3..20]
    static inline float s_recoilHoriScatter{ 1.0f };    // Low-Strength alternating horizontal scatter multiplier (default: 1.0)
    static inline float s_recoilHoriDamping{ 0.70f };   // High-Strength native horizontal recoil neutralization factor (default: 0.70)
    static inline float s_playerStrengthFactor{ 0.0f }; // Normalized Body/Strength in [0.0, 1.0] ((Body - 3) / 17)
    static inline float s_shotKickTimer{ 0.0f };        // Duration of current shot kick window (s)
    static inline float s_prevDRecoilPitch{ 0.0f };     // Previous frame native recoil pitch delta for rising-edge shot detection
    static inline float s_lastHoriPushSign{ 1.0f };     // Direction (+1 right, -1 left) of the previous shot's net horizontal kick
    static inline float s_currentShotRandSign{ 1.0f };  // Per-shot randomized horizontal impulse sign (+1 or -1)
    static inline float s_currentShotRandMag{ 0.8f };   // Per-shot randomized horizontal impulse magnitude [0.40, 1.25]
    static inline float s_currentShotCompMult{ 0.9f };  // Per-shot randomized neutralization multiplier [0.65, 1.15]
    static inline uint32_t s_rngState{ 0xA341316Cu };   // Fast xorshift32 PRNG state for per-shot horizontal recoil dynamics

    // Tier 2B Compensation Parameters
    static inline float s_compSpeedSettled{ 12.0f };
    static inline float s_compSpeedMoving{ 4.0f };
    static inline float s_compMaxSpeed{ 240.0f };
    static inline float s_compGapThreshold{ 3.0f };
    static inline float s_compMinSpeed{ 6.0f };

    // Model A (Braking Zone) Parameters
    static inline float s_brakeThreshold{ 2.0f };   // Degrees: distance from target where deceleration begins
    static inline float s_brakeMaxSpeed{ 360.0f };  // Deg/s: cruising speed outside braking zone (if <= 0, uses lambda * 60)

    // Option A: Continuous Power-Law Curve Parameters
    static inline float s_expPower{ 0.6f };         // Curve exponent: 1.0 = linear exponential, 0.6 = tight power-law chase

    static void ResetChase(float aInitialPitch = 0.0f);
    static void ProcessMouseAim(void* aFpp, float aRawYaw, float aRawPitch, const float* aSplitProbe, float& outYaw, float& outPitch);

private:
    static inline RED4ext::v1::PluginHandle s_handle{ nullptr };
    static inline const RED4ext::v1::Sdk* s_sdk{ nullptr };
    static inline std::mutex s_eventMutex;
    static inline std::vector<std::string> s_eventBuffer;
    static inline bool s_isInitialized{ false };
    static inline bool s_isHooked{ false };
    static inline uint8_t* s_lookRelay{ nullptr };
    static inline std::chrono::steady_clock::time_point s_lastTime{};
    static inline float s_smoothedDt{ 1.0f / 60.0f };
};

} // namespace DetachedReticle

extern "C" void MouseLookRelay();
extern "C" void OnNativeMouseAim(void* aFpp, float* aYawDelta, float* aPitchDelta, const float* aSplitProbe);
