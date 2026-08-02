--[[
    master-setup.lua
    Deep Tide Studios — Master Place Setup Script
    Combines place/setup.lua (terrain + structures) and place/atmosphere-setup.lua
    (lighting + VFX) into a single script. Run this in Roblox Studio Command Bar
    after syncing with Rojo.

    Usage: Paste into Command Bar in Studio and run.
    Order: Terrain/Structures → Lighting/VFX → Verification
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("========================================")
print(" Deep Tide — Master Place Setup")
print("========================================")
print("")

-- ============================================================
-- PART 1: TERRAIN & STRUCTURES
-- (from place/setup.lua — creates water, seafloor, coral, shipwreck, spawn)
-- ============================================================
print("[Setup] Part 1/3: Creating terrain and structures...")

-- 1a. Lighting (basic pre-config — will be refined in Part 2)
Lighting.ClockTime = 10
Lighting.Brightness = 1.5
Lighting.GlobalShadows = true
Lighting.EnvironmentSpecularScale = 0.5

-- 1b. Water plane
local existingWater = Workspace:FindFirstChild("WaterSurface")
if not existingWater then
    local waterPart = Instance.new("Part")
    waterPart.Name = "WaterSurface"
    waterPart.Size = Vector3.new(400, 1, 400)
    waterPart.Position = Vector3.new(0, 0.5, 0)
    waterPart.Anchored = true
    waterPart.CanCollide = false
    waterPart.Transparency = 0.6
    waterPart.Color = Color3.fromRGB(64, 180, 220)
    waterPart.Material = Enum.Material.Glass
    waterPart.Parent = Workspace
    print("[Setup]   ✓ Water surface created")
else
    print("[Setup]   Water surface already exists — skipping")
end

-- 1c. Sea floor
local existingFloor = Workspace:FindFirstChild("SeaFloor")
if not existingFloor then
    local floorPart = Instance.new("Part")
    floorPart.Name = "SeaFloor"
    floorPart.Size = Vector3.new(400, 2, 400)
    floorPart.Position = Vector3.new(0, -51, 0)
    floorPart.Anchored = true
    floorPart.CanCollide = true
    floorPart.Color = Color3.fromRGB(210, 190, 150)
    floorPart.Material = Enum.Material.Sand
    floorPart.Parent = Workspace
end
print("[Setup]   ✓ Sea floor ready")

-- 1d. Player spawn
local existingSpawn = Workspace:FindFirstChild("BoatSpawn")
if not existingSpawn then
    local spawnPart = Instance.new("Part")
    spawnPart.Name = "PlayerSpawn"
    spawnPart.Size = Vector3.new(8, 2, 8)
    spawnPart.Position = Vector3.new(0, 1, 0)
    spawnPart.Anchored = true
    spawnPart.CanCollide = true
    spawnPart.Color = Color3.fromRGB(139, 90, 43)
    spawnPart.Material = Enum.Material.WoodPlanks
    spawnPart.Parent = Workspace

    local spawnLocation = Instance.new("SpawnLocation")
    spawnLocation.Name = "BoatSpawn"
    spawnLocation.Size = Vector3.new(6, 1, 6)
    spawnLocation.Position = Vector3.new(0, 2.5, 0)
    spawnLocation.Anchored = true
    spawnLocation.CanCollide = false
    spawnLocation.Transparency = 0.7
    spawnLocation.Color = Color3.fromRGB(255, 255, 0)
    spawnLocation.Parent = Workspace

    Players.RespawnTime = 0
    Players.CharacterAutoLoads = true
    print("[Setup]   ✓ Spawn created")
else
    print("[Setup]   Spawn already exists — skipping")
end

-- 1e. Coral structures (Coral Gardens at Y=-10)
local coralCount = 0
for _, obj in ipairs(Workspace:GetChildren()) do
    if obj.Name == "Coral" then coralCount = coralCount + 1 end
end
if coralCount < 5 then
    local function createCoral(position, size, color)
        local coral = Instance.new("Part")
        coral.Name = "Coral"
        coral.Size = size
        coral.Position = position
        coral.Anchored = true
        coral.CanCollide = true
        coral.Color = color
        coral.Material = Enum.Material.Plastic
        local mesh = Instance.new("BlockMesh")
        mesh.Scale = Vector3.new(1, 1, 1)
        mesh.Parent = coral
        coral.Parent = Workspace
        return coral
    end

    local coralColors = {
        Color3.fromRGB(255, 100, 100), Color3.fromRGB(255, 150, 50),
        Color3.fromRGB(255, 100, 200), Color3.fromRGB(100, 50, 200),
        Color3.fromRGB(50, 200, 150),
    }
    local basePos = Vector3.new(0, -10, 0)
    for i = 1, 15 do
        local angle = (i / 15) * math.pi * 2
        local radius = 15 + math.random() * 10
        createCoral(
            Vector3.new(math.cos(angle) * radius, basePos.Y + math.random() * 3 - 1.5, math.sin(angle) * radius),
            Vector3.new(2 + math.random(), 3 + math.random() * 5, 2 + math.random()),
            coralColors[math.random(1, #coralColors)]
        )
    end
    print("[Setup]   ✓ Coral Gardens created (15 structures)")
else
    print("[Setup]   Coral already exists — skipping (" .. coralCount .. " found)")
end

-- 1f. Shipwreck
local shipHull = Workspace:FindFirstChild("ShipHullBottom")
if not shipHull then
    local function createShipPart(name, size, position, color)
        local part = Instance.new("Part")
        part.Name = name
        part.Size = size
        part.Position = position
        part.Anchored = true
        part.CanCollide = true
        part.Color = color
        part.Material = Enum.Material.WoodPlanks
        part.Parent = Workspace
        return part
    end
    local shipPos = Vector3.new(15, -37, -8)
    createShipPart("ShipHullBottom", Vector3.new(8, 3, 24), shipPos, Color3.fromRGB(80, 50, 30))
    createShipPart("ShipHullTop", Vector3.new(8, 3, 20), shipPos + Vector3.new(0, 3, 0), Color3.fromRGB(70, 45, 25))
    createShipPart("ShipBow", Vector3.new(4, 3, 6), shipPos + Vector3.new(0, 0, 15), Color3.fromRGB(60, 35, 20))
    print("[Setup]   ✓ Shipwreck created")
else
    print("[Setup]   Shipwreck already exists — skipping")
end

-- 1g. Zone boundary markers
local boundaryMarkers = 0
for _, obj in ipairs(Workspace:GetChildren()) do
    if obj.Name == "BoundaryMarker" then boundaryMarkers = boundaryMarkers + 1 end
end
if boundaryMarkers < 4 then
    local boundaryPos = Vector3.new(-20, -47, -25)
    for i = 1, 8 do
        local angle = (i / 8) * math.pi * 2
        local x = boundaryPos.X + math.cos(angle) * 12
        local z = boundaryPos.Z + math.sin(angle) * 12
        local marker = Instance.new("Part")
        marker.Name = "BoundaryMarker"
        marker.Size = Vector3.new(1, 3, 1)
        marker.Position = Vector3.new(x, boundaryPos.Y, z)
        marker.Anchored = true
        marker.CanCollide = false
        marker.Color = Color3.fromRGB(255, 50, 50)
        marker.Material = Enum.Material.Neon
        marker.Parent = Workspace
    end
    print("[Setup]   ✓ Zone boundary created")
end

print("[Setup] Part 1/3 complete.")
print("")

-- ============================================================
-- PART 2: ATMOSPHERE & VFX (from place/atmosphere-setup.lua)
-- Configures lighting, fog, god rays, caustics, landmark lights,
-- bioluminescent particles, marine snow, and plankton.
-- ============================================================
print("[Setup] Part 2/3: Configuring atmosphere and VFX...")

-- 2a. Base lighting
Lighting.ClockTime = 10
Lighting.Brightness = 1.2
Lighting.EnvironmentSpecularScale = 0.3
Lighting.EnvironmentDiffuseScale = 0.8
Lighting.Ambient = Color3.fromRGB(30, 60, 120)
Lighting.OutdoorAmbient = Color3.fromRGB(40, 80, 140)
Lighting.FogColor = Color3.fromRGB(64, 180, 200)
Lighting.FogStart = 20
Lighting.FogEnd = 65
print("[Atmosphere]   ✓ Base lighting configured")

-- 2b. Atmosphere
local existingAtmo = Lighting:FindFirstChild("Atmosphere")
if existingAtmo then existingAtmo:Destroy() end
local atmosphere = Instance.new("Atmosphere")
atmosphere.Name = "Atmosphere"
atmosphere.Density = 0.35
atmosphere.Offset = 0.15
atmosphere.Color = Color3.fromRGB(40, 130, 180)
atmosphere.Decay = Color3.fromRGB(20, 50, 100)
atmosphere.Glare = 0.05
atmosphere.Haze = 0.8
atmosphere.Parent = Lighting
print("[Atmosphere]   ✓ Volumetric atmosphere configured")

-- 2c. Post-processing
local existingBloom = Lighting:FindFirstChild("Bloom")
if existingBloom then existingBloom:Destroy() end
local bloom = Instance.new("Bloom")
bloom.Name = "Bloom"
bloom.Intensity = 0.4
bloom.Threshold = 0.75
bloom.Size = 24
bloom.Parent = Lighting

local existingCC = Lighting:FindFirstChild("ColorCorrection")
if existingCC then existingCC:Destroy() end
local colorCorrection = Instance.new("ColorCorrection")
colorCorrection.Name = "ColorCorrection"
colorCorrection.TintColor = Color3.fromRGB(180, 220, 255)
colorCorrection.Saturation = -0.08
colorCorrection.Contrast = 0.05
colorCorrection.Parent = Lighting

local existingDOF = Lighting:FindFirstChild("DepthOfField")
if existingDOF then existingDOF:Destroy() end
local dof = Instance.new("DepthOfField")
dof.Name = "DepthOfField"
dof.FarIntensity = 0.15
dof.FocusDistance = 25
dof.InFocusRadius = 40
dof.NearIntensity = 0.0
dof.Enabled = true
dof.Parent = Lighting

local existingSR = Lighting:FindFirstChild("SunRays")
if existingSR then existingSR:Destroy() end
local sunRays = Instance.new("SunRays")
sunRays.Name = "SunRays"
sunRays.Intensity = 0.25
sunRays.Spread = 0.4
sunRays.Parent = Lighting
print("[Atmosphere]   ✓ Post-processing configured")

-- 2d. God rays
local function createGodRay(index, offsetX, offsetZ)
    local surfaceY, maxDepth = 0, 55
    local origin = Vector3.new(offsetX, surfaceY, offsetZ)
    local target = Vector3.new(offsetX + math.random() * 4 - 2, -maxDepth, offsetZ + math.random() * 4 - 2)
    local rayOriginPart = Instance.new("Part")
    rayOriginPart.Name = "GodRayOrigin_" .. index
    rayOriginPart.Size = Vector3.new(0.1, 0.1, 0.1)
    rayOriginPart.Position = origin
    rayOriginPart.Transparency = 1
    rayOriginPart.Anchored = true
    rayOriginPart.CanCollide = false
    rayOriginPart.Parent = Workspace
    local rayTargetPart = Instance.new("Part")
    rayTargetPart.Name = "GodRayTarget_" .. index
    rayTargetPart.Size = Vector3.new(0.1, 0.1, 0.1)
    rayTargetPart.Position = target
    rayTargetPart.Transparency = 1
    rayTargetPart.Anchored = true
    rayTargetPart.CanCollide = false
    rayTargetPart.Parent = Workspace
    local attach0 = Instance.new("Attachment"); attach0.Parent = rayOriginPart
    local attach1 = Instance.new("Attachment"); attach1.Parent = rayTargetPart
    local beam = Instance.new("Beam")
    beam.Name = "GodRayBeam_" .. index
    beam.Attachment0 = attach0; beam.Attachment1 = attach1
    beam.Color = ColorSequence.new(Color3.fromRGB(180, 220, 255))
    beam.LightEmission = 0.3; beam.LightInfluence = 0.2
    beam.Width0 = 0.5 + math.random() * 1.5; beam.Width1 = 0.3 + math.random() * 1.0
    beam.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(0.3, 0.7),
        NumberSequenceKeypoint.new(0.7, 0.8), NumberSequenceKeypoint.new(1, 0.95),
    }
    beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    beam.TextureSpeed = 0.02; beam.TextureLength = 1; beam.FaceCamera = false
    beam.Parent = rayOriginPart
end

-- Only create god rays if they don't exist
local godRayCount = 0
for _, obj in ipairs(Workspace:GetChildren()) do
    if obj.Name:find("GodRayOrigin_") then godRayCount = godRayCount + 1 end
end
if godRayCount == 0 then
    for i = 1, 8 do
        createGodRay(i, (i - 4) * 18 + math.random() * 8, (i - 4) * 12 + math.random() * 6)
    end
    print("[Atmosphere]   ✓ 8 god rays created")
else
    print("[Atmosphere]   God rays already exist — skipping")
end

-- 2e. Caustic lights
local causticFound = 0
for _, obj in ipairs(Workspace:GetChildren()) do
    if obj.Name:find("CausticAnchor_") then causticFound = causticFound + 1 end
end
if causticFound == 0 then
    for i = 1, 6 do
        local anchor = Instance.new("Part")
        anchor.Name = "CausticAnchor_" .. i
        anchor.Size = Vector3.new(0.2, 0.2, 0.2)
        anchor.Position = Vector3.new((i - 3) * 25 + math.random() * 10, -3 - math.random() * 8, math.random() * 40 - 20)
        anchor.Transparency = 1; anchor.Anchored = true; anchor.CanCollide = false
        anchor.Parent = Workspace
        local light = Instance.new("PointLight")
        light.Name = "CausticLight_" .. i
        light.Brightness = 0.3 + math.random() * 0.4; light.Range = 8 + math.random() * 6
        light.Color = Color3.fromRGB(140, 210, 240); light.Shadows = false; light.Enabled = true
        light.Parent = anchor
    end
    print("[Atmosphere]   ✓ 6 caustic lights created")
else
    print("[Atmosphere]   Caustic lights already exist — skipping")
end

-- 2f. Landmark lights and bioluminescent particles
local LANDMARK_PRESETS = {
    CoralGardens = {
        Center = Vector3.new(0, -10, 0), Radius = 40,
        Color1 = Color3.fromRGB(255, 170, 60), Color2 = Color3.fromRGB(255, 120, 200),
        GlowRange = 18, GlowBrightness = 0.6,
        ParticleColor = Color3.fromRGB(100, 220, 255), ParticleCount = 6, LightCount = 5,
    },
    Shipwreck = {
        Center = Vector3.new(10, -37, -8), Radius = 25,
        Color1 = Color3.fromRGB(140, 200, 255), Color2 = Color3.fromRGB(80, 255, 180),
        GlowRange = 14, GlowBrightness = 0.5,
        ParticleColor = Color3.fromRGB(60, 255, 140), ParticleCount = 4, LightCount = 4,
    },
    DeepReefEdge = {
        Center = Vector3.new(-20, -47, -25), Radius = 30,
        Color1 = Color3.fromRGB(160, 60, 220), Color2 = Color3.fromRGB(40, 20, 100),
        GlowRange = 10, GlowBrightness = 0.3,
        ParticleColor = Color3.fromRGB(180, 80, 255), ParticleCount = 4, LightCount = 3,
    },
}

local landmarkLightsFound = 0
for _, obj in ipairs(Workspace:GetChildren()) do
    if obj.Name:find("_LightAnchor_") then landmarkLightsFound = landmarkLightsFound + 1 end
end
if landmarkLightsFound == 0 then
    for presetName, preset in pairs(LANDMARK_PRESETS) do
        -- Point lights
        for i = 1, preset.LightCount do
            local angle = (i / preset.LightCount) * math.pi * 2 + math.random() * 0.5
            local radius = preset.Radius * (0.3 + math.random() * 0.7)
            local x = preset.Center.X + math.cos(angle) * radius
            local z = preset.Center.Z + math.sin(angle) * radius
            local y = preset.Center.Y + math.random() * 4 - 2
            local anchor = Instance.new("Part")
            anchor.Name = presetName .. "_LightAnchor_" .. i
            anchor.Size = Vector3.new(0.2, 0.2, 0.2)
            anchor.Position = Vector3.new(x, y, z)
            anchor.Transparency = 1; anchor.Anchored = true; anchor.CanCollide = false
            anchor.Parent = Workspace
            local light = Instance.new("PointLight")
            light.Name = presetName .. "_AccentLight_" .. i
            light.Brightness = preset.GlowBrightness * (0.6 + math.random() * 0.4)
            light.Range = preset.GlowRange * (0.7 + math.random() * 0.3)
            light.Color = (i % 2 == 0) and preset.Color1 or preset.Color2
            light.Shadows = false; light.Enabled = true
            light.Parent = anchor
        end
        -- Particles
        for i = 1, preset.ParticleCount do
            local angle = (i / preset.ParticleCount) * math.pi * 2
            local radius = preset.Radius * (0.4 + math.random() * 0.5)
            local x = preset.Center.X + math.cos(angle) * radius
            local z = preset.Center.Z + math.sin(angle) * radius
            local y = preset.Center.Y + math.random() * 5 - 2
            local anchor = Instance.new("Part")
            anchor.Name = presetName .. "_ParticleAnchor_" .. i
            anchor.Size = Vector3.new(0.2, 0.2, 0.2)
            anchor.Position = Vector3.new(x, y, z)
            anchor.Transparency = 1; anchor.Anchored = true; anchor.CanCollide = false
            anchor.Parent = Workspace
            local emitter = Instance.new("ParticleEmitter")
            emitter.Name = "BioluminescentEmitter_" .. i
            emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
            emitter.Rate = 5 + math.random() * 8
            emitter.Lifetime = NumberRange.new(1.5, 4)
            emitter.Speed = NumberRange.new(0.5, 2)
            emitter.Size = NumberSequence.new{
                NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 0.05),
            }
            emitter.Transparency = NumberSequence.new{
                NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.5, 0.0), NumberSequenceKeypoint.new(1, 1),
            }
            emitter.Color = ColorSequence.new(preset.ParticleColor)
            emitter.SpreadAngle = Vector2.new(15, 30)
            emitter.Acceleration = Vector3.new(0, 0.5, 0); emitter.Drag = 0.3
            emitter.LockedToPart = true; emitter.Enabled = true
            emitter.Parent = anchor
        end
    end
    print("[Atmosphere]   ✓ Landmark lights and bioluminescent VFX created")
else
    print("[Atmosphere]   Landmark VFX already exists — skipping")
end

-- 2g. Marine snow
local snowContainer = Workspace:FindFirstChild("MarineSnowContainer")
if not snowContainer then
    snowContainer = Instance.new("Part")
    snowContainer.Name = "MarineSnowContainer"
    snowContainer.Size = Vector3.new(120, 55, 120)
    snowContainer.Position = Vector3.new(0, -25, 0)
    snowContainer.Transparency = 1; snowContainer.Anchored = true; snowContainer.CanCollide = false
    snowContainer.Parent = Workspace
    local snowEmitter = Instance.new("ParticleEmitter")
    snowEmitter.Name = "MarineSnowEmitter"
    snowEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    snowEmitter.Rate = 80; snowEmitter.Lifetime = NumberRange.new(4, 12)
    snowEmitter.Speed = NumberRange.new(0.3, 1.5)
    snowEmitter.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.03), NumberSequenceKeypoint.new(0.5, 0.06), NumberSequenceKeypoint.new(1, 0.02),
    }
    snowEmitter.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.5, 0.4), NumberSequenceKeypoint.new(1, 0.85),
    }
    snowEmitter.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
    snowEmitter.SpreadAngle = Vector2.new(0, 0)
    snowEmitter.Acceleration = Vector3.new(0, 0.1, 0); snowEmitter.Drag = 0.5
    snowEmitter.VelocityInheritance = 0.1; snowEmitter.LockedToPart = true; snowEmitter.Enabled = true
    snowEmitter.Parent = snowContainer
    print("[Atmosphere]   ✓ Marine snow created")
else
    print("[Atmosphere]   Marine snow already exists — skipping")
end

-- 2h. Plankton fields
local planktonFound = 0
for _, obj in ipairs(Workspace:GetChildren()) do
    if obj.Name:find("PlanktonField_") then planktonFound = planktonFound + 1 end
end
if planktonFound == 0 then
    local planktonPositions = {
        Vector3.new(-15, -12, 15), Vector3.new(20, -8, -10), Vector3.new(35, -20, 25),
        Vector3.new(10, -25, 30), Vector3.new(5, -40, -5), Vector3.new(20, -38, -15),
        Vector3.new(-15, -48, -20), Vector3.new(-28, -46, -30),
    }
    for i, pos in ipairs(planktonPositions) do
        local anchor = Instance.new("Part")
        anchor.Name = "PlanktonField_" .. i
        anchor.Size = Vector3.new(30, 15, 30); anchor.Position = pos
        anchor.Transparency = 1; anchor.Anchored = true; anchor.CanCollide = false
        anchor.Parent = Workspace
        local emitter = Instance.new("ParticleEmitter")
        emitter.Name = "PlanktonEmitter"
        emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        emitter.Rate = 3 + math.random() * 4; emitter.Lifetime = NumberRange.new(3, 8)
        emitter.Speed = NumberRange.new(0.2, 0.8)
        emitter.Size = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.04), NumberSequenceKeypoint.new(0.5, 0.12), NumberSequenceKeypoint.new(1, 0.02),
        }
        emitter.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.3, 0.1),
            NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1),
        }
        local hue = 0.5 + math.random() * 0.2
        emitter.Color = ColorSequence.new(Color3.fromHSV(hue, 0.6, 0.9))
        emitter.SpreadAngle = Vector2.new(0, 360)
        emitter.Acceleration = Vector3.new(0, 0.3, 0); emitter.Drag = 0.2
        emitter.LockedToPart = true; emitter.Enabled = true
        emitter.Parent = anchor
    end
    print("[Atmosphere]   ✓ 8 plankton fields created")
else
    print("[Atmosphere]   Plankton already exists — skipping")
end

print("[Setup] Part 2/3 complete.")
print("")

-- ============================================================
-- PART 3: KELP FOREST ZONE SETUP (Phase 2)
-- Kelp strand assemblies, Rocky Grotto structures, Abyss Edge,
-- air pocket bubbles, current particles, bioluminescent plankton
-- ============================================================
print("[Setup] Part 3/4: Setting up Kelp Forest zone (Phase 2)...")

-- 3a. Create kelp strands (run kelp-forest-setup inline)
print("[KelpForest] Creating kelp strand assemblies...")

local function createKelpStrand(basePos, height, color, swaySpeed, swayPhase)
    local base = Instance.new("Part")
    base.Name = "KelpBase"
    base.Size = Vector3.new(0.4, 0.4, 0.4)
    base.Position = basePos
    base.Anchored = true
    base.CanCollide = false
    base.Transparency = 0.8
    base.Color = color
    base.Material = Enum.Material.Grass
    base.Parent = Workspace

    local top = Instance.new("Part")
    top.Name = "KelpTop"
    top.Size = Vector3.new(0.15, 0.15, 0.15)
    top.Position = basePos + Vector3.new(0, height, 0)
    top.Anchored = true
    top.CanCollide = false
    top.Transparency = 1
    top.Parent = Workspace

    local attachBase = Instance.new("Attachment"); attachBase.Name = "KelpBaseAttach"; attachBase.Parent = base
    local attachTop = Instance.new("Attachment"); attachTop.Name = "KelpTopAttach"; attachTop.Parent = top

    local beam = Instance.new("Beam")
    beam.Name = "KelpBeam"; beam.Attachment0 = attachBase; beam.Attachment1 = attachTop
    beam.Color = ColorSequence.new(color)
    beam.Width0 = 0.3 + math.random() * 0.3; beam.Width1 = 0.08 + math.random() * 0.1
    beam.Transparency = NumberSequence.new(0.25)
    beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    beam.TextureSpeed = 0.005 + math.random() * 0.01; beam.TextureLength = 1
    beam.CurveSize0 = 1.5 + math.random() * 2; beam.CurveSize1 = -(1 + math.random() * 2)
    beam.FaceCamera = true; beam.Parent = base

    -- Sway animation
    RunService.Heartbeat:Connect(function()
        if not top or not top.Parent then return end
        local swayX = math.sin(tick() * swaySpeed + swayPhase) * 1.2
        local swayZ = math.cos(tick() * (swaySpeed * 0.8) + swayPhase + 1) * 1.2
        top.Position = Vector3.new(basePos.X + swayX, basePos.Y + height, basePos.Z + swayZ)
    end)
    return { Base = base, Top = top, Beam = beam, BasePosition = basePos }
end

local kelpColors = {
    Color3.fromRGB(20, 80, 30), Color3.fromRGB(15, 70, 25), Color3.fromRGB(25, 90, 35),
    Color3.fromRGB(30, 60, 20), Color3.fromRGB(18, 75, 28), Color3.fromRGB(40, 50, 25),
}

-- Kelp Canopy strands (Y=-50 to -75, center 0,-62,0, radius 80)
local canopyKelpCount = 0
for _, obj in ipairs(Workspace:GetChildren()) do
    if obj.Name == "KelpBase" then canopyKelpCount = canopyKelpCount + 1 end
end
if canopyKelpCount < 30 then
    local canopyCenter = Vector3.new(0, -62, 0)
    local canopyRadius = 80
    local placed = 0
    for _ = 1, 45 do
        local angle = math.random() * math.pi * 2
        local r = math.random() * canopyRadius * 0.85
        local x = canopyCenter.X + math.cos(angle) * r
        local z = canopyCenter.Z + math.sin(angle) * r
        local y = -50 - math.random() * 25
        if math.random() < 0.7 then
            createKelpStrand(Vector3.new(x, y, z), 50 + math.random() * 50, kelpColors[math.random(1, #kelpColors)], 0.7 + math.random() * 0.6, math.random() * math.pi * 2)
            placed = placed + 1
        end
    end
    print("[KelpForest]   ✓ " .. placed .. " kelp canopy strands created")
else
    print("[KelpForest]   Kelp strands already exist — skipping (" .. canopyKelpCount .. " found)")
end

-- 3b. Rocky Grotto rocks & caves (Y=-100 to -130, center -15,-115,-10, radius 45)
local grottoRockCount = 0
for _, obj in ipairs(Workspace:GetChildren()) do
    if obj.Name:find("GrottoRock_") then grottoRockCount = grottoRockCount + 1 end
end
if grottoRockCount < 6 then
    local grottoCenter = Vector3.new(-15, -115, -10)
    local grottoRadius = 45
    for i = 1, 10 do
        local angle = (i / 10) * math.pi * 2 + math.random() * 0.3
        local r = math.random() * grottoRadius * 0.7
        local rock = Instance.new("Part")
        rock.Name = "GrottoRock_" .. i
        rock.Size = Vector3.new(6 + math.random() * 10, 4 + math.random() * 8, 6 + math.random() * 10)
        rock.Position = Vector3.new(grottoCenter.X + math.cos(angle) * r, grottoCenter.Y + math.random() * 15 - 7, grottoCenter.Z + math.sin(angle) * r)
        rock.Anchored = true; rock.CanCollide = true
        rock.Color = Color3.fromRGB(25 + math.random() * 20, 20 + math.random() * 15, 30 + math.random() * 15)
        rock.Material = Enum.Material.Basalt
        rock.Parent = Workspace
    end
    print("[KelpForest]   ✓ Rocky Grotto created (10 rocks)")
else
    print("[KelpForest]   Rocky Grotto already exists — skipping")
end

-- 3c. Abyss Edge void boundary (Y=-130 to -150)
local abyssWall = Workspace:FindFirstChild("AbyssVoidWall")
if not abyssWall then
    local abyssCenter = Vector3.new(-30, -140, -35)
    local abyssRadius = 40
    local voidWall = Instance.new("Part")
    voidWall.Name = "AbyssVoidWall"
    voidWall.Size = Vector3.new(120, 30, 2)
    voidWall.Position = abyssCenter + Vector3.new(0, 0, -abyssRadius * 0.8)
    voidWall.Anchored = true; voidWall.CanCollide = true
    voidWall.Transparency = 0.9; voidWall.Color = Color3.fromRGB(2, 0, 8)
    voidWall.Material = Enum.Material.Glass
    voidWall.Parent = Workspace
    print("[KelpForest]   ✓ Abyss Edge void boundary created")
else
    print("[KelpForest]   Abyss Edge already exists — skipping")
end

-- 3d. Air pocket bubble VFX (2 grotto cave locations)
local airPocketPositions = {
    Vector3.new(-20, -108, -5),
    Vector3.new(-8, -112, -18),
}
for i, pos in ipairs(airPocketPositions) do
    local anchorName = "AirPocketVFX_" .. i
    if not Workspace:FindFirstChild(anchorName) then
        local anchor = Instance.new("Part")
        anchor.Name = anchorName; anchor.Size = Vector3.new(6, 3, 6)
        anchor.Position = pos; anchor.Transparency = 1
        anchor.Anchored = true; anchor.CanCollide = false; anchor.Parent = Workspace
        local emitter = Instance.new("ParticleEmitter")
        emitter.Name = "AirPocketBubbles"; emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        emitter.Rate = 25; emitter.Lifetime = NumberRange.new(1, 3); emitter.Speed = NumberRange.new(0.5, 2)
        emitter.Size = NumberSequence.new{ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 0.3) }
        emitter.Transparency = NumberSequence.new{ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 0.7) }
        emitter.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
        emitter.SpreadAngle = Vector2.new(5, 10); emitter.Acceleration = Vector3.new(0, 3, 0)
        emitter.Drag = 0.3; emitter.LockedToPart = true; emitter.Enabled = true; emitter.Parent = anchor
    end
end
print("[KelpForest]   ✓ Air pocket bubble columns created")

-- 3e. Bioluminescent plankton for Kelp Forest (brighter, more dense)
local kelpPlanktonCount = 0
for _, obj in ipairs(Workspace:GetChildren()) do
    if obj.Name:find("KelpPlankton_") then kelpPlanktonCount = kelpPlanktonCount + 1 end
end
if kelpPlanktonCount < 4 then
    local kelpPlanktonPos = {
        Vector3.new(-20, -60, -15), Vector3.new(15, -55, 10), Vector3.new(-10, -55, 20),
        Vector3.new(5, -70, -15), Vector3.new(25, -85, 15), Vector3.new(35, -90, 5),
    }
    for i, pos in ipairs(kelpPlanktonPos) do
        local anchor = Instance.new("Part")
        anchor.Name = "KelpPlankton_" .. i; anchor.Size = Vector3.new(25, 12, 25)
        anchor.Position = pos; anchor.Transparency = 1
        anchor.Anchored = true; anchor.CanCollide = false; anchor.Parent = Workspace
        local emitter = Instance.new("ParticleEmitter")
        emitter.Name = "KelpPlanktonEmitter"; emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        emitter.Rate = 8 + math.random() * 6; emitter.Lifetime = NumberRange.new(2, 6); emitter.Speed = NumberRange.new(0.1, 0.6)
        emitter.Size = NumberSequence.new{ NumberSequenceKeypoint.new(0, 0.03), NumberSequenceKeypoint.new(0.5, 0.15), NumberSequenceKeypoint.new(1, 0.02) }
        emitter.Transparency = NumberSequence.new{ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(0.3, 0.05), NumberSequenceKeypoint.new(0.7, 0.15), NumberSequenceKeypoint.new(1, 1) }
        local hue = 0.45 + math.random() * 0.15
        emitter.Color = ColorSequence.new(Color3.fromHSV(hue, 0.7, 0.95))
        emitter.SpreadAngle = Vector2.new(0, 360); emitter.Acceleration = Vector3.new(0, 0.2, 0)
        emitter.Drag = 0.3; emitter.LockedToPart = true; emitter.Enabled = true; emitter.Parent = anchor
    end
    print("[KelpForest]   ✓ " .. #kelpPlanktonPos .. " Kelp Forest plankton fields created")
end

print("[Setup] Part 3/4 complete.")
print("")

-- ============================================================
-- PART 5: OUTPOST HUB (Phase 3)
-- Requires outpost-setup.lua to be executed in the Studio command bar context.
print("[Setup] Part 5/5: Creating Outpost hub...")
local outpostSetup = Workspace:FindFirstChild("Outpost")
if not outpostSetup then
    warn("[Setup] Outpost model not found. Run place/outpost-setup.lua after this setup.")
else
    print("[Setup]   ✓ Outpost hub already present")
end

-- PART 4: VERIFICATION
-- ============================================================
print("[Setup] Part 4/4: Verifying project structure...")

-- Check Rojo-synced modules
local sharedOk = pcall(function()
    local Shared = require(ReplicatedStorage:WaitForChild("Shared"))
    assert(Shared.Constants.FishSpecies, "FishSpecies missing")
    assert(Shared.Constants.RodTiers, "RodTiers missing")
    assert(Shared.Constants.ZoneConfigs, "ZoneConfigs missing")
    assert(Shared.NPC.FishSignals, "FishSignals missing")
end)

local knitOk = pcall(function()
    local Knit = require(ReplicatedStorage:WaitForChild("Knit"))
    assert(Knit.CreateService, "CreateService missing")
    assert(Knit.GetSignal, "GetSignal missing")
end)

if sharedOk and knitOk then
    print("[Setup]   ✓ Shared + Knit modules verified")
else
    warn("[Setup]   ✗ Module verification failed — is Rojo synced?")
end

-- Check NPC & service modules
local serverOk = pcall(function()
    local ServerScriptService = game:GetService("ServerScriptService")
    local npc = ServerScriptService.Server.NPC
    assert(npc:FindFirstChild("FishNPC"), "FishNPC missing")
    assert(npc:FindFirstChild("FishSpawner"), "FishSpawner missing")
    local svc = ServerScriptService.Server.Services
    assert(svc:FindFirstChild("PlayerDataService"), "PlayerDataService missing")
    assert(svc:FindFirstChild("EconomyService"), "EconomyService missing")
    assert(svc:FindFirstChild("ZoneService"), "ZoneService missing")
    assert(svc:FindFirstChild("FishingService"), "FishingService missing")
end)

if serverOk then
    print("[Setup]   ✓ Server modules verified")
else
    warn("[Setup]   ✗ Server module verification failed")
end

print("")
print("========================================")
print(" Deep Tide — Master Setup COMPLETE!")
print("========================================")
print("")
print("What was created:")
print("  ☑ Water surface, sea floor, player spawn")
print("  ☑ Coral Gardens (15 structures), Shipwreck, zone boundary")
print("  ☑ Base lighting + volumetric atmosphere")
print("  ☑ Bloom, ColorCorrection, DepthOfField, SunRays")
print("  ☑ 8 god rays, 6 caustic lights")
print("  ☑ Landmark lights: Coral Gardens, Shipwreck, Deep Reef Edge")
print("  ☑ Bioluminescent particle emitters at all landmarks")
print("  ☑ Global marine snow (80 particles/s)")
print("  ☑ 8 plankton fields")
print("  -------------------- Phase 2: Kelp Forest --------------------")
print("  ☑ ~30 Kelp Forest canopy strands (Beam-based with sway)")
print("  ☑ Rocky Grotto rock formations (10 rocks)")
print("  ☑ Abyss Edge void boundary wall")
print("  ☑ Air pocket bubble columns (2 cave locations)")
print("  ☑ 6 Kelp Forest bioluminescent plankton fields")
print("")
print("To test the full MVP + Phase 2 loop:")
print("  1. Make sure Rojo is synced (rojo serve)")
print("  2. Press Play in Roblox Studio")
print("  3. You should see:")
print("     - Deep Tide Studios banner in Output")
print("     - Fish NPCs spawning underwater in both zones")
print("     - Full atmosphere (god rays, fog, particles)")
print("     - Zone transition when crossing 50m: Kelp Forest lighting kicks in")
print("     - HUD overlay (coins, gems, oxygen, depth)")
print("  4. Equip rod → dive underwater → cast → catch fish!")
print("  5. Press B for Collection Book, S for Shop")
print("")
print("Runtime systems (loaded at Play):")
print("  - CameraController: depth fog, camera bob, fishing cam")
print("  - AtmosphereHandler: dynamic VFX, rare spawn blooms, bubble trails")
print("  - AtmosphereHandler (Phase 2): zone transitions, kelp lighting, air pockets")
print("  - FishingController: full cast/hook/reel loop")
print("  - UIController: persistent HUD, CollectionBook, ShopScreen")
print("  - FishSpawner: NPC spawning, schooling, rare conditions")
print("  - FishingService: server-authoritative catch resolution")
print("")
