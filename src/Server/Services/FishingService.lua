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
        -- Phase 3: Surface fishing
        BobberDrifted = Knit.CreateSignal(),       -- (castId, bobberPosition) — drifting surface bobber
        RodLost = Knit.CreateSignal(),             -- (rodData) — storm rod-loss
        RodRecovered = Knit.CreateSignal(),        -- (rodData) — rod recovered at sea
        RodExpired = Knit.CreateSignal(),          -- (rodData) — rod lost for good, rebuy at 50%
        RecoverRod = Knit.CreateSignal(),          -- (rodId) -> result
        WeatherModifiers = Knit.CreateSignal(),    -- (modifiers) — current weather fishing mods
    },
})

-- Active fishing sessions
FishingService._activeSessions = {}

-- Phase 3: lost surface rods (storm rod-loss mechanic, GDD 4.3)
FishingService._lostRods = {}   -- [rodId] = { Player, RodKey, DropPosition, ExpiresAt, Marker }

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

    -- Phase 3: Lost-rod recovery
    self.Client.RecoverRod:Connect(function(player, rodId)
        return self:RecoverRod(player, rodId)
    end)

    -- Start the global sonar loop
    self:_startSonarLoop()

    -- Phase 3: Surface bobber drift + line-break + rod expiry loop
    self:_startSurfaceLoop()
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

    -- Phase 3: surface cast (from a boat) vs underwater cast
    local isSurface, surfaceInfo = self:IsSurfaceCast(player, targetPosition)

    local rod
    if isSurface then
        rod = Shared.Constants.SurfaceRodTiers.GetByKey(data.Gear.EquippedSurfaceRod)
        if not rod then
            return { Success = false, Message = "No surface rod equipped" }
        end
    else
        rod = Shared.Constants.RodTiers.GetByKey(data.Gear.EquippedRod)
        if not rod then
            return { Success = false, Message = "No rod equipped" }
        end
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
    local bobberPos = isSurface and Vector3.new(targetPosition.X, 0, targetPosition.Z) or targetPosition
    session = {
        CastId = castId,
        TargetPosition = targetPosition,
        BobberPosition = bobberPos,
        CastTime = tick(),
        Phase = "Waiting",
        Tension = 0,
        Progress = 0,
        RodKey = rod.Key,
        RodStats = rod,
        FishId = nil,
        FishNPC = nil,
        -- Phase 3: surface session state
        Surface = isSurface and true or false,
        SurfaceInfo = surfaceInfo,
        BobberDriftSpeed = surfaceInfo and surfaceInfo.BobberDriftSpeed or 0,
        _nextSpecial = 0,
        _slackUntil = 0,
        _runUntil = 0,
    }
    self._activeSessions[player] = session

    -- Register bobber with ZoneService
    local zoneKey = isSurface and "Surface" or (self.Services.ZoneService:GetPlayerZone(player) or "SunkenShallows")
    self.Services.ZoneService:RegisterBobber(player.UserId, bobberPos, zoneKey)

    -- Notify nearby fish about the bobber
    self:_notifyFishOfBobber(bobberPos, player, zoneKey)

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
    local now = tick()

    -- Phase 3: weather tension modifier (Calm 0 / Rain +15% / Storm +40%)
    local tensionMod = 0
    if session.Surface and session.SurfaceInfo then
        tensionMod = session.SurfaceInfo.TensionMod or 0
    end

    -- Phase 3: surface species signature behaviors (leap, run, glide, surrender)
    if session.Surface then
        self:_applySurfaceReelBehavior(session, species, now, tickRate)
    end

    -- Slack windows (Flying Fish glide, Mahi land): tension drops to 0;
    -- over-reeling during slack snaps the line at 2x rate
    local inSlack = session._slackUntil and now < session._slackUntil

    if isReeling then
        local increase = Shared.Fishing.BaseReelRate * rod.ReelSpeed
            * (1.0 - (session.Progress / 100) * Shared.Fishing.ProgressDecayFactor)
            * (1.0 + tensionMod)
        if inSlack then
            increase = increase * 2.0  -- over-reel during slack: punished
        end
        session.Tension = math.min(tensionMax, session.Tension + increase * tickRate)

        local progressGain = 2.0 * rod.ReelSpeed * tickRate
        if inSlack then progressGain = progressGain * 0.25 end -- no progress while slack
        session.Progress = math.min(100, session.Progress + progressGain)

        if math.random() < (0.3 * tickRate) then
            local tugStrength = species.TugStrength * (0.8 + math.random() * 0.4)
            session.Tension = math.min(tensionMax, session.Tension + tugStrength * tensionMax)
        end
    else
        local decrease = Shared.Fishing.BaseReleaseRate * rod.ReelSpeed
        if inSlack then
            decrease = decrease * 2.0 -- slack releases fast
        end
        session.Tension = math.max(0, session.Tension - decrease * tickRate)
    end

    -- Phase 3: boat-speed line break — boat moving > 8 studs/s snaps the line
    if session.Surface and session.SurfaceInfo then
        local boatSpeed = self.Services.BoatService and self.Services.BoatService:GetBoatSpeed(player) or 0
        if boatSpeed > (session.SurfaceInfo.BoatSpeedLimit or 8) then
            return self:_onLineSnap(player, session, "BoatSpeed")
        end
    end

    if session.Tension >= tensionMax then
        return self:_onLineSnap(player, session, "Tension")
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
        BobberPosition = session.BobberPosition, -- Phase 3: drifting bobber
    }
end

-- ============================================================
-- Phase 3: surface species signature reel behaviors
-- ============================================================
function FishingService:_applySurfaceReelBehavior(session, species, now, tickRate)
    local key = species.Key
    local tensionMax = Shared.Fishing.TensionMax

    if key == "MahiMahi" then
        -- Leap: +40% tension spike, then slack (GDD 4.6.4.5)
        if now >= (session._nextSpecial or 0) then
            session._nextSpecial = now + 4 + math.random() * 2
            session.Tension = math.min(tensionMax, session.Tension + 40)
            session._slackUntil = now + 0.8
        end
    elseif key == "Sailfish" then
        -- The Run: sustained 45% tension for 2s, then 1.5s window (GDD 4.6.4.6)
        if now >= (session._nextSpecial or 0) then
            session._nextSpecial = now + 5 + math.random() * 2
            session._runUntil = now + 2
        end
        if session._runUntil and now < session._runUntil then
            session.Tension = math.min(tensionMax, session.Tension + 45 * tickRate)
        end
    elseif key == "FlyingFish" then
        -- Glide slack: drops line tension to 0 for 0.5s (GDD 4.6.4.3)
        if now >= (session._nextSpecial or 0) then
            session._nextSpecial = now + 5 + math.random() * 3
            session._slackUntil = now + 0.5
        end
    elseif key == "Moonfish" then
        -- Steady heavy pulls + 1s surrender windows bait over-reeling (GDD 4.6.4.7)
        if now >= (session._nextSpecial or 0) then
            session._nextSpecial = now + 3 + math.random() * 2
            if math.random() < 0.5 then
                session.Tension = math.min(tensionMax, session.Tension + 35)
            else
                session._slackUntil = now + 1.0 -- surrender window
            end
        end
    elseif key == "StormMarlin" then
        -- Alternating: 3s runs, 0.5s head-shake spikes, slack feints (GDD 4.6.4.8)
        if now >= (session._nextSpecial or 0) then
            session._nextSpecial = now + 2.5 + math.random() * 1.5
            local roll = math.random()
            if roll < 0.4 then
                session._runUntil = now + 1.5
            elseif roll < 0.7 then
                session.Tension = math.min(tensionMax, session.Tension + 30)
            else
                session._slackUntil = now + 0.5
            end
        end
        if session._runUntil and now < session._runUntil then
            session.Tension = math.min(tensionMax, session.Tension + 50 * tickRate)
        end
    end
end

-- ============================================================
-- Phase 3: line snap (tension or boat speed) + storm rod-loss roll
-- ============================================================
function FishingService:_onLineSnap(player, session, reason)
    if session.FishNPC then
        session.FishNPC:OnLineSnap()
    end

    local rodLostData = nil
    if session.Surface then
        rodLostData = self:_rollRodLoss(player, session)
    end

    self.Client.LineSnapped:Fire(player, { Reason = reason })
    self.CancelSession(player)
    return { State = "LineSnapped", Tension = Shared.Fishing.TensionMax, Progress = session.Progress, RodLost = rodLostData ~= nil }
end

-- ============================================================
-- Phase 3: storm rod-loss (GDD 4.3) — 12% base × (1 − Line Strength)
-- ============================================================
function FishingService:_rollRodLoss(player, session)
    local weatherService = self.Services.WeatherService
    if not weatherService then return nil end
    local state, cfg = weatherService:GetState()
    if state ~= "Storm" then return nil end

    local baseChance = cfg.RodLossChance or 0.12
    local lineStrength = session.RodStats.LineStrength or 0
    local finalChance = baseChance * (1 - lineStrength)
    if math.random() >= finalChance then return nil end

    -- Rod flung 15-30 studs downwind, floats with a red marker (5 min)
    local wind = weatherService:GetWindVector()
    local windDir = wind.Magnitude > 0.1 and wind.Unit or Vector3.new(1, 0, 0)
    local dropPos = (session.BobberPosition or session.TargetPosition) + windDir * (15 + math.random() * 15)
    dropPos = Vector3.new(dropPos.X, 0.5, dropPos.Z)

    local rodId = HttpService:GenerateGUID(false)
    local expiresAt = os.time() + 300

    local marker = self:_createLostRodMarker(rodId, dropPos)

    self._lostRods[rodId] = {
        Player = player,
        RodKey = session.RodStats.Key,
        DropPosition = dropPos,
        ExpiresAt = expiresAt,
        Marker = marker,
    }

    local rodData = {
        RodId = rodId,
        RodKey = session.RodStats.Key,
        RodName = session.RodStats.Name,
        DropPosition = dropPos,
        ExpiresAt = expiresAt,
        RebuyCost = math.floor((session.RodStats.Cost or 0) * 0.5),
    }
    self.Client.RodLost:Fire(player, rodData)
    return rodData
end

function FishingService:_createLostRodMarker(rodId, position)
    local model = Instance.new("Model")
    model.Name = "LostRod_" .. rodId

    local float = Instance.new("Part")
    float.Name = "Float"
    float.Shape = Enum.PartType.Ball
    float.Size = Vector3.new(0.8, 0.8, 0.8)
    float.Position = position
    float.Anchored = true
    float.CanCollide = false
    float.Material = Enum.Material.Neon
    float.Color = Color3.fromRGB(255, 60, 60)
    float.Parent = model

    local pole = Instance.new("Part")
    pole.Name = "Pole"
    pole.Size = Vector3.new(0.12, 1.5, 0.12)
    pole.Position = position + Vector3.new(0, 0.9, 0)
    pole.Anchored = true
    pole.CanCollide = false
    pole.Material = Enum.Material.SmoothPlastic
    pole.Color = Color3.fromRGB(80, 80, 120)
    pole.Parent = model

    local label = Instance.new("BillboardGui")
    label.Name = "RecoverLabel"
    label.Size = UDim2.new(0, 160, 0, 40)
    label.StudsOffset = Vector3.new(0, 2.2, 0)
    label.AlwaysOnTop = true
    local text = Instance.new("TextLabel")
    text.Size = UDim2.new(1, 0, 1, 0)
    text.BackgroundTransparency = 1
    text.Text = "LOST ROD — E TO RECOVER"
    text.TextColor3 = Color3.new(1, 1, 1)
    text.TextStrokeTransparency = 0
    text.Font = Enum.Font.GothamBold
    text.TextScaled = true
    text.Parent = label
    label.Parent = model

    model.PrimaryPart = float
    model.Parent = workspace
    return model
end

-- ============================================================
-- Phase 3: recover a lost rod (owner only, within 10 studs)
-- ============================================================
function FishingService:RecoverRod(player, rodId)
    local lost = self._lostRods[rodId]
    if not lost then return false, "Not found" end
    if lost.Player ~= player then return false, "Not your rod" end
    if os.time() > lost.ExpiresAt then return false, "Rod lost at sea" end

    local char = player.Character
    local pos = char and char:GetPivot().Position
    if not pos then return false, "Character not found" end
    if (pos - lost.DropPosition).Magnitude > 10 then return false, "Too far" end

    -- Re-equip the surface rod
    self.Services.PlayerDataService:GrantSurfaceRod(player, lost.RodKey)
    self.Services.PlayerDataService:EquipSurfaceRod(player, lost.RodKey)

    if lost.Marker then lost.Marker:Destroy() end
    self._lostRods[rodId] = nil

    local rodData = { RodId = rodId, RodKey = lost.RodKey }
    self.Client.RodRecovered:Fire(player, rodData)
    return true, "Recovered"
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

    local zoneKey = session.Surface and "Surface" or (self.Services.ZoneService:GetPlayerZone(player) or "SunkenShallows")
    if session.FishId then
        self.Services.ZoneService:DespawnFish(zoneKey, session.FishId)
    end

    -- Phase 3: surface catches route to boat storage first (Trawler 40 / RV 100),
    -- then personal inventory on overflow (Raft has no hold)
    local storedInBoat = false
    if session.Surface and self.Services.BoatService then
        local ok = self.Services.BoatService:AddFishToStorage(player, fishData)
        if ok then storedInBoat = true end
    end

    if not storedInBoat then
        local success, reason = self.Services.PlayerDataService:AddFish(
            player, fishData.SpeciesKey, fishData.Weight, fishData.SellPrice
        )

        if not success then
            self.CancelSession(player)
            return { State = "InventoryFull", Reason = reason }
        end
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

    -- Phase 3: Captain XP for surface catches (GDD 7.2)
    if session.Surface and self.Services.CaptainService then
        local captainXp = 0
        if fishData.Rarity == "Common" then captainXp = 10
        elseif fishData.Rarity == "Uncommon" then captainXp = 25
        elseif fishData.Rarity == "Rare" then captainXp = 60
        elseif fishData.Rarity == "Legendary" then captainXp = 150 end
        if fishData.Rarity == "Rare" or fishData.Rarity == "Legendary" then
            captainXp = captainXp + 40 -- Rare+ bonus
        end
        -- Storm catch bonus
        local wState = self.Services.WeatherService and self.Services.WeatherService:GetState() or "Calm"
        if wState == "Storm" then captainXp = captainXp + 50 end
        if captainXp > 0 then
            pcall(function()
                self.Services.CaptainService:AwardXP(player, captainXp, "SurfaceCatch")
            end)
        end
    end

    local playerPos = player.Character and player.Character:GetPivot().Position
    if playerPos then
        local depth = math.abs(playerPos.Y)
        if self.Services.ChallengeService then
            self.Services.ChallengeService:ReportProgress(player, "DepthReached", { Depth = depth, Count = 1 })
        end
    end

    self.Client.FishCaught:Fire(player, fishData, { XP = xp, Storage = storedInBoat and "Boat" or "Inventory" })
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

    local zoneKey = session.Surface and "Surface" or (self.Services.ZoneService:GetPlayerZone(player) or "SunkenShallows")
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
    local zoneKey = session.Surface and "Surface" or (self.Services.ZoneService:GetPlayerZone(player) or "SunkenShallows")
    local bobberPos = session.BobberPosition or session.TargetPosition

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
    local zoneKey = session.Surface and "Surface" or (self.Services.ZoneService:GetPlayerZone(player) or "SunkenShallows")
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

-- ============================================================
-- Phase 3: Surface fishing helpers
-- ============================================================

--- Detect a surface cast. Player must be aboard a boat; casting while
--- moving auto-brakes the boat (anchor) per GDD 4.1. Returns
--- (true, surfaceInfo) or (false, reason).
function FishingService:IsSurfaceCast(player, targetPosition)
    local boatService = self.Services.BoatService
    if not boatService then return false, "No boat service" end

    local onBoat, boat = boatService:IsOnBoat(player)
    if not onBoat then return false, "Not on a boat" end
    if not boat then return false, "No boat" end

    -- Casting while moving auto-brakes the boat to < 2 studs/s
    local speed = boatService:GetBoatSpeed(player)
    if speed >= 2 and not boat.Anchored then
        boatService:SetAnchor(player)
    end

    -- Bobber drift speed per weather (calm: none / rain: 3 / storm: 8, GDD 4.1)
    local weatherState = "Calm"
    local tensionMod = 0
    local rodLossChance = 0
    local driftSpeed = 0
    if self.Services.WeatherService then
        local cfg
        weatherState, cfg = self.Services.WeatherService:GetState()
        cfg = cfg or {}
        driftSpeed = weatherState == "Storm" and 8 or (weatherState == "Rain" and 3 or 0)
        tensionMod = cfg.TensionMod or 0
        rodLossChance = cfg.RodLossChance or 0
    end

    return true, {
        Zone = "Surface",
        WeatherState = weatherState,
        BobberDriftSpeed = driftSpeed,
        TensionMod = tensionMod,
        RodLossChance = rodLossChance,
        BoatSpeedLimit = 8,   -- studs/s line-break rule
    }
end

--- Boat-speed line validation (used by client/server checks)
function FishingService:ValidateSurfaceLine(player)
    local boatService = self.Services.BoatService
    return not boatService or boatService:GetBoatSpeed(player) <= 8
end

-- ============================================================
-- Phase 3: Surface bobber loop — drift with wind/current, enforce the
-- boat-speed line break, and expire lost rods (GDD 4.1, 4.3)
-- ============================================================
function FishingService:_startSurfaceLoop()
    task.spawn(function()
        while true do
            task.wait(0.5)
            self:_updateSurfaceBobbers()
            self:_expireLostRods()
        end
    end)
end

function FishingService:_updateSurfaceBobbers()
    local weatherService = self.Services.WeatherService
    if not weatherService then return end

    local wind = weatherService:GetWindVector()

    for player, session in pairs(self._activeSessions) do
        if session.Surface then
            -- Drift the bobber on the water plane
            local driftSpeed = session.BobberDriftSpeed or 0
            if driftSpeed > 0 and wind.Magnitude > 0.1 then
                local windDir = wind.Unit
                session.BobberPosition = Vector3.new(
                    session.BobberPosition.X + windDir.X * driftSpeed * 0.5,
                    0,
                    session.BobberPosition.Z + windDir.Z * driftSpeed * 0.5
                )
                -- Re-notify fish near the drifted bobber
                self:_notifyFishOfBobber(session.BobberPosition, player, "Surface")
            end

            self.Client.BobberDrifted:Fire(player, session.CastId, session.BobberPosition)

            -- Boat-speed line break while line is out (all phases)
            local boatSpeed = self.Services.BoatService and self.Services.BoatService:GetBoatSpeed(player) or 0
            if boatSpeed > (session.SurfaceInfo and session.SurfaceInfo.BoatSpeedLimit or 8) then
                self:_onLineSnap(player, session, "BoatSpeed")
            end
        end
    end
end

function FishingService:_expireLostRods()
    local now = os.time()
    for rodId, lost in pairs(self._lostRods) do
        if now > lost.ExpiresAt then
            if lost.Marker then lost.Marker:Destroy() end
            self._lostRods[rodId] = nil
            self.Client.RodExpired:Fire(lost.Player, { RodId = rodId, RodKey = lost.RodKey })
        end
    end
end

return FishingService
