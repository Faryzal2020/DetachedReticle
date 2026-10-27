-- DetachedReticle - Cyber Engine Tweaks Module
-- Phase: Chained Aiming Direction to Camera Reticle
-- 1. Camera Reticle: Instant, mouse-controlled gaze center
-- 2. Aiming Direction: Base world heading of the player puppet & upper-body rig, smoothly chained toward Camera Reticle
-- 3. Gun Reticle: Physical weapon muzzle in 3D world space, naturally driven from Aiming Direction via vanilla sway, breathing, recoil, and ready animations

local Config = {
    catchUpSpeed = 6.0,           -- Modular catch-up weight (1/s: higher = faster catch-up, lower = heavier lag)
    deadzone = 0.0,               -- Degrees: zero deadzone by default (configurable via options)
    maxDivergence = 65.0,         -- Degrees: maximum angular separation before pulling body
    smoothingMode = "exponential" -- "exponential", "linear", "spring", or "power"
}

local DetachedReticle = {
    version = "3.2.0-chained-aim",
    timer = 0,
    freeYaw = 0.0,
    freePitch = 0.0,
    rawMouseX = 0.0,
    rawMouseY = 0.0,
    entryNativePitch = 0.0,
    baselinePos = nil,
    baselineRot = nil,
    isActive = false,
    mouseScale = 0.07, -- degrees per mouse unit
    registeredPlayer = nil,
    lastShotCount = 0,
    isOverlayOpen = false,
    nativeSettingsInitAttempted = false
}

-- Modular Catch-Up Smoothing Algorithms
-- Each algorithm takes (freeYaw, freePitch, divergenceMag, effectiveDivergence, dt, Config, DetachedReticle)
-- and returns (yawStep, pitchStep)
local Algorithms = {
    -- 1. Exponential decay: rate proportional to current angular distance
    exponential = function(freeYaw, freePitch, divergenceMag, effectiveDivergence, dt, cfg, state)
        local decay = 1.0 - math.exp(-cfg.catchUpSpeed * dt)
        decay = math.max(0.0, math.min(1.0, decay))
        if cfg.deadzone > 0.0 and divergenceMag > 0.001 then
            decay = decay * (effectiveDivergence / divergenceMag)
        end
        return freeYaw * decay, freePitch * decay
    end,

    -- 2. Linear rate limit: constant angular speed (catchUpSpeed * 15.0 deg/sec)
    linear = function(freeYaw, freePitch, divergenceMag, effectiveDivergence, dt, cfg, state)
        local rate = cfg.catchUpSpeed * 15.0 -- deg per second
        local maxStep = rate * dt
        local ratio = (divergenceMag > 0.001) and math.min(1.0, maxStep / divergenceMag) or 1.0
        if cfg.deadzone > 0.0 and divergenceMag > 0.001 then
            ratio = ratio * (effectiveDivergence / divergenceMag)
        end
        return freeYaw * ratio, freePitch * ratio
    end,

    -- 3. Critically damped spring (SmoothDamp approximation):
    spring = function(freeYaw, freePitch, divergenceMag, effectiveDivergence, dt, cfg, state)
        local omega = cfg.catchUpSpeed
        local expVal = 1.0 / (1.0 + omega * dt + 0.48 * omega * omega * dt * dt + 0.235 * omega * omega * omega * dt * dt * dt)
        local decay = 1.0 - expVal
        decay = math.max(0.0, math.min(1.0, decay))
        if cfg.deadzone > 0.0 and divergenceMag > 0.001 then
            decay = decay * (effectiveDivergence / divergenceMag)
        end
        return freeYaw * decay, freePitch * decay
    end,

    -- 4. Power-curve ramp: progressive acceleration as angle widens
    power = function(freeYaw, freePitch, divergenceMag, effectiveDivergence, dt, cfg, state)
        local norm = math.min(1.0, effectiveDivergence / math.max(1.0, cfg.maxDivergence))
        local ramp = norm ^ 1.5
        local decay = (1.0 - math.exp(-cfg.catchUpSpeed * dt)) * (0.2 + 0.8 * ramp)
        decay = math.max(0.0, math.min(1.0, decay))
        return freeYaw * decay, freePitch * decay
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
                if data.catchUpSpeed ~= nil then Config.catchUpSpeed = tonumber(data.catchUpSpeed) or Config.catchUpSpeed end
                if data.deadzone ~= nil then Config.deadzone = tonumber(data.deadzone) or Config.deadzone end
                if data.maxDivergence ~= nil then Config.maxDivergence = tonumber(data.maxDivergence) or Config.maxDivergence end
                if data.smoothingMode ~= nil then Config.smoothingMode = tostring(data.smoothingMode):lower() end
            end
        end
    end
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

local function toVector(v)
    return Vector4.new(v.x or v.X or 0.0, v.y or v.Y or 0.0, v.z or v.Z or 0.0, v.w or v.W or 1.0)
end

local function toQuaternion(q)
    return Quaternion.new(q.i or q.x or 0.0, q.j or q.y or 0.0, q.k or q.z or 0.0, q.r or q.w or 1.0)
end

local function registerInputListeners(player)
    if not player or not IsDefined(player) or player:IsReplacer() then
        return
    end

    if DetachedReticle.registeredPlayer == player then
        return
    end

    pcall(function()
        player:RegisterInputListener(player, "CameraMouseX")
        player:RegisterInputListener(player, "CameraMouseY")
        player:RegisterInputListener(player, "CameraX")
        player:RegisterInputListener(player, "CameraY")
        player:RegisterInputListener(player, "right_stick_x")
        player:RegisterInputListener(player, "right_stick_y")
        player:RegisterInputListener(player, "RangedAttack")
        player:RegisterInputListener(player, "mouse_left")
    end)

    DetachedReticle.registeredPlayer = player
    Log("Input listeners registered on PlayerPuppet.")
end

local function unregisterInputListeners(player)
    if not player or not IsDefined(player) then
        return
    end

    pcall(function()
        player:UnregisterInputListener(player, "CameraMouseX")
        player:UnregisterInputListener(player, "CameraMouseY")
        player:UnregisterInputListener(player, "CameraX")
        player:UnregisterInputListener(player, "CameraY")
        player:UnregisterInputListener(player, "right_stick_x")
        player:UnregisterInputListener(player, "right_stick_y")
        player:UnregisterInputListener(player, "RangedAttack")
        player:UnregisterInputListener(player, "mouse_left")
    end)

    DetachedReticle.registeredPlayer = nil
    Log("Input listeners unregistered from PlayerPuppet.")
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

            ns.addRangeFloat(
                "/detachedReticle/aiming",
                "Catch-up Speed",
                "Speed at which the body & aiming direction rotate towards the camera reticle (0 = pure freelook, 6 = default realistic)",
                0.0, 30.0, 0.5, "%.1f", Config.catchUpSpeed, 6.0,
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

            local algoOptions = { "Exponential", "Linear", "Spring", "Power" }
            local currentIdx = 1
            for i, name in ipairs(algoOptions) do
                if name:lower() == Config.smoothingMode:lower() then
                    currentIdx = i
                    break
                end
            end

            ns.addSelectorString(
                "/detachedReticle/aiming",
                "Catch-up Algorithm",
                "Modular algorithm used to calculate the catch-up curve towards the camera reticle",
                algoOptions, currentIdx, 1,
                function(idx)
                    local selected = algoOptions[idx] or "Exponential"
                    DetachedReticle.SetSmoothingMode(selected:lower())
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
    Log(string.format("Initializing Chained Aiming System v%s | CatchUpSpeed=%.2f | Deadzone=%.2f deg | MaxDivergence=%.2f deg | Algorithm=%s",
        DetachedReticle.version, Config.catchUpSpeed, Config.deadzone, Config.maxDivergence, Config.smoothingMode))

    SetupNativeSettings()

    local player = Game.GetPlayer()
    if player then
        registerInputListeners(player)
    end

    Observe('PlayerPuppet', 'OnGameAttached', function(player)
        registerInputListeners(player)
    end)

    Observe('PlayerPuppet', 'OnTakeControl', function(player)
        registerInputListeners(player)
    end)

    Observe('PlayerPuppet', 'OnDetach', function(player)
        unregisterInputListeners(player)
    end)

    -- Intercept mouse look input:
    -- 1. Consume from body so body and gun remain still in world space
    -- 2. Accumulate delta for the camera
    Observe('PlayerPuppet', 'OnAction', function(first, second, third)
        if not DetachedReticle.isActive then return end

        local action = (third ~= nil) and second or first
        local consumer = (third ~= nil) and third or second
        if not action then return end

        local listenerAction = GetSingleton('gameinputScriptListenerAction')
        if not listenerAction then return end

        local ok, actionName, actionValue = pcall(function()
            return Game.NameToString(listenerAction:GetName(action)), listenerAction:GetValue(action)
        end)

        if not ok or not actionName or not actionValue then return end

        if actionName == "RangedAttack" or actionName == "mouse_left" then
            if actionValue > 0.5 then
                Log(string.format("[FIRE INPUT DETECTED] Action=%s | FreeYaw=%.2f deg | FreePitch=%.2f deg | IsActive=%s",
                    actionName, DetachedReticle.freeYaw, DetachedReticle.freePitch, tostring(DetachedReticle.isActive)))
            end
        end

        -- Do NOT intercept mouse_left or RangedAttack; left click must fire the gun!
        if actionName == "CameraMouseX" or actionName == "CameraX" or actionName == "right_stick_x" then
            DetachedReticle.rawMouseX = DetachedReticle.rawMouseX + actionValue
            if consumer then
                pcall(function() consumer:ConsumeSingleAction() end)
            end
        elseif actionName == "CameraMouseY" or actionName == "CameraY" or actionName == "right_stick_y" then
            DetachedReticle.rawMouseY = DetachedReticle.rawMouseY + actionValue
            if consumer then
                pcall(function() consumer:ConsumeSingleAction() end)
            end
        end
    end)
end)

registerForEvent("onUpdate", function(delta)
    local player = Game.GetPlayer()
    if not player then return end

    if not DetachedReticle.registeredPlayer then
        registerInputListeners(player)
    end

    if not DetachedReticle.nativeSettingsInitAttempted then
        SetupNativeSettings()
    end

    local isDual = false
    pcall(function()
        isDual = GameObject.IsDualWielding(player)
    end)
    local weapon = GameObject.GetRightActiveWeapon(player)
    local isArmed = weapon and not weapon:IsMelee() and not isDual
    local fpp = player:GetFPPCameraComponent()

    if isArmed and fpp then
        -- Capture baseline transform and entry pitch once when first arming
        if not DetachedReticle.baselinePos then
            local pos = fpp:GetLocalPosition()
            local rot = fpp:GetLocalOrientation()
            if pos and rot then
                DetachedReticle.baselinePos = toVector(pos)
                DetachedReticle.baselineRot = toQuaternion(rot)
                DetachedReticle.freeYaw = 0.0
                DetachedReticle.freePitch = 0.0
                DetachedReticle.rawMouseX = 0.0
                DetachedReticle.rawMouseY = 0.0

                -- Capture native parent pitch at entry
                DetachedReticle.entryNativePitch = 0.0
                local okMat, worldMatrix = pcall(function() return fpp:GetLocalToWorld() end)
                if okMat and worldMatrix then
                    local okRot, euler = pcall(function() return Matrix.GetRotation(worldMatrix) end)
                    if okRot and euler and euler.Pitch then
                        DetachedReticle.entryNativePitch = euler.Pitch
                    end
                end

                Log(string.format("[FREELOOK] Freelook ACTIVE. EntryPitch=%.2f deg", DetachedReticle.entryNativePitch))
            end
        end

        DetachedReticle.isActive = true

        -- Apply mouse input directly to freeYaw and freePitch
        local zoom = 1.0
        pcall(function() zoom = fpp:GetZoom() or 1.0 end)
        if zoom <= 0.001 then zoom = 1.0 end

        local scale = DetachedReticle.mouseScale / zoom
        DetachedReticle.freeYaw = DetachedReticle.freeYaw - (DetachedReticle.rawMouseX * scale)
        DetachedReticle.freePitch = DetachedReticle.freePitch + (DetachedReticle.rawMouseY * scale)

        -- Clamp pitch to prevent flipping upside down (-85 to +85 degrees)
        DetachedReticle.freePitch = math.max(-85.0, math.min(85.0, DetachedReticle.freePitch))

        -- Clear raw mouse accumulation for this frame
        DetachedReticle.rawMouseX = 0.0
        DetachedReticle.rawMouseY = 0.0

        -- Frame Delta Time
        local dt = delta
        if not dt or dt <= 0.0001 or dt > 0.2 then
            dt = 1.0 / 60.0
        end

        -- Calculate current divergence magnitude between Camera and Aiming Direction
        local divergenceMag = math.sqrt(DetachedReticle.freeYaw^2 + DetachedReticle.freePitch^2)

        -- 1. Enforce Config.maxDivergence (Clamp & pull excess immediately)
        if Config.maxDivergence > 0.0 and divergenceMag > Config.maxDivergence then
            local clampFactor = Config.maxDivergence / divergenceMag
            local excessYaw = DetachedReticle.freeYaw * (1.0 - clampFactor)
            local excessPitch = DetachedReticle.freePitch * (1.0 - clampFactor)

            DetachedReticle.freeYaw = DetachedReticle.freeYaw * clampFactor
            DetachedReticle.freePitch = DetachedReticle.freePitch * clampFactor

            local okYaw, curYaw = pcall(function() return player:GetWorldYaw() end)
            if okYaw and curYaw then
                local teleFac = Game.GetTeleportationFacility()
                if teleFac then
                    pcall(function()
                        teleFac:Teleport(player, player:GetWorldPosition(), EulerAngles.new(0.0, 0.0, curYaw + excessYaw))
                    end)
                end
            end
            DetachedReticle.entryNativePitch = DetachedReticle.entryNativePitch + excessPitch
            divergenceMag = Config.maxDivergence
        end

        -- 2. Chained Catch-Up Smoothing (Aiming Direction turns toward Camera Reticle)
        if Config.catchUpSpeed > 0.0 then
            local effectiveDivergence = divergenceMag
            if Config.deadzone > 0.0 then
                effectiveDivergence = math.max(0.0, divergenceMag - Config.deadzone)
            end

            if effectiveDivergence > 0.001 and divergenceMag > 0.001 then
                local algoFn = Algorithms[Config.smoothingMode:lower()] or Algorithms["exponential"]
                local yawStep, pitchStep = algoFn(DetachedReticle.freeYaw, DetachedReticle.freePitch, divergenceMag, effectiveDivergence, dt, Config, DetachedReticle)

                -- Rotate puppet world yaw toward camera view
                local okYaw, curYaw = pcall(function() return player:GetWorldYaw() end)
                if okYaw and curYaw and math.abs(yawStep) > 0.0001 then
                    local newYaw = curYaw + yawStep
                    local teleFac = Game.GetTeleportationFacility()
                    if teleFac then
                        pcall(function()
                            teleFac:Teleport(player, player:GetWorldPosition(), EulerAngles.new(0.0, 0.0, newYaw))
                        end)
                    end
                end

                -- Shift aiming pitch and reduce local camera divergence
                DetachedReticle.entryNativePitch = DetachedReticle.entryNativePitch + pitchStep
                DetachedReticle.freeYaw = DetachedReticle.freeYaw - yawStep
                DetachedReticle.freePitch = DetachedReticle.freePitch - pitchStep
            end
        end

        -- Apply freelook camera orientation (cancelling parent entry pitch before yaw, then re-applying)
        if DetachedReticle.baselinePos and DetachedReticle.baselineRot then
            local cancelNativePitch = quatAxisAngle(1.0, 0.0, 0.0, -DetachedReticle.entryNativePitch)
            local qYaw = quatAxisAngle(0.0, 0.0, 1.0, DetachedReticle.freeYaw)
            local qPitch = quatAxisAngle(1.0, 0.0, 0.0, DetachedReticle.entryNativePitch + DetachedReticle.freePitch)

            local orient = quatMultiply(cancelNativePitch, qYaw)
            orient = quatMultiply(orient, qPitch)
            local targetRot = quatMultiply(orient, DetachedReticle.baselineRot)

            pcall(function()
                fpp:SetLocalTransform(DetachedReticle.baselinePos, targetRot)
            end)
        end
    else
        -- Reset camera to baseline when unequipped or inactive
        if DetachedReticle.isActive and fpp and DetachedReticle.baselinePos and DetachedReticle.baselineRot then
            pcall(function()
                fpp:SetLocalTransform(DetachedReticle.baselinePos, DetachedReticle.baselineRot)
            end)
            DetachedReticle.isActive = false
            DetachedReticle.freeYaw = 0.0
            DetachedReticle.freePitch = 0.0
            DetachedReticle.rawMouseX = 0.0
            DetachedReticle.rawMouseY = 0.0
            DetachedReticle.baselinePos = nil
            DetachedReticle.baselineRot = nil
            Log("[FREELOOK] Weapon holstered - Camera reset to baseline.")
        end
    end

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
            local modeNum = 0
            local modeName = "Unknown"
            pcall(function()
                mPos = aimSys:GetLastShotMuzzlePos()
                bDir = aimSys:GetLastShotBulletDir()
                tPt = aimSys:GetLastShotTargetPt()
                angle = aimSys:GetLastShotAngleDeg()
                modeNum = aimSys:GetLastShotTestMode() or 0
                modeName = aimSys:GetLastShotTestModeName() or "Unknown"
            end)
            Log(string.format("[BALLISTICS RECORD #%d] [%s (Mode #%d)] GunDivergence=%.2f deg | FreeYaw=%.2f deg, FreePitch=%.2f deg | Muzzle=(%.2f, %.2f, %.2f) | BulletDir=(%.3f, %.3f, %.3f)",
                shotCount, modeName, modeNum, angle or 0.0, DetachedReticle.freeYaw, DetachedReticle.freePitch,
                (mPos and (mPos.x or mPos.X)) or 0.0, (mPos and (mPos.y or mPos.Y)) or 0.0, (mPos and (mPos.z or mPos.Z)) or 0.0,
                (bDir and (bDir.x or bDir.X)) or 0.0, (bDir and (bDir.y or bDir.Y)) or 0.0, (bDir and (bDir.z or bDir.Z)) or 0.0
            ))
        end
    end

    -- Periodic diagnostic health log every 3 seconds
    DetachedReticle.timer = DetachedReticle.timer + delta
    if DetachedReticle.timer >= 3.0 then
        DetachedReticle.timer = 0
        if DetachedReticle.isActive then
            local curMode = 0
            if aimSys then pcall(function() curMode = aimSys:GetTestMode() or 0 end) end
            Log(string.format("[STATUS] Chained Aiming ACTIVE | Yaw=%.2f deg | Pitch=%.2f deg | Speed=%.1f | Deadzone=%.1f deg | Mode=%s",
                DetachedReticle.freeYaw, DetachedReticle.freePitch, Config.catchUpSpeed, Config.deadzone, Config.smoothingMode))
        end
    end
end)

registerForEvent("onShutdown", function()
    local player = Game.GetPlayer()
    local fpp = player and player:GetFPPCameraComponent()
    if fpp and DetachedReticle.baselinePos and DetachedReticle.baselineRot then
        pcall(function()
            fpp:SetLocalTransform(DetachedReticle.baselinePos, DetachedReticle.baselineRot)
        end)
    end
    if player then
        unregisterInputListeners(player)
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

        -- Catch-Up Speed Slider
        local newSpeed, speedChanged = ImGui.SliderFloat("Catch-up Speed", Config.catchUpSpeed, 0.0, 30.0, "%.1f")
        if speedChanged then
            DetachedReticle.SetCatchUpSpeed(newSpeed)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Speed at which the body turns to align with the camera reticle.\n0 = Body doesn't catch up (pure freelook)\n6 = Default realistic smoothed weight\n20+ = Fast / snappy")
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
        local algoList = { "exponential", "linear", "spring", "power" }
        for _, algoName in ipairs(algoList) do
            local isSelected = (Config.smoothingMode:lower() == algoName)
            if ImGui.RadioButton(algoName:gsub("^%l", string.upper), isSelected) then
                DetachedReticle.SetSmoothingMode(algoName)
            end
            ImGui.SameLine()
        end
        ImGui.NewLine()

        ImGui.Separator()
        -- Live telemetry preview
        ImGui.Text(string.format("Status: %s", DetachedReticle.isActive and "ARMED & DECOUPLED" or "Holstered / Inactive"))
        ImGui.Text(string.format("Camera Offset: Yaw = %.1f deg, Pitch = %.1f deg", DetachedReticle.freeYaw, DetachedReticle.freePitch))

        ImGui.End()
    end
end)

-- Console helper for switching test modes from CET console:
DetachedReticle.SetMode = function(mode)
    local aimSys = nil
    pcall(function()
        aimSys = Game.GetScriptableSystemsContainer():Get(CName.new("DetachedReticle.DetachedAimSystem"))
    end)
    if aimSys then
        local m = tonumber(mode) or 0
        aimSys:SetTestMode(m)
        Log(string.format("[CONFIG] Test Mode changed to: %d", m))
    end
end

-- Modular Options API for CET Console and in-game adjustment:
DetachedReticle.SetCatchUpSpeed = function(val)
    Config.catchUpSpeed = math.max(0.0, tonumber(val) or 6.0)
    SaveConfig()
    Log(string.format("[OPTIONS] catchUpSpeed set to: %.2f", Config.catchUpSpeed))
end

DetachedReticle.SetDeadzone = function(val)
    Config.deadzone = math.max(0.0, tonumber(val) or 0.0)
    SaveConfig()
    Log(string.format("[OPTIONS] deadzone set to: %.2f deg", Config.deadzone))
end

DetachedReticle.SetMaxDivergence = function(val)
    Config.maxDivergence = math.max(10.0, tonumber(val) or 65.0)
    SaveConfig()
    Log(string.format("[OPTIONS] maxDivergence set to: %.2f deg", Config.maxDivergence))
end

DetachedReticle.SetSmoothingMode = function(mode)
    local m = tostring(mode):lower()
    if Algorithms[m] then
        Config.smoothingMode = m
        SaveConfig()
        Log(string.format("[OPTIONS] smoothingMode set to: %s", Config.smoothingMode))
    else
        Log(string.format("[OPTIONS] Unknown smoothing mode '%s'. Available: %s", mode, table.concat(DetachedReticle.GetAlgorithms(), ", ")))
    end
end

DetachedReticle.GetOptions = function()
    Log(string.format("[OPTIONS] catchUpSpeed=%.2f | deadzone=%.2f deg | maxDivergence=%.2f deg | smoothingMode=%s",
        Config.catchUpSpeed, Config.deadzone, Config.maxDivergence, Config.smoothingMode))
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
