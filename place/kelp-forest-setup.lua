--[[
    kelp-forest-setup.lua
    Deep Tide Studios — Kelp Forest Place Setup Script
    Phase 2: Creates kelp strand assemblies, Rocky Grotto structures,
    Abyss Edge void boundary, and environmental VFX for the Kelp Forest zone.

    Run this in Roblox Studio (Command Bar) after master-setup.lua.
    Depends on: ZoneConfigs landmark positions (see ZoneConfigs.lua §KelpForest).

    Usage: Paste into Command Bar in Studio and run.
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Zone data from ZoneConfigs must match exactly
local KELP_FOREST_Y_MIN = -150   -- depth in studs (150m)
local KELP_FOREST_Y_MAX = -50    -- depth in studs (50m)
local KELP_CANOPY_MIN = -75
local KELP_CANOPY_MAX = -50
local CLEARING_MIN = -100
local CLEARING_MAX = -75
local GROTTO_MIN = -130
local GROTTO_MAX = -100
local ABYSS_MIN = -150
local ABYSS_MAX = -130

-- Landmark centers from ZoneConfigs.lua:
--   KelpCanopy: Vector3.new(0, -62, 0), Radius 80
--   TheClearing: Vector3.new(25, -87, 20), Radius 55
--   RockyGrotto: Vector3.new(-15, -115, -10), Radius 45
--   AbyssEdge: Vector3.new(-30, -140, -35), Radius 40

local KELP_CANOPY_CENTER = Vector3.new(0, -62, 0)
local KELP_CANOPY_RADIUS = 80
local CLEARING_CENTER = Vector3.new(25, -87, 20)
local CLEARING_RADIUS = 55
local GROTTO_CENTER = Vector3.new(-15, -115, -10)
local GROTTO_RADIUS = 45
local ABYSS_CENTER = Vector3.new(-30, -140, -35)
local ABYSS_RADIUS = 40

-- Air pocket positions from ZoneConfigs.lua:
--   Grotto North Cave: Vector3.new(-20, -108, -5)
--   Grotto South Crevice: Vector3.new(-8, -112, -18)
local AIR_POCKETS = {
    { Name = "Grotto North Cave", Position = Vector3.new(-20, -108, -5) },
    { Name = "Grotto South Crevice", Position = Vector3.new(-8, -112, -18) },
}

print("========================================")
print(" Deep Tide — Kelp Forest Atmosphere Setup")
print(" Phase 2: Kelp Canopy, Clearing, Grotto, Abyss Edge")
print("========================================")
print("")

-- ============================================================
-- PART 1: KELP STRAND ASSEMBLIES (40-60 strands in Kelp Canopy)
-- Each strand: Beam-based, 50-100 studs tall, dark green/brown
-- Sinusoidal sway via RunService.Heartbeat
-- ============================================================
print("[KelpForest] Part 1/5: Creating kelp strand assemblies...")

local kelpStrands = {}
local strandCount = 0
for _, obj in ipairs(Workspace:GetChildren()) do
    if obj.Name == "KelpBase" then strandCount = strandCount + 1 end
end

if strandCount >= 40 then
    print("[KelpForest]   Kelp strands already exist — skipping (" .. strandCount .. " found)")
else
    local kelpColors = {
        Color3.fromRGB(20, 80, 30),   -- dark forest green
        Color3.fromRGB(15, 70, 25),   -- deeper green
        Color3.fromRGB(25, 90, 35),   -- moss green
        Color3.fromRGB(30, 60, 20),   -- olive green
        Color3.fromRGB(18, 75, 28),   -- muted green
        Color3.fromRGB(40, 50, 25),   -- brown-green
    }

    local kelpFrondColors = {
        Color3.fromRGB(25, 100, 40),
        Color3.fromRGB(20, 85, 35),
        Color3.fromRGB(30, 110, 45),
    }

    local totalKelpTarget = 50  -- 40-60, we'll aim for 50

    -- Helper: check if a point is within a cylinder defined by center, radius, yMin, yMax
    local function inCylinder(pos, center, radius, yMin, yMax)
        local dx = pos.X - center.X
        local dz = pos.Z - center.Z
        return (dx*dx + dz*dz) <= radius*radius and pos.Y >= yMin and pos.Y <= yMax
    end

    local function createKelpStrand(basePos, height, color, swaySpeed, swayPhase)
        -- Seafloor anchor
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

        -- Top anchor
        local topPos = basePos + Vector3.new(0, height, 0)
        local top = Instance.new("Part")
        top.Name = "KelpTop"
        top.Size = Vector3.new(0.15, 0.15, 0.15)
        top.Position = topPos
        top.Anchored = true
        top.CanCollide = false
        top.Transparency = 1
        top.Parent = Workspace

        -- Attachments for beam
        local attachBase = Instance.new("Attachment")
        attachBase.Name = "KelpBaseAttach"
        attachBase.Parent = base
        local attachTop = Instance.new("Attachment")
        attachTop.Name = "KelpTopAttach"
        attachTop.Parent = top

        -- Main kelp stalk beam
        local beam = Instance.new("Beam")
        beam.Name = "KelpBeam"
        beam.Attachment0 = attachBase
        beam.Attachment1 = attachTop
        beam.Color = ColorSequence.new(color)
        beam.Width0 = 0.3 + math.random() * 0.3
        beam.Width1 = 0.08 + math.random() * 0.1
        beam.Transparency = NumberSequence.new(0.25)
        beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        beam.TextureSpeed = 0.005 + math.random() * 0.01
        beam.TextureLength = 1
        beam.CurveSize0 = 1.5 + math.random() * 2
        beam.CurveSize1 = -(1 + math.random() * 2)
        beam.FaceCamera = true
        beam.Parent = base

        -- Frond side-beams (2-4 smaller beams branching off)
        local fronds = {}
        local frondCount = 2 + math.random(0, 2)
        for f = 1, frondCount do
            local fracHeight = 0.3 + (f / (frondCount + 1)) * 0.6
            local frondY = basePos.Y + height * fracHeight
            local frondOffset = Vector3.new(
                (math.random() - 0.5) * 2,
                0,
                (math.random() - 0.5) * 2
            )

            local frondBase = Instance.new("Part")
            frondBase.Name = "KelpFrondBase"
            frondBase.Size = Vector3.new(0.15, 0.15, 0.15)
            frondBase.Position = Vector3.new(basePos.X, frondY, basePos.Z)
            frondBase.Anchored = true
            frondBase.CanCollide = false
            frondBase.Transparency = 1
            frondBase.Parent = Workspace

            local frondEnd = Instance.new("Part")
            frondEnd.Name = "KelpFrondEnd"
            frondEnd.Size = Vector3.new(0.08, 0.08, 0.08)
            frondEnd.Position = Vector3.new(
                basePos.X + frondOffset.X,
                frondY + frondOffset.Y + 4 + math.random() * 6,
                basePos.Z + frondOffset.Z
            )
            frondEnd.Anchored = true
            frondEnd.CanCollide = false
            frondEnd.Transparency = 1
            frondEnd.Parent = Workspace

            local fAttachBase = Instance.new("Attachment")
            fAttachBase.Parent = frondBase
            local fAttachEnd = Instance.new("Attachment")
            fAttachEnd.Parent = frondEnd

            local frondBeam = Instance.new("Beam")
            frondBeam.Name = "KelpFrondBeam"
            frondBeam.Attachment0 = fAttachBase
            frondBeam.Attachment1 = fAttachEnd
            frondBeam.Color = ColorSequence.new(kelpFrondColors[math.random(1, #kelpFrondColors)])
            frondBeam.Width0 = 0.12
            frondBeam.Width1 = 0.03
            frondBeam.Transparency = NumberSequence.new(0.35)
            frondBeam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
            frondBeam.TextureSpeed = 0.008
            frondBeam.TextureLength = 1
            frondBeam.CurveSize0 = -1
            frondBeam.CurveSize1 = 1
            frondBeam.FaceCamera = true
            frondBeam.Parent = frondBase

            table.insert(fronds, { Base = frondBase, End = frondEnd, Beam = frondBeam })
        end

        -- Sway animation via Heartbeat
        local swayConnection
        swayConnection = RunService.Heartbeat:Connect(function(dt)
            if not top or not top.Parent then
                if swayConnection then swayConnection:Disconnect() end
                return
            end
            local swayX = math.sin(tick() * swaySpeed + swayPhase) * 1.2
            local swayZ = math.cos(tick() * (swaySpeed * 0.8) + swayPhase + 1) * 1.2
            top.Position = Vector3.new(basePos.X + swayX, basePos.Y + height, basePos.Z + swayZ)
        end)

        return {
            Base = base, Top = top, Beam = beam,
            Fronds = fronds,
            Connection = swayConnection,
            BasePosition = basePos,
            Height = height,
        }
    end

    -- --- Kelp Canopy (50-75m): Dense kelp, 40-50 strands ---
    local canopyKelpCount = 40 + math.random(0, 10)
    print("[KelpForest]   Creating " .. canopyKelpCount .. " kelp strands in Kelp Canopy...")

    local placedCanopy = 0
    local attempts = 0
    local maxAttempts = canopyKelpCount * 10

    while placedCanopy < canopyKelpCount and attempts < maxAttempts do
        attempts = attempts + 1
        local angle = math.random() * math.pi * 2
        local radius = math.random() * KELP_CANOPY_RADIUS * 0.9
        local x = KELP_CANOPY_CENTER.X + math.cos(angle) * radius
        local z = KELP_CANOPY_CENTER.Z + math.sin(angle) * radius
        local y = KELP_CANOPY_MAX - math.random() * (KELP_CANOPY_MAX - KELP_CANOPY_MIN)  -- -50 to -75
        local basePos = Vector3.new(x, y - 0.2, z)  -- anchor slight below seafloor
        local height = 50 + math.random() * 50  -- 50-100 studs tall

        -- Check minimum distance from existing kelp
        local tooClose = false
        for _, existing in ipairs(kelpStrands) do
            local dx = basePos.X - existing.BasePosition.X
            local dz = basePos.Z - existing.BasePosition.Z
            if dx*dx + dz*dz < 25 then  -- min 5 studs apart
                tooClose = true
                break
            end
        end
        if tooClose then continue end

        local color = kelpColors[math.random(1, #kelpColors)]
        local swaySpeed = 0.7 + math.random() * 0.6  -- period 3-5s (2π/speed)
        local swayPhase = math.random() * math.pi * 2

        local strand = createKelpStrand(basePos, height, color, swaySpeed, swayPhase)
        table.insert(kelpStrands, strand)
        placedCanopy = placedCanopy + 1

        if placedCanopy % 20 == 0 then
            print("[KelpForest]     " .. placedCanopy .. "/" .. canopyKelpCount .. " canopy strands placed...")
        end
    end

    print("[KelpForest]     ✓ " .. placedCanopy .. " canopy strands created.")

    -- --- The Clearing (75-100m): Sparse strands (5-10) ---
    local clearingKelpCount = 5 + math.random(0, 5)
    print("[KelpForest]   Creating " .. clearingKelpCount .. " sparse strands in The Clearing...")

    local placedClearing = 0
    attempts = 0
    maxAttempts = clearingKelpCount * 15

    while placedClearing < clearingKelpCount and attempts < maxAttempts do
        attempts = attempts + 1
        local angle = math.random() * math.pi * 2
        local radius = math.random() * CLEARING_RADIUS * 0.7
        local x = CLEARING_CENTER.X + math.cos(angle) * radius
        local z = CLEARING_CENTER.Z + math.sin(angle) * radius
        local y = CLEARING_MIN - math.random() * (CLEARING_MIN - CLEARING_MAX)
        local basePos = Vector3.new(x, y - 0.2, z)
        local height = 15 + math.random() * 25  -- shorter strands

        local tooClose = false
        for _, existing in ipairs(kelpStrands) do
            local dx = basePos.X - existing.BasePosition.X
            local dz = basePos.Z - existing.BasePosition.Z
            if dx*dx + dz*dz < 64 then  -- min 8 studs apart (sparser)
                tooClose = true
                break
            end
        end
        if tooClose then continue end

        local color = kelpColors[math.random(1, #kelpColors)]
        local swaySpeed = 0.8 + math.random() * 0.5
        local swayPhase = math.random() * math.pi * 2

        local strand = createKelpStrand(basePos, height, color, swaySpeed, swayPhase)
        table.insert(kelpStrands, strand)
        placedClearing = placedClearing + 1
    end

    print("[KelpForest]     ✓ " .. placedClearing .. " clearing strands created.")

    -- --- Rocky Grotto (100-130m): Kelp only on ceiling/cliff edges (8-15 strands) ---
    local grottoKelpCount = 8 + math.random(0, 7)
    print("[KelpForest]   Creating " .. grottoKelpCount .. " strands in Rocky Grotto (ceiling/cliff edges)...")

    local placedGrotto = 0
    attempts = 0
    maxAttempts = grottoKelpCount * 15

    -- Grotto kelp grows from the ceiling downward (inverted) and on cliff edges
    while placedGrotto < grottoKelpCount and attempts < maxAttempts do
        attempts = attempts + 1
        local angle = math.random() * math.pi * 2
        local radius = math.random() * GROTTO_RADIUS * 0.8
        local x = GROTTO_CENTER.X + math.cos(angle) * radius
        local z = GROTTO_CENTER.Z + math.sin(angle) * radius
        local y = GROTTO_MIN - math.random() * (GROTTO_MIN - GROTTO_MAX)

        -- Grotto kelp hangs from "ceiling" at y ~ -100 to -110
        local ceilingY = -100 - math.random() * 15
        local basePos = Vector3.new(x, ceilingY, z)
        local height = 10 + math.random() * 20  -- shorter, hanging kelp

        local tooClose = false
        for _, existing in ipairs(kelpStrands) do
            local dx = basePos.X - existing.BasePosition.X
            local dz = basePos.Z - existing.BasePosition.Z
            if dx*dx + dz*dz < 49 then
                tooClose = true
                break
            end
        end
        if tooClose then continue end

        local color = Color3.fromRGB(30, 40, 25)  -- darker for grotto
        local swaySpeed = 0.6 + math.random() * 0.4
        local swayPhase = math.random() * math.pi * 2

        local strand = createKelpStrand(basePos, height, color, swaySpeed, swayPhase)
        table.insert(kelpStrands, strand)
        placedGrotto = placedGrotto + 1
    end

    print("[KelpForest]     ✓ " .. placedGrotto .. " grotto strands created.")
    print("[KelpForest]   ✓ Total kelp strands: " .. #kelpStrands)
end

-- ============================================================
-- PART 2: ROCKY GROTTO STRUCTURES
-- Jagged rock formations, crevices, cave ceilings
-- ============================================================
print("[KelpForest] Part 2/5: Creating Rocky Grotto structures...")

local grottoRocksFound = 0
for _, obj in ipairs(Workspace:GetChildren()) do
    if obj.Name:find("GrottoRock_") then grottoRocksFound = grottoRocksFound + 1 end
end

if grottoRocksFound >= 8 then
    print("[KelpForest]   Rocky Grotto already exists — skipping (" .. grottoRocksFound .. " rocks found)")
else
    -- Dark basalt rock formations
    for i = 1, 12 do
        local angle = (i / 12) * math.pi * 2 + math.random() * 0.3
        local radius = math.random() * GROTTO_RADIUS * 0.7
        local x = GROTTO_CENTER.X + math.cos(angle) * radius
        local z = GROTTO_CENTER.Z + math.sin(angle) * radius
        local y = GROTTO_CENTER.Y + math.random() * 15 - 7
        local rockSize = Vector3.new(6 + math.random() * 10, 4 + math.random() * 8, 6 + math.random() * 10)

        local rock = Instance.new("Part")
        rock.Name = "GrottoRock_" .. i
        rock.Size = rockSize
        rock.Position = Vector3.new(x, y, z)
        rock.Anchored = true
        rock.CanCollide = true
        rock.Color = Color3.fromRGB(25 + math.random() * 20, 20 + math.random() * 15, 30 + math.random() * 15)
        rock.Material = Enum.Material.Basalt
        rock.Parent = Workspace

        -- Bioluminescent lichen glow on some rocks
        if math.random() < 0.7 then
            local lichenLight = Instance.new("PointLight")
            lichenLight.Name = "GrottoLichenLight_" .. i
            lichenLight.Brightness = 0.15 + math.random() * 0.25
            lichenLight.Range = 6 + math.random() * 8
            lichenLight.Color = (math.random() < 0.5)
                and Color3.fromRGB(80, 220, 200)   -- cyan
                or Color3.fromRGB(120, 255, 180)    -- pale green
            lichenLight.Shadows = false
            lichenLight.Enabled = true
            lichenLight.Parent = rock
        end
    end

    -- Cave formations (hollow spaces marked by dark translucent boxes)
    for i = 1, 3 do
        local angle = (i / 3) * math.pi * 2 + math.random()
        local radius = math.random() * GROTTO_RADIUS * 0.4
        local x = GROTTO_CENTER.X + math.cos(angle) * radius
        local z = GROTTO_CENTER.Z + math.sin(angle) * radius
        local y = GROTTO_CENTER.Y + math.random() * 10 - 5

        local caveEntrance = Instance.new("Part")
        caveEntrance.Name = "GrottoCave_" .. i
        caveEntrance.Size = Vector3.new(8, 6, 4)
        caveEntrance.Position = Vector3.new(x, y, z)
        caveEntrance.Anchored = true
        caveEntrance.CanCollide = false
        caveEntrance.Transparency = 0.85
        caveEntrance.Color = Color3.fromRGB(5, 5, 15)
        caveEntrance.Material = Enum.Material.Slate
        caveEntrance.Parent = Workspace

        -- Dark interior glow
        local caveLight = Instance.new("PointLight")
        caveLight.Name = "CaveInteriorLight_" .. i
        caveLight.Brightness = 0.05
        caveLight.Range = 10
        caveLight.Color = Color3.fromRGB(40, 40, 80)
        caveLight.Shadows = false
        caveLight.Enabled = true
        caveLight.Parent = caveEntrance
    end

    print("[KelpForest]   ✓ Rocky Grotto created (12 rocks, 3 caves)")
end

-- ============================================================
-- PART 3: ABYSS EDGE VOID BOUNDARY
-- Diegetic "shimmering current line" at the edge
-- Dark void with occasional shadow silhouettes
-- ============================================================
print("[KelpForest] Part 3/5: Creating Abyss Edge void boundary...")

local abyssWallFound = Workspace:FindFirstChild("AbyssVoidWall")
if abyssWallFound then
    print("[KelpForest]   Abyss Edge already exists — skipping")
else
    -- Create the "void beyond" wall — a large dark semi-transparent plane
    local voidWall = Instance.new("Part")
    voidWall.Name = "AbyssVoidWall"
    voidWall.Size = Vector3.new(120, 30, 2)
    voidWall.Position = ABYSS_CENTER + Vector3.new(0, 0, -ABYSS_RADIUS * 0.8)
    voidWall.Anchored = true
    voidWall.CanCollide = true  -- invisible collision boundary
    voidWall.Transparency = 0.9
    voidWall.Color = Color3.fromRGB(2, 0, 8)
    voidWall.Material = Enum.Material.Glass
    voidWall.Parent = Workspace

    -- Shimmering current line VFX along the boundary
    local shimmerAnchor = Instance.new("Part")
    shimmerAnchor.Name = "AbyssShimmerLine"
    shimmerAnchor.Size = Vector3.new(120, 3, 0.5)
    shimmerAnchor.Position = ABYSS_CENTER + Vector3.new(0, 0, -ABYSS_RADIUS * 0.8 + 1)
    shimmerAnchor.Anchored = true
    shimmerAnchor.CanCollide = false
    shimmerAnchor.Transparency = 1
    shimmerAnchor.Parent = Workspace

    local shimmerEmitter = Instance.new("ParticleEmitter")
    shimmerEmitter.Name = "ShimmerEmitter"
    shimmerEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    shimmerEmitter.Rate = 30
    shimmerEmitter.Lifetime = NumberRange.new(0.5, 2)
    shimmerEmitter.Speed = NumberRange.new(0.5, 1.5)
    shimmerEmitter.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.05),
        NumberSequenceKeypoint.new(0.5, 0.2),
        NumberSequenceKeypoint.new(1, 0.05),
    }
    shimmerEmitter.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(0.5, 0.1),
        NumberSequenceKeypoint.new(1, 0.9),
    }
    shimmerEmitter.Color = ColorSequence.new(Color3.fromRGB(100, 80, 220))  -- purple shimmer
    shimmerEmitter.SpreadAngle = Vector2.new(0, 0)
    shimmerEmitter.LockedToPart = true
    shimmerEmitter.Enabled = true
    shimmerEmitter.Parent = shimmerAnchor

    -- Occasional void silhouette (large dark shape in the distance)
    local silhouetteAnchor = Instance.new("Part")
    silhouetteAnchor.Name = "AbyssSilhouette"
    silhouetteAnchor.Size = Vector3.new(0.5, 0.5, 0.5)
    silhouetteAnchor.Position = ABYSS_CENTER + Vector3.new(0, -5, -ABYSS_RADIUS - 20)
    silhouetteAnchor.Anchored = true
    silhouetteAnchor.CanCollide = false
    silhouetteAnchor.Transparency = 1
    silhouetteAnchor.Parent = Workspace

    -- Large shadow Part that fades in/out (simulated by a big part with high transparency + dark color)
    local shadow = Instance.new("Part")
    shadow.Name = "AbyssShadowShape"
    shadow.Size = Vector3.new(15, 8, 2)
    shadow.Position = ABYSS_CENTER + Vector3.new(0, -5, -ABYSS_RADIUS - 20)
    shadow.Anchored = true
    shadow.CanCollide = false
    shadow.Transparency = 0.92
    shadow.Color = Color3.fromRGB(3, 3, 10)
    shadow.Material = Enum.Material.Slate
    shadow.Parent = Workspace

    -- Subtle purple point lights at the void edge
    for i = 1, 4 do
        local offsetX = (i - 2) * 25
        local voidLightAnchor = Instance.new("Part")
        voidLightAnchor.Name = "AbyssVoidEdgeLight_" .. i
        voidLightAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
        voidLightAnchor.Position = ABYSS_CENTER + Vector3.new(offsetX, 3, -ABYSS_RADIUS * 0.8 + 1)
        voidLightAnchor.Transparency = 1
        voidLightAnchor.Anchored = true
        voidLightAnchor.CanCollide = false
        voidLightAnchor.Parent = Workspace

        local light = Instance.new("PointLight")
        light.Name = "VoidEdgeLight_" .. i
        light.Brightness = 0.3
        light.Range = 12
        light.Color = Color3.fromRGB(120, 40, 160)  -- deep purple
        light.Shadows = false
        light.Enabled = true
        light.Parent = voidLightAnchor
    end

    -- Foreshadowing signpost
    local signAnchor = Instance.new("Part")
    signAnchor.Name = "AbyssSignpost"
    signAnchor.Size = Vector3.new(6, 3, 0.3)
    signAnchor.Position = ABYSS_CENTER + Vector3.new(15, 3, -ABYSS_RADIUS * 0.6)
    signAnchor.Anchored = true
    signAnchor.CanCollide = false
    signAnchor.Color = Color3.fromRGB(60, 30, 10)
    signAnchor.Material = Enum.Material.WoodPlanks
    signAnchor.Parent = Workspace

    -- Sign post
    local signPost = Instance.new("Part")
    signPost.Name = "AbyssSignPost"
    signPost.Size = Vector3.new(0.6, 8, 0.6)
    signPost.Position = signAnchor.Position - Vector3.new(0, 5.5, 0)
    signPost.Anchored = true
    signPost.CanCollide = false
    signPost.Color = Color3.fromRGB(50, 30, 15)
    signPost.Material = Enum.Material.WoodPlanks
    signPost.Parent = Workspace

    print("[KelpForest]   ✓ Abyss Edge void boundary created (wall, shimmer, silhouettes, signpost)")
end

-- ============================================================
-- PART 4: ENVIRONMENTAL VFX
-- Air pocket bubble columns, current particles, kelp snare VFX,
-- Rocky Grotto ambient floating sediment
-- ============================================================
print("[KelpForest] Part 4/5: Creating environmental VFX...")

-- 4a. Air pocket bubble columns (2 locations from ZoneConfigs)
print("[KelpForest]   Creating air pocket bubble columns...")

for _, pocket in ipairs(AIR_POCKETS) do
    local bubbleAnchorName = pocket.Name:gsub(" ", "") .. "_BubbleColumn"
    local existingBubbles = Workspace:FindFirstChild(bubbleAnchorName)
    if existingBubbles then
        print("[KelpForest]     Air pocket bubbles already exist at " .. pocket.Name .. " — skipping")
    else
        local bubbleAnchor = Instance.new("Part")
        bubbleAnchor.Name = bubbleAnchorName
        bubbleAnchor.Size = Vector3.new(6, 3, 6)
        bubbleAnchor.Position = pocket.Position
        bubbleAnchor.Transparency = 1
        bubbleAnchor.Anchored = true
        bubbleAnchor.CanCollide = false
        bubbleAnchor.Parent = Workspace

        -- Bubble column emitter
        local bubbleEmitter = Instance.new("ParticleEmitter")
        bubbleEmitter.Name = "AirPocketBubbles"
        bubbleEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        bubbleEmitter.Rate = 25
        bubbleEmitter.Lifetime = NumberRange.new(1, 3)
        bubbleEmitter.Speed = NumberRange.new(0.5, 2)
        bubbleEmitter.Size = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.1),
            NumberSequenceKeypoint.new(0.5, 0.2),
            NumberSequenceKeypoint.new(1, 0.3),
        }
        bubbleEmitter.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.5),
            NumberSequenceKeypoint.new(0.5, 0.3),
            NumberSequenceKeypoint.new(1, 0.7),
        }
        bubbleEmitter.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
        bubbleEmitter.SpreadAngle = Vector2.new(5, 10)
        bubbleEmitter.Acceleration = Vector3.new(0, 3, 0)  -- bubbles rise
        bubbleEmitter.Drag = 0.3
        bubbleEmitter.LockedToPart = true
        bubbleEmitter.Enabled = true
        bubbleEmitter.Parent = bubbleAnchor

        -- Sparkle particles at bubble source
        local sparkleEmitter = Instance.new("ParticleEmitter")
        sparkleEmitter.Name = "AirPocketSparkles"
        sparkleEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        sparkleEmitter.Rate = 8
        sparkleEmitter.Lifetime = NumberRange.new(0.5, 2)
        sparkleEmitter.Speed = NumberRange.new(0.2, 1)
        sparkleEmitter.Size = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.03),
            NumberSequenceKeypoint.new(0.5, 0.1),
            NumberSequenceKeypoint.new(1, 0.02),
        }
        sparkleEmitter.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.2),
            NumberSequenceKeypoint.new(0.5, 0.05),
            NumberSequenceKeypoint.new(1, 1),
        }
        sparkleEmitter.Color = ColorSequence.new(Color3.fromRGB(180, 230, 255))
        sparkleEmitter.SpreadAngle = Vector2.new(10, 20)
        sparkleEmitter.Acceleration = Vector3.new(0, 1, 0)
        sparkleEmitter.Drag = 0.5
        sparkleEmitter.LockedToPart = true
        sparkleEmitter.Enabled = true
        sparkleEmitter.Parent = bubbleAnchor

        -- Warm amber/golden glow at the cave air pocket
        local airPocketLight = Instance.new("PointLight")
        airPocketLight.Name = "AirPocketLight"
        airPocketLight.Brightness = 0.4
        airPocketLight.Range = 12
        airPocketLight.Color = Color3.fromRGB(255, 200, 100)  -- warm amber
        airPocketLight.Shadows = false
        airPocketLight.Enabled = true
        airPocketLight.Parent = bubbleAnchor

        print("[KelpForest]     ✓ Air pocket created at " .. pocket.Name)
    end
end

-- 4b. Current particles in The Clearing (diagonal-flowing particulate)
print("[KelpForest]   Creating Clearing current particles...")

local currentAnchorName = "ClearingCurrentVFX"
local existingCurrent = Workspace:FindFirstChild(currentAnchorName)
if existingCurrent then
    print("[KelpForest]     Current particles already exist — skipping")
else
    local currentAnchor = Instance.new("Part")
    currentAnchor.Name = currentAnchorName
    currentAnchor.Size = Vector3.new(CLEARING_RADIUS * 1.6, CLEARING_MAX - CLEARING_MIN, CLEARING_RADIUS * 1.6)
    currentAnchor.Position = CLEARING_CENTER
    currentAnchor.Transparency = 1
    currentAnchor.Anchored = true
    currentAnchor.CanCollide = false
    currentAnchor.Parent = Workspace

    -- Diagonal-flowing particulate (NW → SE)
    local currentEmitter = Instance.new("ParticleEmitter")
    currentEmitter.Name = "ClearingCurrent"
    currentEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    currentEmitter.Rate = 40
    currentEmitter.Lifetime = NumberRange.new(2, 5)
    currentEmitter.Speed = NumberRange.new(6, 10)  -- fast flow
    currentEmitter.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.02),
        NumberSequenceKeypoint.new(0.5, 0.05),
        NumberSequenceKeypoint.new(1, 0.02),
    }
    currentEmitter.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.6),
        NumberSequenceKeypoint.new(0.3, 0.3),
        NumberSequenceKeypoint.new(0.7, 0.5),
        NumberSequenceKeypoint.new(1, 0.9),
    }
    currentEmitter.Color = ColorSequence.new(Color3.fromRGB(200, 220, 240))
    currentEmitter.SpreadAngle = Vector2.new(3, 3)
    -- NW → SE diagonal: Vector.new(1, 0, -1).Unit ≈ (0.707, 0, -0.707)
    currentEmitter.VelocitySpread = 20
    -- Use Acceleration to push particles diagonally
    currentEmitter.Acceleration = Vector3.new(4, -0.5, -4.5)  -- NW→SE with slight sinking
    currentEmitter.Drag = 0.1
    currentEmitter.LockedToPart = true
    currentEmitter.Enabled = true
    currentEmitter.Parent = currentAnchor

    print("[KelpForest]     ✓ Clearing current particles created")
end

-- 4c. Rocky Grotto ambient floating sediment + rockfall sparkles
print("[KelpForest]   Creating Rocky Grotto ambient VFX...")

local grottoVFXAnchorName = "GrottoAmbientVFX"
local existingGrottoVFX = Workspace:FindFirstChild(grottoVFXAnchorName)
if existingGrottoVFX then
    print("[KelpForest]     Grotto ambient VFX already exists — skipping")
else
    local grottoAnchor = Instance.new("Part")
    grottoAnchor.Name = grottoVFXAnchorName
    grottoAnchor.Size = Vector3.new(GROTTO_RADIUS * 2, GROTTO_MAX - GROTTO_MIN, GROTTO_RADIUS * 2)
    grottoAnchor.Position = GROTTO_CENTER
    grottoAnchor.Transparency = 1
    grottoAnchor.Anchored = true
    grottoAnchor.CanCollide = false
    grottoAnchor.Parent = Workspace

    -- Floating sediment motes
    local sedimentEmitter = Instance.new("ParticleEmitter")
    sedimentEmitter.Name = "GrottoSediment"
    sedimentEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    sedimentEmitter.Rate = 20
    sedimentEmitter.Lifetime = NumberRange.new(3, 8)
    sedimentEmitter.Speed = NumberRange.new(0.1, 0.5)
    sedimentEmitter.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.02),
        NumberSequenceKeypoint.new(0.5, 0.06),
        NumberSequenceKeypoint.new(1, 0.02),
    }
    sedimentEmitter.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.7),
        NumberSequenceKeypoint.new(0.5, 0.4),
        NumberSequenceKeypoint.new(1, 0.85),
    }
    sedimentEmitter.Color = ColorSequence.new(Color3.fromRGB(140, 130, 120))
    sedimentEmitter.SpreadAngle = Vector2.new(0, 360)
    sedimentEmitter.Acceleration = Vector3.new(0, -0.05, 0)  -- slow settling
    sedimentEmitter.Drag = 0.8
    sedimentEmitter.LockedToPart = true
    sedimentEmitter.Enabled = true
    sedimentEmitter.Parent = grottoAnchor

    -- Occasional rockfall sparkles
    local rockfallEmitter = Instance.new("ParticleEmitter")
    rockfallEmitter.Name = "GrottoRockfall"
    rockfallEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    rockfallEmitter.Rate = 3  -- occasional
    rockfallEmitter.Lifetime = NumberRange.new(0.5, 1.5)
    rockfallEmitter.Speed = NumberRange.new(1, 4)
    rockfallEmitter.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.04),
        NumberSequenceKeypoint.new(0.5, 0.12),
        NumberSequenceKeypoint.new(1, 0.02),
    }
    rockfallEmitter.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(0.3, 0.1),
        NumberSequenceKeypoint.new(1, 1),
    }
    rockfallEmitter.Color = ColorSequence.new(Color3.fromRGB(180, 170, 160))
    rockfallEmitter.SpreadAngle = Vector2.new(10, 20)
    rockfallEmitter.Acceleration = Vector3.new(0, -2, 0)  -- falling
    rockfallEmitter.Drag = 0.3
    rockfallEmitter.LockedToPart = true
    rockfallEmitter.Enabled = true
    rockfallEmitter.Parent = grottoAnchor

    print("[KelpForest]     ✓ Rocky Grotto ambient VFX created")
end

-- 4d. Kelp Canopy — enhanced bioluminescent plankton (more than Shallows)
print("[KelpForest]   Creating Kelp Forest bioluminescent plankton fields...")

local planktonFound = 0
for _, obj in ipairs(Workspace:GetChildren()) do
    if obj.Name:find("KelpPlanktonField_") then planktonFound = planktonFound + 1 end
end

if planktonFound >= 4 then
    print("[KelpForest]     Kelp Forest plankton already exists — skipping (" .. planktonFound .. " found)")
else
    -- Create 6 plankton fields spread through Kelp Canopy and Clearing
    local kelpPlanktonPositions = {
        Vector3.new(-20, -60, -15),  -- Canopy west
        Vector3.new(15, -55, 10),    -- Canopy east
        Vector3.new(-10, -55, 20),   -- Canopy north
        Vector3.new(5, -70, -15),    -- Lower canopy
        Vector3.new(25, -85, 15),    -- Clearing edge
        Vector3.new(35, -90, 5),     -- Clearing deep
    }

    for i, pos in ipairs(kelpPlanktonPositions) do
        local anchor = Instance.new("Part")
        anchor.Name = "KelpPlanktonField_" .. i
        anchor.Size = Vector3.new(25, 12, 25)
        anchor.Position = pos
        anchor.Transparency = 1
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.Parent = Workspace

        local emitter = Instance.new("ParticleEmitter")
        emitter.Name = "KelpPlanktonEmitter"
        emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        emitter.Rate = 8 + math.random() * 6  -- more than Shallows plankton
        emitter.Lifetime = NumberRange.new(2, 6)
        emitter.Speed = NumberRange.new(0.1, 0.6)
        emitter.Size = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.03),
            NumberSequenceKeypoint.new(0.5, 0.15),
            NumberSequenceKeypoint.new(1, 0.02),
        }
        emitter.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.4),
            NumberSequenceKeypoint.new(0.3, 0.05),
            NumberSequenceKeypoint.new(0.7, 0.15),
            NumberSequenceKeypoint.new(1, 1),
        }
        -- Bioluminescent green/cyan — more vivid than Shallows
        local hue = 0.45 + math.random() * 0.15  -- green-cyan
        emitter.Color = ColorSequence.new(Color3.fromHSV(hue, 0.7, 0.95))
        emitter.SpreadAngle = Vector2.new(0, 360)
        emitter.Acceleration = Vector3.new(0, 0.2, 0)
        emitter.Drag = 0.3
        emitter.LockedToPart = true
        emitter.Enabled = true
        emitter.Parent = anchor
    end

    print("[KelpForest]     ✓ " .. #kelpPlanktonPositions .. " Kelp Forest plankton fields created")
end

-- ============================================================
-- PART 5: KELP CANOPY GOD RAYS (dappled, narrower than Shallows)
-- ============================================================
print("[KelpForest] Part 5/5: Creating kelp canopy dappled god rays...")

local canopyRayFound = 0
for _, obj in ipairs(Workspace:GetChildren()) do
    if obj.Name:find("CanopyGodRayOrigin_") then canopyRayFound = canopyRayFound + 1 end
end

if canopyRayFound >= 4 then
    print("[KelpForest]   Canopy god rays already exist — skipping")
else
    -- Dappled through kelp fronds: fewer rays, narrower, green-tinted
    local rayCount = 6
    for i = 1, rayCount do
        local offsetX = (i - rayCount / 2) * 12 + math.random() * 6
        local offsetZ = (i - rayCount / 2) * 8 + math.random() * 4
        local origin = Vector3.new(offsetX, KELP_CANOPY_MAX, offsetZ)  -- from canopy ceiling at Y=-50
        local targetDepth = KELP_CANOPY_MIN + math.random() * 15  -- penetrate 15-25 studs into canopy
        local target = Vector3.new(offsetX + math.random() * 3 - 1.5, targetDepth, offsetZ + math.random() * 3 - 1.5)

        local rayOriginPart = Instance.new("Part")
        rayOriginPart.Name = "CanopyGodRayOrigin_" .. i
        rayOriginPart.Size = Vector3.new(0.1, 0.1, 0.1)
        rayOriginPart.Position = origin
        rayOriginPart.Transparency = 1
        rayOriginPart.Anchored = true
        rayOriginPart.CanCollide = false
        rayOriginPart.Parent = Workspace

        local rayTargetPart = Instance.new("Part")
        rayTargetPart.Name = "CanopyGodRayTarget_" .. i
        rayTargetPart.Size = Vector3.new(0.1, 0.1, 0.1)
        rayTargetPart.Position = target
        rayTargetPart.Transparency = 1
        rayTargetPart.Anchored = true
        rayTargetPart.CanCollide = false
        rayTargetPart.Parent = Workspace

        local attach0 = Instance.new("Attachment"); attach0.Parent = rayOriginPart
        local attach1 = Instance.new("Attachment"); attach1.Parent = rayTargetPart

        local beam = Instance.new("Beam")
        beam.Name = "CanopyGodRayBeam_" .. i
        beam.Attachment0 = attach0
        beam.Attachment1 = attach1
        -- Green-tinted god rays filtering through kelp
        beam.Color = ColorSequence.new(Color3.fromRGB(140, 200, 120))
        beam.LightEmission = 0.2
        beam.LightInfluence = 0.15
        beam.Width0 = 0.3 + math.random() * 0.8  -- narrower than Shallows rays
        beam.Width1 = 0.2 + math.random() * 0.5
        beam.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.8),
            NumberSequenceKeypoint.new(0.3, 0.65),
            NumberSequenceKeypoint.new(0.7, 0.75),
            NumberSequenceKeypoint.new(1, 0.92),
        }
        beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        beam.TextureSpeed = 0.01
        beam.TextureLength = 1
        beam.FaceCamera = false
        beam.Parent = rayOriginPart
    end

    print("[KelpForest]   ✓ " .. rayCount .. " canopy dappled god rays created")
end

-- ============================================================
-- VERIFICATION SUMMARY
-- ============================================================
print("")
print("========================================")
print(" Deep Tide — Kelp Forest Setup COMPLETE!")
print("========================================")
print("")
print("What was created:")
print("  ☑ " .. #kelpStrands .. " kelp strand assemblies (Beam-based with sway)")
print("    - Kelp Canopy: dense, 50-100 studs tall")
print("    - The Clearing: sparse, 15-40 studs tall")
print("    - Rocky Grotto: hanging from ceiling/cliff edges")
print("    - Abyss Edge: no kelp (void)")
print("  ☑ Rocky Grotto: 12 basalt rock formations + 3 caves")
print("  ☑ Abyss Edge: void wall, shimmer line, silhouettes, signpost")
print("  ☑ Environmental VFX:")
print("    - 2 air pocket bubble columns with amber glow")
print("    - Clearing current particulate (NW→SE diagonal)")
print("    - Rocky Grotto floating sediment + rockfall sparkles")
print("  ☑ 6 Kelp Forest bioluminescent plankton fields (brighter than Shallows)")
print("  ☑ 6 dappled canopy god rays (green-tinted, narrow)")
print("")
print("Next: Modify AtmosphereHandler.lua to support zone transitions")
print("  - Kelp Forest lighting presets")
print("  - Smooth zone transitions (2-second tweens)")
print("  - Zone-specific fog/bloom/color parameters")
print("  - UI zone transition popups")
print("")
