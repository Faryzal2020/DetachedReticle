#pragma once

#include <RED4ext/RED4ext.hpp>
#include <string>
#include <mutex>
#include <vector>

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

    // Tier 2B Active Barrel Offset Compensation
    static void SetBarrelOffset(float aYaw, float aPitch);
    static float GetCompYaw();
    static float GetCompPitch();
    static float GetT2BYaw();
    static float GetT2BPitch();

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
    static inline float s_lambda{ 4.0f };
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

    static void ResetChase(float aInitialPitch = 0.0f);
    static void ProcessMouseAim(void* aFpp, float aRawYaw, float aRawPitch, float& outYaw, float& outPitch);

private:
    static inline RED4ext::v1::PluginHandle s_handle{ nullptr };
    static inline const RED4ext::v1::Sdk* s_sdk{ nullptr };
    static inline std::mutex s_eventMutex;
    static inline std::vector<std::string> s_eventBuffer;
    static inline bool s_isInitialized{ false };
    static inline bool s_isHooked{ false };
    static inline uint8_t* s_lookRelay{ nullptr };
    static inline std::chrono::steady_clock::time_point s_lastTime{};
};

} // namespace DetachedReticle

extern "C" void MouseLookRelay();
extern "C" void OnNativeMouseAim(void* aFpp, float* aYawDelta, float* aPitchDelta);

