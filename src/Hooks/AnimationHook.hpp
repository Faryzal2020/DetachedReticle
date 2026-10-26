#pragma once

#include <RED4ext/RED4ext.hpp>

namespace DetachedReticle {

class AnimationHook {
public:
    static bool Initialize(RED4ext::v1::PluginHandle aHandle, const RED4ext::v1::Sdk* aSdk);
    static void Shutdown();

    static void SetAimDeflection(float aYawDeg, float aPitchDeg);

private:
    static inline RED4ext::v1::PluginHandle s_handle{ nullptr };
    static inline const RED4ext::v1::Sdk* s_sdk{ nullptr };
    static inline float s_yawLagDeg{ 0.0f };
    static inline float s_pitchLagDeg{ 0.0f };
    static inline bool s_isHooked{ false };
};

} // namespace DetachedReticle
