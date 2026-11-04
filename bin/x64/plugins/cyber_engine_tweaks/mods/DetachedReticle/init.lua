-- DetachedReticle - Cyber Engine Tweaks Module
-- Decoupled Aiming System (MVP 2 Production Release)
-- 1. Camera Freelook: 100% controllable with mouse gaze; zero lag, instant response.
-- 2. Physical Aiming Direction: Weapon rig & body smoothly lag behind and chase gaze via native exponential smoothing.
-- 3. Muzzle Ballistics: Bullets launch physically from weapon barrel in 3D world space.

local Config = {
    enabled = true,               -- Master switch for decoupled aiming
    activeAimOffset = true,       -- Tier 2B: Actively offset aiming direction to center gun reticle
    catchUpSpeed = 22.0,          -- Responsiveness gain factor k (default: 22.0, yields ~0.7 deg lag at 20 deg/s)
    deadzone = 0.0,               -- Degrees: zero deadzone by default (turns immediately)
    maxDivergence = 65.0,         -- Degrees: maximum angular separation before pulling body
    smoothingMode = "exponential",-- "exponential" (Option A Power-Law), "braking" (Model A), "linear", "spring", or "power"
    expPower = 0.60,              -- Option A: Continuous Power-Law Exponent (1.0 = linear, 0.60 = tight sub-linear chase, default: 0.60)
    brakeThreshold = 2.0,         -- Model A: Degrees from target where deceleration begins (default: 2.0)
    brakeMaxSpeed = 360.0,        -- Model A: Max cruising speed in deg/s (default: 360.0)
    -- Tier 2B Barrel Compensation Parameters (Snappy by default)
    compSpeedSettled = 12.0,      -- T2B compensation speed when settled (default: 12.0, old: 4.5)
    compSpeedMoving = 4.0,        -- T2B compensation speed while swinging mouse (default: 4.0, old: 1.0)
    compMaxSpeed = 240.0,         -- T2B maximum angular speed in deg/s (default: 240.0 deg/s)
    compMinSpeed = 6.0,           -- T2B minimum angular speed in deg/s (prevents early slowdown tail crawl, default: 6.0)
    compGapThreshold = 3.0,       -- Mouse gap threshold in degrees between moving and settled (default: 3.0, old: 5.0)
    -- Tier 2 Recoil Rubber Leash (Option A Radial Soft-Wall Attenuation)
    recoilMaxRadius = 7.0,        -- Degrees: max recoil distance from center reticle during sustained fire (0 = unlimited, default: 7.0)
    recoilLeashCurve = 1.5,       -- Power-law resistance exponent as recoil approaches recoilMaxRadius (default: 1.5)
    -- Tier 2 Strength-Scaled Horizontal Recoil Dynamics
    recoilHoriStatScaling = true, -- Scale horizontal scatter (low Strength) & damping (high Strength) with player Body/Strength [3..20]
    recoilHoriScatter = 1.0,      -- Low-Strength alternating horizontal scatter multiplier (default: 1.0)
    recoilHoriDamping = 0.70,     -- High-Strength native horizontal recoil neutralization factor (default: 0.70)
    -- ADS Lever-Arm Drop Compensation
    adsLeverArmComp = true,       -- Dynamically lower lever-arm root during ADS recoil to prevent sight occlusion
    adsLeverArmLength = 0.35,     -- Effective lever-arm length L in meters for vertical drop h = L * sin(wPitch) (default: 0.35)
    debugLogging = false          -- Verbose telemetry logging to DetachedReticle.log
}

local DetachedReticle = {
    version = "2.0.0",
    timer = 0,
    frameCounter = 0,
    bodyYaw = 0.0,
    baselineRot = nil,
    baselinePos = nil,
    lastAppliedDrop = 0.0,
    playerBodyStat = 3.0,
    playerStrengthFactor = 0.0,
    origHeadingLocked = nil,
    origSensX = nil,
    origSensY = nil,
    isActive = false,
    chaseActive = false,
    registeredPlayer = nil,
    lastShotCount = 0,
    lastLoggedWeapon = nil,
    lastLoggedADS = nil,
    restingFrames = 0,
    isOverlayOpen = false,
    nativeSettingsInitAttempted = false
}

-- Math Helpers for Angle Normalization & Vectors
local function normalizeDeg(angle)
    while angle > 180.0 do angle = angle - 360.0 end
    while angle < -180.0 do angle = angle + 360.0 end
    return angle
end

-- Modular Catch-Up Smoothing Algorithms (script-side fallbacks/references)
local Algorithms = {
    braking = function(diffYaw, diffPitch, divergenceMag, effectiveDivergence, dt, cfg, state)
        if divergenceMag < 0.0001 then return 0.0, 0.0 end
        local thresh = cfg.brakeThreshold or 2.0
        local maxSpd = cfg.brakeMaxSpeed or (cfg.catchUpSpeed * 60.0)
        if divergenceMag <= 0.02 then
            return diffYaw, diffPitch
        end
        local v = maxSpd
        if divergenceMag <= thresh then
            local u = divergenceMag / thresh
            local smooth = u * u * (3.0 - 2.0 * u)
            v = maxSpd * smooth
        end
        local step = math.min(divergenceMag, v * dt)
        local ratio = step / divergenceMag
        return diffYaw * ratio, diffPitch * ratio
    end,

    exponential = function(diffYaw, diffPitch, divergenceMag, effectiveDivergence, dt, cfg, state)
        if divergenceMag < 0.0001 then return 0.0, 0.0 end
        local p = cfg.expPower or 0.60
        local step = 0.0
        if math.abs(p - 1.0) < 0.001 then
            local decay = 1.0 - math.exp(-cfg.catchUpSpeed * dt)
            step = divergenceMag * math.max(0.0, math.min(1.0, decay))
        else
            local oneMinusP = 1.0 - p
            local rem = (divergenceMag ^ oneMinusP) - (oneMinusP * cfg.catchUpSpeed * dt)
            if rem <= 0.0 then
                step = divergenceMag
            else
                local nextGap = rem ^ (1.0 / oneMinusP)
                step = divergenceMag - nextGap
            end
        end
        if step > divergenceMag then step = divergenceMag end
        if divergenceMag <= 0.005 then step = divergenceMag end
        local ratio = step / divergenceMag
        return diffYaw * ratio, diffPitch * ratio
    end,

    linear = function(diffYaw, diffPitch, divergenceMag, effectiveDivergence, dt, cfg, state)
        local rate = cfg.catchUpSpeed * 15.0
        local maxStep = rate * dt
        local ratio = (divergenceMag > 0.001) and math.min(1.0, maxStep / divergenceMag) or 1.0
        if cfg.deadzone > 0.0 and divergenceMag > 0.001 then
            ratio = ratio * (effectiveDivergence / divergenceMag)
        end
        return diffYaw * ratio, diffPitch * ratio
    end,

    spring = function(diffYaw, diffPitch, divergenceMag, effectiveDivergence, dt, cfg, state)
        local omega = cfg.catchUpSpeed
        local expVal = 1.0 / (1.0 + omega * dt + 0.48 * omega * omega * dt * dt + 0.235 * omega * omega * omega * dt * dt * dt)
        local decay = 1.0 - expVal
        decay = math.max(0.0, math.min(1.0, decay))
        if cfg.deadzone > 0.0 and divergenceMag > 0.001 then
            decay = decay * (effectiveDivergence / divergenceMag)
        end
        return diffYaw * decay, diffPitch * decay
    end,

    power = function(diffYaw, diffPitch, divergenceMag, effectiveDivergence, dt, cfg, state)
        local norm = math.min(1.0, effectiveDivergence / math.max(1.0, cfg.maxDivergence))
        local ramp = norm ^ 1.5
        local decay = (1.0 - math.exp(-cfg.catchUpSpeed * dt)) * (0.2 + 0.8 * ramp)
        decay = math.max(0.0, math.min(1.0, decay))
        return diffYaw * decay, diffPitch * decay
    end
}

local function LoadConfig()
    local f = io.open("plugins/cyber_engine_tweaks/mods/DetachedReticle/config.json", "r")
    if not f then
        f = io.open("bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/config.json", "r")
    end
    if f then
        local content = f:read("*a")
        f:close()
        if content and #content > 0 then
            local ok, data = pcall(json.decode, content)
            if ok and type(data) == "table" then
                if data.enabled ~= nil then Config.enabled = (data.enabled == true) end
                if data.activeAimOffset ~= nil then Config.activeAimOffset = (data.activeAimOffset == true) end
                if data.catchUpSpeed ~= nil then Config.catchUpSpeed = tonumber(data.catchUpSpeed) or Config.catchUpSpeed end
                if data.deadzone ~= nil then Config.deadzone = tonumber(data.deadzone) or Config.deadzone end
                if data.maxDivergence ~= nil then Config.maxDivergence = tonumber(data.maxDivergence) or Config.maxDivergence end
                if data.smoothingMode ~= nil then Config.smoothingMode = tostring(data.smoothingMode):lower() end
                if data.brakeThreshold ~= nil then Config.brakeThreshold = tonumber(data.brakeThreshold) or Config.brakeThreshold end
                if data.brakeMaxSpeed ~= nil then Config.brakeMaxSpeed = tonumber(data.brakeMaxSpeed) or Config.brakeMaxSpeed end
                if data.expPower ~= nil then Config.expPower = tonumber(data.expPower) or Config.expPower end
                if data.compSpeedSettled ~= nil then Config.compSpeedSettled = tonumber(data.compSpeedSettled) or Config.compSpeedSettled end
                if data.compSpeedMoving ~= nil then Config.compSpeedMoving = tonumber(data.compSpeedMoving) or Config.compSpeedMoving end
                if data.compMaxSpeed ~= nil then Config.compMaxSpeed = tonumber(data.compMaxSpeed) or Config.compMaxSpeed end
                if data.compMinSpeed ~= nil then Config.compMinSpeed = tonumber(data.compMinSpeed) or Config.compMinSpeed end
                if data.compGapThreshold ~= nil then Config.compGapThreshold = tonumber(data.compGapThreshold) or Config.compGapThreshold end
                if data.recoilMaxRadius ~= nil then Config.recoilMaxRadius = tonumber(data.recoilMaxRadius) or Config.recoilMaxRadius end
                if data.recoilLeashCurve ~= nil then Config.recoilLeashCurve = tonumber(data.recoilLeashCurve) or Config.recoilLeashCurve end
                if data.recoilHoriStatScaling ~= nil then Config.recoilHoriStatScaling = (data.recoilHoriStatScaling == true) end
                if data.recoilHoriScatter ~= nil then Config.recoilHoriScatter = tonumber(data.recoilHoriScatter) or Config.recoilHoriScatter end
                if data.recoilHoriDamping ~= nil then Config.recoilHoriDamping = tonumber(data.recoilHoriDamping) or Config.recoilHoriDamping end
                if data.adsLeverArmComp ~= nil then Config.adsLeverArmComp = (data.adsLeverArmComp == true) end
                if data.adsLeverArmLength ~= nil then Config.adsLeverArmLength = tonumber(data.adsLeverArmLength) or Config.adsLeverArmLength end
                if data.debugLogging ~= nil then Config.debugLogging = (data.debugLogging == true) end
            end
        end
    end
end

local function GetSmoothingModeInt()
    local m = tostring(Config.smoothingMode):lower()
    if m == "braking" or m == "brake" or m == "modela" or m == "smoothstep" then
        return 1
    end
    return 0 -- default to exponential
end

local function SyncRecoilHorizontalParams()
    pcall(function()
        Game.DR_SetRecoilHorizontalParams(
            Config.recoilHoriStatScaling and true or false,
            Config.recoilHoriScatter,
            Config.recoilHoriDamping,
            DetachedReticle.playerStrengthFactor or 0.0
        )
    end)
end

local function UpdatePlayerStrengthStat(player)
    if not player then return end
    local ok, val = pcall(function()
        local statsSys = Game.GetStatsSystem()
        if statsSys then
            return statsSys:GetStatValue(player:GetEntityID(), gamedataStatType.Strength)
        end
        return nil
    end)
    if ok and type(val) == "number" and val > 0.0 then
        DetachedReticle.playerBodyStat = val
        DetachedReticle.playerStrengthFactor = math.max(0.0, math.min(1.0, (val - 3.0) / 17.0))
        SyncRecoilHorizontalParams()
    end
end

local function SyncSmoothing()
    local modeInt = GetSmoothingModeInt()
    pcall(function()
        Game.DR_SetSmoothing(Config.catchUpSpeed, modeInt, Config.maxDivergence, Config.deadzone, DetachedReticle.chaseActive or false)
        Game.DR_SetBrakeParams(Config.brakeThreshold, Config.brakeMaxSpeed)
        Game.DR_SetExpParams(Config.expPower)
        Game.DR_SetRecoilLeashParams(Config.recoilMaxRadius, Config.recoilLeashCurve)
        Game.DR_SetRecoilHorizontalParams(
            Config.recoilHoriStatScaling and true or false,
            Config.recoilHoriScatter,
            Config.recoilHoriDamping,
            DetachedReticle.playerStrengthFactor or 0.0
        )
    end)
end

local function SyncCompParams()
    pcall(function()
        Game.DR_SetCompParams(
            Config.compSpeedSettled,
            Config.compSpeedMoving,
            Config.compMaxSpeed,
            Config.compGapThreshold,
            Config.compMinSpeed
        )
    end)
end

local function SyncRecoilLeashParams()
    pcall(function()
        Game.DR_SetRecoilLeashParams(Config.recoilMaxRadius, Config.recoilLeashCurve)
    end)
end

local function SaveConfig()
    local ok, content = pcall(json.encode, Config)
    if ok and content then
        local f = io.open("plugins/cyber_engine_tweaks/mods/DetachedReticle/config.json", "w")
        if not f then
            f = io.open("bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/config.json", "w")
        end
        if f then
            f:write(content)
            f:flush()
            f:close()
        end
    end
end

local function Log(msg)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local line = string.format("[%s] [DetachedReticle] %s", timestamp, msg)
    print(string.format("[DetachedReticle] %s", msg))

    local f = io.open("plugins/cyber_engine_tweaks/mods/DetachedReticle/DetachedReticle.log", "a")
    if not f then
        f = io.open("bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/DetachedReticle.log", "a")
    end
    if not f then
        f = io.open("DetachedReticle.log", "a")
    end
    if f then
        f:write(line .. "\n")
        f:flush()
        f:close()
    end
end

-- Math Helpers for Quaternions & Vectors (CET Sol sandbox compatible)
local function quatAxisAngle(x, y, z, deg)
    local rad = math.rad(deg)
    local half = rad * 0.5
    local s = math.sin(half)
    return Quaternion.new(x * s, y * s, z * s, math.cos(half))
end

local function quatMultiply(a, b)
    local ar = a.r or a.w or 1
    local ai = a.i or a.x or 0
    local aj = a.j or a.y or 0
    local ak = a.k or a.z or 0

    local br = b.r or b.w or 1
    local bi = b.i or b.x or 0
    local bj = b.j or b.y or 0
    local bk = b.k or b.z or 0

    return Quaternion.new(
        ar * bi + ai * br + aj * bk - ak * bj,
        ar * bj - ai * bk + aj * br + ak * bi,
        ar * bk + ai * bj - aj * bi + ak * br,
        ar * br - ai * bi - aj * bj - ak * bk
    )
end

local function SetupNativeSettings()
    if DetachedReticle.nativeSettingsInitAttempted then return true end

    local ns = nil
    pcall(function()
        ns = GetMod("nativeSettings") or GetMod("NativeSettings")
    end)
    if not ns then return false end

    local ok = pcall(function()
        if not ns.pathExists("/detachedReticle") then
            ns.addTab("/detachedReticle", "Detached Reticle")
            ns.addSubcategory("/detachedReticle/aiming", "Aiming & Catch-up Settings")

            ns.addSwitch(
                "/detachedReticle/aiming",
                "Enable Decoupled Aim",
                "Master switch to toggle decoupled aiming and physical muzzle ballistics",
                Config.enabled, true,
                function(val)
                    DetachedReticle.SetEnabled(val)
                end
            )

            ns.addSwitch(
                "/detachedReticle/aiming",
                "Active Aim Offset (Tier 2B)",
                "Actively offsets the character body and arms to center the gun reticle at rest",
                Config.activeAimOffset, true,
                function(val)
                    DetachedReticle.SetActiveAimOffset(val)
                end
            )

            ns.addRangeFloat(
                "/detachedReticle/aiming",
                "Catch-up Speed",
                "Speed at which the body and gun turn to align with the camera reticle (0 = pure freelook, 22 = default)",
                0.0, 30.0, 0.5, "%.1f", Config.catchUpSpeed, 22.0,
                function(val)
                    DetachedReticle.SetCatchUpSpeed(val)
                end
            )

            ns.addRangeFloat(
                "/detachedReticle/aiming",
                "Deadzone Angle",
                "Angular zone where the body does not turn towards the camera (0.0 = zero deadzone, turns immediately)",
                0.0, 30.0, 0.5, "%.1f deg", Config.deadzone, 0.0,
                function(val)
                    DetachedReticle.SetDeadzone(val)
                end
            )

            ns.addRangeFloat(
                "/detachedReticle/aiming",
                "Max Divergence",
                "Maximum angular separation between camera and body before pulling the body along immediately",
                15.0, 110.0, 1.0, "%.0f deg", Config.maxDivergence, 65.0,
                function(val)
                    DetachedReticle.SetMaxDivergence(val)
                end
            )

            local algoOptions = { "Braking", "Exponential", "Linear", "Spring", "Power" }
            local currentIdx = 2
            for i, name in ipairs(algoOptions) do
                if name:lower() == Config.smoothingMode:lower() then
                    currentIdx = i
                    break
                end
            end

            ns.addSelectorString(
                "/detachedReticle/aiming",
                "Catch-up Algorithm",
                "Algorithm used to calculate the catch-up curve towards the camera reticle (Exponential = default Power-Law, Braking = Model A)",
                algoOptions, currentIdx, 2,
                function(idx)
                    local selected = algoOptions[idx] or "Exponential"
                    DetachedReticle.SetSmoothingMode(selected:lower())
                end
            )

            ns.addRangeFloat(
                "/detachedReticle/aiming",
                "Braking Threshold Angle",
                "Model A: Distance in degrees from camera gaze where deceleration begins (default: 2.0 deg)",
                0.5, 10.0, 0.1, "%.1f deg", Config.brakeThreshold, 2.0,
                function(val)
                    DetachedReticle.SetBrakeThreshold(val)
                end
            )

            ns.addRangeFloat(
                "/detachedReticle/aiming",
                "Max Cruise Speed",
                "Model A: Maximum cruising angular speed in degrees per second before entering braking zone (default: 360 deg/s)",
                60.0, 1200.0, 10.0, "%.0f deg/s", Config.brakeMaxSpeed, 360.0,
                function(val)
                    DetachedReticle.SetBrakeMaxSpeed(val)
                end
            )

            ns.addRangeFloat(
                "/detachedReticle/aiming",
                "Curve Exponent (Power-Law)",
                "Option A: Continuous Power-Law curve exponent p. 1.0 = linear exponential, 0.60 = tight sub-linear chase (reaches 20% distance at normal speed, default: 0.60)",
                0.30, 1.20, 0.05, "%.2f", Config.expPower, 0.60,
                function(val)
                    DetachedReticle.SetExpPower(val)
                end
            )

            ns.addSubcategory("/detachedReticle/compensation", "Tier 2B Gun Alignment Speed & Snappiness")

            ns.addRangeFloat(
                "/detachedReticle/compensation",
                "Settled Alignment Speed",
                "Speed at which the gun aligns to center when mouse movement settles (default: 12.0, old: 4.5)",
                1.0, 30.0, 0.5, "%.1f", Config.compSpeedSettled, 12.0,
                function(val)
                    DetachedReticle.SetCompSpeedSettled(val)
                end
            )

            ns.addRangeFloat(
                "/detachedReticle/compensation",
                "Moving Alignment Speed",
                "Speed at which the gun aligns while swinging or moving mouse (default: 4.0, old: 1.0)",
                0.5, 20.0, 0.5, "%.1f", Config.compSpeedMoving, 4.0,
                function(val)
                    DetachedReticle.SetCompSpeedMoving(val)
                end
            )

            ns.addRangeFloat(
                "/detachedReticle/compensation",
                "Max Angular Speed",
                "Maximum angular speed for barrel offset compensation in degrees per second (default: 240.0 deg/s)",
                30.0, 600.0, 10.0, "%.0f deg/s", Config.compMaxSpeed, 240.0,
                function(val)
                    DetachedReticle.SetCompMaxSpeed(val)
                end
            )

            ns.addRangeFloat(
                "/detachedReticle/compensation",
                "Min Tail Angular Speed",
                "Minimum speed to snap the last degrees of alignment and prevent early slowdown (default: 6.0 deg/s)",
                0.0, 30.0, 0.5, "%.1f deg/s", Config.compMinSpeed, 6.0,
                function(val)
                    DetachedReticle.SetCompMinSpeed(val)
                end
            )

            ns.addRangeFloat(
                "/detachedReticle/compensation",
                "Dynamic Gap Threshold",
                "Mouse divergence angle threshold switching between moving and settled speeds (default: 3.0 deg, old: 5.0 deg)",
                0.5, 15.0, 0.5, "%.1f deg", Config.compGapThreshold, 3.0,
                function(val)
                    DetachedReticle.SetCompGapThreshold(val)
                end
            )

            ns.addSubcategory("/detachedReticle/recoilLeash", "Tier 2 Recoil Rubber Leash")

            ns.addRangeFloat(
                "/detachedReticle/recoilLeash",
                "Max Recoil Leash Angle",
                "Maximum angular distance the gun reticle can climb from center during extended fire (0.0 = unlimited, default: 7.0 deg)",
                0.0, 25.0, 0.5, "%.1f deg", Config.recoilMaxRadius, 7.0,
                function(val)
                    DetachedReticle.SetRecoilMaxRadius(val)
                end
            )

            ns.addRangeFloat(
                "/detachedReticle/recoilLeash",
                "Leash Resistance Curve",
                "Rubber resistance exponent p (1 - (r/Rmax)^p). Lower = earlier progressive pull; Higher = freer climb then firm wall near Rmax (default: 1.5)",
                0.5, 4.0, 0.1, "%.1f", Config.recoilLeashCurve, 1.5,
                function(val)
                    DetachedReticle.SetRecoilLeashCurve(val)
                end
            )

            ns.addSubcategory("/detachedReticle/recoilHorizontal", "Tier 2 Horizontal Recoil & Strength Scaling")

            ns.addSwitch(
                "/detachedReticle/recoilHorizontal",
                "Scale with Body/Strength Stat",
                "Automatically scales low-Strength alternating horizontal scatter (Body 3 -> 100%, Body 20 -> 0%) and high-Strength native recoil neutralization (Body 3 -> 0%, Body 20 -> 100%) (default: On)",
                Config.recoilHoriStatScaling, true,
                function(val)
                    DetachedReticle.SetRecoilHoriStatScaling(val)
                end
            )

            ns.addRangeFloat(
                "/detachedReticle/recoilHorizontal",
                "Low-Strength Horizontal Scatter",
                "Alternating left/right horizontal recoil push multiplier at low Body/Strength (0.0 = off, default: 1.0)",
                0.0, 3.0, 0.05, "%.2f", Config.recoilHoriScatter, 1.0,
                function(val)
                    DetachedReticle.SetRecoilHoriScatter(val)
                end
            )

            ns.addRangeFloat(
                "/detachedReticle/recoilHorizontal",
                "High-Strength Horizontal Damping",
                "Fraction of native horizontal recoil counteracted in the opposite direction at high Body/Strength (0.0 = off, default: 0.70)",
                0.0, 0.95, 0.05, "%.2f", Config.recoilHoriDamping, 0.70,
                function(val)
                    DetachedReticle.SetRecoilHoriDamping(val)
                end
            )

            ns.addSubcategory("/detachedReticle/leverArm", "ADS Lever-Arm Sight-Line Compensation")

            ns.addSwitch(
                "/detachedReticle/leverArm",
                "Enable ADS Lever-Arm Drop",
                "Dynamically lower the lever-arm root during ADS in proportion to upward gun recoil pitch, keeping the gun body/receiver below the sight-line to T3 (default: On)",
                Config.adsLeverArmComp, true,
                function(val)
                    DetachedReticle.SetAdsLeverArmComp(val)
                end
            )

            ns.addRangeFloat(
                "/detachedReticle/leverArm",
                "Lever-Arm Drop Length",
                "Effective lever-arm length L in meters for vertical drop h = L * sin(wPitch) (default: 0.35m)",
                0.10, 1.00, 0.05, "%.2f m", Config.adsLeverArmLength, 0.35,
                function(val)
                    DetachedReticle.SetAdsLeverArmLength(val)
                end
            )

            Log("[SETTINGS] NativeSettings tab '/detachedReticle' successfully initialized.")
        end
    end)

    DetachedReticle.nativeSettingsInitAttempted = ok
    return ok
end

registerForEvent("onInit", function()
    LoadConfig()
    SyncCompParams()
    SyncRecoilLeashParams()
    SyncRecoilHorizontalParams()
    Log(string.format("Initializing Decoupled Aiming System v%s | Enabled=%s | Speed=%.1f | Deadzone=%.1f deg | MaxDiv=%.1f deg | CompSettled=%.1f | CompMoving=%.1f | CompMax=%.0f deg/s | RecoilLeash=%.1f deg (p=%.1f) | HoriScale=%s (Scatter=%.2f, Damping=%.2f)",
        DetachedReticle.version, tostring(Config.enabled), Config.catchUpSpeed, Config.deadzone, Config.maxDivergence, Config.compSpeedSettled, Config.compSpeedMoving, Config.compMaxSpeed, Config.recoilMaxRadius, Config.recoilLeashCurve, tostring(Config.recoilHoriStatScaling), Config.recoilHoriScatter, Config.recoilHoriDamping))

    SetupNativeSettings()
end)

registerForEvent("onUpdate", function(delta)
    local player = Game.GetPlayer()
    if not player then
        DetachedReticle.isActive = false
        DetachedReticle.chaseActive = false
        DetachedReticle.wasArmed = false
        DetachedReticle.lastWrittenRPitch = 0.0
        return
    end

    if not DetachedReticle.nativeSettingsInitAttempted then
        SetupNativeSettings()
    end

    local weapon = GameObject.GetRightActiveWeapon(player)
    local fpp = player:GetFPPCameraComponent()

    local isDual = false
    pcall(function()
        isDual = GameObject.IsDualWielding(player)
    end)
    local isArmed = weapon and not weapon:IsMelee() and not isDual

    -- Residual, compensation, and recoil settling state:
    -- Keeps decoupled camera active until compensation, recoil, and residual smoothly reach 0.0,
    -- preventing any camera snap during holster or weapon transition.
    local rYaw = 0.0
    local rPitch = 0.0
    local cYaw = 0.0
    local cPitch = 0.0
    local wYaw = 0.0
    local wPitch = 0.0
    pcall(function() rYaw = Game.DR_GetResidualYaw() end)
    pcall(function() rPitch = Game.DR_GetResidualPitch() end)
    pcall(function() cYaw = Game.DR_GetCompYaw() end)
    pcall(function() cPitch = Game.DR_GetCompPitch() end)
    pcall(function() wYaw = Game.DR_GetRecoilYaw() end)
    pcall(function() wPitch = Game.DR_GetRecoilPitch() end)
    local settling = (math.abs(rYaw) + math.abs(rPitch) > 0.10) or (math.abs(cYaw) + math.abs(cPitch) > 0.10) or (math.abs(wYaw) + math.abs(wPitch) > 0.05)

    -- Prevent settling deadlock when unarmed and native mouse hook (0x51D462) is not ticking (e.g. Hacking UI, menus, dialogs)
    if not isArmed and settling then
        local settleDelta = math.abs(rYaw - (DetachedReticle.lastSettleRYaw or 0.0))
                          + math.abs(rPitch - (DetachedReticle.lastSettleRPitch or 0.0))
                          + math.abs(cYaw - (DetachedReticle.lastSettleCYaw or 0.0))
                          + math.abs(cPitch - (DetachedReticle.lastSettleCPitch or 0.0))
                          + math.abs(wYaw - (DetachedReticle.lastSettleWYaw or 0.0))
                          + math.abs(wPitch - (DetachedReticle.lastSettleWPitch or 0.0))
        if settleDelta < 1e-5 then
            DetachedReticle.stalledSettleFrames = (DetachedReticle.stalledSettleFrames or 0) + 1
            if DetachedReticle.stalledSettleFrames >= 3 then
                settling = false
            end
        else
            DetachedReticle.stalledSettleFrames = 0
        end
    else
        DetachedReticle.stalledSettleFrames = 0
    end
    DetachedReticle.lastSettleRYaw = rYaw
    DetachedReticle.lastSettleRPitch = rPitch
    DetachedReticle.lastSettleCYaw = cYaw
    DetachedReticle.lastSettleCPitch = cPitch
    DetachedReticle.lastSettleWYaw = wYaw
    DetachedReticle.lastSettleWPitch = wPitch

    local shouldBeActive = Config.enabled and fpp and (isArmed or settling)

    if shouldBeActive then
        DetachedReticle.isActive = true
        DetachedReticle.frameCounter = (DetachedReticle.frameCounter or 0) + 1
        if DetachedReticle.frameCounter % 30 == 1 then
            UpdatePlayerStrengthStat(player)
        end

        -- 1. Read player puppet world yaw in engine convention
        local bodyYaw = 0.0
        local okYaw, valYaw = pcall(function() return player:GetWorldYaw() end)
        if okYaw and valYaw then
            bodyYaw = valYaw
        else
            local okFwd, fwd = pcall(function() return player:GetWorldForward() end)
            if okFwd and fwd then
                local okHead, head = pcall(function() return Vector4.Heading(fwd) end)
                if okHead and head then bodyYaw = head end
            end
        end
        DetachedReticle.bodyYaw = bodyYaw

        -- 2. Read camera component local orientation and rendered camera forward
        local localRot = nil
        pcall(function() localRot = fpp:GetLocalOrientation() end)

        local camYaw, camPitch = 0.0, 0.0
        local hasCamFwd = false
        pcall(function()
            local cf = Game.GetCameraSystem():GetActiveCameraForward()
            if cf then
                local cx = cf.x or cf.X or 0.0
                local cy = cf.y or cf.Y or 0.0
                local cz = cf.z or cf.Z or 0.0
                local xy = math.sqrt(cx * cx + cy * cy)
                if xy > 0.0001 or math.abs(cz) > 0.0001 then
                    camYaw = Vector4.Heading(cf)
                    camPitch = math.deg(math.atan2(cz, xy))
                    hasCamFwd = true
                end
            end
        end)

        if not DetachedReticle.chaseActive then
            DetachedReticle.chaseActive = true
            DetachedReticle.baselineRot = localRot or Quaternion.new(0, 0, 0, 1)
            local okPos, bPos = pcall(function() return fpp:GetLocalPosition() end)
            if okPos and bPos then
                DetachedReticle.baselinePos = Vector4.new(bPos.x or 0.0, bPos.y or 0.0, bPos.z or 0.0, bPos.w or 1.0)
            end
            DetachedReticle.lastAppliedDrop = 0.0
            DetachedReticle.lastWrittenRot = nil
            DetachedReticle.lastWrittenRPitch = 0.0
            DetachedReticle.lastCamYaw = nil
            DetachedReticle.lastBodyYaw = nil
            DetachedReticle.lastCYaw = nil
            DetachedReticle.lastSettledCompTargetYaw = 0.0
            DetachedReticle.lastSettledCompTargetPitch = 0.0

            -- Capture baseline sensitivity and heading lock before enabling chase
            local okNatX, natX = pcall(function() return Game.DR_GetSensitivityMultX(fpp) end)
            local okNatY, natY = pcall(function() return Game.DR_GetSensitivityMultY(fpp) end)
            local okPropX, propX = pcall(function() return fpp.sensitivityMultX end)
            local okPropY, propY = pcall(function() return fpp.sensitivityMultY end)
            DetachedReticle.origSensX = (okNatX and type(natX) == "number" and natX > 0.0) and natX or ((okPropX and type(propX) == "number") and propX or 1.0)
            DetachedReticle.origSensY = (okNatY and type(natY) == "number" and natY > 0.0) and natY or ((okPropY and type(propY) == "number") and propY or 1.0)

            local okHead, headLocked = pcall(function() return Game.DR_GetHeadingLocked(fpp) end)
            DetachedReticle.origHeadingLocked = (okHead and headLocked) or false

            -- Get initial camera pitch before chase begins from rendered active camera (Fix F0)
            local initPitch = hasCamFwd and camPitch or 0.0

            -- Reset native chase state with initial pitch and activate native look smoothing
            UpdatePlayerStrengthStat(player)
            pcall(function() Game.DR_ResetChasePitch(initPitch) end)
            SyncSmoothing()
            SyncCompParams()

            -- Ensure heading lock is FALSE so engine actuates native chase deltas
            pcall(function() Game.DR_SetHeadingLocked(fpp, false) end)
            pcall(function() fpp.headingLocked = false end)

            -- Ensure sensitivity multipliers are at baseline
            pcall(function() Game.DR_SetSensitivityMult(fpp, DetachedReticle.origSensX, DetachedReticle.origSensY) end)
            pcall(function() fpp.sensitivityMultX = DetachedReticle.origSensX end)
            pcall(function() fpp.sensitivityMultY = DetachedReticle.origSensY end)

            Log(string.format("Decoupled Aim ACTIVE: mode=%s speed=%.1f expPower=%.2f brakeThresh=%.1f brakeMax=%.0f maxDiv=%.1f deadzone=%.1f initPitch=%.2f",
                Config.smoothingMode, Config.catchUpSpeed, Config.expPower, Config.brakeThreshold, Config.brakeMaxSpeed, Config.maxDivergence, Config.deadzone, initPitch))
        elseif isArmed and not DetachedReticle.wasArmed and hasCamFwd then
            -- Re-arming while chaseActive remained true (e.g. exiting Hacking UI or cancelling holster):
            -- Re-seed pitch if external camera controller shifted pitch while unarmed.
            local curTPitch = camPitch
            pcall(function() curTPitch = Game.DR_GetTargetPitch() end)
            if math.abs(camPitch - curTPitch) > 0.5 then
                pcall(function() Game.DR_ResetChasePitch(camPitch) end)
                DetachedReticle.lastWrittenRPitch = 0.0
                DetachedReticle.lastSettledCompTargetYaw = 0.0
                DetachedReticle.lastSettledCompTargetPitch = 0.0
                Log(string.format("Decoupled Aim RE-SEED on re-arm: camPitch=%.2f prevTPitch=%.2f", camPitch, curTPitch))
            end
        end

        -- Read native camera residuals (R = T - T2B = (T - A) + C - W)
        local rYaw = 0.0
        local rPitch = 0.0
        pcall(function() rYaw = Game.DR_GetResidualYaw() end)
        pcall(function() rPitch = Game.DR_GetResidualPitch() end)
        pcall(function() wYaw = Game.DR_GetRecoilYaw() end)
        pcall(function() wPitch = Game.DR_GetRecoilPitch() end)

        -- When fully settled at rest, silently re-sync native dead-reckoned pitch if external camera shifted it
        if hasCamFwd and math.abs(rYaw) < 0.05 and math.abs(rPitch) < 0.05 and math.abs(cYaw) < 0.05 and math.abs(cPitch) < 0.05 and math.abs(wYaw) < 0.05 and math.abs(wPitch) < 0.05 then
            local curTPitch = camPitch
            pcall(function() curTPitch = Game.DR_GetTargetPitch() end)
            if math.abs(camPitch - curTPitch) > 0.5 then
                pcall(function() Game.DR_ResetChasePitch(camPitch) end)
                rYaw, rPitch = 0.0, 0.0
                DetachedReticle.lastWrittenRPitch = 0.0
            end
        end

        -- Resolve aiming posture and ADS state
        local psmBB = nil
        pcall(function() psmBB = player:GetPlayerStateMachineBlackboard() end)
        local crosshairState = -1
        local upperBodyState = -1
        if psmBB then
            pcall(function()
                crosshairState = psmBB:GetInt(GetAllBlackboardDefs().PlayerStateMachine.Crosshair)
                upperBodyState = psmBB:GetInt(GetAllBlackboardDefs().PlayerStateMachine.UpperBody)
            end)
        end
        local isADS = (crosshairState == 4 or upperBodyState == 6)

        -- Physical socket pitch angle in parent coordinate frame:
        -- Derived directly from rendered camera pitch minus the previous frame's written local pitch residual,
        -- guaranteeing the horizontal yaw axis is always aligned with true world-up even if the engine alters pitch externally.
        local socketPitch = 0.0
        if hasCamFwd then
            socketPitch = camPitch - (DetachedReticle.lastWrittenRPitch or 0.0)
        else
            pcall(function() socketPitch = Game.DR_GetT2BPitch() end)
        end
        local pitchRad = math.rad(socketPitch)
        local fwdZ = math.sin(pitchRad)
        local fwdXY = math.cos(pitchRad)

        -- Compose residual onto camera local orientation without gimbal roll:
        -- 1. qRx: pitch around local horizontal right axis (1, 0, 0)
        -- 2. qRz: yaw around true gravity-up axis (0, fwdZ, fwdXY) in parent coordinate frame
        local baseline = DetachedReticle.baselineRot or Quaternion.new(0, 0, 0, 1)
        local qRx = quatAxisAngle(1.0, 0.0, 0.0, rPitch)
        local qRz = quatAxisAngle(0.0, fwdZ, fwdXY, rYaw)
        local qRel = quatMultiply(qRz, qRx)
        local targetRot = quatMultiply(qRel, baseline)
        -- [PROBE 1C] Did anything else write the fpp local orientation since our last write?
        -- Angle between the orientation read this frame (before writing) and the one we wrote last frame.
        local fppOverwriteDeg = 0.0
        local lastRot = DetachedReticle.lastWrittenRot
        if Config.debugLogging and lastRot and localRot then
            local dot = (localRot.i or 0) * (lastRot.i or 0) + (localRot.j or 0) * (lastRot.j or 0)
                      + (localRot.k or 0) * (lastRot.k or 0) + (localRot.r or 1) * (lastRot.r or 1)
            fppOverwriteDeg = math.deg(2.0 * math.acos(math.min(1.0, math.abs(dot))))
        end

        -- Apply ADS Lever-Arm Drop Compensation:
        -- In ADS, when the gun pitches up due to weapon recoil (wPitch > 0), the skeletal lever arm
        -- around the shoulder pivot causes the gun body/receiver to rise up faster than the distant T3 sight line.
        -- We lower the root of the lever arm (elevate camera along world-up) by h = L_drop * sin(wPitch),
        -- keeping the gun receiver from occluding the line of sight between the camera and T3.
        local dropDist = 0.0
        if Config.adsLeverArmComp and isADS and (wPitch > 0.001) then
            local armLen = (type(Config.adsLeverArmLength) == "number") and Config.adsLeverArmLength or 0.35
            dropDist = armLen * math.sin(math.rad(wPitch))
        end

        local curPos = nil
        local okCurPos, cp = pcall(function() return fpp:GetLocalPosition() end)
        if okCurPos and cp then
            curPos = cp
        else
            curPos = DetachedReticle.baselinePos or Vector4.new(0.0, 0.0, 0.0, 1.0)
        end

        local lastDrop = DetachedReticle.lastAppliedDrop or 0.0
        DetachedReticle.lastAppliedDrop = dropDist

        -- In the parent coordinate frame (head socket tilted by socketPitch):
        -- True world-up is (0.0, fwdZ, fwdXY).
        -- Moving the camera along world-up by +dropDist lowers the gun body relative to camera gaze.
        -- Apply delta dDrop = dropDist - lastDrop to prevent compounding:
        local dDrop = dropDist - lastDrop
        local targetPosX = (curPos.x or 0.0)
        local targetPosY = (curPos.y or 0.0) + (dDrop * fwdZ)
        local targetPosZ = (curPos.z or 0.0) + (dDrop * fwdXY)
        local targetPos = Vector4.new(targetPosX, targetPosY, targetPosZ, curPos.w or 1.0)

        pcall(function()
            fpp:SetLocalTransform(targetPos, targetRot)
        end)
        DetachedReticle.lastWrittenRot = targetRot
        DetachedReticle.lastWrittenRPitch = rPitch

        if Config.debugLogging then
            local tYaw = 0.0
            local aYaw = 0.0
            local tPitch = 0.0
            local aPitch = 0.0
            local cYawNow = 0.0
            local dRecYaw = 0.0
            local dRecPitch = 0.0
            local splitErrYaw = 0.0
            local splitErrPitch = 0.0
            pcall(function() tYaw = Game.DR_GetTargetYaw() end)
            pcall(function() aYaw = Game.DR_GetAimYaw() end)
            pcall(function() tPitch = Game.DR_GetTargetPitch() end)
            pcall(function() aPitch = Game.DR_GetAimPitch() end)
            pcall(function() cYawNow = Game.DR_GetCompYaw() end)
            pcall(function() dRecYaw = Game.DR_GetLastDeltaRecoilYaw() end)
            pcall(function() dRecPitch = Game.DR_GetLastDeltaRecoilPitch() end)
            pcall(function() splitErrYaw = Game.DR_GetSplitErrYaw() end)
            pcall(function() splitErrPitch = Game.DR_GetSplitErrPitch() end)

            -- [PROBE P1] Rendered camera heading/pitch (CameraSystem.GetActiveCameraForward, cameraSystem.script:14)
            local dCamYaw = normalizeDeg(camYaw - (DetachedReticle.lastCamYaw or camYaw))
            local dBody = normalizeDeg(bodyYaw - (DetachedReticle.lastBodyYaw or bodyYaw))
            -- Predicted puppet step from the hook: dA - dC + dRec
            local predBody = aYaw - (cYawNow - (DetachedReticle.lastCYaw or cYawNow)) + dRecYaw
            DetachedReticle.lastCamYaw = camYaw
            DetachedReticle.lastBodyYaw = bodyYaw
            DetachedReticle.lastCYaw = cYawNow

            -- [PROBE SEED] Model pitch T vs rendered camera pitch. Non-zero steady error = wrong initPitch seed or skeletal camera shake.
            local seedErr = camPitch - tPitch

            local line = string.format("[F=%d] bodyYaw=%.4f rYaw=%.4f rPitch=%.4f tPitch=%.4f aPitch=%.4f fwdZ=%.4f fwdXY=%.4f | [P1] camYaw=%.3f camPitch=%.3f dCam=%+.3f dBody=%+.3f predBody=%+.3f cYaw=%+.3f | [1C] fppOverwrite=%.3f | [SEED] pitchErr=%+.3f | [RECOIL] W=(%+.3f,%+.3f) dRec=(%+.4f,%+.4f) splitErr=(%+.5f,%+.5f)",
                DetachedReticle.frameCounter, bodyYaw, rYaw, rPitch, tPitch, aPitch, fwdZ, fwdXY,
                camYaw, camPitch, dCamYaw, dBody, predBody, cYawNow, fppOverwriteDeg, seedErr,
                wYaw, wPitch, dRecYaw, dRecPitch, splitErrYaw, splitErrPitch)
            Log(line)
        end

        -- 3. Resolve weapon type and evolution
        local weaponName = "Unknown"
        local isHeavyWeapon = false
        local isLMG = false
        local isSmartWeapon = false
        if weapon then
            pcall(function()
                local itemID = weapon:GetItemID()
                local tdbid = ItemID.GetTDBID(itemID)
                weaponName = TDBID.ToStringDEBUG(tdbid)
                isHeavyWeapon = weapon:IsHeavyWeapon()
                local wType = WeaponObject.GetWeaponType(itemID)
                if not wType then
                    wType = RPGManager.GetItemType(itemID)
                end
                if wType then
                    local wTypeStr = tostring(wType)
                    if wType.value == "Wea_LightMachineGun" or wTypeStr:find("Wea_LightMachineGun") or wType == gamedataItemType.Wea_LightMachineGun then
                        isLMG = true
                    elseif wType.value == "Wea_HeavyMachineGun" or wTypeStr:find("Wea_HeavyMachineGun") or wType == gamedataItemType.Wea_HeavyMachineGun then
                        isHeavyWeapon = true
                    end
                end
                local evo = RPGManager.GetWeaponEvolution(itemID)
                if evo and (evo.value == "Smart" or tostring(evo) == "gamedataWeaponEvolution.Smart" or evo == gamedataWeaponEvolution.Smart) then
                    isSmartWeapon = true
                end
            end)
            if not isHeavyWeapon and weaponName and (weaponName:find("HMG") or weaponName:find("HeavyMachineGun")) then
                isHeavyWeapon = true
            end
            if not isLMG and weaponName and (weaponName:find("Defender") or weaponName:find("MA70") or weaponName:find("LMG") or weaponName:find("LightMachineGun")) then
                isLMG = true
            end
            if not isSmartWeapon and weaponName and (weaponName:find("Smart") or weaponName:find("smart")) then
                isSmartWeapon = true
            end
        end

        -- [PROBE SMART] Log smart weapon targeting parameters and UI state every 30 frames
        if isSmartWeapon then
            DetachedReticle.smartFrameCounter = (DetachedReticle.smartFrameCounter or 0) + 1
            if DetachedReticle.smartFrameCounter % 30 == 0 then
                local ctrlClass = "NULL"
                local widgetName = "NULL"
                local xhairRecord = "NULL"
                local calls = 0
                local preIntro = 0
                local targets = 0
                local locked = 0
                local hasLink = false
                local regX, regY = 0.0, 0.0
                local rootVis = false
                local rootOpacity = 0.0

                pcall(function()
                    local probeAimSys = Game.GetScriptableSystemsContainer():Get(CName.new("DetachedReticle.DetachedAimSystem"))
                    if probeAimSys then
                        ctrlClass = probeAimSys:GetSmartCtrlClass()
                        widgetName = probeAimSys:GetSmartWidgetName()
                        xhairRecord = probeAimSys:GetSmartExpectedXhair()
                        calls = probeAimSys:GetSmartCalls()
                        preIntro = probeAimSys:GetSmartPreIntro()
                        targets = probeAimSys:GetSmartTargets()
                        locked = probeAimSys:GetSmartLocked()
                        hasLink = probeAimSys:GetSmartHasLink()
                        local reg = probeAimSys:GetSmartRegion()
                        if reg then
                            regX = reg.x or reg.X or 0.0
                            regY = reg.y or reg.Y or 0.0
                        end
                        rootVis = probeAimSys:GetSmartRootVis()
                        rootOpacity = probeAimSys:GetSmartRootOpacity()
                    end
                end)

                local deltaCalls = calls - (DetachedReticle.lastSmartCalls or 0)
                DetachedReticle.lastSmartCalls = calls

                local psmLocked = false
                pcall(function()
                    if psmBB then
                        psmLocked = psmBB:GetBool(GetAllBlackboardDefs().PlayerStateMachine.HasSmartGunLockedOnTarget)
                    end
                end)

                local playerSmartLink = 0.0
                pcall(function()
                    local statsSys = Game.GetStatsSystem()
                    if statsSys and player then
                        playerSmartLink = statsSys:GetStatValue(player:GetEntityID(), gamedataStatType.HasSmartLink)
                    end
                end)

                local smartLine = string.format("[SMART] ctrl=%s widget=%s xhairRecord=%s calls=%d preIntro=%d targets=%d locked=%d hasLink=%s region=(%.1f,%.1f) rootVis=%s rootOpacity=%.2f psmLocked=%s playerSmartLink=%.0f chase=%s",
                    tostring(ctrlClass), tostring(widgetName), tostring(xhairRecord), deltaCalls, preIntro, targets, locked,
                    tostring(hasLink), regX, regY, tostring(rootVis), rootOpacity,
                    tostring(psmLocked), playerSmartLink, tostring(DetachedReticle.chaseActive))
                Log(smartLine)
            end
        end

        local aimSys = nil
        pcall(function()
            aimSys = Game.GetScriptableSystemsContainer():Get(CName.new("DetachedReticle.DetachedAimSystem"))
        end)

        local gunFwd = nil
        local scrX, scrY = 0.0, 0.0
        local muzScrX, muzScrY = 0.0, 0.0
        local muzRelR, muzRelF, muzRelU = 0.0, 0.0, 0.0
        local angleDeg = 0.0
        local yawLag = 0.0
        local pitchLag = 0.0
        if aimSys then
            pcall(function()
                gunFwd = aimSys:GetGunForward()
                local offset = aimSys:GetScreenOffset()
                if offset then
                    scrX = offset.x or offset.X or 0.0
                    scrY = offset.y or offset.Y or 0.0
                end
                local muzOffset = aimSys:GetMuzzleScreen()
                if muzOffset then
                    muzScrX = muzOffset.x or muzOffset.X or 0.0
                    muzScrY = muzOffset.y or muzOffset.Y or 0.0
                end
                local relCam = aimSys:GetMuzzleRelCam()
                if relCam then
                    muzRelR = relCam.x or relCam.X or 0.0
                    muzRelF = relCam.y or relCam.Y or 0.0
                    muzRelU = relCam.z or relCam.Z or 0.0
                end
                angleDeg = aimSys:GetAngleLagDeg() or 0.0
                yawLag = aimSys:GetYawLagDeg() or 0.0
                pitchLag = aimSys:GetPitchLagDeg() or 0.0
            end)
        end

        local stateStr = "HIP"
        if isADS then
            stateStr = "ADS"
        elseif crosshairState == 5 or upperBodyState == 3 then
            stateStr = "RELOAD"
        elseif crosshairState == 7 then
            stateStr = "SPRINT"
        elseif crosshairState == 1 or upperBodyState == 1 then
            stateStr = "SAFE"
        end

        -- Check mouse deflection gap and active recoil state to determine resting status
        local tYaw = 0.0
        local aYaw = 0.0
        local tPitch = 0.0
        local aPitch = 0.0
        pcall(function() tYaw = Game.DR_GetTargetYaw() end)
        pcall(function() aYaw = Game.DR_GetAimYaw() end)
        pcall(function() tPitch = Game.DR_GetTargetPitch() end)
        pcall(function() aPitch = Game.DR_GetAimPitch() end)
        local rawGapYaw = math.abs(normalizeDeg(tYaw - aYaw))
        local rawGapPitch = math.abs(tPitch - aPitch)
        local isRecoiling = (math.abs(wYaw) + math.abs(wPitch) > 0.02)
        local isResting = (rawGapYaw < 0.10) and (rawGapPitch < 0.10) and (not isRecoiling)

        if isResting and stateStr == "HIP" then
            DetachedReticle.restingFrames = (DetachedReticle.restingFrames or 0) + 1
        else
            DetachedReticle.restingFrames = 0
        end

        -- 4. Tier 2B Active Barrel Offset Control Loop (Per-Frame Execution)
        local diffYaw = 0.0
        local diffPitch = 0.0
        local gunYaw = 0.0
        local gunPitch = 0.0
        local t2bPitch = 0.0
        local fx, fy, fz = 0.0, 0.0, 0.0
        if gunFwd then
            fx = gunFwd.x or gunFwd.X or 0.0
            fy = gunFwd.y or gunFwd.Y or 0.0
            fz = gunFwd.z or gunFwd.Z or 0.0
            local fxy = math.sqrt(fx * fx + fy * fy)
            gunPitch = (fxy > 0.0001 or math.abs(fz) > 0.0001) and math.deg(math.atan2(fz, fxy)) or 0.0

            local okGYaw, gYaw = pcall(function() return Vector4.Heading(gunFwd) end)
            if okGYaw and gYaw then
                gunYaw = gYaw
            else
                gunYaw = math.deg(math.atan2(-fx, fy))
            end

            t2bPitch = socketPitch

            -- Body-relative anatomical offset (fixed-point target C = O):
            -- Eliminates the half-gain error and dynamic chase gap pollution
            diffYaw = normalizeDeg(gunYaw - bodyYaw)
            diffPitch = gunPitch - t2bPitch

            -- Ready stance gate:
            -- Regular guns: steady-state barrel offset is < 1.0 deg. Gate [2.5 deg, 4.0 deg], clamp +/- 2.0 deg.
            -- Heavy weapons (HMG) & Light Machine Guns (LMG): hip-cradle offset is ~6.4-7.1 deg. Gate [8.5 deg, 12.0 deg], clamp +/- 8.5 deg.
            -- Smart weapons: homing targeting, bypass Tier 2B completely.
            local useHeavyCradleGate = isHeavyWeapon or isLMG
            local maxAngle = math.max(math.abs(diffYaw), math.abs(diffPitch))
            local readyWeight = 0.0
            local maxReady = useHeavyCradleGate and 8.5 or 2.5
            local maxBlend = useHeavyCradleGate and 12.0 or 4.0
            local maxClamp = useHeavyCradleGate and 8.5 or 2.0

            if not isSmartWeapon and (stateStr == "HIP" or stateStr == "ADS") then
                if maxAngle < maxReady then
                    readyWeight = 1.0
                elseif maxAngle < maxBlend then
                    local t = (maxBlend - maxAngle) / (maxBlend - maxReady)
                    readyWeight = t * t * (3.0 - 2.0 * t)
                end
            end
            local isReadyStance = (readyWeight > 0.001)
            local isSwinging = (rawGapYaw > 0.50) or (rawGapPitch > 0.50)
            DetachedReticle.lastReadyWeight = readyWeight

            -- Reset integral trim and settled compensation on weapon change;
            -- on HIP <-> ADS transitions, reset trim and settled target for non-heavy weapons
            -- (HMG toggles crosshairState 4 <-> 8 on every zoomed shot without changing stance, whereas LMG/rifles transition between hip-cradle and iron-sight ADS)
            if weaponName ~= DetachedReticle.lastTrimWeapon then
                DetachedReticle.lastTrimWeapon = weaponName
                DetachedReticle.lastTrimADS = isADS
                DetachedReticle.trimYaw = 0.0
                DetachedReticle.trimPitch = 0.0
                DetachedReticle.lastSettledCompTargetYaw = nil
                DetachedReticle.lastSettledCompTargetPitch = nil
            elseif isADS ~= DetachedReticle.lastTrimADS then
                DetachedReticle.lastTrimADS = isADS
                if not isHeavyWeapon then
                    DetachedReticle.trimYaw = 0.0
                    DetachedReticle.trimPitch = 0.0
                    DetachedReticle.lastSettledCompTargetYaw = nil
                    DetachedReticle.lastSettledCompTargetPitch = nil
                end
            end

            -- Convergence on camera hit point: slow integral trim on screen error (only when fully resting and not recoiling)
            -- Sign convention: scrX > 0 means reticle is right -> subtract trimYaw to steer gun left towards center (negative feedback)
            if isResting and isReadyStance and isArmed then
                local dt = (type(delta) == "number" and delta > 0.0001 and delta < 0.1) and delta or 0.016
                DetachedReticle.trimYaw = math.max(-maxClamp, math.min(maxClamp, (DetachedReticle.trimYaw or 0.0) - scrX * 0.005 * dt))
                DetachedReticle.trimPitch = math.max(-maxClamp, math.min(maxClamp, (DetachedReticle.trimPitch or 0.0) - scrY * 0.005 * dt))
            end

            local rawTargetYaw = (diffYaw + (DetachedReticle.trimYaw or 0.0)) * readyWeight
            local rawTargetPitch = (diffPitch + (DetachedReticle.trimPitch or 0.0)) * readyWeight
            local targetYaw = math.max(-maxClamp, math.min(maxClamp, rawTargetYaw))
            local targetPitch = math.max(-maxClamp, math.min(maxClamp, rawTargetPitch))

            -- Hold Tier 2B target at its last settled pre-recoil/pre-swing value whenever recoiling,
            -- swinging (mouse pan > 0.5 deg where upper-body turn lag twists diffYaw), or momentarily dipping
            -- readyWeight from skeletal recoil animations while remaining in HIP/ADS stance.
            local hasSettledComp = (DetachedReticle.lastSettledCompTargetYaw ~= nil) and (DetachedReticle.lastSettledCompTargetPitch ~= nil)
            local isCombatStance = (not isSmartWeapon) and (stateStr == "HIP" or stateStr == "ADS")
            if isRecoiling or isSwinging or (isCombatStance and readyWeight < 0.999 and hasSettledComp) then
                if hasSettledComp then
                    targetYaw = DetachedReticle.lastSettledCompTargetYaw
                    targetPitch = DetachedReticle.lastSettledCompTargetPitch
                end
            elseif readyWeight >= 0.999 then
                DetachedReticle.lastSettledCompTargetYaw = targetYaw
                DetachedReticle.lastSettledCompTargetPitch = targetPitch
            end

            if Config.activeAimOffset and isArmed and isCombatStance and (isReadyStance or isRecoiling or isSwinging or hasSettledComp) then
                pcall(function() Game.DR_SetBarrelOffset(targetYaw, targetPitch) end)
            else
                -- While holstering, drawing, or unready: decay C smoothly to 0 via native filter
                pcall(function() Game.DR_SetBarrelOffset(0.0, 0.0) end)
            end
        else
            pcall(function() Game.DR_SetBarrelOffset(0.0, 0.0) end)
        end

        -- 5. Diagnostic Telemetry & Anomaly Watchdogs
        local weaponChanged = (weaponName ~= DetachedReticle.lastLoggedWeapon)
        local adsChanged = (isADS ~= DetachedReticle.lastLoggedADS)
        local shouldLogMonitor = weaponChanged or adsChanged or (DetachedReticle.frameCounter % 10 == 0)

        if Config.debugLogging and shouldLogMonitor and gunFwd then
            DetachedReticle.lastLoggedWeapon = weaponName
            DetachedReticle.lastLoggedADS = isADS

            local aimPitchRad = math.rad(aPitch)
            local aimYawRad = math.rad(bodyYaw)
            local ax = -math.sin(aimYawRad) * math.cos(aimPitchRad)
            local ay = math.cos(aimYawRad) * math.cos(aimPitchRad)
            local az = math.sin(aimPitchRad)
            local dotAim = math.max(-1.0, math.min(1.0, fx * ax + fy * ay + fz * az))
            local totalDiv = math.deg(math.acos(dotAim))

            local modeStr = isResting and ("RESTING(" .. stateStr .. ")") or ("SWINGING(" .. stateStr .. ")")
            if isRecoiling then
                modeStr = "RECOILING(" .. stateStr .. ")"
            end

            local logLine = string.format("[GUN_OFFSET_MONITOR] Weapon=%s | Mode=%s | ReticleScreen=(%.1f, %.1f)px | MuzzleScreen=(%.1f, %.1f)px | MuzzleRelCam=(R:%+.2f, F:%.2f, U:%+.2f)m | Drop=%+.1fcm | GunAngles=(Yaw:%.2f, Pitch:%.2f) | AimAngles=(Yaw:%.2f, Pitch:%.2f) | RecoilW=(Y:%+.2f, P:%+.2f) | Offset=(dYaw:%+.2f deg, dPitch:%+.2f deg, Total:%.2f deg)",
                weaponName, modeStr, scrX, scrY, muzScrX, muzScrY, muzRelR, muzRelF, muzRelU, (DetachedReticle.lastAppliedDrop or 0.0) * 100.0,
                gunYaw, gunPitch, bodyYaw, aPitch, wYaw, wPitch, diffYaw, diffPitch, totalDiv)
            Log(logLine)

            local cYaw = 0.0
            local cPitch = 0.0
            local t2bYaw = 0.0
            local t2bPitch = 0.0
            pcall(function() cYaw = Game.DR_GetCompYaw() end)
            pcall(function() cPitch = Game.DR_GetCompPitch() end)
            pcall(function() t2bYaw = Game.DR_GetT2BYaw() end)
            pcall(function() t2bPitch = Game.DR_GetT2BPitch() end)

            local compLine = string.format("[T2B_OFFSET_COMP] ReadyW=" .. string.format("%.2f", DetachedReticle.lastReadyWeight or 0.0) .. " | TargetErr=(dYaw:%+.2f deg, dPitch:%+.2f deg) | Trim=(Y:%+.2f, P:%+.2f) | CompApplied=(C_yaw:%+.2f deg, C_pitch:%+.2f deg) | RecoilW=(Y:%+.2f, P:%+.2f) | T2A_Aim=(Yaw:%.2f, Pitch:%.2f) | T2B_Body=(Yaw:%.2f, Pitch:%.2f) | Residual=(rYaw:%.4f, rPitch:%.4f)",
                diffYaw, diffPitch, (DetachedReticle.trimYaw or 0.0), (DetachedReticle.trimPitch or 0.0), cYaw, cPitch, wYaw, wPitch, bodyYaw, aPitch, t2bYaw, t2bPitch, rYaw, rPitch)
            Log(compLine)

            -- Anomaly Watchdogs:
            if math.abs(cYaw) >= 14.5 or math.abs(cPitch) >= 14.5 then
                Log(string.format("[WARN][T2B_CLAMP] Compensation reached clamp limit! cYaw=%.2f, cPitch=%.2f", cYaw, cPitch))
            end
            if cYaw ~= cYaw or cPitch ~= cPitch or diffYaw ~= diffYaw or diffPitch ~= diffPitch then
                Log("[WARN][T2B_NAN] NaN detected in compensation variables!")
            end
            if math.abs(diffYaw) > 25.0 or math.abs(diffPitch) > 25.0 then
                Log(string.format("[WARN][T2B_EXCESSIVE_OFFSET] Barrel offset exceeded expected bounds! dYaw=%.2f, dPitch=%.2f", diffYaw, diffPitch))
            end
            if math.abs(rYaw) > 70.0 or math.abs(rPitch) > 70.0 then
                Log(string.format("[WARN][T2B_RESIDUAL_HIGH] Camera residual exceeded expected bounds! rYaw=%.2f, rPitch=%.2f", rYaw, rPitch))
            end
            if DetachedReticle.restingFrames > 120 and (math.abs(scrX) > 40.0 or math.abs(scrY) > 40.0) and (DetachedReticle.frameCounter % 30 == 0) then
                Log(string.format("[WARN][T2B_CONVERGENCE_STALL] Reticle screen offset not converging to center! scr=(%.1f, %.1f)px, targetErr=(%.2f, %.2f) applied=(%.2f, %.2f)",
                    scrX, scrY, diffYaw, diffPitch, cYaw, cPitch))
            end
        end
    else
        if DetachedReticle.isActive then
            DetachedReticle.isActive = false
            pcall(function() Game.DR_SetBarrelOffset(0.0, 0.0) end)
            DetachedReticle.restingFrames = 0
            if DetachedReticle.chaseActive then
                DetachedReticle.chaseActive = false
                pcall(function() Game.DR_SetSmoothing(Config.catchUpSpeed, GetSmoothingModeInt(), Config.maxDivergence, Config.deadzone, false) end)
            end
            if fpp then
                local bPos = DetachedReticle.baselinePos or fpp:GetLocalPosition()
                if DetachedReticle.baselineRot then
                    pcall(function()
                        fpp:SetLocalTransform(bPos, DetachedReticle.baselineRot)
                    end)
                end
                -- Restore heading lock and sensitivity multipliers
                if DetachedReticle.origHeadingLocked ~= nil then
                    pcall(function() Game.DR_SetHeadingLocked(fpp, DetachedReticle.origHeadingLocked) end)
                    pcall(function() fpp.headingLocked = DetachedReticle.origHeadingLocked end)
                end
                if DetachedReticle.origSensX and DetachedReticle.origSensY then
                    pcall(function() Game.DR_SetSensitivityMult(fpp, DetachedReticle.origSensX, DetachedReticle.origSensY) end)
                    pcall(function() fpp.sensitivityMultX = DetachedReticle.origSensX end)
                    pcall(function() fpp.sensitivityMultY = DetachedReticle.origSensY end)
                end
            end
            DetachedReticle.baselineRot = nil
            DetachedReticle.baselinePos = nil
            DetachedReticle.lastAppliedDrop = 0.0
            DetachedReticle.lastWrittenRot = nil
            DetachedReticle.lastWrittenRPitch = 0.0
            DetachedReticle.origHeadingLocked = nil
            DetachedReticle.origSensX = nil
            DetachedReticle.origSensY = nil
            DetachedReticle.lastLoggedWeapon = nil
            DetachedReticle.lastLoggedADS = nil
        end
    end
    DetachedReticle.wasArmed = isArmed

    -- Telemetry bridge: poll DetachedAimSystem for ballistics shot telemetry
    local aimSys = nil
    pcall(function()
        aimSys = Game.GetScriptableSystemsContainer():Get(CName.new("DetachedReticle.DetachedAimSystem"))
    end)
    if aimSys then
        local okCount, shotCount = pcall(function() return aimSys:GetShotCount() end)
        if okCount and shotCount and shotCount > (DetachedReticle.lastShotCount or 0) then
            DetachedReticle.lastShotCount = shotCount
            local mPos, bDir, tPt, angle = nil, nil, nil, 0.0
            pcall(function()
                mPos = aimSys:GetLastShotMuzzlePos()
                bDir = aimSys:GetLastShotBulletDir()
                tPt = aimSys:GetLastShotTargetPt()
                angle = aimSys:GetLastShotAngleDeg()
            end)
            Log(string.format("[BALLISTICS RECORD #%d] Divergence=%.2f deg | RecoilW=(%+.2f, %+.2f) deg | Muzzle=(%.2f, %.2f, %.2f) | BulletDir=(%.3f, %.3f, %.3f)",
                shotCount, angle or 0.0, wYaw or 0.0, wPitch or 0.0,
                (mPos and (mPos.x or mPos.X)) or 0.0, (mPos and (mPos.y or mPos.Y)) or 0.0, (mPos and (mPos.z or mPos.Z)) or 0.0,
                (bDir and (bDir.x or bDir.X)) or 0.0, (bDir and (bDir.y or bDir.Y)) or 0.0, (bDir and (bDir.z or bDir.Z)) or 0.0
            ))
        end
    end
end)

registerForEvent("onShutdown", function()
    local player = Game.GetPlayer()
    local fpp = player and player:GetFPPCameraComponent()
    if fpp then
        local bPos = DetachedReticle.baselinePos or fpp:GetLocalPosition()
        if DetachedReticle.baselineRot then
            pcall(function()
                fpp:SetLocalTransform(bPos, DetachedReticle.baselineRot)
            end)
        end
        if DetachedReticle.origHeadingLocked ~= nil then
            pcall(function() Game.DR_SetHeadingLocked(fpp, DetachedReticle.origHeadingLocked) end)
            pcall(function() fpp.headingLocked = DetachedReticle.origHeadingLocked end)
        end
        if DetachedReticle.origSensX and DetachedReticle.origSensY then
            pcall(function() Game.DR_SetSensitivityMult(fpp, DetachedReticle.origSensX, DetachedReticle.origSensY) end)
            pcall(function() fpp.sensitivityMultX = DetachedReticle.origSensX end)
            pcall(function() fpp.sensitivityMultY = DetachedReticle.origSensY end)
        end
    end
    Log("Shutdown cleanly.")
end)

-- CET Overlay UI
registerForEvent("onOverlayOpen", function()
    DetachedReticle.isOverlayOpen = true
end)

registerForEvent("onOverlayClose", function()
    DetachedReticle.isOverlayOpen = false
end)

registerForEvent("onDraw", function()
    if not DetachedReticle.isOverlayOpen then return end

    if ImGui.Begin("Detached Reticle Options", true, ImGuiWindowFlags.AlwaysAutoResize) then
        ImGui.Text(string.format("Detached Reticle v%s", DetachedReticle.version))
        ImGui.Separator()

        -- Enable Mod Checkbox
        local newEnabled, enabledChanged = ImGui.Checkbox("Enable Decoupled Aim", Config.enabled)
        if enabledChanged then
            DetachedReticle.SetEnabled(newEnabled)
        end

        -- Active Aim Offset Checkbox
        local newOffset, offsetChanged = ImGui.Checkbox("Active Aim Offset (Tier 2B)", Config.activeAimOffset)
        if offsetChanged then
            DetachedReticle.SetActiveAimOffset(newOffset)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Actively offsets the character body and arms to center the gun reticle at rest.")
        end

        -- Catch-Up Speed Slider
        local newSpeed, speedChanged = ImGui.SliderFloat("Catch-up Speed", Config.catchUpSpeed, 0.0, 30.0, "%.1f")
        if speedChanged then
            DetachedReticle.SetCatchUpSpeed(newSpeed)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Speed at which the body turns to align with the camera reticle.\n0 = Body doesn't catch up (pure freelook)\n22.0 = Default responsive weight")
        end

        -- Deadzone Slider (Zero deadzone by default)
        local newDeadzone, dzChanged = ImGui.SliderFloat("Deadzone", Config.deadzone, 0.0, 30.0, "%.1f deg")
        if dzChanged then
            DetachedReticle.SetDeadzone(newDeadzone)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Angular zone within which the body does not turn.\n0.0 deg = Zero deadzone (any mouse movement immediately turns body)")
        end

        -- Max Divergence Slider
        local newMaxDiv, maxDivChanged = ImGui.SliderFloat("Max Divergence", Config.maxDivergence, 15.0, 110.0, "%.1f deg")
        if maxDivChanged then
            DetachedReticle.SetMaxDivergence(newMaxDiv)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Maximum angle the camera can look away from the body before dragging the body along immediately.")
        end

        -- Algorithm Selector
        ImGui.Separator()
        ImGui.Text("Catch-Up Algorithm:")
        local algoList = { "braking", "exponential", "linear", "spring", "power" }
        for _, algoName in ipairs(algoList) do
            local isSelected = (Config.smoothingMode:lower() == algoName)
            local label = (algoName == "braking") and "Braking (Model A)" or algoName:gsub("^%l", string.upper)
            if ImGui.RadioButton(label, isSelected) then
                DetachedReticle.SetSmoothingMode(algoName)
            end
            ImGui.SameLine()
        end
        ImGui.NewLine()

        if Config.smoothingMode:lower() == "braking" then
            local newBrakeThresh, threshChanged = ImGui.SliderFloat("Braking Zone", Config.brakeThreshold, 0.5, 10.0, "%.1f deg")
            if threshChanged then DetachedReticle.SetBrakeThreshold(newBrakeThresh) end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip("Distance in degrees from camera gaze where deceleration begins.\nDefault: 2.0 deg")
            end

            local newBrakeMax, maxSpdChanged = ImGui.SliderFloat("Max Cruise Speed", Config.brakeMaxSpeed, 60.0, 1200.0, "%.0f deg/s")
            if maxSpdChanged then DetachedReticle.SetBrakeMaxSpeed(newBrakeMax) end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip("Maximum cruising angular speed before entering braking zone.\nDefault: 360 deg/s")
            end
        elseif Config.smoothingMode:lower() == "exponential" then
            local newExpPower, powerChanged = ImGui.SliderFloat("Curve Exponent (p)", Config.expPower, 0.30, 1.20, "%.2f")
            if powerChanged then DetachedReticle.SetExpPower(newExpPower) end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip("Option A: Continuous Power-Law Exponent (v = k * gap^p).\n1.0 = linear exponential, 0.60 = tight sub-linear chase (reaches 20% distance at normal speed).\nNaturally settles to rest in 4 frames with ZERO artificial thresholds.\nDefault: 0.60")
            end
        end

        -- Tier 2B Gun Alignment (T2B-to-T2A) Snappiness Sliders
        ImGui.Separator()
        ImGui.Text("Tier 2B Gun Alignment (T2B-to-T2A) Snappiness:")

        local newCompSettled, compSettledChanged = ImGui.SliderFloat("Settled Speed", Config.compSpeedSettled, 1.0, 30.0, "%.1f")
        if compSettledChanged then DetachedReticle.SetCompSpeedSettled(newCompSettled) end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Speed at which the gun aligns to center when resting/settling.\nDefault: 12.0 (Old hardcoded: 4.5)")
        end

        local newCompMoving, compMovingChanged = ImGui.SliderFloat("Moving Speed", Config.compSpeedMoving, 0.5, 20.0, "%.1f")
        if compMovingChanged then DetachedReticle.SetCompSpeedMoving(newCompMoving) end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Speed at which the gun aligns while swinging mouse.\nDefault: 4.0 (Old hardcoded: 1.0)")
        end

        local newCompMax, compMaxChanged = ImGui.SliderFloat("Max Angular Speed", Config.compMaxSpeed, 30.0, 600.0, "%.0f deg/s")
        if compMaxChanged then DetachedReticle.SetCompMaxSpeed(newCompMax) end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Maximum angular speed in deg/s for barrel offset compensation.\nDefault: 240 deg/s")
        end

        local newCompMin, compMinChanged = ImGui.SliderFloat("Min Tail Speed", Config.compMinSpeed, 0.0, 30.0, "%.1f deg/s")
        if compMinChanged then DetachedReticle.SetCompMinSpeed(newCompMin) end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Minimum speed to prevent asymptotic tail slowdown and snap cleanly into center.\nDefault: 6.0 deg/s")
        end

        local newCompThresh, compThreshChanged = ImGui.SliderFloat("Gap Threshold", Config.compGapThreshold, 0.5, 15.0, "%.1f deg")
        if compThreshChanged then DetachedReticle.SetCompGapThreshold(newCompThresh) end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Angle threshold in degrees between moving and settled alignment speeds.\nDefault: 3.0 deg (Old hardcoded: 5.0 deg)")
        end

        -- Tier 2 Recoil Rubber Leash (Option A Radial Soft-Wall Attenuation)
        ImGui.Separator()
        ImGui.Text("Tier 2 Recoil Rubber Leash (Extended Fire Ceiling):")

        local newLeashMax, leashMaxChanged = ImGui.SliderFloat("Max Recoil Leash", Config.recoilMaxRadius, 0.0, 25.0, "%.1f deg")
        if leashMaxChanged then DetachedReticle.SetRecoilMaxRadius(newLeashMax) end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Maximum angular distance from center reticle that the gun reticle can climb during extended fire (e.g. HMG / LMG).\n0.0 deg = Unlimited\nDefault: 7.0 deg")
        end

        local newLeashCurve, leashCurveChanged = ImGui.SliderFloat("Leash Resistance Curve", Config.recoilLeashCurve, 0.5, 4.0, "%.1f")
        if leashCurveChanged then DetachedReticle.SetRecoilLeashCurve(newLeashCurve) end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Power-law rubber resistance exponent p (1 - (r/Rmax)^p).\nLower (0.8-1.2) = earlier elastic resistance\nHigher (2.0-3.5) = free climb then firm wall near Max Leash\nDefault: 1.5")
        end

        -- Tier 2 Horizontal Recoil & Strength Scaling
        ImGui.Separator()
        ImGui.Text("Tier 2 Horizontal Recoil & Strength Scaling:")

        local newHoriScale, horiScaleChanged = ImGui.Checkbox("Scale with Body/Strength Stat", Config.recoilHoriStatScaling)
        if horiScaleChanged then DetachedReticle.SetRecoilHoriStatScaling(newHoriScale) end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Scales Low-Strength Scatter with (1 - s) and High-Strength Damping with s,\nwhere s = (Body - 3) / 17 in [0, 1].\nWhen unchecked, both sliders apply directly regardless of Body stat.\nDefault: On")
        end

        local newHoriScatter, horiScatterChanged = ImGui.SliderFloat("Low-Strength Scatter", Config.recoilHoriScatter, 0.0, 3.0, "%.2f")
        if horiScatterChanged then DetachedReticle.SetRecoilHoriScatter(newHoriScatter) end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Alternating left/right horizontal recoil push multiplier at low Body/Strength.\nWhen a shot kicks right, the next shot is biased (~75% chance) to kick left with random strength.\nDefault: 1.00")
        end

        local newHoriDamping, horiDampingChanged = ImGui.SliderFloat("High-Strength Damping", Config.recoilHoriDamping, 0.0, 0.95, "%.2f")
        if horiDampingChanged then DetachedReticle.SetRecoilHoriDamping(newHoriDamping) end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Fraction of native horizontal recoil counteracted in the opposite direction at high Body/Strength.\nDefault: 0.70")
        end

        -- ADS Lever-Arm Sight-Line Compensation
        ImGui.Separator()
        ImGui.Text("ADS Lever-Arm Sight-Line Compensation:")

        local newLeverComp, leverCompChanged = ImGui.Checkbox("Enable ADS Lever-Arm Drop", Config.adsLeverArmComp)
        if leverCompChanged then DetachedReticle.SetAdsLeverArmComp(newLeverComp) end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Lowers the lever-arm root (elevates camera) in proportion to upward weapon recoil pitch during ADS,\npreventing the gun body from occluding the line of sight to T3.\nDefault: On")
        end

        local newLeverArmLen, leverArmLenChanged = ImGui.SliderFloat("Lever-Arm Length", Config.adsLeverArmLength, 0.10, 1.00, "%.2f m")
        if leverArmLenChanged then DetachedReticle.SetAdsLeverArmLength(newLeverArmLen) end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Effective lever-arm length L in meters for vertical drop h = L * sin(wPitch).\nDefault: 0.35 m")
        end

        -- Debug Telemetry Checkbox
        local newDebug, debugChanged = ImGui.Checkbox("Verbose Debug Logging", Config.debugLogging)
        if debugChanged then
            DetachedReticle.SetDebugLogging(newDebug)
        end

        ImGui.Separator()
        -- Live status preview
        local statusStr = "Disabled"
        if Config.enabled then
            statusStr = DetachedReticle.isActive and "ARMED (Decoupled)" or "Holstered / Inactive"
        end
        ImGui.Text(string.format("Status: %s", statusStr))
        ImGui.Text(string.format("Current Body Yaw: %.2f deg", DetachedReticle.bodyYaw or 0.0))
        if DetachedReticle.isActive then
            local rYaw = 0.0
            local rPitch = 0.0
            local cYaw = 0.0
            local cPitch = 0.0
            local wYaw = 0.0
            local wPitch = 0.0
            pcall(function() rYaw = Game.DR_GetResidualYaw() end)
            pcall(function() rPitch = Game.DR_GetResidualPitch() end)
            pcall(function() cYaw = Game.DR_GetCompYaw() end)
            pcall(function() cPitch = Game.DR_GetCompPitch() end)
            pcall(function() wYaw = Game.DR_GetRecoilYaw() end)
            pcall(function() wPitch = Game.DR_GetRecoilPitch() end)
            ImGui.Text(string.format("Camera Residual: Yaw=%.2f deg | Pitch=%.2f deg", rYaw, rPitch))
            ImGui.Text(string.format("Tier 2B Compensation: C_yaw=%+.2f deg | C_pitch=%+.2f deg", cYaw, cPitch))
            ImGui.Text(string.format("Tier 2 Recoil Offset: W_yaw=%+.2f deg | W_pitch=%+.2f deg", wYaw, wPitch))
            ImGui.Text(string.format("Player Body/Strength: %.0f (Factor s=%.2f)", DetachedReticle.playerBodyStat or 3.0, DetachedReticle.playerStrengthFactor or 0.0))
            if DetachedReticle.lastAppliedDrop and DetachedReticle.lastAppliedDrop > 0.0001 then
                ImGui.Text(string.format("ADS Lever Drop: %+.1f cm", DetachedReticle.lastAppliedDrop * 100.0))
            end
        end

        ImGui.End()
    end
end)

-- Modular Options API for CET Console and in-game adjustment:
DetachedReticle.SetEnabled = function(val)
    Config.enabled = val and true or false
    SaveConfig()
    if not Config.enabled and DetachedReticle.chaseActive then
        DetachedReticle.chaseActive = false
        pcall(function() Game.DR_SetBarrelOffset(0.0, 0.0) end)
        pcall(function() Game.DR_SetSmoothing(Config.catchUpSpeed, GetSmoothingModeInt(), Config.maxDivergence, Config.deadzone, false) end)
        local player = Game.GetPlayer()
        local fpp = player and player:GetFPPCameraComponent()
        if fpp and DetachedReticle.baselineRot then
            local bPos = DetachedReticle.baselinePos or fpp:GetLocalPosition()
            pcall(function() fpp:SetLocalTransform(bPos, DetachedReticle.baselineRot) end)
        end
    end
    Log(string.format("[OPTIONS] Enabled set to: %s", tostring(Config.enabled)))
end

DetachedReticle.SetActiveAimOffset = function(val)
    Config.activeAimOffset = val and true or false
    SaveConfig()
    if not Config.activeAimOffset then
        pcall(function() Game.DR_SetBarrelOffset(0.0, 0.0) end)
    end
    Log(string.format("[OPTIONS] activeAimOffset set to: %s", tostring(Config.activeAimOffset)))
end

DetachedReticle.SetCatchUpSpeed = function(val)
    Config.catchUpSpeed = math.max(0.0, tonumber(val) or 22.0)
    SaveConfig()
    SyncSmoothing()
    Log(string.format("[OPTIONS] catchUpSpeed set to: %.2f", Config.catchUpSpeed))
end

DetachedReticle.SetDeadzone = function(val)
    Config.deadzone = math.max(0.0, tonumber(val) or 0.0)
    SaveConfig()
    SyncSmoothing()
    Log(string.format("[OPTIONS] deadzone set to: %.2f deg", Config.deadzone))
end

DetachedReticle.SetMaxDivergence = function(val)
    Config.maxDivergence = math.max(10.0, tonumber(val) or 65.0)
    SaveConfig()
    SyncSmoothing()
    Log(string.format("[OPTIONS] maxDivergence set to: %.2f deg", Config.maxDivergence))
end

DetachedReticle.SetSmoothingMode = function(mode)
    local m = tostring(mode):lower()
    if Algorithms[m] or m == "braking" then
        Config.smoothingMode = m
        SaveConfig()
        SyncSmoothing()
        Log(string.format("[OPTIONS] smoothingMode set to: %s", Config.smoothingMode))
    else
        Log(string.format("[OPTIONS] Unknown smoothing mode '%s'. Available: %s", mode, table.concat(DetachedReticle.GetAlgorithms(), ", ")))
    end
end

DetachedReticle.SetBrakeThreshold = function(val)
    Config.brakeThreshold = math.max(0.1, tonumber(val) or 2.0)
    SaveConfig()
    SyncSmoothing()
    Log(string.format("[OPTIONS] brakeThreshold set to: %.2f deg", Config.brakeThreshold))
end

DetachedReticle.SetBrakeMaxSpeed = function(val)
    Config.brakeMaxSpeed = math.max(10.0, tonumber(val) or 360.0)
    SaveConfig()
    SyncSmoothing()
    Log(string.format("[OPTIONS] brakeMaxSpeed set to: %.1f deg/s", Config.brakeMaxSpeed))
end

DetachedReticle.SetExpPower = function(val)
    Config.expPower = math.max(0.1, math.min(1.5, tonumber(val) or 0.60))
    SaveConfig()
    SyncSmoothing()
    Log(string.format("[OPTIONS] expPower set to: %.2f", Config.expPower))
end

-- Backward compatibility alias
DetachedReticle.SetExpMinSpeed = function(val)
    DetachedReticle.SetExpPower(val)
end

DetachedReticle.SetCompSpeedSettled = function(val)
    Config.compSpeedSettled = math.max(0.1, tonumber(val) or 12.0)
    SaveConfig()
    SyncCompParams()
    Log(string.format("[OPTIONS] compSpeedSettled set to: %.1f", Config.compSpeedSettled))
end

DetachedReticle.SetCompSpeedMoving = function(val)
    Config.compSpeedMoving = math.max(0.1, tonumber(val) or 4.0)
    SaveConfig()
    SyncCompParams()
    Log(string.format("[OPTIONS] compSpeedMoving set to: %.1f", Config.compSpeedMoving))
end

DetachedReticle.SetCompMaxSpeed = function(val)
    Config.compMaxSpeed = math.max(10.0, tonumber(val) or 240.0)
    SaveConfig()
    SyncCompParams()
    Log(string.format("[OPTIONS] compMaxSpeed set to: %.1f deg/s", Config.compMaxSpeed))
end

DetachedReticle.SetCompMinSpeed = function(val)
    Config.compMinSpeed = math.max(0.0, tonumber(val) or 6.0)
    SaveConfig()
    SyncCompParams()
    Log(string.format("[OPTIONS] compMinSpeed set to: %.1f deg/s", Config.compMinSpeed))
end

DetachedReticle.SetCompGapThreshold = function(val)
    Config.compGapThreshold = math.max(0.1, tonumber(val) or 3.0)
    SaveConfig()
    SyncCompParams()
    Log(string.format("[OPTIONS] compGapThreshold set to: %.1f deg", Config.compGapThreshold))
end

DetachedReticle.SetRecoilMaxRadius = function(val)
    Config.recoilMaxRadius = math.max(0.0, math.min(45.0, tonumber(val) or 7.0))
    SaveConfig()
    SyncRecoilLeashParams()
    Log(string.format("[OPTIONS] recoilMaxRadius set to: %.1f deg", Config.recoilMaxRadius))
end

DetachedReticle.SetRecoilLeashCurve = function(val)
    Config.recoilLeashCurve = math.max(0.2, math.min(6.0, tonumber(val) or 1.5))
    SaveConfig()
    SyncRecoilLeashParams()
    Log(string.format("[OPTIONS] recoilLeashCurve set to: %.2f", Config.recoilLeashCurve))
end

DetachedReticle.SetRecoilHoriStatScaling = function(val)
    Config.recoilHoriStatScaling = val and true or false
    SaveConfig()
    SyncRecoilHorizontalParams()
    Log(string.format("[OPTIONS] recoilHoriStatScaling set to: %s", tostring(Config.recoilHoriStatScaling)))
end

DetachedReticle.SetRecoilHoriScatter = function(val)
    Config.recoilHoriScatter = math.max(0.0, math.min(4.0, tonumber(val) or 1.0))
    SaveConfig()
    SyncRecoilHorizontalParams()
    Log(string.format("[OPTIONS] recoilHoriScatter set to: %.2f", Config.recoilHoriScatter))
end

DetachedReticle.SetRecoilHoriDamping = function(val)
    Config.recoilHoriDamping = math.max(0.0, math.min(0.95, tonumber(val) or 0.70))
    SaveConfig()
    SyncRecoilHorizontalParams()
    Log(string.format("[OPTIONS] recoilHoriDamping set to: %.2f", Config.recoilHoriDamping))
end

DetachedReticle.SetAdsLeverArmComp = function(val)
    Config.adsLeverArmComp = val and true or false
    SaveConfig()
    Log(string.format("[OPTIONS] adsLeverArmComp set to: %s", tostring(Config.adsLeverArmComp)))
end

DetachedReticle.SetAdsLeverArmLength = function(val)
    Config.adsLeverArmLength = math.max(0.05, math.min(1.50, tonumber(val) or 0.35))
    SaveConfig()
    Log(string.format("[OPTIONS] adsLeverArmLength set to: %.2f m", Config.adsLeverArmLength))
end

DetachedReticle.SetDebugLogging = function(val)
    Config.debugLogging = val and true or false
    SaveConfig()
    Log(string.format("[OPTIONS] debugLogging set to: %s", tostring(Config.debugLogging)))
end

DetachedReticle.GetOptions = function()
    Log(string.format("[OPTIONS] enabled=%s | catchUpSpeed=%.2f | deadzone=%.2f deg | maxDivergence=%.2f deg | smoothingMode=%s | expPower=%.2f | brakeThresh=%.1f deg | brakeMax=%.0f deg/s | compSettled=%.1f | compMoving=%.1f | compMax=%.0f deg/s | compMin=%.1f deg/s | compThresh=%.1f deg | recoilMaxRadius=%.1f deg | recoilLeashCurve=%.2f | adsLeverArmComp=%s | adsLeverArmLength=%.2fm",
        tostring(Config.enabled), Config.catchUpSpeed, Config.deadzone, Config.maxDivergence, Config.smoothingMode,
        Config.expPower, Config.brakeThreshold, Config.brakeMaxSpeed,
        Config.compSpeedSettled, Config.compSpeedMoving, Config.compMaxSpeed, Config.compMinSpeed, Config.compGapThreshold,
        Config.recoilMaxRadius, Config.recoilLeashCurve, tostring(Config.adsLeverArmComp), Config.adsLeverArmLength))
    return Config
end

DetachedReticle.RegisterAlgorithm = function(name, fn)
    if type(name) == "string" and type(fn) == "function" then
        Algorithms[name:lower()] = fn
        Log(string.format("[ALGORITHM] Registered custom catch-up algorithm: '%s'", name))
    end
end

DetachedReticle.GetAlgorithms = function()
    local names = {}
    for k, _ in pairs(Algorithms) do
        table.insert(names, k)
    end
    table.sort(names)
    return names
end

return DetachedReticle
