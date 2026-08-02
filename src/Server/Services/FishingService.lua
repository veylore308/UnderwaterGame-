--[[
	FishingService.lua
	Deep Tide Studios — Server Service
	Authoritative fishing logic: validates casts, hooks, and reeling.
	Integrated with FishNPC system — hooks real fish instead of random species.
	Prevents exploits by being the single source of truth for catch outcomes.
	Phase 2: Zone-aware fishing, sonar system, bait placement (Grotto Crab).
]]

local Knit = require(game:GetService("ReplicatedStorage"):WaitForChild("Knit"))
local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))
local FishSignals = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("NPC"):WaitForChild("FishSignals"))
local HttpService = game:GetService("HttpService")

local FishingService = Knit.CreateService({
	Name = "FishingService",
	Client = {
		CastLine = Knit.CreateSignal(),
		HookAttempt = Knit.CreateSignal(),
		ReelUpdate = Knit.CreateSignal(),
		CancelFishing = Knit.CreateSignal(),
		FishHooked = Knit.CreateSignal(),
		FishCaught = Knit.CreateSignal(),
		FishEscaped = Knit.CreateSignal(),
		LineSnapped = Knit.CreateSignal(),
		SonarPing = Knit.CreateSignal(),         -- Phase 2 sonar
		PlaceBait = Knit.CreateSignal(),          -- Phase 2 bait placement (Grotto Crab)
		BaitResult = Knit.CreateSignal(),         -- Phase 2 bait outcome
		InkBurst = Knit.CreateSignal(),           -- Phase 2 ink burst notification
		ApexPresence = Knit.CreateSignal(),        -- Phase 2 apex spawn warning
		ZoneTransition = Knit.CreateSignal(),      -- Phase 2 zone change notification
	},
})

-- Active fishing sessions
FishingService._activeSessions = {}

-- ============================================================

function FishingService:KnitStart()
	print("[FishingService] Started — integrated with FishNPC system (Phase 2)")
end

function FishingService:KnitInit()
	self.Client.CastLine:Connect(function(player, targetPosition)
		return self:ProcessCast(player, targetPosition)
	end)

	self.Client.HookAttempt:Connect(function(player, castId, timingQuality)
		return self:ProcessHook(player, castId, timingQuality)
	end)

	self.Client.ReelUpdate:Connect(function(player, castId, isReeling)
		return self:ProcessReelTick(player, castId, isReeling)
	end)

	self.Client.CancelFishing:Connect(function(player, castId)
		self:CancelSession(player)
	end)

	-- Phase 2: Bait placement
	self.Client.PlaceBait:Connect(function(player, baitPosition)
		return self:ProcessBaitPlacement(player, baitPosition)
	end)

	-- Start the global sonar loop
	self:_startSonarLoop()
end

-- ============================================================
-- Sonar System (GDD 4.1.1 — Phase 2)
-- ============================================================

FishingService._sonarPlayerData = {}

function FishingService:_startSonarLoop()
	task.spawn(function()
		while true do
			task.wait(0.5)

			local now = tick()
			local players = game:GetService("Players"):GetPlayers()

			for _, player in ipairs(players) do
				local data = self.Services.PlayerDataService:GetData(player)
				if not data then continue end

				local rod = Shared.Constants.RodTiers.GetByKey(data.Gear.EquippedRod)
				if not rod or not rod.SonarRange or rod.SonarRange <= 0 then
					continue
				end

				local sonarData = self._sonarPlayerData[player]
				if not sonarData then
					sonarData = { lastPingTime = 0 }
					self._sonarPlayerData[player] = sonarData
				end

				local interval = rod.SonarPingInterval or 3.0
				if (now - sonarData.lastPingTime) >= interval then
					sonarData.lastPingTime = now
					self:_performSonarPing(player, rod)
				end
			end
		end
	end)
end

function FishingService:_performSonarPing(player, rod)
	local character = player.Character
	if not character then return end
	local playerPos = character:GetPivot().Position
	local sonarRange = rod.SonarRange

	-- Determine which zone the player is in
	local zoneKey = self.Services.ZoneService:GetPlayerZone(player) or "SunkenShallows"

	-- Register sonar with the spawner (so fish can detect sonar for light-attraction)
	local spawner = self.Services.ZoneService:GetSpawner(zoneKey)
	if spawner and spawner.RegisterSonarPing then
		spawner:RegisterSonarPing(player.UserId, playerPos)
	end

	-- Reveal camouflaged fish within sonar range
	if spawner then
		local allFish = spawner:GetAllFish()
		for _, fishNPC in pairs(allFish) do
			if fishNPC and fishNPC.Species then
				local fishPos = fishNPC:GetPosition()
				local dist = (fishPos - playerPos).Magnitude
				if dist <= sonarRange then
					if fishNPC.OnSonarPing then
						fishNPC:OnSonarPing()
					end
				end
			end
		end
	end

	-- Get fish within sonar range from ZoneService
	local nearbyFish = self.Services.ZoneService:GetFishNearBobber(playerPos, sonarRange, zoneKey)

	local detectedFish = {}
	for _, entry in ipairs(nearbyFish) do
		if entry.Fish and entry.Fish.Species then
			local species = entry.Fish.Species
			local distance = entry.Distance or ((entry.Fish:GetPosition() - playerPos).Magnitude)

			detectedFish[#detectedFish + 1] = {
				FishId = entry.Fish.Id,
				SpeciesKey = species.Key,
				SpeciesName = species.Name,
				Rarity = species.Rarity,
				RarityColor = Shared.Constants.RarityTiers.GetColor(species.Rarity),
				Distance = distance,
				Position = entry.Fish:GetPosition(),
			}
		end
	end

	-- Also scan all fish from the zone spawner
	if spawner then
		local allFish = spawner:GetAllFish()
		for fishId, fishNPC in pairs(allFish) do
			if fishNPC and fishNPC.Species then
				local fishPos = fishNPC:GetPosition()
				local dist = (fishPos - playerPos).Magnitude
				if dist <= sonarRange then
					local alreadyListed = false
					for _, df in ipairs(detectedFish) do
						if df.FishId == fishNPC.Id then
							alreadyListed = true
							break
						end
					end
					if not alreadyListed then
						detectedFish[#detectedFish + 1] = {
							FishId = fishNPC.Id,
							SpeciesKey = fishNPC.Species.Key,
							SpeciesName = fishNPC.Species.Name,
							Rarity = fishNPC.Species.Rarity,
							RarityColor = Shared.Constants.RarityTiers.GetColor(fishNPC.Species.Rarity),
							Distance = dist,
							Position = fishPos,
						}
					end
				end
			end
		end
	end

	-- Send ping data to client (always fire, even if empty — so client can show VFX)
	self.Client.SonarPing:Fire(player, {
		Origin = playerPos,
		Range = sonarRange,
		DetectedFish = detectedFish,
		Timestamp = tick(),
	})
end

-- ============================================================
-- Bait placement (Grotto Crab — Phase 2)
-- ============================================================
function FishingService:ProcessBaitPlacement(player, baitPosition)
	-- Validate player has bait
	local data = self.Services.PlayerDataService:GetData(player)
	if not data then
		return { Success = false, Message = "Player data not loaded" }
	end

	-- Check bait inventory
	if not data.Inventory or not data.Inventory.Bait or data.Inventory.Bait <= 0 then
		return { Success = false, Message = "No bait available" }
	end

	-- Validate bait is placed on sea floor
	local zoneKey = self.Services.ZoneService:GetPlayerZone(player) or "SunkenShallows"
	local spawner = self.Services.ZoneService:GetSpawner(zoneKey)
	if not spawner then
		return { Success = false, Message = "No active spawner" }
	end

	-- Consume bait
	self.Services.PlayerDataService:RemoveBait(player, 1)

	-- Register bait with spawner
	if spawner.PlaceBait then
		spawner:PlaceBait(player.UserId, baitPosition)
	end

	return { Success = true, Message = "Bait placed" }
end

-- ============================================================
-- Cast
-- ============================================================

function FishingService:ProcessCast(player, targetPosition)
	local session = self._activeSessions[player]
	if session then
		return { Success = false, Message = "Already fishing" }
	end

	local data = self.Services.PlayerDataService:GetData(player)
	if not data then
		return { Success = false, Message = "Player data not loaded" }
	end

	local rod = Shared.Constants.RodTiers.GetByKey(data.Gear.EquippedRod)
	if not rod then
		return { Success = false, Message = "No rod equipped" }
	end

	local playerPos = player.Character and player.Character:GetPivot().Position
	if not playerPos then
		return { Success = false, Message = "Character not found" }
	end

	local distance = (targetPosition - playerPos).Magnitude
	if distance > rod.CastRange then
		return { Success = false, Message = "Target out of range" }
	end

	-- Create session
	local castId = HttpService:GenerateGUID(false)
	session = {
		CastId = castId,
		TargetPosition = targetPosition,
		CastTime = tick(),
		Phase = "Waiting",
		Tension = 0,
		Progress = 0,
		RodKey = rod.Key,
		RodStats = rod,
		FishId = nil,
		FishNPC = nil,
	}
	self._activeSessions[player] = session

	-- Register bobber with ZoneService
	local zoneKey = self.Services.ZoneService:GetPlayerZone(player) or "SunkenShallows"
	self.Services.ZoneService:RegisterBobber(player.UserId, targetPosition, zoneKey)

	-- Notify nearby fish about the bobber
	self:_notifyFishOfBobber(targetPosition, player, zoneKey)

	return { Success = true, CastId = castId }
end

function FishingService:_notifyFishOfBobber(position, player, zoneKey)
	local nearbyFish = self.Services.ZoneService:GetFishNearBobber(position, 30, zoneKey)

	for _, entry in ipairs(nearbyFish) do
		if entry.Fish and not entry.Fish:IsHooked() then
			entry.Fish:OnBobberNearby(position, player.UserId)
		end
	end
end

-- ============================================================
-- Hook
-- ============================================================

function FishingService:ProcessHook(player, castId, timingQuality)
	local session = self._activeSessions[player]
	if not session or session.CastId ~= castId then
		return { Result = "InvalidSession" }
	end

	local bitingFish = self:_resolveBitingFish(session, player)
	session.FishNPC = bitingFish
	session.FishId = bitingFish and bitingFish.Id

	if timingQuality == "Early" then
		local fleeChance = Shared.Fishing.FleeChanceCommon
		if bitingFish then
			if bitingFish.Species.Rarity == "Legendary" then
				fleeChance = Shared.Fishing.FleeChanceLegendary
			elseif bitingFish.Species.Rarity == "Uncommon" or bitingFish.Species.Rarity == "Rare" then
				fleeChance = Shared.Fishing.FleeChanceUncommonPlus
			end
		end

		if math.random() < fleeChance then
			if bitingFish then
				bitingFish:OnHookAttempt(false)
			end
			self:CancelSession(player)
			return { Result = "FishFled" }
		end

		session.Phase = "Waiting"
		return { Result = "TooSoon" }
	end

	if timingQuality == "Late" then
		if bitingFish then
			bitingFish:OnHookAttempt(false)
		end
		self:CancelSession(player)
		return { Result = "FishFled" }
	end

	-- Perfect or Good
	if not bitingFish then
		bitingFish = nil
		session.FishId = nil
		session.FishNPC = nil
	else
		bitingFish:OnHookAttempt(true)
	end

	-- Resolve species
	local species = self:_resolveBitingSpecies(session, bitingFish, player)
	if not species then
		self:CancelSession(player)
		return { Result = "NoFishNearby" }
	end

	session.Phase = "Reeling"
	session.Tension = (timingQuality == "Perfect") and 0 or 20
	session.SpeciesKey = species.Key

	local weight = self:_rollWeight(species)
	local sellPrice = self:_calculateSellPrice(species, weight)

	local fishData = {
		FishId = session.FishId,
		SpeciesKey = species.Key,
		SpeciesName = species.Name,
		Rarity = species.Rarity,
		Weight = weight,
		SellPrice = sellPrice,
	}

	session.FishData = fishData

	self.Client.FishHooked:Fire(player, fishData)

	return {
		Result = "Hooked",
		FishData = fishData,
		Tension = session.Tension,
	}
end

-- ============================================================
-- Reel Tick
-- ============================================================

function FishingService:ProcessReelTick(player, castId, isReeling)
	local session = self._activeSessions[player]
	if not session or session.CastId ~= castId then
		return { State = "InvalidSession" }
	end

	if session.Phase ~= "Reeling" then
		return { State = session.Phase }
	end

	local rod = session.RodStats
	local species = Shared.Constants.FishSpecies.GetByKey(session.SpeciesKey)
	if not species then
		self:CancelSession(player)
		return { State = "Error", Message = "Species data missing" }
	end

	local tickRate = Shared.Fishing.TensionTickRate
	local tensionMax = Shared.Fishing.TensionMax

	if isReeling then
		local increase = Shared.Fishing.BaseReelRate * rod.ReelSpeed * (1.0 - (session.Progress / 100) * Shared.Fishing.ProgressDecayFactor)
		session.Tension = math.min(tensionMax, session.Tension + increase * tickRate)

		local progressGain = 2.0 * rod.ReelSpeed * tickRate
		session.Progress = math.min(100, session.Progress + progressGain)

		if math.random() < (0.3 * tickRate) then
			local tugStrength = species.TugStrength * (0.8 + math.random() * 0.4)
			session.Tension = math.min(tensionMax, session.Tension + tugStrength * tensionMax)
		end
	else
		local decrease = Shared.Fishing.BaseReleaseRate * rod.ReelSpeed
		session.Tension = math.max(0, session.Tension - decrease * tickRate)
	end

	if session.Tension >= tensionMax then
		if session.FishNPC then
			session.FishNPC:OnLineSnap()
		end
		self.Client.LineSnapped:Fire(player)
		self.CancelSession(player)
		return { State = "LineSnapped", Tension = tensionMax, Progress = session.Progress }
	end

	if session.Tension <= 0 and session.Progress > 0 then
		if session.FishNPC then
			session.FishNPC:OnEscape()
		end
		self.Client.FishEscaped:Fire(player, "LowTension")
		self.CancelSession(player)
		return { State = "FishEscaped", Reason = "LowTension", Tension = 0, Progress = session.Progress }
	end

	if session.Progress >= 100 then
		return self:_completeCatch(player, session)
	end

	return {
		State = "Reeling",
		Tension = session.Tension,
		Progress = session.Progress,
		Zone = self:_getTensionZone(session.Tension),
	}
end

-- ============================================================
-- Catch completion
-- ============================================================

function FishingService:_completeCatch(player, session)
	local fishData = session.FishData
	session.Phase = "Caught"

	if session.FishNPC then
		session.FishNPC:OnCaught()
	end

	local zoneKey = self.Services.ZoneService:GetPlayerZone(player) or "SunkenShallows"
	if session.FishId then
		self.Services.ZoneService:DespawnFish(zoneKey, session.FishId)
	end

	local success, reason = self.Services.PlayerDataService:AddFish(
		player, fishData.SpeciesKey, fishData.Weight, fishData.SellPrice
	)

	if not success then
		self.CancelSession(player)
		return { State = "InventoryFull", Reason = reason }
	end

	local species = Shared.Constants.FishSpecies.GetByKey(fishData.SpeciesKey)
	local xp = Shared.Constants.RarityTiers.GetXPValue(fishData.Rarity)
	self.Services.PlayerDataService:AddXP(player, xp)
	self.Services.PlayerDataService:AddDivePassXPForCatch(player, fishData.Rarity)

	if self.Services.ChallengeService then
		self.Services.ChallengeService:ReportProgress(player, "CatchRarity", { Rarity = fishData.Rarity, Count = 1 })
		self.Services.ChallengeService:ReportProgress(player, "CatchAny", { Count = 1 })
		self.Services.ChallengeService:ReportProgress(player, "CatchWeight", { WeightKg = fishData.Weight, Count = 1 })
		local speciesZone = species.Zone or "SunkenShallows"
		self.Services.ChallengeService:ReportProgress(player, "CatchInZone", { Zone = speciesZone, Count = 1 })
	end

	local playerPos = player.Character and player.Character:GetPivot().Position
	if playerPos then
		local depth = math.abs(playerPos.Y)
		if self.Services.ChallengeService then
			self.Services.ChallengeService:ReportProgress(player, "DepthReached", { Depth = depth, Count = 1 })
		end
	end

	self.Client.FishCaught:Fire(player, fishData, { XP = xp })
	self._activeSessions[player] = nil

	return { State = "Caught", FishData = fishData, Tension = session.Tension, Progress = 100 }
end

-- ============================================================
-- Helpers
-- ============================================================

function FishingService:CancelSession(player)
	local session = self._activeSessions[player]
	if not session then
		self._activeSessions[player] = nil
		return
	end

	local zoneKey = self.Services.ZoneService:GetPlayerZone(player) or "SunkenShallows"
	self.Services.ZoneService:UnregisterBobber(player.UserId, zoneKey)

	if session.FishNPC and (session.Phase == "Reeling" or session.Phase == "Hooking") then
		session.FishNPC:OnEscape()
	end

	self._activeSessions[player] = nil
end

-- ============================================================
-- Resolve which REAL fish is biting (zone-aware)
-- ============================================================
function FishingService:_resolveBitingFish(session, player)
	local zoneKey = self.Services.ZoneService:GetPlayerZone(player) or "SunkenShallows"
	local bobberPos = session.TargetPosition

	local nearbyFish = self.Services.ZoneService:GetFishNearBobber(bobberPos, 15, zoneKey)

	-- Prefer fish in ReadyToBite or Biting state
	for _, entry in ipairs(nearbyFish) do
		if entry.IsBiteReady then
			return entry.Fish
		end
	end

	-- Prefer Curious or Investigate
	for _, entry in ipairs(nearbyFish) do
		if entry.State == FishSignals.FishState.Curious
			or entry.State == FishSignals.FishState.Investigate
			or entry.State == FishSignals.FishState.Emerging then
			if entry.Fish._transitionTo then
				entry.Fish:_transitionTo(FishSignals.FishState.Biting)
			end
			return entry.Fish
		end
	end

	return nil
end

-- ============================================================
-- Resolve species — from real fish or fallback (zone-aware)
-- ============================================================
function FishingService:_resolveBitingSpecies(session, bitingFish, player)
	if bitingFish then
		return bitingFish.Species
	end

	-- Fallback: weighted random by zone
	local zoneKey = self.Services.ZoneService:GetPlayerZone(player) or "SunkenShallows"
	local spawnTable, totalWeight = Shared.Constants.FishSpecies.GetSpawnTable(0, zoneKey)

	if totalWeight <= 0 then return Shared.Constants.FishSpecies[1] end

	local roll = math.random() * totalWeight
	for _, entry in ipairs(spawnTable) do
		if roll <= entry.CumulativeWeight then
			return entry.Species
		end
	end

	return Shared.Constants.FishSpecies[1]
end

function FishingService:_rollWeight(species)
	local minW = species.WeightRange.Min
	local maxW = species.WeightRange.Max
	local midpoint = (minW + maxW) / 2
	local stddev = (maxW - minW) / 6

	local u1 = math.random()
	local u2 = math.random()
	local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)

	local weight = midpoint + z * stddev
	return math.clamp(weight, minW, maxW)
end

function FishingService:_calculateSellPrice(species, weight)
	local priceMin = species.BaseSellPrice.Min
	local priceMax = species.BaseSellPrice.Max
	local weightMin = species.WeightRange.Min
	local weightMax = species.WeightRange.Max

	local weightRatio = (weight - weightMin) / (weightMax - weightMin)
	local basePrice = priceMin + (priceMax - priceMin) * weightRatio

	return math.floor(basePrice)
end

function FishingService:_getTensionZone(tension)
	if tension < Shared.Fishing.TensionGreenZone then
		return "Green"
	elseif tension < Shared.Fishing.TensionYellowZone then
		return "Yellow"
	else
		return "Red"
	end
end

return FishingService

-- Phase 3 surface helpers. BoatService remains the server authority for speed.
function FishingService:IsSurfaceCast(player, targetPosition)
    local boatService = self.Services.BoatService
    local boat = boatService and boatService:GetBoat(player)
    if not boat then return false, "No boat" end
    local speed = boatService:GetBoatSpeed(player)
    if speed >= 2 and boatService.SetAnchor then boatService:SetAnchor(player) end
    return true, { Zone = "Surface", BobberDriftSpeed = (self.Services.WeatherService and self.Services.WeatherService:GetState() == "Storm") and 8 or 3, BoatSpeedLimit = 8 }
end
function FishingService:ValidateSurfaceLine(player)
    local boatService = self.Services.BoatService
    return not boatService or boatService:GetBoatSpeed(player) <= 8
end
