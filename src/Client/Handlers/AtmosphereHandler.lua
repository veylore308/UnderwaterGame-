--[[
    AtmosphereHandler.lua
    Deep Tide Studios — Client Handler
    Manages all underwater atmosphere: lighting, fog, god rays, caustics,
    bioluminescent VFX, player VFX (bubbles, glow ring, oxygen warning),
    landmark-specific lighting, marine snow, and rare-fish spawn visuals.

    Runs alongside CameraController; CameraController handles the base
    depth-to-fog/ambient transition, AtmosphereHandler handles all the
    rich visual detail that sells the deep-sea fantasy.

    Zone reference: The Sunken Shallows (0–50m)
      - Coral Gardens:  5–15m  — warm golden/orange accents
      - Sandy Plains:   15–30m — open, diffuse light
      - The Shipwreck:  30–45m — cold blue-white, eerie flickering
      - Deep Reef Edge: 45–50m — near-darkness, purple/magenta tint
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("Shared"))
local ZoneConfigs = Shared.Constants.ZoneConfigs

local AtmosphereHandler = {}
AtmosphereHandler.__index = AtmosphereHandler

-- ============================================================
-- Depth transition thresholds (meters from surface)
-- ============================================================
local DEPTH_SURFACE     = 0
local DEPTH_SHALLOW     = 15
local DEPTH_MID         = 30
local DEPTH_DEEP        = 45
local DEPTH_ABYSSAL     = 50

-- ============================================================
-- Zone landmark lighting presets
-- ============================================================
local LANDMARK_PRESETS = {
    CoralGardens = {
        CenterPosition = Vector3.new(0, -10, 0),
        Radius = 40,
        AccentColor = Color3.fromRGB(255, 170, 60),   -- warm golden-orange
        AccentColor2 = Color3.fromRGB(255, 120, 200),  -- warm pink accent
        GlowRange = 18,
        GlowBrightness = 0.6,
        ParticleColor = Color3.fromRGB(100, 220, 255), -- bioluminescent cyan
    },
    Shipwreck = {
        CenterPosition = Vector3.new(10, -37, -8),
        Radius = 25,
        AccentColor = Color3.fromRGB(140, 200, 255),   -- cold blue-white
        AccentColor2 = Color3.fromRGB(80, 255, 180),   -- eerie green
        GlowRange = 14,
        GlowBrightness = 0.5,
        FlickerSpeed = 3.0,
        ParticleColor = Color3.fromRGB(60, 255, 140),  -- eerie green motes
    },
    DeepReefEdge = {
        CenterPosition = Vector3.new(-20, -47, -25),
        Radius = 30,
        AccentColor = Color3.fromRGB(160, 60, 220),    -- purple/magenta
        AccentColor2 = Color3.fromRGB(40, 20, 100),    -- deep blue
        GlowRange = 10,
        GlowBrightness = 0.3,
        ParticleColor = Color3.fromRGB(180, 80, 255),  -- purple motes
    },
}

-- ============================================================
-- Constructor
-- ============================================================
function AtmosphereHandler.new()
    local self = setmetatable({}, AtmosphereHandler)

    -- Core lighting objects we create & manage
    self._godRayBeams = {}          -- beam-based god rays
    self._causticLights = {}        -- SurfaceLight/PointLight for caustic patterns
    self._landmarkLights = {}       -- lights placed at landmarks
    self._landmarkParticles = {}    -- bioluminescent emitters at landmarks
    self._marineSnowEmitter = nil   -- global floating particulate
    self._planktonEmitters = {}     -- floating bioluminescent plankton

    -- Player VFX
    self._bubbleTrailEmitter = nil  -- attachment-based bubble trail on player
    self._playerGlowRing = nil      -- subtle glow ring around player
    self._oxygenWarningGui = nil    -- screen-edge red tint
    self._heartbeatPulse = nil      -- heartbeat particle pulse

    -- State
    self._currentDepth = 0
    self._currentZone = nil
    self._closestLandmark = nil
    self._isInitialized = false
    self._isUnderwater = false
    self._activeConnections = {}
    self._rareSpawnVFX = {}         -- active rare-spawn particle blooms

    -- Depth ratio cache
    self._depthRatio = 0            -- 0 (surface) to 1 (max depth)

    -- Oxygen warning state (applied by UpdateDepth, not directly)
    self._oxygenWarningEnabled = false
    self._oxygenWarningIntensity = 0

    return self
end

-- ============================================================
-- Initialize — called once on client start
-- ============================================================
function AtmosphereHandler:Initialize()
    if self._isInitialized then return end
    self._isInitialized = true

    print("[AtmosphereHandler] Initializing deep-sea atmosphere...")

    -- Configure base lighting (one-time setup)
    self:_configureBaseLighting()

    -- Create environmental VFX that persist
    self:_createMarineSnow()
    self:_createLandmarkLighting()
    self:_createLandmarkParticles()
    self:_createPlanktonEmitters()

    -- Player VFX will be created when character spawns
    self:_bindCharacterSpawn()

    -- Depth-tracking loop
    local depthConnection = RunService.RenderStepped:Connect(function(deltaTime)
        self:_onUpdate(deltaTime)
    end)
    table.insert(self._activeConnections, depthConnection)

    -- Bind to rare fish spawn events
    self:_bindRareSpawnEvents()

    print("[AtmosphereHandler] Atmosphere system initialized.")
end

-- ============================================================
-- Base lighting configuration
-- ============================================================
function AtmosphereHandler:_configureBaseLighting()
    -- Surface-visible sun / sky
    Lighting.ClockTime = 10
    Lighting.Brightness = 1.2
    Lighting.GlobalShadows = true
    Lighting.EnvironmentSpecularScale = 0.3  -- muted underwater specular
    Lighting.EnvironmentDiffuseScale = 0.8

    -- Ambient: deep blue-green underwater base (GDD 6.2)
    Lighting.Ambient = Color3.fromRGB(30, 60, 120)
    Lighting.OutdoorAmbient = Color3.fromRGB(40, 80, 140)

    -- Fog: blue-green, starts close for underwater feel
    Lighting.FogColor = Color3.fromRGB(64, 180, 200)
    Lighting.FogStart = 20
    Lighting.FogEnd = 65

    -- Atmosphere (volumetric)
    local atmosphere = Lighting:FindFirstChild("Atmosphere")
    if not atmosphere then
        atmosphere = Instance.new("Atmosphere")
        atmosphere.Parent = Lighting
    end
    atmosphere.Density = 0.35         -- visible volumetric haze
    atmosphere.Offset = 0.15
    atmosphere.Color = Color3.fromRGB(40, 130, 180)
    atmosphere.Decay = Color3.fromRGB(20, 50, 100)
    atmosphere.Glare = 0.05
    atmosphere.Haze = 0.8

    -- Bloom for bioluminescent glows
    local bloom = Lighting:FindFirstChild("Bloom")
    if not bloom then
        bloom = Instance.new("Bloom")
        bloom.Parent = Lighting
    end
    bloom.Intensity = 0.4
    bloom.Threshold = 0.75
    bloom.Size = 24

    -- ColorCorrection for underwater tint
    local colorCorrection = Lighting:FindFirstChild("ColorCorrection")
    if not colorCorrection then
        colorCorrection = Instance.new("ColorCorrection")
        colorCorrection.Parent = Lighting
    end
    colorCorrection.TintColor = Color3.fromRGB(180, 220, 255)
    colorCorrection.Saturation = -0.08
    colorCorrection.Contrast = 0.05

    -- DepthOfField — subtle blur at distance for immersion
    local dof = Lighting:FindFirstChild("DepthOfField")
    if not dof then
        dof = Instance.new("DepthOfField")
        dof.Parent = Lighting
    end
    dof.FarIntensity = 0.15
    dof.FocusDistance = 25
    dof.InFocusRadius = 40
    dof.NearIntensity = 0.0
    dof.Enabled = true

    -- SunRays for god rays
    local sunRays = Lighting:FindFirstChild("SunRays")
    if not sunRays then
        sunRays = Instance.new("SunRays")
        sunRays.Parent = Lighting
    end
    sunRays.Intensity = 0.25
    sunRays.Spread = 0.4
end

-- ============================================================
-- Marine snow — floating particulate matter
-- ============================================================
function AtmosphereHandler:_createMarineSnow()
    -- Create a large invisible part in the zone that emits marine snow
    local snowContainer = Instance.new("Part")
    snowContainer.Name = "MarineSnowContainer"
    snowContainer.Size = Vector3.new(120, 55, 120)  -- covers entire zone
    snowContainer.Position = Vector3.new(0, -25, 0) -- centered in zone
    snowContainer.Transparency = 1
    snowContainer.Anchored = true
    snowContainer.CanCollide = false
    snowContainer.Parent = workspace

    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "MarineSnowEmitter"
    emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    emitter.Rate = 80
    emitter.Lifetime = NumberRange.new(4, 12)
    emitter.Speed = NumberRange.new(0.3, 1.5)
    emitter.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.03),
        NumberSequenceKeypoint.new(0.5, 0.06),
        NumberSequenceKeypoint.new(1, 0.02),
    }
    emitter.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.7),
        NumberSequenceKeypoint.new(0.5, 0.4),
        NumberSequenceKeypoint.new(1, 0.85),
    }
    emitter.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
    emitter.SpreadAngle = Vector2.new(0, 0)
    emitter.Acceleration = Vector3.new(0, 0.1, 0)    -- gentle upward drift
    emitter.Drag = 0.5
    emitter.VelocityInheritance = 0.1
    emitter.LockedToPart = true
    emitter.Enabled = true
    emitter.Parent = snowContainer

    self._marineSnowEmitter = emitter
    self._marineSnowContainer = snowContainer
end

-- ============================================================
-- Landmark lighting — placed at GDD 6.3 coordinates
-- ============================================================
function AtmosphereHandler:_createLandmarkLighting()
    -- Coral Gardens: warm golden/orange accent
    self:_addLandmarkLightGroup("CoralGardens", 5)

    -- Shipwreck: cold blue-white, eerie flickering
    self:_addLandmarkLightGroup("Shipwreck", 4)

    -- Deep Reef Edge: purple/magenta deep-water tint
    self:_addLandmarkLightGroup("DeepReefEdge", 3)
end

function AtmosphereHandler:_addLandmarkLightGroup(presetKey, lightCount)
    local preset = LANDMARK_PRESETS[presetKey]
    if not preset then return end

    for i = 1, lightCount do
        local angle = (i / lightCount) * math.pi * 2 + math.random() * 0.5
        local radius = preset.Radius * (0.3 + math.random() * 0.7)
        local x = preset.CenterPosition.X + math.cos(angle) * radius
        local z = preset.CenterPosition.Z + math.sin(angle) * radius
        local y = preset.CenterPosition.Y + math.random() * 4 - 2

        local light = Instance.new("PointLight")
        light.Name = presetKey .. "_AccentLight_" .. i
        light.Brightness = preset.GlowBrightness * (0.6 + math.random() * 0.4)
        light.Range = preset.GlowRange * (0.7 + math.random() * 0.3)
        light.Color = (i % 2 == 0) and preset.AccentColor or preset.AccentColor2
        light.Shadows = false
        light.Enabled = true

        -- Anchor light in workspace via a small invisible part
        local anchor = Instance.new("Part")
        anchor.Name = presetKey .. "_LightAnchor_" .. i
        anchor.Size = Vector3.new(0.2, 0.2, 0.2)
        anchor.Position = Vector3.new(x, y, z)
        anchor.Transparency = 1
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.Parent = workspace
        light.Parent = anchor

        table.insert(self._landmarkLights, {
            Light = light,
            Anchor = anchor,
            Preset = presetKey,
            BaseBrightness = light.Brightness,
            BaseColor = light.Color,
        })
    end
end

-- ============================================================
-- Landmark bioluminescent particles
-- ============================================================
function AtmosphereHandler:_createLandmarkParticles()
    for presetKey, preset in pairs(LANDMARK_PRESETS) do
        self:_addLandmarkParticles(presetKey, preset)
    end
end

function AtmosphereHandler:_addLandmarkParticles(presetKey, preset)
    local count = (presetKey == "CoralGardens") and 6 or 4

    for i = 1, count do
        local angle = (i / count) * math.pi * 2
        local radius = preset.Radius * (0.4 + math.random() * 0.5)
        local x = preset.CenterPosition.X + math.cos(angle) * radius
        local z = preset.CenterPosition.Z + math.sin(angle) * radius
        local y = preset.CenterPosition.Y + math.random() * 5 - 2

        local anchor = Instance.new("Part")
        anchor.Name = presetKey .. "_ParticleAnchor_" .. i
        anchor.Size = Vector3.new(0.2, 0.2, 0.2)
        anchor.Position = Vector3.new(x, y, z)
        anchor.Transparency = 1
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.Parent = workspace

        local emitter = Instance.new("ParticleEmitter")
        emitter.Name = "BioluminescentEmitter_" .. i
        emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        emitter.Rate = 5 + math.random() * 8
        emitter.Lifetime = NumberRange.new(1.5, 4)
        emitter.Speed = NumberRange.new(0.5, 2)
        emitter.Size = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.1),
            NumberSequenceKeypoint.new(0.5, 0.25),
            NumberSequenceKeypoint.new(1, 0.05),
        }
        emitter.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.3),
            NumberSequenceKeypoint.new(0.5, 0.0),
            NumberSequenceKeypoint.new(1, 1),
        }
        emitter.Color = ColorSequence.new(preset.ParticleColor)
        emitter.SpreadAngle = Vector2.new(15, 30)
        emitter.Acceleration = Vector3.new(0, 0.5, 0)  -- drift upward
        emitter.Drag = 0.3
        emitter.LockedToPart = true
        emitter.Enabled = true
        emitter.Parent = anchor

        table.insert(self._landmarkParticles, {
            Emitter = emitter,
            Anchor = anchor,
            Preset = presetKey,
        })
    end
end

-- ============================================================
-- Floating bioluminescent plankton — drifting particles
-- ============================================================
function AtmosphereHandler:_createPlanktonEmitters()
    -- Create several plankton fields scattered through the zone
    local planktonPositions = {
        Vector3.new(-15, -12, 15),   -- Coral Gardens area
        Vector3.new(20, -8, -10),    -- Coral Gardens edge
        Vector3.new(35, -20, 25),    -- Sandy Plains
        Vector3.new(10, -25, 30),    -- Sandy Plains deep
        Vector3.new(5, -40, -5),     -- Shipwreck vicinity
        Vector3.new(20, -38, -15),   -- Shipwreck edge
        Vector3.new(-15, -48, -20),  -- Deep Reef Edge
        Vector3.new(-28, -46, -30),  -- Deep Reef Edge
    }

    for i, pos in ipairs(planktonPositions) do
        local anchor = Instance.new("Part")
        anchor.Name = "PlanktonField_" .. i
        anchor.Size = Vector3.new(30, 15, 30)
        anchor.Position = pos
        anchor.Transparency = 1
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.Parent = workspace

        local emitter = Instance.new("ParticleEmitter")
        emitter.Name = "PlanktonEmitter"
        emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        emitter.Rate = 3 + math.random() * 4
        emitter.Lifetime = NumberRange.new(3, 8)
        emitter.Speed = NumberRange.new(0.2, 0.8)
        emitter.Size = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.04),
            NumberSequenceKeypoint.new(0.5, 0.12),
            NumberSequenceKeypoint.new(1, 0.02),
        }
        emitter.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.5),
            NumberSequenceKeypoint.new(0.3, 0.1),
            NumberSequenceKeypoint.new(0.7, 0.2),
            NumberSequenceKeypoint.new(1, 1),
        }
        -- Bioluminescent blue-green
        local hue = 0.5 + math.random() * 0.2
        emitter.Color = ColorSequence.new(Color3.fromHSV(hue, 0.6, 0.9))
        emitter.SpreadAngle = Vector2.new(0, 360)
        emitter.Acceleration = Vector3.new(0, 0.3, 0)    -- slow upward drift
        emitter.Drag = 0.2
        emitter.LockedToPart = true
        emitter.Enabled = true
        emitter.Parent = anchor

        table.insert(self._planktonEmitters, {
            Emitter = emitter,
            Anchor = anchor,
        })
    end
end

-- ============================================================
-- God rays / volumetric light shafts
-- ============================================================
function AtmosphereHandler:_createGodRays()
    self:_destroyGodRays()

    -- Create beam-based god rays from the surface downward
    local rayCount = 8
    local surfaceY = 0
    local maxDepth = 55

    for i = 1, rayCount do
        local offsetX = (i - rayCount / 2) * 18 + math.random() * 8
        local offsetZ = (i - rayCount / 2) * 12 + math.random() * 6
        local origin = Vector3.new(offsetX, surfaceY, offsetZ)
        local target = Vector3.new(offsetX + math.random() * 4 - 2, -maxDepth, offsetZ + math.random() * 4 - 2)

        -- Beam-based ray: create two attachments linked by a Beam
        local rayOriginPart = Instance.new("Part")
        rayOriginPart.Name = "GodRayOrigin_" .. i
        rayOriginPart.Size = Vector3.new(0.1, 0.1, 0.1)
        rayOriginPart.Position = origin
        rayOriginPart.Transparency = 1
        rayOriginPart.Anchored = true
        rayOriginPart.CanCollide = false
        rayOriginPart.Parent = workspace

        local rayTargetPart = Instance.new("Part")
        rayTargetPart.Name = "GodRayTarget_" .. i
        rayTargetPart.Size = Vector3.new(0.1, 0.1, 0.1)
        rayTargetPart.Position = target
        rayTargetPart.Transparency = 1
        rayTargetPart.Anchored = true
        rayTargetPart.CanCollide = false
        rayTargetPart.Parent = workspace

        local attach0 = Instance.new("Attachment")
        attach0.Parent = rayOriginPart
        local attach1 = Instance.new("Attachment")
        attach1.Parent = rayTargetPart

        local beam = Instance.new("Beam")
        beam.Name = "GodRayBeam_" .. i
        beam.Attachment0 = attach0
        beam.Attachment1 = attach1
        beam.Color = ColorSequence.new(Color3.fromRGB(180, 220, 255))
        beam.LightEmission = 0.3
        beam.LightInfluence = 0.2
        beam.Width0 = 0.5 + math.random() * 1.5
        beam.Width1 = 0.3 + math.random() * 1.0
        beam.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.85),
            NumberSequenceKeypoint.new(0.3, 0.7),
            NumberSequenceKeypoint.new(0.7, 0.8),
            NumberSequenceKeypoint.new(1, 0.95),
        }
        beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        beam.TextureSpeed = 0.02
        beam.TextureLength = 1
        beam.FaceCamera = false
        beam.Parent = rayOriginPart

        table.insert(self._godRayBeams, {
            OriginPart = rayOriginPart,
            TargetPart = rayTargetPart,
            Beam = beam,
            BaseTransparency = 0.85,
        })
    end
end

function AtmosphereHandler:_destroyGodRays()
    for _, ray in ipairs(self._godRayBeams) do
        if ray.OriginPart then ray.OriginPart:Destroy() end
        if ray.TargetPart then ray.TargetPart:Destroy() end
    end
    self._godRayBeams = {}
end

-- ============================================================
-- Caustic light patterns — animated SurfaceLight / PointLight
-- ============================================================
function AtmosphereHandler:_createCausticLights()
    self:_destroyCausticLights()

    local causticCount = 6

    for i = 1, causticCount do
        local x = (i - causticCount / 2) * 25 + math.random() * 10
        local z = math.random() * 40 - 20
        local y = -3 - math.random() * 8

        local anchor = Instance.new("Part")
        anchor.Name = "CausticAnchor_" .. i
        anchor.Size = Vector3.new(0.2, 0.2, 0.2)
        anchor.Position = Vector3.new(x, y, z)
        anchor.Transparency = 1
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.Parent = workspace

        local light = Instance.new("PointLight")
        light.Name = "CausticLight_" .. i
        light.Brightness = 0.3 + math.random() * 0.4
        light.Range = 8 + math.random() * 6
        light.Color = Color3.fromRGB(140, 210, 240)
        light.Shadows = false
        light.Enabled = true
        light.Parent = anchor

        table.insert(self._causticLights, {
            Light = light,
            Anchor = anchor,
            BaseBrightness = light.Brightness,
            Phase = math.random() * math.pi * 2,   -- random phase for oscillation
            Speed = 0.8 + math.random() * 1.5,      -- oscillation speed
        })
    end
end

function AtmosphereHandler:_destroyCausticLights()
    for _, caustic in ipairs(self._causticLights) do
        if caustic.Anchor then caustic.Anchor:Destroy() end
    end
    self._causticLights = {}
end

-- ============================================================
-- Player VFX: Bubble trail
-- ============================================================
function AtmosphereHandler:_createBubbleTrail(character)
    self:_destroyBubbleTrail()

    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end

    -- Create an attachment on the HumanoidRootPart
    local attachment = Instance.new("Attachment")
    attachment.Name = "BubbleTrailAttachment"
    attachment.Position = Vector3.new(0, 1.5, -1) -- behind and above player
    attachment.Parent = humanoidRootPart

    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "BubbleTrailEmitter"
    emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    emitter.Rate = 15
    emitter.Lifetime = NumberRange.new(0.8, 2.5)
    emitter.Speed = NumberRange.new(1, 3)
    emitter.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.08),
        NumberSequenceKeypoint.new(0.5, 0.16),
        NumberSequenceKeypoint.new(1, 0.25),
    }
    emitter.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.6),
        NumberSequenceKeypoint.new(0.3, 0.3),
        NumberSequenceKeypoint.new(1, 0.9),
    }
    emitter.Color = ColorSequence.new(Color3.fromRGB(200, 230, 255))
    emitter.SpreadAngle = Vector2.new(10, 20)
    emitter.Acceleration = Vector3.new(0, 2, 0)    -- bubbles rise
    emitter.Drag = 0.5
    emitter.LockedToPart = false
    emitter.VelocityInheritance = 0.2
    emitter.Enabled = true
    emitter.Parent = attachment

    self._bubbleTrailAttachment = attachment
    self._bubbleTrailEmitter = emitter
end

function AtmosphereHandler:_destroyBubbleTrail()
    if self._bubbleTrailAttachment then
        self._bubbleTrailAttachment:Destroy()
        self._bubbleTrailAttachment = nil
    end
    self._bubbleTrailEmitter = nil
end

-- ============================================================
-- Player VFX: Bubble burst on dive entry
-- ============================================================
function AtmosphereHandler:PlayDiveEntryBurst()
    local player = Players.LocalPlayer
    local character = player.Character
    if not character then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    -- Create a temporary burst at player position
    local burstAnchor = Instance.new("Part")
    burstAnchor.Name = "DiveBurstAnchor"
    burstAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
    burstAnchor.Position = rootPart.Position
    burstAnchor.Transparency = 1
    burstAnchor.Anchored = true
    burstAnchor.CanCollide = false
    burstAnchor.Parent = workspace

    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "DiveBurstEmitter"
    emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    emitter.Rate = 200                      -- burst rate
    emitter.Lifetime = NumberRange.new(0.5, 1.5)
    emitter.Speed = NumberRange.new(2, 8)
    emitter.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.15),
        NumberSequenceKeypoint.new(0.5, 0.3),
        NumberSequenceKeypoint.new(1, 0.05),
    }
    emitter.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(0.5, 0.2),
        NumberSequenceKeypoint.new(1, 1),
    }
    emitter.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
    emitter.SpreadAngle = Vector2.new(0, 360)
    emitter.Acceleration = Vector3.new(0, 3, 0)
    emitter.Drag = 0.8
    emitter.LockedToPart = true
    emitter.Enabled = true
    emitter.Parent = burstAnchor

    -- Auto-destroy after burst
    task.delay(2, function()
        burstAnchor:Destroy()
    end)
end

-- ============================================================
-- Player VFX: Glow ring in dark areas
-- ============================================================
function AtmosphereHandler:_createPlayerGlowRing(character)
    self:_destroyPlayerGlowRing()

    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end

    local glowLight = Instance.new("PointLight")
    glowLight.Name = "PlayerGlowRing"
    glowLight.Brightness = 0     -- starts off, fades in at depth
    glowLight.Range = 15
    glowLight.Color = Color3.fromRGB(100, 180, 230)
    glowLight.Shadows = false
    glowLight.Enabled = true
    glowLight.Parent = humanoidRootPart

    self._playerGlowRing = glowLight
end

function AtmosphereHandler:_destroyPlayerGlowRing()
    if self._playerGlowRing then
        self._playerGlowRing:Destroy()
        self._playerGlowRing = nil
    end
end

-- ============================================================
-- Player VFX: Oxygen low warning
-- ============================================================
function AtmosphereHandler:SetOxygenWarning(enabled, intensity)
    -- Store state only — actual Lighting modifications happen in UpdateDepth()
    -- so Bloom/DoF/ColorCorrection are set from a single authority each frame.
    self._oxygenWarningEnabled = enabled
    self._oxygenWarningIntensity = intensity or 0

    -- Heartbeat particle pulse (VFX only, doesn't touch Lighting)
    if enabled and intensity > 0.5 and not self._heartbeatPulse then
        self:_createHeartbeatPulse()
    elseif (not enabled or intensity <= 0.5) and self._heartbeatPulse then
        self:_destroyHeartbeatPulse()
    end
end

function AtmosphereHandler:_createHeartbeatPulse()
    local player = Players.LocalPlayer
    local character = player.Character
    if not character then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    local attachment = Instance.new("Attachment")
    attachment.Name = "HeartbeatPulseAttachment"
    attachment.Parent = rootPart

    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "HeartbeatPulseEmitter"
    emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    emitter.Rate = 2                        -- slow pulse
    emitter.Lifetime = NumberRange.new(0.3, 1.0)
    emitter.Speed = NumberRange.new(0.5, 1.5)
    emitter.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(0.5, 0.6),
        NumberSequenceKeypoint.new(1, 0.1),
    }
    emitter.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(0.5, 0.1),
        NumberSequenceKeypoint.new(1, 1),
    }
    emitter.Color = ColorSequence.new(Color3.fromRGB(255, 40, 40)) -- red pulse
    emitter.SpreadAngle = Vector2.new(0, 360)
    emitter.LockedToPart = true
    emitter.Enabled = true
    emitter.Parent = attachment

    self._heartbeatPulseAttachment = attachment
    self._heartbeatPulse = emitter
end

function AtmosphereHandler:_destroyHeartbeatPulse()
    if self._heartbeatPulseAttachment then
        self._heartbeatPulseAttachment:Destroy()
        self._heartbeatPulseAttachment = nil
    end
    self._heartbeatPulse = nil
end

-- ============================================================
-- Rare fish spawn visual: bioluminescent bloom
-- ============================================================
function AtmosphereHandler:PlayRareSpawnBloom(position, rarity)
    -- Determine bloom color and intensity by rarity
    local color, particleCount, lifetime
    if rarity == "Legendary" then
        color = Color3.fromRGB(255, 220, 100)     -- gold/white bloom
        particleCount = 100
        lifetime = 6
    elseif rarity == "Rare" then
        color = Color3.fromRGB(100, 220, 255)      -- cyan bloom
        particleCount = 60
        lifetime = 4
    else
        color = Color3.fromRGB(150, 200, 255)
        particleCount = 30
        lifetime = 3
    end

    local anchor = Instance.new("Part")
    anchor.Name = "RareSpawnBloom_" .. rarity
    anchor.Size = Vector3.new(0.2, 0.2, 0.2)
    anchor.Position = position
    anchor.Transparency = 1
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.Parent = workspace

    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "RareSpawnEmitter"
    emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    emitter.Rate = particleCount
    emitter.Lifetime = NumberRange.new(1, lifetime)
    emitter.Speed = NumberRange.new(1, 5)
    emitter.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.05),
        NumberSequenceKeypoint.new(0.3, 0.25),
        NumberSequenceKeypoint.new(1, 0.02),
    }
    emitter.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(0.4, 0.0),
        NumberSequenceKeypoint.new(1, 1),
    }
    emitter.Color = ColorSequence.new(color)
    emitter.SpreadAngle = Vector2.new(0, 360)
    emitter.Acceleration = Vector3.new(0, 1.5, 0)    -- bloom outward and up
    emitter.Drag = 0.4
    emitter.LockedToPart = true
    emitter.Enabled = true
    emitter.Parent = anchor

    -- Also create a flash PointLight
    local flashLight = Instance.new("PointLight")
    flashLight.Name = "RareSpawnFlash"
    flashLight.Brightness = (rarity == "Legendary") and 3 or 1.5
    flashLight.Range = (rarity == "Legendary") and 20 or 12
    flashLight.Color = color
    flashLight.Shadows = false
    flashLight.Enabled = true
    flashLight.Parent = anchor

    -- Fade out the flash over 1 second
    TweenService:Create(flashLight, TweenInfo.new(1.0), { Brightness = 0 }):Play()

    -- Auto-destroy after animation
    task.delay(lifetime + 1, function()
        anchor:Destroy()
    end)

    -- Store reference
    table.insert(self._rareSpawnVFX, anchor)
end

-- ============================================================
-- Shipwreck flicker effect
-- ============================================================
function AtmosphereHandler:_updateShipwreckFlicker(deltaTime)
    local preset = LANDMARK_PRESETS.Shipwreck
    if not preset then return end

    for _, entry in ipairs(self._landmarkLights) do
        if entry.Preset == "Shipwreck" then
            -- Flicker: gentle sinusoidal + random jitter
            local flicker = math.sin(tick() * preset.FlickerSpeed) * 0.3
            local jitter = (math.noise(tick() * 4, entry.Light.Parent.Position.X) - 0.5) * 0.4
            local brightness = entry.BaseBrightness * math.clamp(0.3 + flicker + jitter, 0.1, 1.0)
            entry.Light.Brightness = brightness
        end
    end
end

-- ============================================================
-- Depth-based god ray visibility
-- ============================================================
function AtmosphereHandler:_updateGodRayVisibility(depthRatio)
    for _, ray in ipairs(self._godRayBeams) do
        -- God rays strongest near surface (0-15m), fade out by 30m
        local visibility = 1 - math.clamp(depthRatio * 2.5, 0, 1)
        ray.Beam.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, ray.BaseTransparency + (1 - visibility) * 0.15),
            NumberSequenceKeypoint.new(0.3, 0.7 + (1 - visibility) * 0.2),
            NumberSequenceKeypoint.new(0.7, 0.8 + (1 - visibility) * 0.15),
            NumberSequenceKeypoint.new(1, 0.95 + (1 - visibility) * 0.05),
        }
    end
end

-- ============================================================
-- Depth-based caustic animation
-- ============================================================
function AtmosphereHandler:_updateCausticLights(tickTime, depthRatio)
    for _, caustic in ipairs(self._causticLights) do
        local oscillation = math.sin(tickTime * caustic.Speed + caustic.Phase) * 0.5 + 0.5
        local depthFade = 1 - math.clamp(depthRatio * 3.0, 0, 1)  -- fade out rapidly with depth
        caustic.Light.Brightness = caustic.BaseBrightness * oscillation * depthFade
    end
end

-- ============================================================
-- Player glow ring: fades in at deeper depths
-- ============================================================
function AtmosphereHandler:_updatePlayerGlow(depthRatio)
    if not self._playerGlowRing then return end

    -- Glow ring starts becoming visible below 25m, full at 45m+
    local glowVisibility = math.clamp((depthRatio - 0.5) / 0.4, 0, 1)
    self._playerGlowRing.Brightness = glowVisibility * 1.2
    self._playerGlowRing.Range = 10 + glowVisibility * 8     -- expands from 10 to 18 studs
end

-- ============================================================
-- Per-frame update
-- ============================================================
function AtmosphereHandler:_onUpdate(deltaTime)
    -- Depth / depthRatio are set externally via UpdateDepth() from CameraController
    -- (single authority — no independent depth calculation here)

    -- Update god ray visibility
    self:_updateGodRayVisibility(self._depthRatio)

    -- Animate caustic lights
    self:_updateCausticLights(tick(), self._depthRatio)

    -- Update shipwreck flicker
    self:_updateShipwreckFlicker(deltaTime)

    -- Update player glow ring
    self:_updatePlayerGlow(self._depthRatio)

    -- Marine snow: increase density at mid-depths
    if self._marineSnowEmitter then
        -- More particles in 15-35m range, less near surface and very deep
        local snowDensity = 1
        if self._currentDepth < 10 then
            snowDensity = 0.2 + (self._currentDepth / 10) * 0.8
        elseif self._currentDepth > 40 then
            snowDensity = 1 - (self._currentDepth - 40) / 10 * 0.5
        end
        self._marineSnowEmitter.Rate = 60 + snowDensity * 60
    end
end

function AtmosphereHandler:_updateDepthBloom(depthRatio)
    local bloom = Lighting:FindFirstChild("Bloom")
    if not bloom then return end

    -- At surface: subtle. At depth: more bloom to make bioluminescence pop
    bloom.Intensity = 0.3 + depthRatio * 0.5
    bloom.Threshold = 0.85 - depthRatio * 0.2
end

function AtmosphereHandler:_updateDepthDOF(depthRatio)
    local dof = Lighting:FindFirstChild("DepthOfField")
    if not dof then return end

    -- Subtle blur increase at depth for immersion
    dof.FarIntensity = 0.1 + depthRatio * 0.15
    dof.FocusDistance = 30 - depthRatio * 15
end

-- ============================================================
-- Character spawn binding
-- ============================================================
function AtmosphereHandler:_bindCharacterSpawn()
    local player = Players.LocalPlayer

    local function onCharacterAdded(character)
        -- Wait for character to fully load
        task.wait(0.5)

        -- Create player VFX
        self:_createBubbleTrail(character)
        self:_createPlayerGlowRing(character)

        -- Create god rays and caustics (must be in workspace, not player-specific)
        if #self._godRayBeams == 0 then
            self:_createGodRays()
            self:_createCausticLights()
        end
    end

    -- Bind to character spawn
    player.CharacterAdded:Connect(onCharacterAdded)

    -- If character already exists
    if player.Character then
        onCharacterAdded(player.Character)
    end
end

-- ============================================================
-- Rare spawn event binding
-- ============================================================
function AtmosphereHandler:_bindRareSpawnEvents()
    -- Listen for rare fish spawns via Knit signals
    -- This pattern uses the shared Knit framework
    local Knit
    pcall(function()
        Knit = require(ReplicatedStorage:WaitForChild("Knit"))
    end)

    if not Knit then return end

    -- Try to get the ZoneService signal for rare spawns
    pcall(function()
        local rareSpawnSignal = Knit.GetSignal("RareFishSpawned")
        if rareSpawnSignal then
            rareSpawnSignal:Connect(function(position, speciesName, rarity)
                self:PlayRareSpawnBloom(position, rarity)
            end)
        end
    end)
end

-- ============================================================
-- Public API: trigger from other controllers
-- ============================================================

-- Single authority for all per-frame Lighting post-processing.
-- Called by CameraController each frame with the authoritative depth value.
function AtmosphereHandler:UpdateDepth(depth, isUnderwater)
    self._currentDepth = depth
    self._isUnderwater = isUnderwater or false

    -- Compute depth ratio from zone config
    local zone = ZoneConfigs.GetZoneAtDepth(depth)
    local maxDepth = (zone and zone.DepthMax) or 50
    self._depthRatio = math.clamp(depth / maxDepth, 0, 1)

    local dr = self._depthRatio  -- shorthand

    -- === Bloom: depth-based bioluminescence pop + oxygen warning overlay ===
    local bloom = Lighting:FindFirstChild("Bloom")
    if bloom then
        local baseIntensity = 0.3 + dr * 0.5
        local baseThreshold = 0.85 - dr * 0.2

        if self._oxygenWarningEnabled and self._oxygenWarningIntensity > 0 then
            local wi = self._oxygenWarningIntensity
            bloom.Intensity = baseIntensity + wi * 0.5
            bloom.Threshold = baseThreshold - wi * 0.3
        else
            bloom.Intensity = baseIntensity
            bloom.Threshold = baseThreshold
        end
    end

    -- === DepthOfField: subtle distance blur that deepens with depth ===
    local dof = Lighting:FindFirstChild("DepthOfField")
    if dof then
        if self._isUnderwater then
            dof.FarIntensity = 0.1 + dr * 0.15
            dof.FocusDistance = 30 - dr * 15
        else
            -- Surface defaults (no underwater blur)
            dof.FarIntensity = 0.05
            dof.FocusDistance = 100
        end
    end

    -- === ColorCorrection: underwater tint + oxygen warning red-shift ===
    local cc = Lighting:FindFirstChild("ColorCorrection")
    if cc then
        if self._oxygenWarningEnabled and self._oxygenWarningIntensity > 0 then
            local wi = self._oxygenWarningIntensity
            cc.Saturation = -0.08 - wi * 0.3
            cc.Contrast = 0.05 + wi * 0.15
            local redTint = Color3.fromRGB(
                180 + 75 * wi,
                220 * (1 - wi * 0.5),
                255 * (1 - wi * 0.6)
            )
            cc.TintColor = cc.TintColor:Lerp(redTint, 0.5)
        else
            -- Reset to underwater base (no warning)
            cc.Saturation = -0.08
            cc.Contrast = 0.05
            cc.TintColor = Color3.fromRGB(180, 220, 255)
        end
    end
end

-- Called when player breaches surface
function AtmosphereHandler:OnSurfaceBreach()
    self._isUnderwater = false
    self:_destroyGodRays()
    self:_destroyCausticLights()

    -- Reset DoF to surface defaults
    local dof = Lighting:FindFirstChild("DepthOfField")
    if dof then
        dof.FarIntensity = 0.05
        dof.FocusDistance = 100
    end
end

-- Called when player submerges
function AtmosphereHandler:OnSubmerge()
    if #self._godRayBeams == 0 then
        self:_createGodRays()
        self:_createCausticLights()
    end
    self:PlayDiveEntryBurst()
end

-- Called when a fish of given rarity enters the player's awareness
function AtmosphereHandler:OnRareFishNearby(position, rarity)
    self:PlayRareSpawnBloom(position, rarity)
end

-- ============================================================
-- Cleanup
-- ============================================================
function AtmosphereHandler:Destroy()
    -- Disconnect all connections
    for _, conn in ipairs(self._activeConnections) do
        conn:Disconnect()
    end
    self._activeConnections = {}

    -- Destroy god rays
    self:_destroyGodRays()

    -- Destroy caustic lights
    self:_destroyCausticLights()

    -- Destroy landmark lights
    for _, entry in ipairs(self._landmarkLights) do
        if entry.Anchor then entry.Anchor:Destroy() end
    end
    self._landmarkLights = {}

    -- Destroy landmark particles
    for _, entry in ipairs(self._landmarkParticles) do
        if entry.Anchor then entry.Anchor:Destroy() end
    end
    self._landmarkParticles = {}

    -- Destroy plankton fields
    for _, entry in ipairs(self._planktonEmitters) do
        if entry.Anchor then entry.Anchor:Destroy() end
    end
    self._planktonEmitters = {}

    -- Destroy marine snow
    if self._marineSnowContainer then
        self._marineSnowContainer:Destroy()
        self._marineSnowContainer = nil
        self._marineSnowEmitter = nil
    end

    -- Destroy player VFX
    self:_destroyBubbleTrail()
    self:_destroyPlayerGlowRing()
    self:_destroyHeartbeatPulse()

    -- Clean rare spawn anchors
    for _, anchor in ipairs(self._rareSpawnVFX) do
        if anchor then anchor:Destroy() end
    end
    self._rareSpawnVFX = {}

    print("[AtmosphereHandler] Atmosphere system destroyed.")
end

return AtmosphereHandler
