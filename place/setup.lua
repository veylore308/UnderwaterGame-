--[[
    setup.lua
    Deep Tide Studios — Place Setup Script
    Run this in Roblox Studio (Command Bar) after syncing with Rojo to
    create the basic underwater test environment.
    
    Usage: Paste this into the Command Bar in Studio and run it.
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Terrain = Workspace:WaitForChild("Terrain")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("========================================")
print(" Deep Tide — Place Setup")
print("========================================")

-- ============================================================
-- 1. Configure Lighting for underwater atmosphere
-- ============================================================
print("[Setup] Configuring lighting...")

Lighting.ClockTime = 10          -- Morning light (sun rays visible)
Lighting.Brightness = 1.5
Lighting.Ambient = Color3.fromRGB(30, 60, 120)
Lighting.OutdoorAmbient = Color3.fromRGB(40, 80, 140)
Lighting.FogColor = Color3.fromRGB(64, 180, 200)
Lighting.FogStart = 20
Lighting.FogEnd = 65
Lighting.GlobalShadows = true
Lighting.EnvironmentSpecularScale = 0.5

-- Post-processing effects for underwater feel
if Lighting:FindFirstChild("Bloom") then
    Lighting.Bloom.Intensity = 0.3
    Lighting.Bloom.Threshold = 0.8
end
if Lighting:FindFirstChild("ColorCorrection") then
    Lighting.ColorCorrection.TintColor = Color3.fromRGB(180, 220, 255)
    Lighting.ColorCorrection.Saturation = -0.1
end

print("[Setup] Lighting configured.")

-- ============================================================
-- 2. Create water plane
-- ============================================================
print("[Setup] Creating water...")

-- In Roblox, water is created via Terrain
-- For a quick setup, place a semi-transparent blue Part at Y=0
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

print("[Setup] Water created.")

-- ============================================================
-- 3. Create basic terrain (coral reef floor)
-- ============================================================
print("[Setup] Generating terrain...")

-- Sandy seafloor at Y=-50
local floorPart = Instance.new("Part")
floorPart.Name = "SeaFloor"
floorPart.Size = Vector3.new(400, 2, 400)
floorPart.Position = Vector3.new(0, -51, 0)
floorPart.Anchored = true
floorPart.CanCollide = true
floorPart.Color = Color3.fromRGB(210, 190, 150) -- Sandy color
floorPart.Material = Enum.Material.Sand
floorPart.Parent = Workspace

print("[Setup] Sea floor created.")

-- ============================================================
-- 4. Create player spawn (surface boat)
-- ============================================================
print("[Setup] Creating spawn...")

local spawnPart = Instance.new("Part")
spawnPart.Name = "PlayerSpawn"
spawnPart.Size = Vector3.new(8, 2, 8)
spawnPart.Position = Vector3.new(0, 1, 0) -- At surface
spawnPart.Anchored = true
spawnPart.CanCollide = true
spawnPart.Color = Color3.fromRGB(139, 90, 43) -- Wood brown
spawnPart.Material = Enum.Material.WoodPlanks
spawnPart.Parent = Workspace

-- SpawnLocation
local spawnLocation = Instance.new("SpawnLocation")
spawnLocation.Name = "BoatSpawn"
spawnLocation.Size = Vector3.new(6, 1, 6)
spawnLocation.Position = Vector3.new(0, 2.5, 0)
spawnLocation.Anchored = true
spawnLocation.CanCollide = false
spawnLocation.Transparency = 0.7
spawnLocation.Color = Color3.fromRGB(255, 255, 0)
spawnLocation.Parent = Workspace

game:GetService("Players").RespawnTime = 0
game:GetService("Players").CharacterAutoLoads = true

print("[Setup] Spawn created.")

-- ============================================================
-- 5. Create simple coral structures (Coral Gardens landmark)
-- ============================================================
print("[Setup] Creating coral structures...")

local function createCoral(position, size, color)
    local coral = Instance.new("Part")
    coral.Name = "Coral"
    coral.Size = size
    coral.Position = position
    coral.Anchored = true
    coral.CanCollide = true
    coral.Color = color
    coral.Material = Enum.Material.Plastic

    -- Make it look more organic
    local mesh = Instance.new("BlockMesh")
    mesh.Scale = Vector3.new(1, 1, 1)
    mesh.Parent = coral
    coral.Parent = Workspace
    return coral
end

-- Coral Garden at Y=-10 (5-15m depth)
local coralColors = {
    Color3.fromRGB(255, 100, 100),   -- Red
    Color3.fromRGB(255, 150, 50),    -- Orange
    Color3.fromRGB(255, 100, 200),   -- Pink
    Color3.fromRGB(100, 50, 200),    -- Purple
    Color3.fromRGB(50, 200, 150),    -- Teal
}

local basePos = Vector3.new(0, -10, 0)
for i = 1, 15 do
    local angle = (i / 15) * math.pi * 2
    local radius = 15 + math.random() * 10
    local x = math.cos(angle) * radius
    local z = math.sin(angle) * radius
    local y = basePos.Y + math.random() * 3 - 1.5
    local height = 3 + math.random() * 5
    local color = coralColors[math.random(1, #coralColors)]

    createCoral(
        Vector3.new(x, y, z),
        Vector3.new(2 + math.random(), height, 2 + math.random()),
        color
    )
end

print("[Setup] Coral Gardens created (15 structures).")

-- ============================================================
-- 6. Create simple shipwreck (at Y=-37)
-- ============================================================
print("[Setup] Creating shipwreck...")

local function createShipwreckPart(name, size, position, color)
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

-- Ship hull
local shipPos = Vector3.new(15, -37, -8)
createShipwreckPart("ShipHullBottom", Vector3.new(8, 3, 24), shipPos, Color3.fromRGB(80, 50, 30))
createShipwreckPart("ShipHullTop", Vector3.new(8, 3, 20), shipPos + Vector3.new(0, 3, 0), Color3.fromRGB(70, 45, 25))
createShipwreckPart("ShipBow", Vector3.new(4, 3, 6), shipPos + Vector3.new(0, 0, 15), Color3.fromRGB(60, 35, 20))
-- Interior: dark cabin
local cabinInterior = Instance.new("Part")
cabinInterior.Name = "CabinInterior"
cabinInterior.Size = Vector3.new(6, 4, 6)
cabinInterior.Position = shipPos + Vector3.new(0, 3, -5)
cabinInterior.Anchored = true
cabinInterior.CanCollide = false
cabinInterior.Transparency = 0.95
cabinInterior.Color = Color3.fromRGB(0, 0, 0)
cabinInterior.Parent = Workspace

print("[Setup] Shipwreck created.")

-- ============================================================
-- 7. Create boundary markers at Deep Reef Edge (Y=-47)
-- ============================================================
print("[Setup] Creating zone boundary...")

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
    marker.Color = Color3.fromRGB(255, 50, 50) -- Red warning
    marker.Material = Enum.Material.Neon
    marker.Parent = Workspace

    -- Warning sign
    local sign = Instance.new("Part")
    sign.Name = "WarningSign"
    sign.Size = Vector3.new(2, 1, 0.2)
    sign.Position = Vector3.new(x, boundaryPos.Y + 3, z)
    sign.Anchored = true
    sign.CanCollide = false
    sign.Color = Color3.fromRGB(255, 255, 50)
    sign.Material = Enum.Material.Neon
    sign.Parent = Workspace
end

print("[Setup] Zone boundary created.")

-- ============================================================
-- 8. Insert bootstrap scripts into proper services
-- ============================================================
print("[Setup] Verifying script structure...")

-- The Rojo sync should have already placed:
-- - ReplicatedStorage.Shared, ReplicatedStorage.Knit
-- - ServerScriptService.DataStore2, ServerScriptService.Server
-- - StarterPlayer.StarterPlayerScripts.Client

-- Add a test script to ServerScriptService to verify initialization
local testScript = Instance.new("Script")
testScript.Name = "DeepTide_TestHarness"
testScript.Source = [[
    -- Deep Tide Test Harness
    -- This script verifies all services initialize correctly.

    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local ServerScriptService = game:GetService("ServerScriptService")

    print("===========================================")
    print(" Deep Tide — Test Harness Starting")
    print("===========================================")

    -- Check Shared module
    local sharedSuccess = pcall(function()
        local Shared = require(ReplicatedStorage:WaitForChild("Shared"))
        assert(Shared.Constants.FishSpecies, "FishSpecies missing")
        assert(Shared.Constants.RodTiers, "RodTiers missing")
        assert(Shared.Constants.SuitTiers, "SuitTiers missing")
        assert(Shared.Constants.RarityTiers, "RarityTiers missing")
        assert(Shared.Constants.ZoneConfigs, "ZoneConfigs missing")
        print("[TEST] ✓ Shared module loaded with all 5 constants")
        print("[TEST]   Fish species:", #Shared.Constants.FishSpecies)
        print("[TEST]   Rod tiers:", #Shared.Constants.RodTiers)
        print("[TEST]   Suit tiers:", #Shared.Constants.SuitTiers)
    end)

    if not sharedSuccess then
        warn("[TEST] ✗ Shared module failed to load")
    end

    -- Check Knit
    local knitSuccess = pcall(function()
        local Knit = require(ReplicatedStorage:WaitForChild("Knit"))
        assert(Knit.CreateService, "CreateService missing")
        assert(Knit.CreateController, "CreateController missing")
        assert(Knit.CreateSignal, "CreateSignal missing")
        print("[TEST] ✓ Knit framework loaded")
    end)

    if not knitSuccess then
        warn("[TEST] ✗ Knit framework failed to load")
    end

    -- Check DataStore2
    local ds2Success = pcall(function()
        local DataStore2 = require(ServerScriptService:WaitForChild("DataStore2"))
        assert(type(DataStore2) == "function", "DataStore2 should be callable")
        print("[TEST] ✓ DataStore2 loaded")
    end)

    if not ds2Success then
        warn("[TEST] ✗ DataStore2 failed to load")
    end

    -- Check all services
    local serviceNames = {
        "PlayerDataService",
        "EconomyService",
        "ZoneService",
        "FishingService",
    }

    for _, name in ipairs(serviceNames) do
        local success = pcall(function()
            local module = require(ServerScriptService.Server.Services:WaitForChild(name))
            assert(module.Name == name, "Name mismatch for " .. name)
            print("[TEST] ✓ " .. name .. " loaded")
        end)
        if not success then
            warn("[TEST] ✗ " .. name .. " failed to load")
        end
    end

    print("===========================================")
    print(" Deep Tide — Test Harness Complete")
    print("===========================================")

    -- Start Knit sequence
    print("")
    print("[TEST] Starting Knit services...")
    
    -- The Knit bootstrap is handled by Server.init.server.lua
    -- which is already loaded by the Rojo sync.
]]
testScript.Parent = game:GetService("ServerScriptService")

print("[Setup] Test harness script added to ServerScriptService.")

-- ============================================================
-- Done
-- ============================================================
print("========================================")
print(" Deep Tide — Place Setup Complete!")
print("========================================")
print("")
print("To test:")
print("  1. Press Play in Roblox Studio")
print("  2. You should see the test harness output in the Output window")
print("  3. Character spawns on the boat at surface")
print("  4. Look down to see the coral reef and shipwreck")
print("")
print("Next steps:")
print("  - Gameplay Scripter: Implement NPC fish AI")
print("  - Technical Artist: Add VFX (god rays, bioluminescence, particles)")
print("    → Run atmosphere-setup.lua next for full atmosphere!")
print("  - UI/UX Designer: Build the UI screens")
print("")
