--[[
    CameraController.lua
    Deep Tide Studios — Client Controller
    Manages camera behavior: underwater sway, depth fog,
    fishing camera transitions, surface breach / submerge transitions,
    and depth warning detection.

    Updated: Delegates ALL Bloom/DoF/ColorCorrection to AtmosphereHandler
    via UpdateDepth() — single Lighting authority, no dual-write flicker.
]]

local Knit = require(game:GetService("ReplicatedStorage"):WaitForChild("Knit"))
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))

local CameraController = Knit.CreateController({
    Name = "CameraController",
})

-- ============================================================
-- State
-- ============================================================
CameraController._cameraBobOffset = 0
CameraController._bobTimer = 0
CameraController._currentDepth = 0
CameraController._targetFogEnd = 60
CameraController._transitionSpeed = 2.0
CameraController._wasUnderwater = false
CameraController._atmosphereHandler = nil  -- set after KnitStart

-- ============================================================

function CameraController:KnitStart()
    print("[CameraController] Started")

    -- Load AtmosphereHandler (client-side handler for VFX)
    local AtmosphereHandler = require(script.Parent.Parent.Handlers:WaitForChild("AtmosphereHandler"))
    self._atmosphereHandler = AtmosphereHandler.new()
    self._atmosphereHandler:Initialize()

    -- Camera bob loop
    RunService.RenderStepped:Connect(function(deltaTime)
        self:_updateCameraBob(deltaTime)
        self:_updateDepthEffects(deltaTime)
    end)
end

function CameraController:KnitInit()
    -- Set up initial camera
    local camera = workspace.CurrentCamera
    if camera then
        camera.FieldOfView = 70
    end
end

-- ============================================================
-- Camera bob (underwater sway)
-- ============================================================

function CameraController:_updateCameraBob(deltaTime)
    self._bobTimer = self._bobTimer + deltaTime

    local amplitude = Shared.Swimming.CameraBobAmplitude
    local period = Shared.Swimming.CameraBobPeriod

    -- Procedural sine wave bob
    local bobX = math.sin(self._bobTimer * (2 * math.pi / period)) * amplitude * 0.3
    local bobY = math.cos(self._bobTimer * (2 * math.pi / (period * 0.7))) * amplitude

    self._cameraBobOffset = Vector3.new(bobX, bobY, 0)
end

-- ============================================================
-- Depth effects
-- ============================================================

function CameraController:_updateDepthEffects(deltaTime)
    local character = Players.LocalPlayer.Character
    if not character then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    -- Calculate depth (Y position relative to water surface at Y=0)
    self._currentDepth = math.abs(math.min(0, rootPart.Position.Y))
    local isUnderwater = rootPart.Position.Y < 0

    -- Detect surface breach / submerge transitions
    if isUnderwater and not self._wasUnderwater then
        self:OnSubmerge()
    elseif not isUnderwater and self._wasUnderwater then
        self:OnSurfaceBreach()
    end
    self._wasUnderwater = isUnderwater

    -- Delegate ALL post-processing Lighting to AtmosphereHandler (single authority).
    -- Bloom, DoF, ColorCorrection are derived from this single depth input each frame,
    -- eliminating the dual-write flicker that occurred when both modules fought over
    -- the same Lighting properties.
    if self._atmosphereHandler then
        self._atmosphereHandler:UpdateDepth(self._currentDepth, isUnderwater)
    end

    -- Fog / ambient / atmosphere density (no conflict — AtmosphereHandler doesn't
    -- touch these per-frame, so CameraController remains the owner here).
    local zone = Shared.Constants.ZoneConfigs.GetZoneAtDepth(self._currentDepth)
    if zone then
        self:_applyZoneAtmosphere(zone, deltaTime)
    end

    -- Update depth warning effects (screen darkening near suit limit)
    self:_updateDepthWarningEffects(isUnderwater)
end

function CameraController:_applyZoneAtmosphere(zone, deltaTime)
    local env = zone.Environment
    if not env then return end

    local lighting = game:GetService("Lighting")

    -- Fog transition
    local fogEnd = env.Visibility
    lighting.FogEnd = self:_smoothDamp(lighting.FogEnd, fogEnd, self._transitionSpeed, deltaTime)
    lighting.FogStart = self:_smoothDamp(lighting.FogStart, env.FogStart, self._transitionSpeed, deltaTime)

    -- Ambient color
    lighting.Ambient = lighting.Ambient:Lerp(env.AmbientColor, deltaTime * self._transitionSpeed)

    -- Depth-based fog color shift (surface turquoise -> deep navy)
    -- Rich gradient across depth bands matching GDD 6.3 landmarks:
    --   0-15m (Coral Gardens): turquoise-blue, bright
    --   15-30m (Sandy Plains): slightly deeper blue
    --   30-45m (Shipwreck): cooler, darker blue
    --   45-50m (Deep Reef Edge): deep navy with purple tint
    local depthRatio = math.clamp(self._currentDepth / zone.DepthMax, 0, 1)

    -- Interpolate through depth bands for richness
    local shallowColor = env.WaterColor                           -- turquoise (0m)
    local midColor = shallowColor:Lerp(Color3.fromRGB(30, 100, 170), 0.6)  -- mid-blue (25m)
    local deepColor = env.DeepWaterColor                          -- navy (50m)

    local fogColor
    if depthRatio < 0.3 then
        -- 0-15m: shallow bright
        local t = depthRatio / 0.3
        fogColor = shallowColor:Lerp(midColor, t)
    elseif depthRatio < 0.6 then
        -- 15-30m: mid-transition
        local t = (depthRatio - 0.3) / 0.3
        fogColor = midColor:Lerp(deepColor, t * 0.5)
    else
        -- 30-50m: deepening
        local t = (depthRatio - 0.6) / 0.4
        fogColor = deepColor:Lerp(Color3.fromRGB(15, 20, 60), t)  -- purple tint at edge
    end

    lighting.FogColor = lighting.FogColor:Lerp(fogColor, deltaTime * self._transitionSpeed)

    -- Update Atmosphere with depth-matched fog density
    local atmosphere = lighting:FindFirstChild("Atmosphere")
    if atmosphere then
        local density = 0.25 + depthRatio * 0.4
        atmosphere.Density = self:_smoothDamp(atmosphere.Density, density, self._transitionSpeed, deltaTime)
        local haze = 0.6 + depthRatio * 0.5
        atmosphere.Haze = self:_smoothDamp(atmosphere.Haze, haze, self._transitionSpeed, deltaTime)
    end

    -- NOTE: DoF is now managed by AtmosphereHandler:UpdateDepth() — single authority.
end

-- ============================================================
-- Depth warning effects (near suit limit)
-- ============================================================
function CameraController:_updateDepthWarningEffects(isUnderwater)
    if not isUnderwater then
        if self._atmosphereHandler then
            self._atmosphereHandler:SetOxygenWarning(false, 0)
        end
        return
    end

    -- Check if player is near or past their suit's max depth
    -- (This is a simplified check — production should check equipped suit)
    local maxSafeDepth = 50  -- Basic Wetsuit = 50m
    local warningThreshold = maxSafeDepth - 5  -- start warning 5m before limit

    if self._currentDepth > warningThreshold then
        local intensity = math.clamp((self._currentDepth - warningThreshold) / (maxSafeDepth - warningThreshold), 0, 1)

        -- Notify AtmosphereHandler — Bloom/ColorCorrection modifications are
        -- now applied in AtmosphereHandler:UpdateDepth() so there's no dual-write.
        if self._atmosphereHandler then
            self._atmosphereHandler:SetOxygenWarning(true, intensity)
        end
    else
        if self._atmosphereHandler then
            self._atmosphereHandler:SetOxygenWarning(false, 0)
        end
    end
end

function CameraController:_smoothDamp(current, target, speed, dt)
    return current + (target - current) * math.min(speed * dt, 1)
end

-- ============================================================
-- Fishing camera
-- ============================================================

function CameraController:TransitionToFishingCam(targetPosition)
    -- Zoom in slightly, focus on bobber/fish area
    local camera = workspace.CurrentCamera
    if not camera then return end

    -- Store original FOV and smoothly transition
    self._originalFOV = camera.FieldOfView
    -- Tween camera to 55 FOV
    camera.FieldOfView = 55
end

function CameraController:TransitionToNormalCam()
    local camera = workspace.CurrentCamera
    if not camera then return end

    camera.FieldOfView = self._originalFOV or 70
end

-- ============================================================
-- Surface transition effects
-- ============================================================

function CameraController:OnSurfaceBreach()
    -- Transition from underwater to surface lighting
    local lighting = game:GetService("Lighting")

    -- Reset to surface defaults
    lighting.FogEnd = 200
    lighting.FogStart = 100
    lighting.FogColor = Color3.fromRGB(180, 210, 240)  -- surface sky blue

    -- Reset atmosphere to surface-level density
    local atmosphere = lighting:FindFirstChild("Atmosphere")
    if atmosphere then
        atmosphere.Density = 0.15
        atmosphere.Haze = 0.3
    end

    -- NOTE: DoF reset is now handled by AtmosphereHandler:OnSurfaceBreach()
    --       (single authority for Bloom/DoF/ColorCorrection).

    -- Notify AtmosphereHandler
    if self._atmosphereHandler then
        self._atmosphereHandler:OnSurfaceBreach()
    end

    print("[CameraController] Surface breached — atmospheric transition complete.")
end

function CameraController:OnSubmerge()
    print("[CameraController] Player submerged — activating underwater atmosphere.")

    -- Notify AtmosphereHandler
    if self._atmosphereHandler then
        self._atmosphereHandler:OnSubmerge()
    end
end

return CameraController
