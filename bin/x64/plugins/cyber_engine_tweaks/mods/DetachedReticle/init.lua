-- DetachedReticle - Cyber Engine Tweaks Module
-- Phase: Pure Detached Freelook while Armed
-- The camera is completely detached from the body & gun.
-- Mouse moves ONLY the camera. Nothing else moves or auto-centers the camera.
-- Left click fires the weapon.

local DetachedReticle = {
    version = "3.0.0-pure-freelook",
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
    lastShotCount = 0
}

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

registerForEvent("onInit", function()
    Log("Initializing Pure Detached Freelook v" .. DetachedReticle.version)

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
    -- 1. Consume from body so body and gun remain completely still in world space
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

    local isDual = false
    pcall(function()
        isDual = GameObject.IsDualWielding(player)
    end)
    local weapon = GameObject.GetRightActiveWeapon(player)
    local isArmed = weapon and not weapon:IsMelee() and not isDual
    local fpp = player:GetFPPCameraComponent()

    if isArmed and fpp then
        -- Enforce native straight shooting on equipped ranged weapon
        pcall(function() weapon:ShootStraight(true) end)

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
            Log(string.format("[STATUS] Pure Freelook ACTIVE | Yaw=%.2f deg | Pitch=%.2f deg | Mode=%d (0=RoundRobin) | LeftClick=Shoots",
                DetachedReticle.freeYaw, DetachedReticle.freePitch, curMode))
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

-- Console helper for switching test modes from CET console:
-- DetachedReticle.SetMode(0) = Round Robin (cycles 1..6 automatically on each shot)
-- DetachedReticle.SetMode(1) = Lock Mode 1 (Anim Suppressed Baseline)
-- DetachedReticle.SetMode(2) = Lock Mode 2 (Proper AI_ShootForwards)
-- DetachedReticle.SetMode(3) = Lock Mode 3 (Attack_GameEffect PrepareAttack & Run)
-- DetachedReticle.SetMode(4) = Lock Mode 4 (GameEffectSystem Static weaponShoot)
-- DetachedReticle.SetMode(5) = Lock Mode 5 (Continuous Attack Vector)
-- DetachedReticle.SetMode(6) = Lock Mode 6 (Vanilla PushAnimationEvent with ShootStraight)
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

return DetachedReticle
