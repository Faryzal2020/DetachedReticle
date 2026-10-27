#include "ShootingHook.hpp"

#include <windows.h>
#include <cmath>
#include <cstring>
#include <algorithm>
#include <fstream>
#include <chrono>

namespace DetachedReticle {

// Verified RVAs in Cyberpunk2077.exe (Build 2.50 / Patch 2.5):
// gameEffectObjectProvider_PhysicalRay::Execute calls the input evaluator at RVA 0x474BCC for:
//   Origin:  callsite RVA 0x9507B7 (CALL 0x474BCC)
//   Forward: callsite RVA 0x9507EC (CALL 0x474BCC)
static constexpr uintptr_t kWaPhysicalRayEvalFn          = 0x474BCC;
static constexpr uintptr_t kWaPhysicalRayOriginCallsite  = 0x9507B7;
static constexpr uintptr_t kWaPhysicalRayForwardCallsite = 0x9507EC;

// Typed Vector4 setter in REDengine:
static constexpr uintptr_t kWaSharedVector4SetRva   = 0x475078;
static constexpr uint8_t kWaSharedVector4SetBytes[] = { 0x4C, 0x8B, 0xDC, 0x49, 0x89, 0x5B, 0x08 };

// CName hashes (FNV1a64):
static constexpr uint64_t kWaPlayerOwnedWeaponCName = 0x8CB4C0891BD255EDull; // FNV1a64("playerOwnedWeapon")
static constexpr uint64_t kWaWeaponItemRecordCName  = 0x8DBDD9257C33612Full; // FNV1a64("weaponItemRecord")
static constexpr uint64_t kWaPositionCName          = 0x4CBF3A26FCA1D74Aull; // FNV1a64("position")
static constexpr uint64_t kWaForwardCName           = 0x1E65942E132F4F7Aull; // FNV1a64("forward")

typedef char (*WaPhysicalRayEvalFn)(void*, void*, float*);
static WaPhysicalRayEvalFn s_originalEval = nullptr;
static uint8_t* s_originRelay = nullptr;
static uint8_t* s_forwardRelay = nullptr;
static uintptr_t s_exeBase = 0;

// Thread-local state for correlating Origin and Forward evaluation of the same ray
static thread_local bool s_waPhysicalRayMine = false;
static thread_local void* s_waPhysicalRayContext = nullptr;
static thread_local float s_waPhysicalRayOrigin[3] = {};
static thread_local float s_waPhysicalRayMuzzleForward[3] = {};

static inline bool WaPlausiblePtr(uintptr_t p) {
    return p >= 0x10000ull && p < 0x00007FFFFFFFFFFFull && (p & 7ull) == 0;
}

static bool WaPlayerOwnedWeapon(const void* aBlackboard) {
    if (!aBlackboard) return false;
    const uint8_t* bb = static_cast<const uint8_t*>(aBlackboard);
    if (!WaPlausiblePtr(reinterpret_cast<uintptr_t>(bb))) return false;

    const uint64_t* keys = *reinterpret_cast<const uint64_t* const*>(bb + 0x48);
    const uint32_t count = *reinterpret_cast<const uint32_t*>(bb + 0x54);
    const uint8_t* vals = *reinterpret_cast<const uint8_t* const*>(bb + 0x58);
    if (!keys || !vals || count == 0 || count > 256) return false;
    if (!WaPlausiblePtr(reinterpret_cast<uintptr_t>(keys))) return false;
    if (!WaPlausiblePtr(reinterpret_cast<uintptr_t>(vals))) return false;

    bool fromWeapon = false;
    bool playerOwned = false;
    for (uint32_t i = 0; i < count; ++i) {
        const uint64_t key = keys[i];
        if (key != kWaPlayerOwnedWeaponCName && key != kWaWeaponItemRecordCName) continue;
        const uint8_t* entry = vals + static_cast<size_t>(i) * 24;
        if ((*reinterpret_cast<const uint64_t*>(entry) & ~1ull) == 0) continue;
        if (key == kWaWeaponItemRecordCName) fromWeapon = true;
        else playerOwned = entry[8] != 0;
    }
    return fromWeapon && playerOwned;
}

static bool WaWriteSharedVector4(void* aBlackboard, uint64_t aKey, const float* aValue, float aW) {
    if (!aBlackboard || !aValue || !s_exeBase) return false;
    if (!std::isfinite(aValue[0]) || !std::isfinite(aValue[1]) || !std::isfinite(aValue[2])) return false;
    static const bool s_setterMatches =
        std::memcmp(reinterpret_cast<const void*>(s_exeBase + kWaSharedVector4SetRva),
                    kWaSharedVector4SetBytes, sizeof(kWaSharedVector4SetBytes)) == 0;
    if (!s_setterMatches) return false;
    using Setter = bool (*)(void*, const uint64_t*, const float*, uint8_t);
    alignas(16) const float value[4] = { aValue[0], aValue[1], aValue[2], aW };
    const auto setter = reinterpret_cast<Setter>(s_exeBase + kWaSharedVector4SetRva);
    return setter(aBlackboard, &aKey, value, 0);
}

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

static void LogRayRedirection(const float* origin, const float* rawFwd, const float* outFwd) {
    try {
        std::ofstream logFile("bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/DetachedReticle.log", std::ios::app);
        if (logFile.is_open()) {
            auto now = std::chrono::system_clock::now();
            auto time_t_now = std::chrono::system_clock::to_time_t(now);
            char timeBuf[32];
            std::strftime(timeBuf, sizeof(timeBuf), "%Y-%m-%d %H:%M:%S", std::localtime(&time_t_now));

            logFile << "[" << timeBuf << "] [DetachedReticle Native Hook] [PHYSICAL RAY INTERCEPTED & REDIRECTED]"
                    << " Origin: (" << origin[0] << ", " << origin[1] << ", " << origin[2] << ")"
                    << " | CameraFwd: (" << rawFwd[0] << ", " << rawFwd[1] << ", " << rawFwd[2] << ")"
                    << " -> BarrelFwd: (" << outFwd[0] << ", " << outFwd[1] << ", " << outFwd[2] << ")\n";
            logFile.flush();
        }
    } catch (...) {}
}

extern "C" char Hooked_WaPhysicalRayOrigin(void* rcx, void* rdx, float* out) {
    s_waPhysicalRayMine = false;
    s_waPhysicalRayContext = nullptr;
    s_waPhysicalRayMuzzleForward[0] = 0.0f;
    s_waPhysicalRayMuzzleForward[1] = 0.0f;
    s_waPhysicalRayMuzzleForward[2] = 0.0f;

    const char result = s_originalEval ? s_originalEval(rcx, rdx, out) : 0;
    if (!result || !out || !ShootingHook::s_isDecoupled) return result;

    __try {
        const float muzzle[3] = { ShootingHook::s_muzzlePos.X, ShootingHook::s_muzzlePos.Y, ShootingHook::s_muzzlePos.Z };
        const float forward[3] = { ShootingHook::s_muzzleFwd.X, ShootingHook::s_muzzleFwd.Y, ShootingHook::s_muzzleFwd.Z };

        // Quick distance check between camera origin and weapon muzzle (must be within 3.0 m)
        const float dx = out[0] - muzzle[0];
        const float dy = out[1] - muzzle[1];
        const float dz = out[2] - muzzle[2];
        const float distanceSq = dx*dx + dy*dy + dz*dz;
        if (!std::isfinite(distanceSq) || distanceSq > 3.0f * 3.0f) {
            return result;
        }

        // Verify this ray belongs to the local player's weapon
        if (!WaPlayerOwnedWeapon(rdx)) {
            return result;
        }

        s_waPhysicalRayMine = true;
        s_waPhysicalRayMuzzleForward[0] = forward[0];
        s_waPhysicalRayMuzzleForward[1] = forward[1];
        s_waPhysicalRayMuzzleForward[2] = forward[2];

        // Override origin with muzzle position
        out[0] = muzzle[0];
        out[1] = muzzle[1];
        out[2] = muzzle[2];
        out[3] = 1.0f;

        s_waPhysicalRayContext = rdx;
        s_waPhysicalRayOrigin[0] = out[0];
        s_waPhysicalRayOrigin[1] = out[1];
        s_waPhysicalRayOrigin[2] = out[2];
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        s_waPhysicalRayMine = false;
        s_waPhysicalRayContext = nullptr;
    }
    return result;
}

extern "C" char Hooked_WaPhysicalRayForward(void* rcx, void* rdx, float* out) {
    const char result = s_originalEval ? s_originalEval(rcx, rdx, out) : 0;
    const bool redirect = s_waPhysicalRayMine;
    void* const sharedContext = s_waPhysicalRayContext;
    const float forward[3] = {
        s_waPhysicalRayMuzzleForward[0],
        s_waPhysicalRayMuzzleForward[1],
        s_waPhysicalRayMuzzleForward[2]
    };
    const float finalOrigin[3] = { s_waPhysicalRayOrigin[0], s_waPhysicalRayOrigin[1], s_waPhysicalRayOrigin[2] };

    s_waPhysicalRayMine = false;
    s_waPhysicalRayContext = nullptr;

    if (!result || !redirect || !out || !ShootingHook::s_isDecoupled) return result;

    __try {
        const float raw[3] = { out[0], out[1], out[2] };

        // Redirect ray along the physical barrel forward direction
        float l2 = forward[0]*forward[0] + forward[1]*forward[1] + forward[2]*forward[2];
        if (l2 > 0.01f) {
            const float invL = 1.0f / std::sqrt(l2);
            out[0] = forward[0] * invL;
            out[1] = forward[1] * invL;
            out[2] = forward[2] * invL;
            out[3] = 0.0f;
        }

        // Write the physical ray back into the blackboard shared data so impact consumers
        // (BulletImpact, decals, audio) read the exact ray that was cast
        if (sharedContext && sharedContext == rdx) {
            WaWriteSharedVector4(sharedContext, kWaPositionCName, finalOrigin, 1.0f);
            WaWriteSharedVector4(sharedContext, kWaForwardCName, out, 0.0f);
        }

        // Telemetry logging to file
        LogRayRedirection(finalOrigin, raw, out);

    } __except (EXCEPTION_EXECUTE_HANDLER) {}
    return result;
}

static bool WaInstallCallsitePatch(uintptr_t siteRva, void* hook, uint8_t*& relayOut) {
    uint8_t* callsite = reinterpret_cast<uint8_t*>(s_exeBase + siteRva);
    if (callsite[0] != 0xE8) return false;
    int32_t rel = 0;
    std::memcpy(&rel, callsite + 1, sizeof(rel));
    if (callsite + 5 + rel != reinterpret_cast<uint8_t*>(s_exeBase + kWaPhysicalRayEvalFn)) return false;

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
    uint8_t patch[5] = {
        0xE8,
        static_cast<uint8_t>(delta & 0xFF),
        static_cast<uint8_t>((delta >> 8) & 0xFF),
        static_cast<uint8_t>((delta >> 16) & 0xFF),
        static_cast<uint8_t>((delta >> 24) & 0xFF)
    };
    DWORD oldProtect = 0;
    if (!VirtualProtect(callsite, sizeof(patch), PAGE_EXECUTE_READWRITE, &oldProtect)) return false;
    std::memcpy(callsite, patch, sizeof(patch));
    FlushInstructionCache(GetCurrentProcess(), callsite, sizeof(patch));
    DWORD ignored = 0;
    VirtualProtect(callsite, sizeof(patch), oldProtect, &ignored);
    return true;
}

bool ShootingHook::Initialize(RED4ext::v1::PluginHandle aHandle, const RED4ext::v1::Sdk* aSdk) {
    s_handle = aHandle;
    s_sdk = aSdk;

    HMODULE h = GetModuleHandleA("Cyberpunk2077.exe");
    if (!h) {
        if (s_sdk && s_sdk->logger) {
            s_sdk->logger->Error(s_handle, "Failed to get Cyberpunk2077.exe module handle.");
        }
        return false;
    }
    s_exeBase = reinterpret_cast<uintptr_t>(h);

    if (s_sdk && s_sdk->logger) {
        s_sdk->logger->Info(s_handle, "Installing PhysicalRay callsites redirection patches...");
    }

    s_originalEval = reinterpret_cast<WaPhysicalRayEvalFn>(s_exeBase + kWaPhysicalRayEvalFn);

    if (!WaInstallCallsitePatch(kWaPhysicalRayOriginCallsite, reinterpret_cast<void*>(&Hooked_WaPhysicalRayOrigin), s_originRelay)) {
        if (s_sdk && s_sdk->logger) {
            s_sdk->logger->Error(s_handle, "Failed to patch PhysicalRay Origin callsite @ 0x9507B7.");
        }
        return false;
    }

    if (!WaInstallCallsitePatch(kWaPhysicalRayForwardCallsite, reinterpret_cast<void*>(&Hooked_WaPhysicalRayForward), s_forwardRelay)) {
        if (s_sdk && s_sdk->logger) {
            s_sdk->logger->Error(s_handle, "Failed to patch PhysicalRay Forward callsite @ 0x9507EC.");
        }
        return false;
    }

    if (s_sdk && s_sdk->logger) {
        s_sdk->logger->Info(s_handle, "PhysicalRay evaluator callsites patched successfully! Ballistics decoupled to weapon muzzle.");
    }

    s_isHooked = true;
    return true;
}

void ShootingHook::Shutdown() {
    if (s_isHooked) {
        s_isHooked = false;
    }
}

void ShootingHook::SetMuzzleAimState(const RED4ext::Vector4& aMuzzlePos, const RED4ext::Vector4& aMuzzleFwd, bool aIsDecoupled) {
    s_muzzlePos = aMuzzlePos;
    s_muzzleFwd = aMuzzleFwd;
    s_isDecoupled = aIsDecoupled;
}

} // namespace DetachedReticle
