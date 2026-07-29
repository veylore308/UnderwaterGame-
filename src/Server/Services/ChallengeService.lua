--[[
	ChallengeService.lua
	Deep Tide Studios — Server Service
	Daily challenge system: generates 3 challenges per player per day,
	tracks progress, awards XP/Coins/Gems, and manages streaks.
	Source: GDD Section 6.
]]

local Knit = require(game:GetService("ReplicatedStorage"):WaitForChild("Knit"))
local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))
local HttpService = game:GetService("HttpService")

local ChallengeService = Knit.CreateService({
	Name = "ChallengeService",
	Client = {
		-- Client can request their daily challenges
		GetDailyChallenges = Knit.CreateSignal(),  -- (player) -> challenges
		ChallengeProgressUpdated = Knit.CreateSignal(), -- (challengeData) -> nil
		AllChallengesCompleted = Knit.CreateSignal(),   -- (bonusRewards) -> nil
		StreakMilestone = Knit.CreateSignal(),          -- (streakDays, reward) -> nil
	},
})

-- ============================================================
-- Challenge Pool — 25 challenges across 5 categories
-- GDD Section 6.3
-- ============================================================
local CHALLENGE_POOL = {
	-- ============================================================
	-- Catch Challenges
	-- ============================================================
	{
		Id = "Catch3Uncommon",
		Category = "Catch",
		Difficulty = "Easy",
		Name = "Catch 3 Uncommon fish",
		Requirement = { Type = "CatchRarity", Rarity = "Uncommon", Count = 3 },
		Reward = { XP = 100, Coins = 50 },
	},
	{
		Id = "Catch5Fish",
		Category = "Catch",
		Difficulty = "Easy",
		Name = "Catch 5 fish of any rarity",
		Requirement = { Type = "CatchAny", Count = 5 },
		Reward = { XP = 100, Coins = 50 },
	},
	{
		Id = "Catch2Rare",
		Category = "Catch",
		Difficulty = "Medium",
		Name = "Catch 2 Rare fish",
		Requirement = { Type = "CatchRarity", Rarity = "Rare", Count = 2 },
		Reward = { XP = 100, Coins = 100 },
	},
	{
		Id = "CatchFishOver5kg",
		Category = "Catch",
		Difficulty = "Medium",
		Name = "Catch a fish weighing over 5 kg",
		Requirement = { Type = "CatchWeight", MinKg = 5.0, Count = 1 },
		Reward = { XP = 100, Coins = 100 },
	},
	{
		Id = "CatchKelpForest",
		Category = "Catch",
		Difficulty = "Easy",
		Name = "Catch a fish from the Kelp Forest",
		Requirement = { Type = "CatchInZone", Zone = "KelpForest", Count = 1 },
		Reward = { XP = 100, Coins = 50 },
		RequiresKelpForest = true,
	},
	{
		Id = "CatchShallows",
		Category = "Catch",
		Difficulty = "Easy",
		Name = "Catch a fish from the Sunken Shallows",
		Requirement = { Type = "CatchInZone", Zone = "SunkenShallows", Count = 1 },
		Reward = { XP = 100, Coins = 50 },
	},
	{
		Id = "Catch3DifferentSpeciesOneDive",
		Category = "Catch",
		Difficulty = "Medium",
		Name = "Catch 3 different species in one dive",
		Requirement = { Type = "CatchUniqueSpeciesInDive", Count = 3 },
		Reward = { XP = 100, Coins = 100 },
	},
	{
		Id = "CatchLegendary",
		Category = "Catch",
		Difficulty = "Hard",
		Name = "Catch a Legendary fish",
		Requirement = { Type = "CatchRarity", Rarity = "Legendary", Count = 1 },
		Reward = { XP = 100, Coins = 150 },
	},

	-- ============================================================
	-- Casting Challenges
	-- ============================================================
	{
		Id = "Cast10Times",
		Category = "Cast",
		Difficulty = "Easy",
		Name = "Cast your rod 10 times",
		Requirement = { Type = "CastCount", Count = 10 },
		Reward = { XP = 100, Coins = 50 },
	},
	{
		Id = "Cast25Times",
		Category = "Cast",
		Difficulty = "Medium",
		Name = "Cast your rod 25 times",
		Requirement = { Type = "CastCount", Count = 25 },
		Reward = { XP = 100, Coins = 75 },
	},
	{
		Id = "PerfectHook5",
		Category = "Cast",
		Difficulty = "Medium",
		Name = "Land 5 Perfect hooks",
		Requirement = { Type = "PerfectHookCount", Count = 5 },
		Reward = { XP = 100, Coins = 100 },
	},
	{
		Id = "HookFirstCast",
		Category = "Cast",
		Difficulty = "Easy",
		Name = "Successfully hook a fish on your first cast of the day",
		Requirement = { Type = "FirstCastHook", Count = 1 },
		Reward = { XP = 100, Coins = 50 },
	},

	-- ============================================================
	-- Exploration Challenges
	-- ============================================================
	{
		Id = "VisitRockyGrotto",
		Category = "Explore",
		Difficulty = "Medium",
		Name = "Visit the Rocky Grotto",
		Requirement = { Type = "VisitLandmark", Landmark = "Rocky Grotto", Count = 1 },
		Reward = { XP = 100, Coins = 75 },
		RequiresDeepDiverSuit = true,
	},
	{
		Id = "CrossClearingNoSprint",
		Category = "Explore",
		Difficulty = "Medium",
		Name = "Swim through The Clearing without using sprint",
		Requirement = { Type = "CrossLandmarkNoSprint", Landmark = "The Clearing", Count = 1 },
		Reward = { XP = 100, Coins = 75 },
		RequiresKelpForest = true,
	},
	{
		Id = "DiscoverNewSpecies",
		Category = "Explore",
		Difficulty = "Hard",
		Name = "Discover a new species",
		Requirement = { Type = "DiscoverSpecies", Count = 1 },
		Reward = { XP = 100, Coins = 150 },
	},
	{
		Id = "Reach120m",
		Category = "Explore",
		Difficulty = "Medium",
		Name = "Reach 120m depth",
		Requirement = { Type = "DepthReached", Depth = 120, Count = 1 },
		Reward = { XP = 100, Coins = 100 },
		RequiresDeepDiverSuit = true,
	},
	{
		Id = "UseAirPocket",
		Category = "Explore",
		Difficulty = "Medium",
		Name = "Find and use an air pocket in the Grotto",
		Requirement = { Type = "UseAirPocket", Count = 1 },
		Reward = { XP = 100, Coins = 100 },
		RequiresDeepDiverSuit = true,
	},

	-- ============================================================
	-- Economy Challenges
	-- ============================================================
	{
		Id = "Sell200Coins",
		Category = "Economy",
		Difficulty = "Easy",
		Name = "Sell 200 Coins worth of fish",
		Requirement = { Type = "SellValue", Coins = 200, Count = 1 },
		Reward = { XP = 100, Coins = 50 },
	},
	{
		Id = "Sell500Coins",
		Category = "Economy",
		Difficulty = "Medium",
		Name = "Sell 500 Coins worth of fish",
		Requirement = { Type = "SellValue", Coins = 500, Count = 1 },
		Reward = { XP = 100, Coins = 100 },
	},
	{
		Id = "UseBaitItem",
		Category = "Economy",
		Difficulty = "Easy",
		Name = "Use a Bait item",
		Requirement = { Type = "UseConsumable", ItemType = "Bait", Count = 1 },
		Reward = { XP = 100, Coins = 50 },
	},
	{
		Id = "PurchaseFromShop",
		Category = "Economy",
		Difficulty = "Easy",
		Name = "Purchase an item from the Shop",
		Requirement = { Type = "ShopPurchase", Count = 1 },
		Reward = { XP = 100, Coins = 50 },
	},

	-- ============================================================
	-- Social Challenges (Phase 2.5 — included for pool readiness)
	-- ============================================================
	{
		Id = "FishNearPlayer",
		Category = "Social",
		Difficulty = "Easy",
		Name = "Fish near another player for 5 minutes",
		Requirement = { Type = "FishNearPlayer", DurationMinutes = 5, Count = 1 },
		Reward = { XP = 100, Coins = 75 },
		IsFuture = true, -- Phase 2.5
	},
	{
		Id = "CatchInParty",
		Category = "Social",
		Difficulty = "Medium",
		Name = "Catch a fish while in a party",
		Requirement = { Type = "CatchInParty", Count = 1 },
		Reward = { XP = 100, Coins = 100 },
		IsFuture = true, -- Phase 2.5
	},
}

-- ============================================================
-- Constants
-- ============================================================
local CHALLENGES_PER_DAY = 3
local FREE_REROLLS_PER_DAY = 1
local REROLL_GEM_COST = 10
local COMPLETE_ALL_BONUS_XP = 50
local COMPLETE_ALL_BONUS_GEMS = 25
local STREAK_DAYS_FOR_BONUS = 7
local STREAK_BONUS_XP = 200
local STREAK_BONUS_GEMS = 100

-- Midnight UTC in seconds (seconds since epoch for today's reset)
local function getMidnightUTC()
	local now = os.time()
	local date = os.date("!*t", now)
	date.hour = 0
	date.min = 0
	date.sec = 0
	return os.time(date)
end

-- ============================================================
-- Per-player challenge state
-- ============================================================
ChallengeService._playerChallenges = {} -- { [player] = ChallengeState }

-- ChallengeState:
-- {
--   AssignedChallenges = { ChallengeData, ... },
--   Completions = { [challengeId] = ProgressData },
--   Date = number (midnight UTC timestamp),
--   Streak = number (consecutive days completed),
--   FreeRerollsUsed = number,
--   AllCompleteBonusClaimed = false,
-- }

-- ChallengeData:
-- {
--   Id = string,
--   Name = string,
--   Category = string,
--   Difficulty = string,
--   Requirement = { ... },
--   Reward = { XP, Coins },
--   Progress = number (current / target),
--   Completed = boolean,
-- }

-- ============================================================
-- Service Lifecycle
-- ============================================================

function ChallengeService:KnitStart()
	print("[ChallengeService] Started — daily challenge system active")
end

function ChallengeService:KnitInit()
	-- Wire player join/leave
	game:GetService("Players").PlayerAdded:Connect(function(player)
		self:OnPlayerAdded(player)
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		self:OnPlayerRemoving(player)
	end)

	-- Wire client remote
	self.Client.GetDailyChallenges:Connect(function(player)
		return self:GetChallengesForPlayer(player)
	end)

	-- Periodic reset check (every 60s)
	task.spawn(function()
		while true do
			task.wait(60)
			self:CheckDailyReset()
		end
	end)
end

-- ============================================================
-- Player Lifecycle
-- ============================================================

function ChallengeService:OnPlayerAdded(player)
	-- Ensure challenges are assigned
	self:EnsureChallengesAssigned(player)
end

function ChallengeService:OnPlayerRemoving(player)
	self._playerChallenges[player] = nil
end

-- ============================================================
-- Challenge Assignment
-- ============================================================

function ChallengeService:EnsureChallengesAssigned(player)
	local state = self._playerChallenges[player]
	local today = getMidnightUTC()

	-- Check if we need a fresh assignment
	if not state or state.Date ~= today then
		self:AssignDailyChallenges(player, today, state)
	end
end

function ChallengeService:AssignDailyChallenges(player, today, previousState)
	local data = self.Services.PlayerDataService:GetData(player)
	if not data then return end

	-- Carry forward streak if completed all yesterday
	local streak = 0
	if previousState then
		local allDone = self:_countCompleted(previousState) >= CHALLENGES_PER_DAY
		if allDone and previousState.Date == (today - 86400) then
			streak = (previousState.Streak or 0) + 1
		end
	end

	-- Build available pool (filter out future challenges + zone-locked)
	local availablePool = {}
	for _, challenge in ipairs(CHALLENGE_POOL) do
		if not challenge.IsFuture then
			-- Zone lock: skip Kelp Forest challenges if player hasn't unlocked it
			if challenge.RequiresKelpForest then
				local zoneConfig = Shared.Constants.ZoneConfigs.GetByKey("KelpForest")
				if zoneConfig and zoneConfig.UnlockRequirement then
					local req = zoneConfig.UnlockRequirement
					local ownsRod = data.Gear.OwnedRods[req.RequiredRod]
					local totalCatches = data.Progression.TotalCatches
					if not ownsRod or totalCatches < req.TotalCatches then
						-- skip — player hasn't unlocked Kelp Forest
					else
						availablePool[#availablePool + 1] = challenge
					end
				end
			elseif challenge.RequiresDeepDiverSuit then
				if data.Gear.OwnedSuits["DeepDiverSuit"] then
					availablePool[#availablePool + 1] = challenge
				end
			else
				availablePool[#availablePool + 1] = challenge
			end
		end
	end

	-- Select 3 challenges: 1 Easy, 1 Medium, 1 Hard
	local easyPool = {}
	local mediumPool = {}
	local hardPool = {}

	for _, ch in ipairs(availablePool) do
		if ch.Difficulty == "Easy" then
			easyPool[#easyPool + 1] = ch
		elseif ch.Difficulty == "Medium" then
			mediumPool[#mediumPool + 1] = ch
		elseif ch.Difficulty == "Hard" then
			hardPool[#hardPool + 1] = ch
		end
	end

	-- Avoid repeating same challenge from yesterday
	local yesterdayIds = {}
	if previousState then
		for _, ch in ipairs(previousState.AssignedChallenges) do
			yesterdayIds[ch.Id] = true
		end
	end

	local function pickFromPool(pool, avoidIds)
		-- Shuffle and pick first non-repeated
		local shuffled = {}
		for i, ch in ipairs(pool) do
			shuffled[i] = ch
		end
		-- Fisher-Yates shuffle
		for i = #shuffled, 2, -1 do
			local j = math.random(i)
			shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
		end
		-- Try to avoid yesterday's
		for _, ch in ipairs(shuffled) do
			if not avoidIds[ch.Id] then
				return ch
			end
		end
		-- All were yesterday's, pick first
		return shuffled[1]
	end

	local assigned = {}
	if #easyPool > 0 then
		assigned[#assigned + 1] = pickFromPool(easyPool, yesterdayIds)
	end
	if #mediumPool > 0 then
		assigned[#assigned + 1] = pickFromPool(mediumPool, yesterdayIds)
	end
	if #hardPool > 0 then
		assigned[#assigned + 1] = pickFromPool(hardPool, yesterdayIds)
	end

	-- If we don't have 3 (pools too small), fill remaining from any pool
	while #assigned < CHALLENGES_PER_DAY and #availablePool > #assigned do
		for _, ch in ipairs(availablePool) do
			local alreadyAssigned = false
			for _, a in ipairs(assigned) do
				if a.Id == ch.Id then
					alreadyAssigned = true
					break
				end
			end
			if not alreadyAssigned then
				assigned[#assigned + 1] = ch
				break
			end
		end
		-- Safety break
		if #assigned >= CHALLENGES_PER_DAY then break end
		if #assigned >= #availablePool then break end
	end

	-- Build challenge data with progress tracking
	local challengeDataList = {}
	for _, ch in ipairs(assigned) do
		challengeDataList[#challengeDataList + 1] = {
			Id = ch.Id,
			Name = ch.Name,
			Category = ch.Category,
			Difficulty = ch.Difficulty,
			Requirement = ch.Requirement,
			Reward = ch.Reward,
			Progress = 0,
			Target = ch.Requirement.Count or 1,
			Completed = false,
			Claimed = false,
		}
	end

	local state = {
		AssignedChallenges = challengeDataList,
		Date = today,
		Streak = streak,
		FreeRerollsUsed = 0,
		AllCompleteBonusClaimed = false,
	}

	self._playerChallenges[player] = state

	-- Push to client
	self.Client.GetDailyChallenges:Fire(player, state.AssignedChallenges)

	print(string.format("[ChallengeService] Assigned %d challenges to %s (streak: %d)",
		#challengeDataList, player.Name, streak))
end

-- ============================================================
-- Challenge Progress Tracking
-- ============================================================

--- Called by other services when relevant events occur
--- progressType: string matching Requirement.Type
--- progressData: { Count = number, ...extra fields }
function ChallengeService:ReportProgress(player, progressType, progressData)
	local state = self._playerChallenges[player]
	if not state then return end

	local anyChanged = false

	for _, ch in ipairs(state.AssignedChallenges) do
		if ch.Completed then
			-- already done
		else
			local matched = false
			local req = ch.Requirement

			if progressType == req.Type then
				if progressType == "CatchRarity" then
					if progressData.Rarity == req.Rarity then
						matched = true
					end
				elseif progressType == "CatchAny" then
					matched = true
				elseif progressType == "CatchWeight" then
					if (progressData.WeightKg or 0) >= (req.MinKg or 0) then
						matched = true
					end
				elseif progressType == "CatchInZone" then
					if progressData.Zone == req.Zone then
						matched = true
					end
				elseif progressType == "CatchUniqueSpeciesInDive" then
					-- tracked per-dive by the caller
					ch.Progress = math.max(ch.Progress, progressData.UniqueCount or 0)
					anyChanged = true
					matched = false -- already handled
				elseif progressType == "CastCount" then
					matched = true
				elseif progressType == "PerfectHookCount" then
					matched = true
				elseif progressType == "FirstCastHook" then
					matched = true
				elseif progressType == "VisitLandmark" then
					if progressData.Landmark == req.Landmark then
						matched = true
					end
				elseif progressType == "CrossLandmarkNoSprint" then
					if progressData.Landmark == req.Landmark then
						matched = true
					end
				elseif progressType == "DiscoverSpecies" then
					matched = true
				elseif progressType == "DepthReached" then
					if (progressData.Depth or 0) >= (req.Depth or 0) then
						matched = true
					end
				elseif progressType == "UseAirPocket" then
					matched = true
				elseif progressType == "SellValue" then
					ch.Progress = ch.Progress + (progressData.Coins or 0)
					anyChanged = true
					matched = false
				elseif progressType == "UseConsumable" then
					if progressData.ItemType == req.ItemType then
						matched = true
					end
				elseif progressType == "ShopPurchase" then
					matched = true
				else
					-- generic count match
					matched = true
				end
			end

			if matched then
				ch.Progress = ch.Progress + (progressData.Count or 1)
				anyChanged = true
			end

			-- Check completion
			local target = req.Count or 1
			if progressType == "SellValue" then
				target = req.Coins or 200
			end
			if ch.Progress >= target and not ch.Completed then
				ch.Completed = true
				self:_awardChallengeCompletion(player, ch)
			end

			-- Notify client of progress
			if anyChanged then
				self.Client.ChallengeProgressUpdated:Fire(player, {
					Id = ch.Id,
					Progress = ch.Progress,
					Target = target,
					Completed = ch.Completed,
				})
			end
		end
	end
end

-- ============================================================
-- Challenge Completion & Rewards
-- ============================================================

function ChallengeService:_awardChallengeCompletion(player, challenge)
	-- Award XP via PlayerDataService
	if self.Services.PlayerDataService then
		if challenge.Reward.XP and challenge.Reward.XP > 0 then
			self.Services.PlayerDataService:AddXP(player, challenge.Reward.XP)
			-- Also award Dive Pass XP (100 per challenge per GDD 5.4)
			self.Services.PlayerDataService:AddDivePassXP(player, 100)
		end
		if challenge.Reward.Coins and challenge.Reward.Coins > 0 then
			self.Services.PlayerDataService:AddCoins(player, challenge.Reward.Coins)
		end
	end

	print(string.format("[ChallengeService] %s completed challenge: %s (+%d XP, +%d Coins)",
		player.Name, challenge.Name, challenge.Reward.XP or 0, challenge.Reward.Coins or 0))

	-- Check if all 3 done
	self:_checkAllComplete(player)
end

function ChallengeService:_checkAllComplete(player)
	local state = self._playerChallenges[player]
	if not state or state.AllCompleteBonusClaimed then return end

	local allComplete = true
	for _, ch in ipairs(state.AssignedChallenges) do
		if not ch.Completed then
			allComplete = false
			break
		end
	end

	if allComplete then
		state.AllCompleteBonusClaimed = true

		-- Award complete-all bonus
		if self.Services.PlayerDataService then
			self.Services.PlayerDataService:AddXP(player, COMPLETE_ALL_BONUS_XP)
			self.Services.PlayerDataService:AddDivePassXP(player, COMPLETE_ALL_BONUS_XP)
			self.Services.PlayerDataService:AddGems(player, COMPLETE_ALL_BONUS_GEMS)
		end

		self.Client.AllChallengesCompleted:Fire(player, {
			XP = COMPLETE_ALL_BONUS_XP,
			Gems = COMPLETE_ALL_BONUS_GEMS,
		})

		-- Check streak bonus
		if state.Streak >= STREAK_DAYS_FOR_BONUS then
			if self.Services.PlayerDataService then
				self.Services.PlayerDataService:AddXP(player, STREAK_BONUS_XP)
				self.Services.PlayerDataService:AddDivePassXP(player, STREAK_BONUS_XP)
				self.Services.PlayerDataService:AddGems(player, STREAK_BONUS_GEMS)
			end
			self.Client.StreakMilestone:Fire(player, {
				StreakDays = state.Streak,
				XP = STREAK_BONUS_XP,
				Gems = STREAK_BONUS_GEMS,
			})
		end

		print(string.format("[ChallengeService] %s completed ALL daily challenges! (streak: %d)",
			player.Name, state.Streak))
	end
end

-- ============================================================
-- Reroll
-- ============================================================

function ChallengeService:RerollChallenge(player, challengeId)
	local state = self._playerChallenges[player]
	if not state then return false, "NoChallenges" end

	local targetIdx = nil
	for i, ch in ipairs(state.AssignedChallenges) do
		if ch.Id == challengeId and not ch.Completed then
			targetIdx = i
			break
		end
	end

	if not targetIdx then
		return false, "NotFoundOrCompleted"
	end

	-- Check free rerolls available
	local data = self.Services.PlayerDataService:GetData(player)
	if not data then return false, "NoData" end

	if state.FreeRerollsUsed < FREE_REROLLS_PER_DAY then
		state.FreeRerollsUsed = state.FreeRerollsUsed + 1
	else
		-- Costs 10 Gems
		if data.Currency.Gems < REROLL_GEM_COST then
			return false, "NotEnoughGems"
		end
		self.Services.PlayerDataService:AddGems(player, -REROLL_GEM_COST)
	end

	-- Remove old and assign new from same difficulty pool
	local oldChallenge = state.AssignedChallenges[targetIdx]
	local difficulty = oldChallenge.Difficulty

	local pool = {}
	for _, ch in ipairs(CHALLENGE_POOL) do
		if not ch.IsFuture and ch.Difficulty == difficulty and ch.Id ~= oldChallenge.Id then
			-- Zone lock checks
			local skip = false
			if ch.RequiresKelpForest then
				local zoneConfig = Shared.Constants.ZoneConfigs.GetByKey("KelpForest")
				if zoneConfig and zoneConfig.UnlockRequirement then
					local req = zoneConfig.UnlockRequirement
					if not data.Gear.OwnedRods[req.RequiredRod] or data.Progression.TotalCatches < req.TotalCatches then
						skip = true
					end
				end
			elseif ch.RequiresDeepDiverSuit then
				if not data.Gear.OwnedSuits["DeepDiverSuit"] then
					skip = true
				end
			end
			-- Skip already assigned
			for _, existing in ipairs(state.AssignedChallenges) do
				if existing.Id == ch.Id then
					skip = true
					break
				end
			end
			if not skip then
				pool[#pool + 1] = ch
			end
		end
	end

	if #pool == 0 then
		return false, "NoAlternatives"
	end

	local newChallenge = pool[math.random(#pool)]
	state.AssignedChallenges[targetIdx] = {
		Id = newChallenge.Id,
		Name = newChallenge.Name,
		Category = newChallenge.Category,
		Difficulty = newChallenge.Difficulty,
		Requirement = newChallenge.Requirement,
		Reward = newChallenge.Reward,
		Progress = 0,
		Target = newChallenge.Requirement.Count or 1,
		Completed = false,
		Claimed = false,
	}

	-- Push updated challenges
	self.Client.GetDailyChallenges:Fire(player, state.AssignedChallenges)

	return true, "Replaced"
end

-- ============================================================
-- Queries
-- ============================================================

function ChallengeService:GetChallengesForPlayer(player)
	self:EnsureChallengesAssigned(player)
	local state = self._playerChallenges[player]
	if not state then return {} end
	return state.AssignedChallenges
end

function ChallengeService:GetStreak(player)
	local state = self._playerChallenges[player]
	return state and state.Streak or 0
end

-- ============================================================
-- Daily Reset Check
-- ============================================================

function ChallengeService:CheckDailyReset()
	local today = getMidnightUTC()

	for player, state in pairs(self._playerChallenges) do
		if state.Date ~= today then
			-- Check if all challenges completed yesterday (for streak)
			local allDone = self:_countCompleted(state) >= CHALLENGES_PER_DAY

			-- Assign new challenges for today
			self:AssignDailyChallenges(player, today, state)
		end
	end
end

-- ============================================================
-- Helpers
-- ============================================================

function ChallengeService:_countCompleted(state)
	local count = 0
	for _, ch in ipairs(state.AssignedChallenges) do
		if ch.Completed then
			count = count + 1
		end
	end
	return count
end

return ChallengeService
