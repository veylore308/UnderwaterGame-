--[[
    FishingService.lua
    Deep Tide Studios — Server Service
    Authoritative fishing logic: validates casts, hooks, and reeling.
    Integrated with FishNPC system — hooks real fish instead of random species.
    Prevents exploits by being the single source of truth for catch outcomes.
]]

local Knit = require(game:GetService("ReplicatedStorage"):WaitForChild("Knit"))
local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))
local FishSignals = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("NPC"):WaitForChild("FishSignals"))
local HttpService = game:GetService("HttpService")

local FishingService = Knit.CreateService({
    Name = "FishingService",
    Client = {
        -- Client -> Server remote calls
        CastLine = Knit.CreateSignal(),        -- (targetPosition) -> { Success, CastId }
        HookAttempt = Knit.CreateSignal(),     -- (castId, timingQuality) -> { Result, FishData? }
        ReelUpdate = Knit.CreateSignal(),      -- (castId, input) -> { Tension, Progress, State }
        CancelFishing = Knit.CreateSignal(),   -- (castId) -> nil

        -- Server -> Client events
        FishHooked = Knit.CreateSignal(),       -- (fishData)
        FishCaught = Knit.CreateSignal(),       -- (fishData, rewards)
        FishEscaped = Knit.CreateSignal(),      -- (reason)
        LineSnapped = Knit.CreateSignal(),      -- ()
        SonarPing = Knit.CreateSignal(),        -- (pingData) — Phase 2 sonar
    },
})

-- ============================================================
-- Active fishing sessions
-- ============================================================
FishingService._activeSessions = {} -- { [player] = SessionState }

-- SessionState:
-- {
--   CastId = string,
--   TargetPosition = Vector3,
--   CastTime = number,
--   FishId = string?,
--   FishNPC = FishNPC?,
--   SpeciesKey = string?,
--   Phase = "Casting" | "Waiting" | "Biting" | "Hooking" | "Reeling" | "Caught",
--   Tension = number (0-100),
--   Progress = number (0-100),
--   BiteStartTime = number?,
--   SpeciesBiteDelay = number?,
-- }

-- ============================================================

function FishingService:KnitStart()
    print("[FishingService] Started — integrated with FishNPC system")
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

    -- Start the global sonar loop for all players
    self:_startSonarLoop()
end

-- ============================================================
-- Sonar System (GDD 4.1.1 — Phase 2)
-- Ping every 3s if equipped rod has SonarRange > 0.
-- Returns fish within range with rarity-colored silhouettes.
-- Works through kelp/camouflage — sonar bypasses visual stealth.
-- ============================================================

FishingService._sonarPlayerData = {} -- { [player] = { lastPingTime, rodKey } }

function FishingService:_startSonarLoop()
    task.spawn(function()
        while true do
            task.wait(0.5) -- check every 500ms for efficiency

            local now = tick()
            local players = game:GetService("Players"):GetPlayers()

            for _, player in ipairs(players) do
                local data = self.Services.PlayerDataService:GetData(player)
                if not data then continue end

                local rod = Shared.Constants.RodTiers.GetByKey(data.Gear.EquippedRod)
                if not rod or not rod.SonarRange or rod.SonarRange <= 0 then
                    -- No sonar on this rod — skip
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

    -- Get all fish within sonar range from the zone
    local nearbyFish = self.Services.ZoneService:GetFishNearBobber(playerPos, sonarRange, zoneKey)

    local detectedFish = {}
    for _, entry in ipairs(nearbyFish) do
        if entry.Fish and entry.Fish.Species then
            local species = entry.Fish.Species
            local distance = entry.Distance or ((entry.Fish:GetPosition() - playerPos).Magnitude)

            -- Sonar bypasses camouflage (GDD 4.1.1: works through kelp/visual obstruction)
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

    -- Also scan fish from the zone spawner for fish not yet in the near-bobber list
    local spawner = self.Services.ZoneService:GetSpawner(zoneKey)
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

    -- Send ping data to client
    if #detectedFish > 0 then
        self.Client.SonarPing:Fire(player, {
            Origin = playerPos,
            Range = sonarRange,
            DetectedFish = detectedFish,
            Timestamp = tick(),
        })
    end
end

-- ============================================================
-- Cast
-- ============================================================

function FishingService:ProcessCast(player, targetPosition)
    local session = self._activeSessions[player]
    if session then
        return { Success = false, Message = "Already fishing" }
    end

    -- Get player's equipped rod
    local data = self.Services.PlayerDataService:GetData(player)
    if not data then
        return { Success = false, Message = "Player data not loaded" }
    end

    local rod = Shared.Constants.RodTiers.GetByKey(data.Gear.EquippedRod)
    if not rod then
        return { Success = false, Message = "No rod equipped" }
    end

    -- Validate cast range
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

    -- Register bobber with ZoneService so fish can detect it
    local zoneKey = self.Services.ZoneService:GetPlayerZone(player) or "SunkenShallows"
    self.Services.ZoneService:RegisterBobber(player.UserId, targetPosition, zoneKey)

    -- Notify nearby fish about the bobber
    self:_notifyFishOfBobber(targetPosition, player, zoneKey)

    return { Success = true, CastId = castId }
end

-- ============================================================
-- Notify fish NPCs about a new bobber in the water
-- ============================================================
function FishingService:_notifyFishOfBobber(position, player, zoneKey)
    local nearbyFish = self.Services.ZoneService:GetFishNearBobber(position, 30, zoneKey)

    for _, entry in ipairs(nearbyFish) do
        if entry.Fish and not entry.Fish:IsHooked() then
            entry.Fish:OnBobberNearby(position, player.UserId)
        end
    end
end

-- ============================================================
-- Hook (bite timing)
-- ============================================================

function FishingService:ProcessHook(player, castId, timingQuality)
    local session = self._activeSessions[player]
    if not session or session.CastId ~= castId then
        return { Result = "InvalidSession" }
    end

    -- timingQuality from client: "Perfect" | "Good" | "Early" | "Late"

    -- Resolve which real fish is biting (from NPC system)
    local bitingFish = self:_resolveBitingFish(session)
    session.FishNPC = bitingFish
    session.FishId = bitingFish and bitingFish.Id

    if timingQuality == "Early" then
        -- Roll for flee
        local fleeChance = Shared.Fishing.FleeChanceCommon
        if bitingFish then
            if bitingFish.Species.Rarity == "Legendary" then
                fleeChance = Shared.Fishing.FleeChanceLegendary
            elseif bitingFish.Species.Rarity == "Uncommon" or bitingFish.Species.Rarity == "Rare" then
                fleeChance = Shared.Fishing.FleeChanceUncommonPlus
            end
        end

        if math.random() < fleeChance then
            -- Notify fish to flee
            if bitingFish then
                bitingFish:OnHookAttempt(false)
            end
            self:CancelSession(player)
            return { Result = "FishFled" }
        end

        -- Otherwise, reset to waiting
        session.Phase = "Waiting"
        return { Result = "TooSoon" }
    end

    if timingQuality == "Late" then
        -- Always flees
        if bitingFish then
            bitingFish:OnHookAttempt(false)
        end
        self:CancelSession(player)
        return { Result = "FishFled" }
    end

    -- "Perfect" or "Good" — hook successful
    -- Need a real fish to hook
    if not bitingFish then
        -- Fallback: no real fish nearby, resolve randomly
        bitingFish = nil
        session.FishId = nil
        session.FishNPC = nil
    else
        -- Notify fish it's been hooked
        bitingFish:OnHookAttempt(true)
    end

    -- Resolve species
    local species = self:_resolveBitingSpecies(session, bitingFish)
    if not species then
        self:CancelSession(player)
        return { Result = "NoFishNearby" }
    end

    session.Phase = "Reeling"
    session.Tension = (timingQuality == "Perfect") and 0 or 20 -- Perfect starts with lower tension
    session.SpeciesKey = species.Key

    -- Calculate catch: weight and price
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

    -- Notify client
    self.Client.FishHooked:Fire(player, fishData)

    return {
        Result = "Hooked",
        FishData = fishData,
        Tension = session.Tension,
    }
end

-- ============================================================
-- Reel Tick (called at ~10Hz by client loop)
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
        -- Tension increases while reeling
        local increase = Shared.Fishing.BaseReelRate * rod.ReelSpeed * (1.0 - (session.Progress / 100) * Shared.Fishing.ProgressDecayFactor)
        session.Tension = math.min(tensionMax, session.Tension + increase * tickRate)

        -- Progress increases
        local progressGain = 2.0 * rod.ReelSpeed * tickRate
        session.Progress = math.min(100, session.Progress + progressGain)

        -- Check for fish tug
        if math.random() < (0.3 * tickRate) then -- ~30% chance per second
            local tugStrength = species.TugStrength * (0.8 + math.random() * 0.4)
            session.Tension = math.min(tensionMax, session.Tension + tugStrength * tensionMax)
        end
    else
        -- Tension decreases when released
        local decrease = Shared.Fishing.BaseReleaseRate * rod.ReelSpeed
        session.Tension = math.max(0, session.Tension - decrease * tickRate)
    end

    -- Check line snap (tension too high)
    if session.Tension >= tensionMax then
        -- Notify fish it's free
        if session.FishNPC then
            session.FishNPC:OnLineSnap()
        end
        self.Client.LineSnapped:Fire(player)
        self.CancelSession(player)
        return { State = "LineSnapped", Tension = tensionMax, Progress = session.Progress }
    end

    -- Check fish escaped (tension too low — not enough pressure)
    if session.Tension <= 0 and session.Progress > 0 then
        -- Fish slips off the hook
        if session.FishNPC then
            session.FishNPC:OnEscape()
        end
        self.Client.FishEscaped:Fire(player, "LowTension")
        self.CancelSession(player)
        return { State = "FishEscaped", Reason = "LowTension", Tension = 0, Progress = session.Progress }
    end

    -- Check catch complete
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

    -- Notify fish NPC it's been caught (triggers despawn)
    if session.FishNPC then
        session.FishNPC:OnCaught()
    end

    -- Despawn from zone
    local zoneKey = self.Services.ZoneService:GetPlayerZone(player) or "SunkenShallows"
    if session.FishId then
        self.Services.ZoneService:DespawnFish(zoneKey, session.FishId)
    end

    -- Add fish to player inventory
    local success, reason = self.Services.PlayerDataService:AddFish(
        player,
        fishData.SpeciesKey,
        fishData.Weight,
        fishData.SellPrice
    )

    if not success then
        -- Inventory full — fish is lost
        self:CancelSession(player)
        return { State = "InventoryFull", Reason = reason }
    end

    -- Award XP
    local species = Shared.Constants.FishSpecies.GetByKey(fishData.SpeciesKey)
    local xp = Shared.Constants.RarityTiers.GetXPValue(fishData.Rarity)
    self.Services.PlayerDataService:AddXP(player, xp)

    -- Award Dive Pass XP based on rarity (GDD 5.4)
    self.Services.PlayerDataService:AddDivePassXPForCatch(player, fishData.Rarity)

    -- Report to ChallengeService
    if self.Services.ChallengeService then
        self.Services.ChallengeService:ReportProgress(player, "CatchRarity", {
            Rarity = fishData.Rarity,
            Count = 1,
        })
        self.Services.ChallengeService:ReportProgress(player, "CatchAny", {
            Count = 1,
        })
        self.Services.ChallengeService:ReportProgress(player, "CatchWeight", {
            WeightKg = fishData.Weight,
            Count = 1,
        })
        -- Zone-specific
        local speciesZone = species.Zone or "SunkenShallows"
        self.Services.ChallengeService:ReportProgress(player, "CatchInZone", {
            Zone = speciesZone,
            Count = 1,
        })
    end

    -- Report depth milestone to ChallengeService (if applicable)
    local playerPos = player.Character and player.Character:GetPivot().Position
    if playerPos then
        local depth = math.abs(playerPos.Y) -- assuming Y is vertical, negative = below surface
        if self.Services.ChallengeService then
            self.Services.ChallengeService:ReportProgress(player, "DepthReached", {
                Depth = depth,
                Count = 1,
            })
        end
    end

    -- Cleanup
    self.Client.FishCaught:Fire(player, fishData, { XP = xp })
    self._activeSessions[player] = nil

    return {
        State = "Caught",
        FishData = fishData,
        Tension = session.Tension,
        Progress = 100,
    }
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

    -- Unregister bobber
    local zoneKey = self.Services.ZoneService:GetPlayerZone(player) or "SunkenShallows"
    self.Services.ZoneService:UnregisterBobber(player.UserId, zoneKey)

    -- If fish was hooked, release it
    if session.FishNPC and (session.Phase == "Reeling" or session.Phase == "Hooking") then
        session.FishNPC:OnEscape()
    end

    self._activeSessions[player] = nil
end

-- ============================================================
-- Resolve which REAL fish is near the bobber and biting
-- ============================================================
function FishingService:_resolveBitingFish(session)
    local zoneKey = "SunkenShallows" -- MVP: single zone
    local bobberPos = session.TargetPosition

    -- Get all fish near the bobber
    local nearbyFish = self.Services.ZoneService:GetFishNearBobber(bobberPos, 15, zoneKey)

    -- Prefer fish in ReadyToBite or Biting state
    for _, entry in ipairs(nearbyFish) do
        if entry.IsBiteReady then
            return entry.Fish
        end
    end

    -- Next preference: fish in Curious or Investigate state that are close
    for _, entry in ipairs(nearbyFish) do
        if entry.State == FishSignals.FishState.Curious
            or entry.State == FishSignals.FishState.Investigate then
            -- Transition them to Biting
            if entry.Fish._transitionTo then
                entry.Fish:_transitionTo(FishSignals.FishState.Biting)
            end
            return entry.Fish
        end
    end

    -- No real fish nearby — fallback to random (for now, or return nil)
    return nil
end

-- ============================================================
-- Resolve species — from real fish or fallback random
-- ============================================================
function FishingService:_resolveBitingSpecies(session, bitingFish)
    if bitingFish then
        return bitingFish.Species
    end

    -- Fallback: no real fish found, use random weighted by spawn rates
    -- This should be rare — fish should always be detectable near bobbers
    local spawnTable, totalWeight = Shared.Constants.FishSpecies.GetSpawnTable(0)
    local roll = math.random() * totalWeight

    for _, entry in ipairs(spawnTable) do
        if roll <= entry.CumulativeWeight then
            return entry.Species
        end
    end

    return Shared.Constants.FishSpecies[1] -- ultimate fallback
end

function FishingService:_rollWeight(species)
    local minW = species.WeightRange.Min
    local maxW = species.WeightRange.Max
    -- Normal-ish distribution centered on midpoint
    local midpoint = (minW + maxW) / 2
    local stddev = (maxW - minW) / 6 -- ~99.7% within range

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

    -- Linear interpolation based on weight
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
