--[[
    init.server.lua
    Deep Tide Studios — Server Bootstrap
    Loads Knit, registers all services (including NPC system), and starts the framework.

    Bootstrap order:
      1. Knit framework
      2. Shared constants (loaded by services)
      3. NPC modules (FishNPC, FishSpawner) — loaded by ZoneService
      4. Services: PlayerData → Economy → Zone → Fishing
      5. Knit.Start() → KnitInit (wiring) → KnitStart (activation)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Wait for Knit to be available
local Knit = require(ReplicatedStorage:WaitForChild("Knit"))

-- Pre-load Shared (validates Rojo sync)
local Shared = require(ReplicatedStorage:WaitForChild("Shared"))
print("[Server] Shared module loaded —", #Shared.Constants.FishSpecies, "fish species,", #Shared.Constants.RodTiers, "rod tiers")

-- Pre-load NPC system (ensures FishSignals, FishNPC, FishSpawner are cached)
local Server = script.Parent -- ServerScriptService.Server
local NPC = Server:WaitForChild("NPC")
local FishSignals = require(ReplicatedStorage.Shared.NPC:WaitForChild("FishSignals"))
local FishNPC = require(NPC:WaitForChild("FishNPC"))
local FishSpawner = require(NPC:WaitForChild("FishSpawner"))
print("[Server] NPC system loaded — FishSignals, FishNPC, FishSpawner")

-- Load all services (ZoneService will use pre-loaded FishSpawner)
local Services = Server:WaitForChild("Services")
local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))
local EconomyService = require(Services:WaitForChild("EconomyService"))
local ZoneService = require(Services:WaitForChild("ZoneService"))
local FishingService = require(Services:WaitForChild("FishingService"))
local ChallengeService = require(Services:WaitForChild("ChallengeService"))

-- Start Knit
Knit.Start():andThen(function()
    print("========================================")
    print(" Deep Tide Studios — Server Initialized")
    print("========================================")
    print(" Services:")
    print("   - PlayerDataService   (data persistence + Dive Pass)")
    print("   - EconomyService      (transactions)")
    print("   - ZoneService         (zones + FishSpawner)")
    print("   - FishingService      (authoritative fishing + Sonar)")
    print("   - ChallengeService    (daily challenges)")
    print("   - FishNPC system      (", FishSignals.FishState and "10-state FSM" or "loaded", ")")
    print("========================================")
end):catch(function(err)
    warn("[DeepTide] Failed to start server:", err)
end)
