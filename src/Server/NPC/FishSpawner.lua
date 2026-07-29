--[[
	FishSpawner.lua
	Deep Tide Studios — Server Fish Spawner
	Manages fish population, spawn/despawn cycle, patrol waypoint generation,
	schooling behavior, rare spawn conditions, and integration with ZoneService.

	Runs as a module used by ZoneService. Each zone gets one FishSpawner instance.
	Phase 2: Extended for Kelp Forest zone with 8 new species, sonar support,
	apex presence broadcasts, ink burst events, bait placement, tentacle hazards.
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("Shared"))
local FishSpecies = Shared.Constants.FishSpecies
local ZoneConfigs = Shared.Constants.ZoneConfigs
local FishSignals = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NPC"):WaitForChild("FishSignals"))
local FishNPC = require(script.Parent:WaitForChild("FishNPC"))

local FishSpawner = {}
FishSpawner.__index = FishSpawner

-- ============================================================
-- Constructor
-- ============================================================
function FishSpawner.new(zoneKey, zoneConfig, knitRef)
	local self = setmetatable({}, FishSpawner)

	self.ZoneKey = zoneKey
	self.ZoneConfig = zoneConfig
	self._knit = knitRef

	-- Active fish
	self._fish = {}              -- { [fishId] = FishNPC }
	self._population = 0
	self._legendaryCount = 0     -- Phase 2: track multiple legendaries (up to 2 in Kelp)
	self._legendaryCap = zoneConfig.Population.LegendaryCap or 1

	-- Patrol waypoints cache
	self._landmarkWaypoints = {}

	-- Active bobber positions
	self._activeBobbers = {}

	-- Player last-known positions
	self._playerPositions = {}

	-- Rare spawn tracking
	self._lastRespawnTime = tick()
	self._lastShipwreckVisit = 0
	self._serverStartTime = tick()
	self._serverUptimeBonus = 0

	-- Day cycle tracking
	self._dayCycleLength = zoneConfig.SpawnConditions and zoneConfig.SpawnConditions.DayCycleMinutes
		and zoneConfig.SpawnConditions.DayCycleMinutes * 60 or 1200
	self._isNight = false

	-- Angler dim state tracking
	self._dimmedAnglers = {}

	-- Phase 2: Kelp Forest specific tracking
	self._leviathanSpawned = false
	self._voidJellyfishSpawned = false
	self._kelpSerpentSpawned = false
	self._lastVoidJellyfishSpawnTime = 0
	self._lastKelpSerpentSpawnTime = 0
	self._lastApexBroadcastTime = 0
	self._kelpSerpent = nil       -- reference to the single Kelp Serpent NPC

	-- Sonar tracking (for fish to know if sonar is active nearby)
	self._activeSonarPlayers = {} -- { [playerId] = { position, timestamp } }

	-- Active bait positions (Grotto Crab)
	self._activeBait = {}         -- { [playerId] = { position, timestamp } }

	-- Zone active time tracking
	self._zoneActiveTime = tick()

	-- Generate waypoints
	self:_generateAllWaypoints()

	return self
end

-- ============================================================
-- Waypoint generation — 3-6 per landmark
-- ============================================================
function FishSpawner:_generateAllWaypoints()
	for _, landmark in ipairs(self.ZoneConfig.Landmarks) do
		local waypointCount = 3 + math.random(0, 3)
		local waypoints = {}

		local center = landmark.CenterPosition
		local radius = landmark.Radius

		for i = 1, waypointCount do
			local angle = (i / waypointCount) * math.pi * 2 + math.random() * 0.5
			local dist = radius * (0.3 + math.random() * 0.7)
			local wp = Vector3.new(
				center.X + math.cos(angle) * dist,
				center.Y + math.random() * 6 - 3,
				center.Z + math.sin(angle) * dist
			)
			table.insert(waypoints, wp)
		end

		self._landmarkWaypoints[landmark.Name] = waypoints
	end
end

function FishSpawner:GetWaypointsForLandmark(landmarkName)
	return self._landmarkWaypoints[landmarkName] or {}
end

function FishSpawner:GetWaypointsForSpecies(species)
	for _, landmark in ipairs(self.ZoneConfig.Landmarks) do
		if landmark.PrimaryFish then
			for _, fishKey in ipairs(landmark.PrimaryFish) do
				if fishKey == species.Key then
					return self._landmarkWaypoints[landmark.Name] or {}
				end
			end
		end
	end
	local firstLandmark = self.ZoneConfig.Landmarks[1]
	return firstLandmark and self._landmarkWaypoints[firstLandmark.Name] or {}
end

-- ============================================================
-- Spawn a single fish (extended for Phase 2)
-- ============================================================
function FishSpawner:SpawnFish(species)
	local population = self.ZoneConfig.Population
	local maxPop = population.MaxConcurrentFish

	if self._population >= maxPop then
		return nil
	end

	-- Check legendary cap (Phase 2: supports multiple up to LegendaryCap)
	if species.Rarity == "Legendary" then
		if self._legendaryCount >= self._legendaryCap then
			return nil
		end
	end

	-- Generate spawn position
	local spawnPos = self:_getSpawnPosition(species)

	-- Check rare spawn conditions (extended for Phase 2)
	if species.Rarity == "Legendary" then
		if not self:_canSpawnLegendary(species) then
			return nil
		end
	elseif species.Rarity == "Rare" then
		if species.Behavior == "Ambush" then
			-- Sunken Angler conditions unchanged from MVP
		end
	end

	-- Create the NPC
	local waypoints = self:GetWaypointsForSpecies(species)
	local fish = FishNPC.new(species, spawnPos, {
		Waypoints = waypoints,
		Zone = self.ZoneKey,
	})

	-- Set zone-specific data
	fish:SetZone(self.ZoneKey)

	-- Kelp Serpent: set figure-eight patrol center
	if species.Behavior == "ApexRoaming" then
		fish:SetApexCenter(spawnPos)
		self._kelpSerpent = fish
	end

	-- Create physical model
	local model = self:_createFishModel(species, spawnPos)
	fish:Initialize(model, self)

	-- Store
	self._fish[fish.Id] = fish
	self._population = self._population + 1

	-- Track legendary
	if species.Rarity == "Legendary" then
		self._legendaryCount = self._legendaryCount + 1
		if species.Key == "VoidJellyfish" then
			self._voidJellyfishSpawned = true
			self._lastVoidJellyfishSpawnTime = tick()
		elseif species.Key == "KelpSerpent" then
			self._kelpSerpentSpawned = true
			self._lastKelpSerpentSpawnTime = tick()
			-- Broadcast "The water grows cold..." zone-wide
			self:_broadcastApexSpawn(fish, spawnPos)
		end
	end

	-- Rare spawn bloom notification
	if species.Rarity == "Rare" or species.Rarity == "Legendary" then
		self:_fireRareSpawnBloom(spawnPos, species)
	end

	-- Auto-despawn timer for special fish
	if species.Key == "AbyssalLeviathan" then
		fish:SetDespawnTimer(60)
		self._leviathanSpawned = true
	elseif species.Key == "KelpSerpent" then
		fish:SetDespawnTimer(species.DespawnTimer or 600)
	elseif species.Key == "VoidJellyfish" then
		fish:SetDespawnTimer(species.DespawnTimer or 480)
	end

	self:_notifyFishSpawned(fish)

	return fish
end

function FishSpawner:DespawnFish(fishOrId)
	local fish = nil
	local fishId = nil

	if type(fishOrId) == "table" then
		fish = fishOrId
		fishId = fish.Id
	else
		fishId = fishOrId
		fish = self._fish[fishId]
	end

	if not fish then return end

	if fish.Species.Rarity == "Legendary" then
		self._legendaryCount = math.max(0, self._legendaryCount - 1)
		if fish.Species.Key == "VoidJellyfish" then
			self._voidJellyfishSpawned = false
		elseif fish.Species.Key == "KelpSerpent" then
			self._kelpSerpentSpawned = false
			self._kelpSerpent = nil
		end
	end

	self._dimmedAnglers[fishId] = nil

	fish:Destroy()
	self._fish[fishId] = nil
	self._population = math.max(0, self._population - 1)

	self:_notifyFishDespawned(fishId)
end

-- ============================================================
-- Spawn a school
-- ============================================================
function FishSpawner:SpawnSchool(species, leaderFish)
	local schoolSize = 4 + math.random(0, 4)
	local school = {}

	if leaderFish then
		table.insert(school, leaderFish)
	else
		local leader = self:SpawnFish(species)
		if leader then
			table.insert(school, leader)
		else
			return school
		end
	end

	local leader = school[1]
	local leaderPos = leader.Position

	for i = 2, schoolSize do
		local theta = math.random() * math.pi * 2
		local phi = math.random() * math.pi
		local radius = 2 + math.random() * 4
		local offset = Vector3.new(
			math.sin(phi) * math.cos(theta) * radius,
			math.sin(phi) * math.sin(theta) * radius,
			math.cos(phi) * radius
		)
		local followerPos = leaderPos + offset

		local followerFish = FishNPC.new(species, followerPos, {
			Waypoints = self:GetWaypointsForSpecies(species),
			Zone = self.ZoneKey,
		})
		local model = self:_createFishModel(species, followerPos)
		followerFish:Initialize(model, self)

		followerFish._isSchoolFollower = true
		followerFish._schoolLeader = leader

		self._fish[followerFish.Id] = followerFish
		self._population = self._population + 1
		table.insert(school, followerFish)
	end

	leader._school = school
	leader._isSchoolLeader = true

	return school
end

-- ============================================================
-- Population check
-- ============================================================
function FishSpawner:ShouldRespawn()
	local maxPop = self.ZoneConfig.Population.MaxConcurrentFish
	local deficit = maxPop - self._population
	return deficit > 0, deficit
end

-- ============================================================
-- Respawn cycle: fill population to cap (zone-aware)
-- ============================================================
function FishSpawner:RunRespawnCycle(luckBonus)
	luckBonus = luckBonus or 0
	local maxPop = self.ZoneConfig.Population.MaxConcurrentFish
	local deficit = maxPop - self._population

	if deficit <= 0 then return end

	-- Get spawn table for this zone
	local spawnTable, totalWeight = FishSpecies.GetSpawnTable(luckBonus, self.ZoneKey)

	if totalWeight <= 0 then return end

	local spawnCount = math.min(deficit, 3)

	for i = 1, spawnCount do
		local roll = math.random() * totalWeight
		local selectedSpecies = nil

		for _, entry in ipairs(spawnTable) do
			if roll <= entry.CumulativeWeight then
				selectedSpecies = entry.Species
				break
			end
		end

		if selectedSpecies then
			if selectedSpecies.Rarity == "Legendary" and self._legendaryCount >= self._legendaryCap then
				-- Skip
			elseif selectedSpecies.Schooling then
				local remaining = maxPop - self._population
				if remaining >= 3 then
					self:SpawnSchool(selectedSpecies)
				else
					self:SpawnFish(selectedSpecies)
				end
			else
				self:SpawnFish(selectedSpecies)
			end
		end
	end

	-- Update server uptime bonus
	if self.ZoneConfig.SpawnConditions and self.ZoneConfig.SpawnConditions.ServerUptimeBonus then
		self._serverUptimeBonus = math.floor((tick() - self._serverStartTime)
			/ self.ZoneConfig.SpawnConditions.ServerUptimeInterval)
			* self.ZoneConfig.SpawnConditions.ServerUptimeBonus
	end
end

-- ============================================================
-- Rare spawn conditions (extended Phase 2)
-- ============================================================
function FishSpawner:_canSpawnLegendary(species)
	if species.Key == "SpectralRay" then
		if self._legendaryCount >= self._legendaryCap then return false end
		return self:_isNightTime()
	end

	if species.Key == "AbyssalLeviathan" then
		if self._leviathanSpawned then return false end
		return self._population < 15
	end

	-- Phase 2: Void Jellyfish
	if species.Key == "VoidJellyfish" then
		if self._voidJellyfishSpawned then return false end
		local spawnConds = self.ZoneConfig.SpawnConditions
			and self.ZoneConfig.SpawnConditions.VoidJellyfish
		if not spawnConds then return true end

		-- Must have min server population
		local playerCount = #Players:GetPlayers()
		if playerCount < (spawnConds.MinServerPopulation or 10) then return false end

		-- Zone must be active for minimum time
		local zoneAge = tick() - self._zoneActiveTime
		if zoneAge < (spawnConds.MinZoneActiveMinutes or 5) * 60 then return false end

		-- Respawn cooldown
		if self._lastVoidJellyfishSpawnTime > 0 then
			local cooldown = spawnConds.RespawnCooldownSeconds or 120
			if (tick() - self._lastVoidJellyfishSpawnTime) < cooldown then return false end
		end

		return true
	end

	-- Phase 2: Kelp Serpent
	if species.Key == "KelpSerpent" then
		if self._kelpSerpentSpawned then return false end
		local spawnConds = self.ZoneConfig.SpawnConditions
			and self.ZoneConfig.SpawnConditions.KelpSerpent
		if not spawnConds then return true end

		-- Respawn cooldown
		if self._lastKelpSerpentSpawnTime > 0 then
			local cooldown = spawnConds.RespawnCooldownSeconds or 300
			if (tick() - self._lastKelpSerpentSpawnTime) < cooldown then return false end
		end

		-- Base spawn chance with player count bonus
		local baseChance = spawnConds.SpawnChancePerDayCycle or 0.03
		local playerBonus = #Players:GetPlayers() * (spawnConds.PlayerCountBonus or 0.005)
		playerBonus = math.min(playerBonus, spawnConds.MaxPlayerBonus or 0.125)
		local totalChance = baseChance + playerBonus

		return math.random() < totalChance
	end

	return true
end

function FishSpawner:_isNightTime()
	local clockTime = Lighting.ClockTime
	return clockTime >= 18 or clockTime < 6
end

-- ============================================================
-- Spawn position selection (extended for Phase 2 landmarks)
-- ============================================================
function FishSpawner:_getSpawnPosition(species)
	-- MVP: Abyssal Leviathan
	if species.Key == "AbyssalLeviathan" then
		for _, landmark in ipairs(self.ZoneConfig.Landmarks) do
			if landmark.Name == "Deep Reef Edge" then
				return self:_randomPosInLandmark(landmark)
			end
		end
	end

	-- Phase 2: Frilled Seahorse — only near kelp stalk positions
	if species.Key == "FrilledSeahorse" then
		local preferred = self:_findLandmark("Kelp Canopy")
		if preferred then
			return self:_randomPosInLandmark(preferred)
		end
	end

	-- Phase 2: Grotto Crab — only in Rocky Grotto
	if species.Key == "GrottoCrab" then
		local preferred = self:_findLandmark("Rocky Grotto")
		if preferred then
			return self:_randomPosInLandmark(preferred)
		end
	end

	-- Phase 2: Lantern Squid — prefers The Clearing
	if species.Key == "LanternSquid" then
		local preferred = self:_findLandmark("The Clearing")
		if preferred then
			return self:_randomPosInLandmark(preferred)
		end
	end

	-- Phase 2: Kelp Serpent — zone-wide, prefer Abyss Edge
	if species.Key == "KelpSerpent" then
		local preferred = self:_findLandmark("Abyss Edge") or self:_findLandmark("The Clearing")
		if preferred then
			return self:_randomPosInLandmark(preferred)
		end
	end

	-- Find preferred landmark for this species
	local preferredLandmark = nil
	for _, landmark in ipairs(self.ZoneConfig.Landmarks) do
		if landmark.PrimaryFish then
			for _, fishKey in ipairs(landmark.PrimaryFish) do
				if fishKey == species.Key then
					preferredLandmark = landmark
					break
				end
			end
		end
		if preferredLandmark then break end
	end

	if not preferredLandmark then
		preferredLandmark = self.ZoneConfig.Landmarks[math.random(1, #self.ZoneConfig.Landmarks)]
	end

	-- Specific spawn positions for Angler
	if species.Behavior == "Ambush" and preferredLandmark.AnglerSpawnPoints then
		local points = preferredLandmark.AnglerSpawnPoints
		return points[math.random(1, #points)]
	end

	return self:_randomPosInLandmark(preferredLandmark)
end

function FishSpawner:_findLandmark(name)
	for _, landmark in ipairs(self.ZoneConfig.Landmarks) do
		if landmark.Name == name then return landmark end
	end
	return nil
end

function FishSpawner:_randomPosInLandmark(landmark)
	local center = landmark.CenterPosition
	local angle = math.random() * math.pi * 2
	local distance = math.random() * landmark.Radius
	return center + Vector3.new(
		math.cos(angle) * distance,
		math.random() * 5 - 2.5,
		math.sin(angle) * distance
	)
end

-- ============================================================
-- Model creation — extended for Phase 2 species sizes
-- ============================================================
function FishSpawner:_createFishModel(species, position)
	local scale = species.Scale or { Min = 1, Max = 1 }
	local sizeScale = scale.Min + math.random() * (scale.Max - scale.Min)

	-- Legendary scaling
	if species.Key == "AbyssalLeviathan" then
		sizeScale = sizeScale * (3 + math.random() * 2)
	elseif species.Key == "KelpSerpent" then
		sizeScale = sizeScale * (3.5 + math.random() * 1.5) -- 3.5-5x
	elseif species.Key == "VoidJellyfish" then
		sizeScale = sizeScale * (2.5 + math.random() * 1.0) -- 2.5-3.5x
	elseif species.Rarity == "Legendary" then
		sizeScale = sizeScale * 2
	end

	local model = Instance.new("Model")
	model.Name = species.Name .. "_" .. HttpService:GenerateGUID(false)

	-- Root part (body)
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2 * sizeScale, 0.8 * sizeScale, 0.6 * sizeScale)
	body.Position = position
	body.Anchored = false
	body.CanCollide = false
	body.Material = Enum.Material.SmoothPlastic
	body.Color = species.GlowColor or Color3.fromRGB(150, 150, 150)
	body.Transparency = (species.Key == "SpectralRay") and 0.5 or 0
	body.Parent = model

	-- Tail
	local tail = Instance.new("Part")
	tail.Name = "Tail"
	tail.Size = Vector3.new(1.2 * sizeScale, 0.5 * sizeScale, 0.3 * sizeScale)
	tail.Position = position + Vector3.new(-1.5 * sizeScale, 0, 0)
	tail.Anchored = false
	tail.CanCollide = false
	tail.Material = Enum.Material.SmoothPlastic
	tail.Color = body.Color
	tail.Transparency = body.Transparency
	tail.Parent = model

	-- Weld
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = tail
	weld.Parent = tail

	-- Bioluminescence
	if species.Bioluminescent and species.GlowColor then
		local glowLight = Instance.new("PointLight")
		glowLight.Name = "BioluminescentGlow"
		glowLight.Brightness = (species.Rarity == "Legendary") and 2 or 0.5
		glowLight.Range = (species.Rarity == "Legendary") and 15 or 6
		glowLight.Color = species.GlowColor
		glowLight.Shadows = false
		glowLight.Parent = body

		-- Unique effects per species
		if species.Behavior == "Ambush" then
			local lureLight = Instance.new("PointLight")
			lureLight.Name = "Lure"
			lureLight.Brightness = 1.5
			lureLight.Range = 8
			lureLight.Color = species.GlowColor
			lureLight.Shadows = false
			lureLight.Parent = body

			local lureOrb = Instance.new("Part")
			lureOrb.Name = "LureOrb"
			lureOrb.Size = Vector3.new(0.4, 0.4, 0.4)
			lureOrb.Position = body.Position + Vector3.new(1.5 * sizeScale, 0.5 * sizeScale, 0)
			lureOrb.Anchored = false
			lureOrb.CanCollide = false
			lureOrb.Material = Enum.Material.Neon
			lureOrb.Color = species.GlowColor
			lureOrb.Shape = Enum.PartType.Ball
			lureOrb.Parent = model

			local lureWeld = Instance.new("WeldConstraint")
			lureWeld.Part0 = body
			lureWeld.Part1 = lureOrb
			lureWeld.Parent = lureOrb
		end

		if species.Key == "AbyssalLeviathan" then
			local auraLight = Instance.new("PointLight")
			auraLight.Name = "LeviathanAura"
			auraLight.Brightness = 5
			auraLight.Range = 30
			auraLight.Color = species.GlowColor or Color3.fromRGB(255, 100, 50)
			auraLight.Shadows = false
			auraLight.Parent = body

			local body2 = Instance.new("Part")
			body2.Name = "Body2"
			body2.Size = Vector3.new(1.8 * sizeScale, 0.7 * sizeScale, 0.5 * sizeScale)
			body2.Position = position + Vector3.new(-2 * sizeScale, 0, 0)
			body2.Anchored = false
			body2.CanCollide = false
			body2.Material = Enum.Material.SmoothPlastic
			body2.Color = body.Color
			body2.Transparency = body.Transparency
			body2.Parent = model

			local bodyWeld = Instance.new("WeldConstraint")
			bodyWeld.Part0 = body
			bodyWeld.Part1 = body2
			bodyWeld.Parent = body2
		end

		-- Kelp Serpent: additional bioluminescent lure spots
		if species.Key == "KelpSerpent" then
			for i = 1, 4 do
				local spot = Instance.new("PointLight")
				spot.Name = "LureSpot_" .. i
				spot.Brightness = 2
				spot.Range = 12
				spot.Color = species.GlowColor or Color3.fromRGB(255, 80, 30)
				spot.Shadows = false
				spot.Parent = body
			end
		end

		-- Void Jellyfish: cascading pulse light
		if species.Key == "VoidJellyfish" then
			for i = 1, 3 do
				local node = Instance.new("PointLight")
				node.Name = "TentacleNode_" .. i
				node.Brightness = 1.5
				node.Range = 10
				node.Color = species.GlowColor or Color3.fromRGB(100, 150, 255)
				node.Shadows = false
				node.Parent = body
			end
		end
	end

	model.PrimaryPart = body
	model.Parent = workspace

	return model
end

-- ============================================================
-- Bobber registration
-- ============================================================
function FishSpawner:RegisterBobber(playerId, position)
	self._activeBobbers[playerId] = {
		position = position,
		castTime = tick(),
	}
end

function FishSpawner:UnregisterBobber(playerId)
	if self._activeBobbers[playerId] then
		self._activeBobbers[playerId].stale = true
	end
end

function FishSpawner:GetNearbyBobbers(fishPosition, maxRadius)
	local nearby = {}
	local now = tick()

	for playerId, bobber in pairs(self._activeBobbers) do
		if not bobber.stale and now - bobber.castTime < 30 then
			local dist = (bobber.position - fishPosition).Magnitude
			if dist <= maxRadius then
				table.insert(nearby, {
					position = bobber.position,
					playerId = playerId,
					distance = dist,
				})
			end
		end
	end

	table.sort(nearby, function(a, b) return a.distance < b.distance end)
	return nearby
end

-- ============================================================
-- Player position tracking
-- ============================================================
function FishSpawner:UpdatePlayerPosition(playerId, position)
	self._playerPositions[playerId] = position
end

function FishSpawner:GetNearbyPlayers(fishPosition, maxRadius)
	local nearby = {}
	for playerId, pos in pairs(self._playerPositions) do
		local dist = (pos - fishPosition).Magnitude
		if dist <= maxRadius then
			table.insert(nearby, {
				playerId = playerId,
				position = pos,
				distance = dist,
			})
		end
	end
	return nearby
end

-- ============================================================
-- Find fish near a bobber
-- ============================================================
function FishSpawner:GetFishNearBobber(bobberPosition, maxRadius)
	local nearby = {}

	for fishId, fish in pairs(self._fish) do
		if not fish:IsHooked() then
			local dist = (fish.Position - bobberPosition).Magnitude
			local checkRadius = maxRadius or fish:GetInterestRadius()

			if dist <= checkRadius then
				table.insert(nearby, {
					Fish = fish,
					FishId = fishId,
					Distance = dist,
					State = fish:GetState(),
					IsBiteReady = fish:IsBiteReady(),
					Species = fish.Species,
				})
			end
		end
	end

	table.sort(nearby, function(a, b)
		if a.IsBiteReady ~= b.IsBiteReady then
			return a.IsBiteReady
		end
		return a.Distance < b.Distance
	end)

	return nearby
end

-- ============================================================
-- State change callback from FishNPC
-- ============================================================
function FishSpawner:OnFishStateChanged(fish, oldState, newState)
	-- School behavior
	if fish._isSchoolLeader and newState == FishSignals.FishState.Fleeing and fish._school then
		for _, follower in ipairs(fish._school) do
			if follower ~= fish and follower._state ~= FishSignals.FishState.Fleeing
				and follower._state ~= FishSignals.FishState.Despawning then
				follower:_transitionTo(FishSignals.FishState.Fleeing, {
					threatPosition = fish.Position,
				})
			end
		end
	end

	if fish._isSchoolFollower and newState == FishSignals.FishState.Hooked and fish._schoolLeader then
		local leader = fish._schoolLeader
		if leader._state ~= FishSignals.FishState.Fleeing
			and leader._state ~= FishSignals.FishState.Despawning then
			leader:_transitionTo(FishSignals.FishState.Fleeing, {
				threatPosition = fish.Position,
			})
		end
		if leader._school then
			for _, follower in ipairs(leader._school) do
				if follower ~= fish and follower ~= leader
					and follower._state ~= FishSignals.FishState.Fleeing
					and follower._state ~= FishSignals.FishState.Despawning then
					follower:_transitionTo(FishSignals.FishState.Fleeing, {
						threatPosition = fish.Position,
					})
				end
			end
		end
	end

	-- Phase 2: Kelp Serpent apex — all fish within alert radius flee
	if fish.Species.ApexPresence and (newState == FishSignals.FishState.Patrol or newState == FishSignals.FishState.Idle) then
		self:_alertFishInRadius(fish.Position, fish.Species.ApexAlertRadius or 40, fish)
	end

	-- Track despawns
	if newState == FishSignals.FishState.Despawning then
		if fish.Species.Rarity == "Legendary" then
			self._legendaryCount = math.max(0, self._legendaryCount - 1)
		end
		if fish.Species.Key == "AbyssalLeviathan" then
			self._leviathanSpawned = false
		elseif fish.Species.Key == "VoidJellyfish" then
			self._voidJellyfishSpawned = false
		elseif fish.Species.Key == "KelpSerpent" then
			self._kelpSerpentSpawned = false
			self._kelpSerpent = nil
		end
	end
end

-- ============================================================
-- Phase 2: Apex presence alert
-- ============================================================
function FishSpawner:_alertFishInRadius(apexPosition, radius, apexFish)
	for _, fish in pairs(self._fish) do
		if fish ~= apexFish then
			local dist = (fish.Position - apexPosition).Magnitude
			if dist <= radius then
				if fish.OnApexNearby then
					fish:OnApexNearby(apexPosition)
				end
			end
		end
	end
end

function FishSpawner:OnApexPresence(apexFish, position, radius)
	-- Alert all fish in radius
	self:_alertFishInRadius(position, radius, apexFish)

	-- Broadcast to zone
	self:_fireApexBroadcast(position)
end

function FishSpawner:_broadcastApexSpawn(fish, position)
	-- Fire zone-wide "The water grows cold..." message
	if self._knit then
		pcall(function()
			local signal = self._knit.GetSignal and self._knit.GetSignal("ApexSpawned")
			if signal then
				signal:Fire(position, fish.Species.Name, fish.Species.Key)
			end
		end)
	end
end

function FishSpawner:_fireApexBroadcast(position)
	local now = tick()
	if now - self._lastApexBroadcastTime < 5 then return end -- throttle
	self._lastApexBroadcastTime = now

	if self._knit then
		pcall(function()
			local signal = self._knit.GetSignal and self._knit.GetSignal("ApexPresenceWarning")
			if signal then
				signal:Fire(position, "The water grows cold...")
			end
		end)
	end
end

-- ============================================================
-- Phase 2: Ink burst broadcast
-- ============================================================
function FishSpawner:OnInkBurst(fish, position, radius, duration)
	-- Broadcast ink burst to nearby clients via Knit signal
	if self._knit then
		pcall(function()
			local signal = self._knit.GetSignal and self._knit.GetSignal("InkBurst")
			if signal then
				signal:Fire(fish.Id, position, radius, duration)
			end
		end)
	end
end

-- ============================================================
-- Phase 2: Sonar tracking
-- ============================================================
function FishSpawner:RegisterSonarPing(playerId, position)
	self._activeSonarPlayers[playerId] = { position = position, timestamp = tick() }
end

function FishSpawner:IsSonarActive(nearPosition, radius)
	local now = tick()
	for _, data in pairs(self._activeSonarPlayers) do
		if now - data.timestamp < 5 then -- sonar data valid for 5s
			if (data.position - nearPosition).Magnitude <= radius then
				return true
			end
		end
	end
	return false
end

-- ============================================================
-- Phase 2: Bait placement (Grotto Crab)
-- ============================================================
function FishSpawner:PlaceBait(playerId, baitPosition)
	self._activeBait[playerId] = { position = baitPosition, timestamp = tick() }

	-- Notify nearby burrower fish
	for _, fish in pairs(self._fish) do
		if fish.Species.Behavior == "Burrower" then
			local dist = (fish.Position - baitPosition).Magnitude
			if dist <= 15 then
				if fish.OnBaitPlaced then
					fish:OnBaitPlaced(baitPosition)
				end
			end
		end
	end
end

-- ============================================================
-- Phase 2: Tentacle collision checking
-- ============================================================
function FishSpawner:CheckTentacleCollisions()
	for _, fish in pairs(self._fish) do
		if fish.Species.Behavior == "Drifter" and fish.Species.TentacleLength then
			for _, playerPos in pairs(self._playerPositions) do
				if fish.CheckTentacleCollision then
					fish:CheckTentacleCollision(playerPos)
				end
			end
		end
	end
end

-- ============================================================
-- Phase 2: Kelp Serpent warning display check
-- ============================================================
function FishSpawner:CheckKelpSerpentWarningDisplay(playerPosition)
	if not self._kelpSerpent then return false, nil end
	if self._kelpSerpent.CheckWarningDisplay then
		return self._kelpSerpent:CheckWarningDisplay(playerPosition), self._kelpSerpent
	end
	return false, nil
end

-- ============================================================
-- Angler dimming
-- ============================================================
function FishSpawner:OnAnglerDimmed(fish)
	local fishId = fish.Id
	local dimCooldown = fish.Species.DimCooldown or 30
	self._dimmedAnglers[fishId] = tick() + dimCooldown

	if fish._model then
		local lure = fish._model:FindFirstChild("Lure", true)
		if lure and lure:IsA("PointLight") then
			lure.Brightness = 0.1
		end
	end

	task.delay(dimCooldown, function()
		self._dimmedAnglers[fishId] = nil
		if fish._model then
			local lure = fish._model:FindFirstChild("Lure", true)
			if lure and lure:IsA("PointLight") then
				lure.Brightness = 1.5
			end
		end
	end)
end

function FishSpawner:OnShipwreckVisited()
	self._lastShipwreckVisit = tick()
end

-- ============================================================
-- Rare spawn bloom notification
-- ============================================================
function FishSpawner:_fireRareSpawnBloom(position, species)
	if self._knit then
		pcall(function()
			local rareSpawnSignal = self._knit.GetSignal and self._knit.GetSignal("RareFishSpawned")
			if rareSpawnSignal then
				rareSpawnSignal:Fire(position, species.Name, species.Rarity)
			end
		end)
	end
end

-- ============================================================
-- Knit signal notifications
-- ============================================================
function FishSpawner:_notifyFishSpawned(fish) end
function FishSpawner:_notifyFishDespawned(fishId) end

-- ============================================================
-- Update loop — called periodically by ZoneService
-- ============================================================
function FishSpawner:Update(dt)
	local now = tick()

	-- Check auto-despawn
	local toRemove = {}
	for fishId, fish in pairs(self._fish) do
		if fish:CheckDespawn(now) then
			table.insert(toRemove, fishId)
		end

		local boundary = self.ZoneConfig.Population.DespawnBoundary or 60
		local zoneCenter = Vector3.zero
		local dist = (fish.Position - zoneCenter).Magnitude
		if dist > boundary then
			table.insert(toRemove, fishId)
		end
	end

	for _, fishId in ipairs(toRemove) do
		self:DespawnFish(fishId)
	end

	-- Clean stale bobbers
	for playerId, bobber in pairs(self._activeBobbers) do
		if bobber.stale and now - bobber.castTime > 10 then
			self._activeBobbers[playerId] = nil
		end
	end

	-- Clean stale bait
	for playerId, bait in pairs(self._activeBait) do
		if now - bait.timestamp > 120 then -- bait expires after 2 min
			self._activeBait[playerId] = nil
		end
	end

	-- Clean stale sonar data
	for playerId, data in pairs(self._activeSonarPlayers) do
		if now - data.timestamp > 10 then
			self._activeSonarPlayers[playerId] = nil
		end
	end

	-- Phase 2: check tentacle collisions
	self:CheckTentacleCollisions()

	-- Day/night
	self._isNight = self:_isNightTime()

	-- Track player positions
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				self._playerPositions[player.UserId] = rootPart.Position
			end
		end
	end
end

-- ============================================================
-- Get all active fish
-- ============================================================
function FishSpawner:GetAllFish()
	return self._fish
end

function FishSpawner:GetFishById(fishId)
	return self._fish[fishId]
end

function FishSpawner:GetPopulation()
	return self._population
end

-- ============================================================
-- Cleanup
-- ============================================================
function FishSpawner:Destroy()
	for _, fish in pairs(self._fish) do
		fish:Destroy()
	end
	self._fish = {}
	self._population = 0
end

return FishSpawner
