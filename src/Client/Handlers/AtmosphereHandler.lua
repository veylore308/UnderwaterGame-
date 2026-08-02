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

    Zone reference: The Kelp Forest (50–150m) — Phase 2
      - Kelp Canopy:   50–75m  — dark blue-green, dappled god rays through fronds
      - The Clearing:  75–100m — open teal/cyan, diagonal current particles
      - Rocky Grotto:  100–130m — near-dark, amber cave glows, bioluminescent lichen
      - Abyss Edge:    130–150m — near-black, deep purple fog, void silhouettes
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
    -- Kelp Forest zone lighting presets (Phase 2, GDD §2)
    -- ============================================================
    local KELP_LANDMARK_PRESETS = {
    KelpCanopy = {
        CenterPosition = Vector3.new(0, -62, 0),
        Radius = 80,
        AccentColor = Color3.fromRGB(60, 180, 140),    -- dappled green-gold
        AccentColor2 = Color3.fromRGB(40, 140, 100),   -- deep teal
        GlowRange = 14,
        GlowBrightness = 0.4,
        ParticleColor = Color3.fromRGB(80, 255, 160),  -- bioluminescent green
    },
    TheClearing = {
        CenterPosition = Vector3.new(25, -87, 20),
        Radius = 55,
        AccentColor = Color3.fromRGB(100, 200, 220),   -- open cyan/teal
        AccentColor2 = Color3.fromRGB(60, 150, 180),   -- mid-water blue
        GlowRange = 16,
        GlowBrightness = 0.35,
        ParticleColor = Color3.fromRGB(140, 220, 255), -- clearing motes
    },
    RockyGrotto = {
        CenterPosition = Vector3.new(-15, -115, -10),
        Radius = 45,
        AccentColor = Color3.fromRGB(255, 180, 80),    -- warm amber/gold cave glow
        AccentColor2 = Color3.fromRGB(200, 140, 60),   -- muted gold
        GlowRange = 8,
        GlowBrightness = 0.25,
        ParticleColor = Color3.fromRGB(100, 220, 200), -- cyan lichen motes
        -- Air pocket positions for bubble VFX
        AirPockets = {
            { Name = "Grotto North Cave", Position = Vector3.new(-20, -108, -5) },
            { Name = "Grotto South Crevice", Position = Vector3.new(-8, -112, -18) },
        },
    },
    AbyssEdge = {
        CenterPosition = Vector3.new(-30, -140, -35),
        Radius = 40,
        AccentColor = Color3.fromRGB(120, 40, 160),    -- deep purple
        AccentColor2 = Color3.fromRGB(20, 10, 60),     -- near-black violet
        GlowRange = 6,
        GlowBrightness = 0.15,
        ParticleColor = Color3.fromRGB(160, 80, 255),  -- purple void motes
    },
    }

    -- Kelp Forest zone-wide atmosphere parameters
    local KELP_FOREST_ATMOSPHERE = {
    -- Navy at 50m → near-black at 150m (GDD §2.2)
    WaterColorShallow = Color3.fromRGB(10, 22, 40),     -- navy #0A1628 at 50m
    WaterColorDeep = Color3.fromRGB(2, 8, 16),           -- near-black #020810 at 150m
    FogColorShallow = Color3.fromRGB(15, 40, 35),        -- deep teal fog at canopy
    FogColorDeep = Color3.fromRGB(3, 8, 10),             -- murky near-black at 150m
    AbyssFogColor = Color3.fromRGB(15, 3, 30),           -- deep purple/magenta at 140-150m
    AbyssFogStartDepth = 140,                             -- studs depth for purple fog transition

    -- Fog increases 2× from Shallows: visibility 40→30 below 100m
    FogStartShallow = 20,     -- fog begins at 20 studs
    FogEndShallow = 40,       -- visibility 40 studs (vs 65 in Shallows)
    FogStartDeep = 15,        -- tighter fog below 100m
    FogEndDeep = 30,          -- visibility 30 studs below 100m

    -- Bioluminescence: more bloom at depth (less surface light = creatures glow brighter)
    BloomIntensityBase = 0.45,
    BloomIntensityDeep = 0.7,
    BloomThresholdBase = 0.7,
    BloomThresholdDeep = 0.5,

    -- Darker ambient
    AmbientShallow = Color3.fromRGB(20, 50, 30),
    AmbientDeep = Color3.fromRGB(8, 15, 12),

    -- Dappled god rays: fewer, narrower, filtering through canopy
    GodRayCount = 6,
    GodRayWidth0 = 0.3,
    GodRayWidth1 = 0.2,

    -- Depth transition marker for zone boundary
    BoundaryDepth = 50,
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
    self._currentZoneKey = "SunkenShallows"   -- zone tracking for transitions
    self._previousZoneKey = "SunkenShallows"
    self._zoneTransitionProgress = 1.0        -- 0→1 tween progress
    self._zoneTransitionTween = nil           -- active TweenService tween
    self._closestLandmark = nil
    self._isInitialized = false
    self._isUnderwater = false
    self._activeConnections = {}
    self._rareSpawnVFX = {}         -- active rare-spawn particle blooms

    -- Kelp Forest runtime VFX
    self._airPocketBubbles = {}     -- air pocket bubble column emitters
    self._currentParticles = nil    -- Clearing diagonal current particles
    self._grottoSediment = nil      -- Rocky Grotto floating sediment
    self._entanglementVFX = nil     -- active kelp entanglement particle effect

    -- Phase 3 surface weather runtime
    self._surfaceMode = false
    self._outpostMode = false
    self._weatherState = "Calm"
    self._weatherContainer = nil
    self._rainEmitter = nil
    self._splashEmitter = nil
    self._whitecaps = {}
    self._weatherTween = nil

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
    self:_createKelpForestVFX()       -- Phase 2: Grotto air pockets, current, sediment

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
-- Kelp Forest persistent VFX (Phase 2, GDD §2.6)
-- Air pocket bubble columns, Clearing current, Grotto sediment
-- ============================================================
function AtmosphereHandler:_createKelpForestVFX()
    -- 1. Air pocket bubble columns (Rocky Grotto, 2 cave locations)
    local grottoPreset = KELP_LANDMARK_PRESETS.RockyGrotto
    if grottoPreset and grottoPreset.AirPockets then
        for _, pocket in ipairs(grottoPreset.AirPockets) do
            local anchor = Instance.new("Part")
            anchor.Name = "AirPocketBubbles_" .. pocket.Name:gsub(" ", "_")
            anchor.Size = Vector3.new(6, 3, 6)
            anchor.Position = pocket.Position
            anchor.Transparency = 1
            anchor.Anchored = true
            anchor.CanCollide = false
            anchor.Parent = workspace

            -- Rising bubble column
            local bubbleEmitter = Instance.new("ParticleEmitter")
            bubbleEmitter.Name = "AirPocketBubbles"
            bubbleEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
            bubbleEmitter.Rate = 25
            bubbleEmitter.Lifetime = NumberRange.new(1, 3)
            bubbleEmitter.Speed = NumberRange.new(0.5, 2)
            bubbleEmitter.Size = NumberSequence.new{
                NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.2),
                NumberSequenceKeypoint.new(1, 0.3),
            }
            bubbleEmitter.Transparency = NumberSequence.new{
                NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.5, 0.3),
                NumberSequenceKeypoint.new(1, 0.7),
            }
            bubbleEmitter.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
            bubbleEmitter.SpreadAngle = Vector2.new(5, 10)
            bubbleEmitter.Acceleration = Vector3.new(0, 3, 0)
            bubbleEmitter.Drag = 0.3
            bubbleEmitter.LockedToPart = true
            bubbleEmitter.Enabled = false  -- only in Kelp Forest zone
            bubbleEmitter.Parent = anchor

            -- Sparkle particles
            local sparkleEmitter = Instance.new("ParticleEmitter")
            sparkleEmitter.Name = "AirPocketSparkles"
            sparkleEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
            sparkleEmitter.Rate = 8
            sparkleEmitter.Lifetime = NumberRange.new(0.5, 2)
            sparkleEmitter.Speed = NumberRange.new(0.2, 1)
            sparkleEmitter.Size = NumberSequence.new{
                NumberSequenceKeypoint.new(0, 0.03), NumberSequenceKeypoint.new(0.5, 0.1),
                NumberSequenceKeypoint.new(1, 0.02),
            }
            sparkleEmitter.Transparency = NumberSequence.new{
                NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 0.05),
                NumberSequenceKeypoint.new(1, 1),
            }
            sparkleEmitter.Color = ColorSequence.new(Color3.fromRGB(180, 230, 255))
            sparkleEmitter.SpreadAngle = Vector2.new(10, 20)
            sparkleEmitter.Acceleration = Vector3.new(0, 1, 0)
            sparkleEmitter.Drag = 0.5
            sparkleEmitter.LockedToPart = true
            sparkleEmitter.Enabled = false
            sparkleEmitter.Parent = anchor

            -- Warm amber glow light
            local glowLight = Instance.new("PointLight")
            glowLight.Name = "AirPocketGlow"
            glowLight.Brightness = 0.4
            glowLight.Range = 12
            glowLight.Color = Color3.fromRGB(255, 200, 100)
            glowLight.Shadows = false
            glowLight.Enabled = false
            glowLight.Parent = anchor

            table.insert(self._airPocketBubbles, {
                Anchor = anchor,
                Bubbles = bubbleEmitter,
                Sparkles = sparkleEmitter,
                Glow = glowLight,
            })
        end
    end

    -- 2. Diagonal current particles for The Clearing
    local clearingPreset = KELP_LANDMARK_PRESETS.TheClearing
    if clearingPreset then
        local currentAnchor = Instance.new("Part")
        currentAnchor.Name = "ClearingCurrentVFX"
        currentAnchor.Size = Vector3.new(clearingPreset.Radius * 1.6, 25, clearingPreset.Radius * 1.6)
        currentAnchor.Position = clearingPreset.CenterPosition
        currentAnchor.Transparency = 1
        currentAnchor.Anchored = true
        currentAnchor.CanCollide = false
        currentAnchor.Parent = workspace

        local currentEmitter = Instance.new("ParticleEmitter")
        currentEmitter.Name = "ClearingCurrent"
        currentEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        currentEmitter.Rate = 40
        currentEmitter.Lifetime = NumberRange.new(2, 5)
        currentEmitter.Speed = NumberRange.new(6, 10)
        currentEmitter.Size = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.02), NumberSequenceKeypoint.new(0.5, 0.05),
            NumberSequenceKeypoint.new(1, 0.02),
        }
        currentEmitter.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.3, 0.3),
            NumberSequenceKeypoint.new(0.7, 0.5), NumberSequenceKeypoint.new(1, 0.9),
        }
        currentEmitter.Color = ColorSequence.new(Color3.fromRGB(200, 220, 240))
        currentEmitter.SpreadAngle = Vector2.new(3, 3)
        currentEmitter.VelocitySpread = 20
        currentEmitter.Acceleration = Vector3.new(4, -0.5, -4.5)  -- NW→SE
        currentEmitter.Drag = 0.1
        currentEmitter.LockedToPart = true
        currentEmitter.Enabled = false
        currentEmitter.Parent = currentAnchor

        self._currentParticles = currentEmitter
        self._currentParticlesAnchor = currentAnchor
    end

    -- 3. Rocky Grotto floating sediment + rockfall sparkles
    local grottoCenter = grottoPreset.CenterPosition
    local grottoRadius = grottoPreset.Radius
    if grottoCenter then
        local sedimentAnchor = Instance.new("Part")
        sedimentAnchor.Name = "GrottoAmbientVFX"
        sedimentAnchor.Size = Vector3.new(grottoRadius * 2, 30, grottoRadius * 2)
        sedimentAnchor.Position = grottoCenter
        sedimentAnchor.Transparency = 1
        sedimentAnchor.Anchored = true
        sedimentAnchor.CanCollide = false
        sedimentAnchor.Parent = workspace

        local sedimentEmitter = Instance.new("ParticleEmitter")
        sedimentEmitter.Name = "GrottoSediment"
        sedimentEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        sedimentEmitter.Rate = 20
        sedimentEmitter.Lifetime = NumberRange.new(3, 8)
        sedimentEmitter.Speed = NumberRange.new(0.1, 0.5)
        sedimentEmitter.Size = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.02), NumberSequenceKeypoint.new(0.5, 0.06),
            NumberSequenceKeypoint.new(1, 0.02),
        }
        sedimentEmitter.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.5, 0.4),
            NumberSequenceKeypoint.new(1, 0.85),
        }
        sedimentEmitter.Color = ColorSequence.new(Color3.fromRGB(140, 130, 120))
        sedimentEmitter.SpreadAngle = Vector2.new(0, 360)
        sedimentEmitter.Acceleration = Vector3.new(0, -0.05, 0)
        sedimentEmitter.Drag = 0.8
        sedimentEmitter.LockedToPart = true
        sedimentEmitter.Enabled = false
        sedimentEmitter.Parent = sedimentAnchor

        -- Rockfall sparkles
        local rockfallEmitter = Instance.new("ParticleEmitter")
        rockfallEmitter.Name = "GrottoRockfall"
        rockfallEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        rockfallEmitter.Rate = 3
        rockfallEmitter.Lifetime = NumberRange.new(0.5, 1.5)
        rockfallEmitter.Speed = NumberRange.new(1, 4)
        rockfallEmitter.Size = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.04), NumberSequenceKeypoint.new(0.5, 0.12),
            NumberSequenceKeypoint.new(1, 0.02),
        }
        rockfallEmitter.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(0.3, 0.1),
            NumberSequenceKeypoint.new(1, 1),
        }
        rockfallEmitter.Color = ColorSequence.new(Color3.fromRGB(180, 170, 160))
        rockfallEmitter.SpreadAngle = Vector2.new(10, 20)
        rockfallEmitter.Acceleration = Vector3.new(0, -2, 0)
        rockfallEmitter.Drag = 0.3
        rockfallEmitter.LockedToPart = true
        rockfallEmitter.Enabled = false
        rockfallEmitter.Parent = sedimentAnchor

        self._grottoSediment = sedimentEmitter
        self._grottoRockfall = rockfallEmitter
        self._grottoSedimentAnchor = sedimentAnchor
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

    -- Surface weather owns the above-water visual layer.
    if self._surfaceMode then
        self:_updateSurfaceWeather(deltaTime)
        return
    end

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

    -- === ZONE DETECTION: Check if we've crossed a zone boundary ===
    local zone = ZoneConfigs.GetZoneAtDepth(depth)
    local zoneKey = (zone and zone.Key) or "SunkenShallows"

    if zoneKey ~= self._currentZoneKey and not self._zoneTransitionTween then
        -- Zone boundary crossed — trigger transition
        self._previousZoneKey = self._currentZoneKey
        self._currentZoneKey = zoneKey
        self:_onZoneTransition(self._previousZoneKey, self._currentZoneKey)
    end

    -- Compute depth ratio from zone config
    local maxDepth = (zone and zone.DepthMax) or 50
    self._depthRatio = math.clamp(depth / maxDepth, 0, 1)

    local dr = self._depthRatio  -- shorthand
    local isKelpForest = (zoneKey == "KelpForest")

    -- === ZONE-SPECIFIC FOG & AMBIENT ===
    if isKelpForest then
        -- Kelp Forest atmosphere: darker, denser fog, more bioluminescence
        self:_applyKelpForestLighting(depth, dr)
    else
        -- Sunken Shallows: restore default underwater atmosphere
        self:_applyShallowsLighting(dr)
    end

    -- === Bloom: depth-based bioluminescence pop + oxygen warning overlay ===
    local bloom = Lighting:FindFirstChild("Bloom")
    if bloom then
        local baseIntensity, baseThreshold
        if isKelpForest then
            -- More bloom at depth (less surface light = bioluminescence pops more)
            local kelpAtmo = KELP_FOREST_ATMOSPHERE
            baseIntensity = kelpAtmo.BloomIntensityBase + dr * 0.25
            baseThreshold = kelpAtmo.BloomThresholdBase - dr * 0.2
        else
            baseIntensity = 0.3 + dr * 0.5
            baseThreshold = 0.85 - dr * 0.2
        end

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
        elseif isKelpForest then
            -- Kelp Forest: green-shifted tint
            cc.Saturation = -0.12
            cc.Contrast = 0.08
            cc.TintColor = Color3.fromRGB(140, 200, 180)
        else
            cc.Saturation = -0.08
            cc.Contrast = 0.05
            cc.TintColor = Color3.fromRGB(180, 220, 255)
        end
    end

    -- === SUNRAYS: reduce in Kelp Forest (dappled light through canopy) ===
    local sunRays = Lighting:FindFirstChild("SunRays")
    if sunRays then
        if isKelpForest then
            sunRays.Intensity = 0.1 + (1 - dr) * 0.1   -- much less surface light
            sunRays.Spread = 0.2
        else
            sunRays.Intensity = 0.25
            sunRays.Spread = 0.4
        end
    end
end

-- ============================================================
-- Kelp Forest lighting application
-- ============================================================
function AtmosphereHandler:_applyKelpForestLighting(depth, dr)
    local atmo = KELP_FOREST_ATMOSPHERE

    -- Fog: denser, starts closer
    -- Above 100m: FogStart=20, FogEnd=40 (40 studs visibility)
    -- Below 100m: FogStart=15, FogEnd=30 (30 studs visibility)
    local fogStart, fogEnd, fogColor
    if depth >= 100 then
        fogStart = atmo.FogStartDeep
        fogEnd = atmo.FogEndDeep
    else
        fogStart = atmo.FogStartShallow
        fogEnd = atmo.FogEndShallow
    end

    -- Below AbyssFogStartDepth (140m): transition to deep purple/magenta
    if depth >= atmo.AbyssFogStartDepth then
        local abyssBlend = math.clamp((depth - atmo.AbyssFogStartDepth) / 10, 0, 1)
        fogColor = atmo.FogColorDeep:Lerp(atmo.AbyssFogColor, abyssBlend)
    else
        -- Interpolate fog color from shallow to deep
        local depthBlend = math.clamp((depth - 50) / 50, 0, 1)  -- 50→100m gradient
        fogColor = atmo.FogColorShallow:Lerp(atmo.FogColorDeep, depthBlend)
    end

    Lighting.FogColor = fogColor
    Lighting.FogStart = fogStart
    Lighting.FogEnd = fogEnd

    -- Ambient: darker blue-green, trending toward near-black
    local ambientBlend = math.clamp((depth - 50) / 100, 0, 1)  -- 50→150m
    Lighting.Ambient = atmo.AmbientShallow:Lerp(atmo.AmbientDeep, ambientBlend)

    -- Atmosphere (volumetric): denser at depth
    local atmosphere = Lighting:FindFirstChild("Atmosphere")
    if atmosphere then
        atmosphere.Density = 0.35 + dr * 0.3
        atmosphere.Haze = 0.8 + dr * 0.4
    end
end

-- ============================================================
-- Sunken Shallows lighting restoration
-- ============================================================
function AtmosphereHandler:_applyShallowsLighting(dr)
    -- Restore standard Shallows parameters
    local zone = ZoneConfigs.GetByKey("SunkenShallows")
    if zone and zone.Environment then
        local env = zone.Environment
        Lighting.FogColor = env.WaterColor
        Lighting.FogStart = env.FogStart or 20
        Lighting.FogEnd = env.Visibility or 65
    else
        Lighting.FogColor = Color3.fromRGB(64, 180, 200)
        Lighting.FogStart = 20
        Lighting.FogEnd = 65
    end
    Lighting.Ambient = Color3.fromRGB(30, 60, 120)
end

-- ============================================================
-- Zone transition: triggered when crossing 50m boundary
-- ============================================================
function AtmosphereHandler:_onZoneTransition(fromZone, toZone)
    print("[AtmosphereHandler] Zone transition: " .. fromZone .. " → " .. toZone)

    -- Cancel any existing transition tween
    if self._zoneTransitionTween then
        self._zoneTransitionTween:Cancel()
        self._zoneTransitionTween = nil
    end

    self._zoneTransitionProgress = 0

    -- Fire UI popup event via Knit signal (if available)
    local zoneNames = {
        SunkenShallows = "Sunken Shallows",
        KelpForest = "Kelp Forest",
    }
    local fromName = zoneNames[fromZone] or fromZone
    local toName = zoneNames[toZone] or toZone

    local message
    if toZone == "KelpForest" then
        message = "Entering: Kelp Forest"
        -- Enable Kelp Forest VFX
        self:_enableKelpForestVFX(true)
    elseif toZone == "SunkenShallows" then
        message = "Ascending: Sunken Shallows"
        -- Disable Kelp Forest VFX
        self:_enableKelpForestVFX(false)
    end

    -- Try to fire the zone transition signal via Knit
    pcall(function()
        local Knit = require(ReplicatedStorage:WaitForChild("Knit"))
        local zoneTransitionSignal = Knit.GetSignal("ZoneTransition")
        if zoneTransitionSignal then
            zoneTransitionSignal:Fire(fromZone, toZone, message)
        end
    end)

    -- 2-second smooth transition tween
    local tweenInfo = TweenInfo.new(2.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tweenGoal = { _zoneTransitionProgress = 1.0 }

    self._zoneTransitionTween = TweenService:Create(self, tweenInfo, tweenGoal)
    self._zoneTransitionTween:Play()
    self._zoneTransitionTween.Completed:Connect(function()
        self._zoneTransitionTween = nil
        self._zoneTransitionProgress = 1.0
        print("[AtmosphereHandler] Zone transition complete: " .. toName)
    end)
end

-- ============================================================
-- Enable/disable Kelp Forest-specific VFX based on zone
-- ============================================================
function AtmosphereHandler:_enableKelpForestVFX(enabled)
    -- Air pocket bubbles
    for _, pocket in ipairs(self._airPocketBubbles) do
        if pocket.Bubbles then pocket.Bubbles.Enabled = enabled end
        if pocket.Sparkles then pocket.Sparkles.Enabled = enabled end
        if pocket.Glow then pocket.Glow.Enabled = enabled end
    end

    -- Clearing current particles
    if self._currentParticles then
        self._currentParticles.Enabled = enabled
    end

    -- Grotto sediment + rockfall
    if self._grottoSediment then
        self._grottoSediment.Enabled = enabled
    end
    if self._grottoRockfall then
        self._grottoRockfall.Enabled = enabled
    end
end

-- ============================================================
-- Public API: Smooth zone transition (can be called externally)
-- ============================================================
function AtmosphereHandler:TransitionToKelpForest()
    if self._currentZoneKey == "KelpForest" then return end
    print("[AtmosphereHandler] TransitionToKelpForest() called")
    self._previousZoneKey = self._currentZoneKey
    self._currentZoneKey = "KelpForest"
    self:_onZoneTransition(self._previousZoneKey, "KelpForest")
end

function AtmosphereHandler:TransitionToShallows()
    if self._currentZoneKey == "SunkenShallows" then return end
    print("[AtmosphereHandler] TransitionToShallows() called")
    self._previousZoneKey = self._currentZoneKey
    self._currentZoneKey = "SunkenShallows"
    self:_onZoneTransition(self._previousZoneKey, "SunkenShallows")
end

-- ============================================================
-- Kelp entanglement VFX — called when player is snared
-- ============================================================
function AtmosphereHandler:PlayKelpEntanglementVFX(playerPosition)
    -- Create green-brown particle burst at entanglement point
    local anchor = Instance.new("Part")
    anchor.Name = "KelpEntanglementVFX"
    anchor.Size = Vector3.new(0.2, 0.2, 0.2)
    anchor.Position = playerPosition
    anchor.Transparency = 1
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.Parent = workspace

    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "KelpEntangleEmitter"
    emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    emitter.Rate = 80
    emitter.Lifetime = NumberRange.new(0.5, 1.5)
    emitter.Speed = NumberRange.new(2, 6)
    emitter.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.05),
        NumberSequenceKeypoint.new(0.3, 0.15),
        NumberSequenceKeypoint.new(1, 0.02),
    }
    emitter.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(0.5, 0.1),
        NumberSequenceKeypoint.new(1, 1),
    }
    emitter.Color = ColorSequence.new(Color3.fromRGB(30, 90, 25))  -- green-brown
    emitter.SpreadAngle = Vector2.new(0, 360)
    emitter.Acceleration = Vector3.new(0, 1, 0)
    emitter.Drag = 0.6
    emitter.LockedToPart = true
    emitter.Enabled = true
    emitter.Parent = anchor

    -- Also emit brownish "tangled" motes
    local brownEmitter = Instance.new("ParticleEmitter")
    brownEmitter.Name = "KelpEntangleBrown"
    brownEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    brownEmitter.Rate = 30
    brownEmitter.Lifetime = NumberRange.new(0.3, 1.0)
    brownEmitter.Speed = NumberRange.new(1, 3)
    brownEmitter.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.03),
        NumberSequenceKeypoint.new(0.5, 0.08),
        NumberSequenceKeypoint.new(1, 0.01),
    }
    brownEmitter.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(0.5, 0.2),
        NumberSequenceKeypoint.new(1, 0.9),
    }
    brownEmitter.Color = ColorSequence.new(Color3.fromRGB(80, 60, 30))
    brownEmitter.SpreadAngle = Vector2.new(5, 15)
    brownEmitter.Acceleration = Vector3.new(0, 0.5, 0)
    brownEmitter.Drag = 0.7
    brownEmitter.LockedToPart = true
    brownEmitter.Enabled = true
    brownEmitter.Parent = anchor

    -- Auto-destroy after 2 seconds
    task.delay(2, function()
        anchor:Destroy()
    end)

    self._entanglementVFX = anchor
end

-- ============================================================
-- Phase 3: surface sky, weather and Outpost atmosphere
-- ============================================================
local SURFACE_WEATHER = {
    Calm = {Ambient=Color3.fromRGB(120,150,185), Outdoor=Color3.fromRGB(170,190,210), Fog=Color3.fromRGB(150,190,220), FogEnd=300, Brightness=2.2, Density=0.12, Rain=0, Wind=Vector3.new(0,0,0), Water=Color3.fromRGB(60,120,190)},
    Rain = {Ambient=Color3.fromRGB(75,85,105), Outdoor=Color3.fromRGB(105,115,135), Fog=Color3.fromRGB(105,120,140), FogEnd=150, Brightness=1.25, Density=0.25, Rain=180, Wind=Vector3.new(5,-2,1), Water=Color3.fromRGB(55,105,155)},
    Storm = {Ambient=Color3.fromRGB(35,40,55), Outdoor=Color3.fromRGB(55,60,80), Fog=Color3.fromRGB(65,75,95), FogEnd=80, Brightness=0.75, Density=0.38, Rain=360, Wind=Vector3.new(12,-4,5), Water=Color3.fromRGB(38,78,125)},
}
function AtmosphereHandler:_ensureSurfaceVFX()
    if self._weatherContainer then return end
    local sky=Lighting:FindFirstChild("SurfaceSky") or Instance.new("Sky"); sky.Name="SurfaceSky"; sky.SkyboxBk="rbxasset://sky/sky512_bk.tex"; sky.SkyboxDn="rbxasset://sky/sky512_dn.tex"; sky.SkyboxFt="rbxasset://sky/sky512_ft.tex"; sky.SkyboxLf="rbxasset://sky/sky512_lf.tex"; sky.SkyboxRt="rbxasset://sky/sky512_rt.tex"; sky.SkyboxUp="rbxasset://sky/sky512_up.tex"; sky.Parent=Lighting
    local anchor=Instance.new("Part"); anchor.Name="SurfaceWeatherVFX"; anchor.Size=Vector3.new(180,70,180); anchor.Position=Vector3.new(0,35,0); anchor.Transparency=1; anchor.Anchored=true; anchor.CanCollide=false; anchor.Parent=workspace
    local rain=Instance.new("ParticleEmitter"); rain.Name="RainStreaks"; rain.Texture="rbxasset://textures/particles/ rain_main.dds"; rain.Lifetime=NumberRange.new(.6,1.1); rain.Speed=NumberRange.new(55,75); rain.Size=NumberSequence.new(.08); rain.Transparency=NumberSequence.new(.35); rain.SpreadAngle=Vector2.new(4,4); rain.Parent=anchor
    local splash=Instance.new("ParticleEmitter"); splash.Name="SurfaceSplashes"; splash.Texture="rbxasset://textures/particles/sparkles_main.dds"; splash.Lifetime=NumberRange.new(.15,.35); splash.Speed=NumberRange.new(2,6); splash.Rate=0; splash.Size=NumberSequence.new(.15); splash.Parent=anchor
    self._weatherContainer=anchor; self._rainEmitter=rain; self._splashEmitter=splash
    for i=1,18 do local p=Instance.new("Part"); p.Name="StormWhitecap"; p.Size=Vector3.new(4,.12,1); p.Position=Vector3.new(math.random(-80,80),.8,math.random(-80,80)); p.Anchored=true; p.CanCollide=false; p.Material=Enum.Material.Neon; p.Color=Color3.fromRGB(220,240,255); p.Transparency=1; p.Parent=anchor; table.insert(self._whitecaps,p) end
end
function AtmosphereHandler:_tweenSurfaceLighting(preset, duration)
    local info=TweenInfo.new(duration or 4,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut)
    local atmosphere=Lighting:FindFirstChild("Atmosphere")
    if self._weatherTween then self._weatherTween:Cancel() end
    self._weatherTween=TweenService:Create(Lighting,info,{Ambient=preset.Ambient,OutdoorAmbient=preset.Outdoor,FogColor=preset.Fog,FogEnd=preset.FogEnd,Brightness=preset.Brightness})
    self._weatherTween:Play()
    if atmosphere then TweenService:Create(atmosphere,info,{Density=preset.Density,Color=preset.Fog,Decay=preset.Fog}):Play() end
end
function AtmosphereHandler:_updateSurfaceWeather(deltaTime)
    local p=SURFACE_WEATHER[self._weatherState] or SURFACE_WEATHER.Calm
    if self._rainEmitter then self._rainEmitter.Rate=p.Rain; self._rainEmitter.Acceleration=p.Wind; self._rainEmitter.Enabled=p.Rain>0 end
    for _,cap in ipairs(self._whitecaps) do cap.Transparency=(self._weatherState=="Storm") and .15 or 1; cap.Position=cap.Position+Vector3.new(p.Wind.X,0,p.Wind.Z)*deltaTime*.08 end
end
function AtmosphereHandler:TransitionToSurface()
    self._surfaceMode=true; self._outpostMode=false; self._isUnderwater=false; self:_ensureSurfaceVFX(); self:SetWeather(self._weatherState); self:_destroyGodRays(); self:_destroyCausticLights()
end
function AtmosphereHandler:TransitionToOutpost()
    self:TransitionToSurface(); self._outpostMode=true
    self:_tweenSurfaceLighting({Ambient=Color3.fromRGB(155,125,100),Outdoor=Color3.fromRGB(215,180,130),Fog=Color3.fromRGB(205,180,145),FogEnd=220,Brightness=2.4,Density=.08},4)
    Lighting.ClockTime=17.5
end
function AtmosphereHandler:SetWeather(weatherState)
    if not SURFACE_WEATHER[weatherState] then return false end
    self._weatherState=weatherState; self:_ensureSurfaceVFX(); self:_tweenSurfaceLighting(SURFACE_WEATHER[weatherState],4); return true
end
function AtmosphereHandler:PlayLightningStrike()
    if self._weatherState~="Storm" then return end
    local cc=Lighting:FindFirstChild("ColorCorrection"); local old=cc and cc.TintColor
    if cc then cc.TintColor=Color3.new(1,1,1); cc.Brightness=.8; task.delay(.12,function() if cc then cc.TintColor=old or Color3.new(1,1,1); cc.Brightness=0 end end) end
    task.delay(.75,function() self._lastThunderAt=os.clock() end) -- audio hook for AudioController
end
-- Called when player breaches surface
function AtmosphereHandler:OnSurfaceBreach()
    self._isUnderwater = false
    self:TransitionToSurface()
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
    self._surfaceMode = false
    self._outpostMode = false
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

    if self._weatherContainer then self._weatherContainer:Destroy(); self._weatherContainer=nil end
    self._rainEmitter=nil; self._splashEmitter=nil; self._whitecaps={}
    -- Clean rare spawn anchors
    for _, anchor in ipairs(self._rareSpawnVFX) do
        if anchor then anchor:Destroy() end
    end
    self._rareSpawnVFX = {}

    print("[AtmosphereHandler] Atmosphere system destroyed.")
end

return AtmosphereHandler
