--[[
	ZoneService.lua
	Deep Tide Studios — Server Service
	Manages zone state, fish population via FishSpawner, spawning, and zone transitions.
	Handles per-zone fish population, spawn RNG, and population management.
]]

local Knit = require(game:GetService("ReplicatedStorage"):WaitForChild("Knit"))
local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))
local FishSpawner = require(game:GetService("ServerScriptService"):WaitForChild("Server"):WaitForChild("NPC"):WaitForChild("FishSpawner"))

local ZoneService = Knit.CreateService({
	Name = "ZoneService",
	Client = {
		GetCurrentZone = Knit.CreateSignal(),    -- (player) -> zoneData
		ZoneChanged = Knit.CreateSignal(),       -- (zoneKey) -> nil
		FishSpawned = Knit.CreateSignal(),       -- (fishData) -> nil
		FishDespawned = Knit.CreateSignal(),     -- (fishId) -> nil
	},
})

-- ============================================================
-- Service state
-- ============================================================
ZoneService._zones = {}         -- { [zoneKey] = ZoneState }
ZoneService._playerZones = {}   -- { [player] = zoneKey }
ZoneService._spawners = {}      -- { [zoneKey] = FishSpawner }

-- Zone state structure:
-- {
--   Config = ZoneConfig,
--   Spawner = FishSpawner,
--   Population = <current count>,
--   LastRespawnTime = tick(),
--   LastVisitTime = { [landmarkName] = tick() },
--   LegendaryAlive = false,
-- }

-- ============================================================

function ZoneService:KnitStart()
	-- Initialize all MVP zones
	local mvpZones = Shared.Constants.ZoneConfigs.GetMVPZones()
	for key, config in pairs(mvpZones) do
		-- Create FishSpawner for this zone
		local spawner = FishSpawner.new(key, config, Knit)

		self._zones[key] = {
			Config = config,
			Spawner = spawner,
			Population = 0,
			LastRespawnTime = tick(),
			LastVisitTime = {},
			LegendaryAlive = false,
		}
		self._spawners[key] = spawner
		print(string.format("[ZoneService] Initialized zone: %s with FishSpawner", config.Name))
	end

	-- Start population loop
	self:_startPopulationLoop()

	-- Start spawner update loop (handles despawns, day/night, etc.)
	self:_startSpawnerUpdateLoop()

	print("[ZoneService] Started — managing zones with FishSpawner")
end

function ZoneService:KnitInit()
	-- Track players entering/leaving zones
	-- In MVP, all players are in SunkenShallows
	game:GetService("Players").PlayerAdded:Connect(function(player)
		self._playerZones[player] = "SunkenShallows"
		self.Client.ZoneChanged:Fire(player, "SunkenShallows")
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		self._playerZones[player] = nil
	end)
end

-- ============================================================
-- Zone queries
-- ============================================================

function ZoneService:GetPlayerZone(player)
	return self._playerZones[player] or "SunkenShallows"
end

function ZoneService:CanEnterZone(player, zoneKey)
	if zoneKey ~= "KelpForest" then return zoneKey == "SunkenShallows" end
	local data = self.Services.PlayerDataService:GetData(player)
	if not data then return false, "Player data not loaded" end
	local config = Shared.Constants.ZoneConfigs.GetByKey(zoneKey)
	local req = config and config.UnlockRequirement or { RequiredRod = "CoralRod", TotalCatches = 50 }
	if not data.Gear.OwnedRods[req.RequiredRod] then return false, "Coral Rod required" end
	if (data.Progression.TotalCatches or 0) < req.TotalCatches then return false, "Catch 50 fish required" end
	return true
end

function ZoneService:SetPlayerZone(player, zoneKey)
	local allowed, reason = self:CanEnterZone(player, zoneKey)
	if not allowed then return false, reason end
	self._playerZones[player] = zoneKey
	self.Client.ZoneChanged:Fire(player, zoneKey)
	return true
end

function ZoneService:GetZoneAtDepth(depth)
	local config = Shared.Constants.ZoneConfigs.GetZoneAtDepth(math.abs(depth))
	return config and config.Key or "SunkenShallows"
end

function ZoneService:GetZoneState(zoneKey)
	return self._zones[zoneKey]
end

function ZoneService:GetZoneConfig(zoneKey)
	local zone = self._zones[zoneKey]
	return zone and zone.Config
end

-- ============================================================
-- Spawner access (for FishingService and other services)
-- ============================================================

function ZoneService:GetSpawner(zoneKey)
	return self._spawners[zoneKey]
end

-- ============================================================
-- Population management (GDD 8.6)
-- ============================================================

function ZoneService:_startPopulationLoop()
	while true do
		task.wait(1)

		for zoneKey, zone in pairs(self._zones) do
			local config = zone.Config
			local elapsed = tick() - zone.LastRespawnTime

			if elapsed >= config.Population.RespawnIntervalSeconds then
				self:_respawnFish(zoneKey, zone, config)
				zone.LastRespawnTime = tick()
			end
		end
	end
end

-- ============================================================
-- Spawner update loop (runs fish maintenance tasks)
-- ============================================================
function ZoneService:_startSpawnerUpdateLoop()
	task.spawn(function()
		while true do
			task.wait(1)

			for zoneKey, spawner in pairs(self._spawners) do
				spawner:Update(1)
				-- Sync population count from spawner
				local zone = self._zones[zoneKey]
				if zone then
					zone.Population = spawner:GetPopulation()
				end
			end
		end
	end)
end

function ZoneService:_respawnFish(zoneKey, zone, config)
	local spawner = zone.Spawner
	if not spawner then return end

	local shouldRespawn, deficit = spawner:ShouldRespawn()
	if not shouldRespawn then
		return
	end

	-- Calculate luck bonus (highest among players in this zone)
	local luckBonus = self:_getMaxLuckBonus(zoneKey)

	-- Run the spawner's respawn cycle
	spawner:RunRespawnCycle(luckBonus)

	-- Sync legendary state
	zone.LegendaryAlive = spawner._legendaryAlive
	zone.Population = spawner:GetPopulation()
end

-- ============================================================
-- Bobber registration (called by FishingService)
-- ============================================================
function ZoneService:RegisterBobber(playerId, position, zoneKey)
	zoneKey = zoneKey or "SunkenShallows"
	local spawner = self._spawners[zoneKey]
	if spawner then
		spawner:RegisterBobber(playerId, position)
	end
end

function ZoneService:UnregisterBobber(playerId, zoneKey)
	zoneKey = zoneKey or "SunkenShallows"
	local spawner = self._spawners[zoneKey]
	if spawner then
		spawner:UnregisterBobber(playerId)
	end
end

-- ============================================================
-- Fish query (for FishingService integration)
-- ============================================================
function ZoneService:GetFishNearBobber(bobberPosition, maxRadius, zoneKey)
	zoneKey = zoneKey or "SunkenShallows"
	local spawner = self._spawners[zoneKey]
	if spawner then
		return spawner:GetFishNearBobber(bobberPosition, maxRadius)
	end
	return {}
end

-- ============================================================
-- Legacy despawn (still needed for FishingService cleanup)
-- ============================================================
function ZoneService:DespawnFish(zoneKey, fishId)
	local spawner = self._spawners[zoneKey]
	if spawner then
		spawner:DespawnFish(fishId)
	end

	local zone = self._zones[zoneKey]
	if zone then
		zone.Population = spawner and spawner:GetPopulation() or math.max(0, (zone.Population or 1) - 1)
		self.Client.FishDespawned:FireAll(fishId)
	end
end

-- ============================================================
-- Shipwreck visit tracking
-- ============================================================
function ZoneService:MarkShipwreckVisited(zoneKey)
	zoneKey = zoneKey or "SunkenShallows"
	local zone = self._zones[zoneKey]
	if zone then
		zone.LastVisitTime["Shipwreck"] = tick()
	end
	local spawner = self._spawners[zoneKey]
	if spawner then
		spawner:OnShipwreckVisited()
	end
end

-- ============================================================
-- Luck calculation
-- ============================================================

function ZoneService:_getMaxLuckBonus(zoneKey)
	local maxLuck = 0

	for player, zKey in pairs(self._playerZones) do
		if zKey == zoneKey then
			local data = self.Services.PlayerDataService:GetData(player)
			if data then
				local rodKey = data.Gear.EquippedRod
				local rod = Shared.Constants.RodTiers.GetByKey(rodKey)
				if rod then
					maxLuck = math.max(maxLuck, rod.LuckBonus)
				end
			end
		end
	end

	return maxLuck
end

return ZoneService
