--[[
    FishSpawner.lua
    Deep Tide Studios — Server Fish Spawner
    Manages fish population, spawn/despawn cycle, patrol waypoint generation,
    schooling behavior, rare spawn conditions, and integration with ZoneService.

    Runs as a module used by ZoneService. Each zone gets one FishSpawner instance.
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
    self._legendaryAlive = false

    -- Patrol waypoints cache — generated once per landmark
    self._landmarkWaypoints = {} -- { [landmarkName] = { Vector3, ... } }

    -- Active bobber positions (reported by FishingService)
    self._activeBobbers = {}     -- { [playerId] = { position, castTime } }

    -- Player last-known positions
    self._playerPositions = {}   -- { [playerId] = Vector3 }

    -- Rare spawn tracking
    self._lastRespawnTime = tick()
    self._lastShipwreckVisit = 0
    self._serverStartTime = tick()
    self._serverUptimeBonus = 0

    -- Day cycle tracking (for Spectral Ray)
    self._dayCycleLength = zoneConfig.SpawnConditions.DayCycleMinutes * 60
    self._isNight = false

    -- Angler dim state tracking
    self._dimmedAnglers = {}     -- { [fishId] = dimUntilTimestamp }

    -- Abyssal Leviathan despawn tracking
    self._leviathanSpawned = false

    -- Generate waypoints for all landmarks
    self:_generateAllWaypoints()

    return self
end

-- ============================================================
-- Waypoint generation — 3-6 waypoints per landmark
-- ============================================================
function FishSpawner:_generateAllWaypoints()
    for _, landmark in ipairs(self.ZoneConfig.Landmarks) do
        local waypointCount = 3 + math.random(0, 3) -- 3-6 waypoints
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

-- ============================================================
-- Get waypoints for a specific landmark
-- ============================================================
function FishSpawner:GetWaypointsForLandmark(landmarkName)
    return self._landmarkWaypoints[landmarkName] or {}
end

-- ============================================================
-- Get waypoints for a species (based on its preferred landmark)
-- ============================================================
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
    -- Fallback: return first landmark's waypoints
    local firstLandmark = self.ZoneConfig.Landmarks[1]
    return firstLandmark and self._landmarkWaypoints[firstLandmark.Name] or {}
end

-- ============================================================
-- Spawn a single fish
-- ============================================================
function FishSpawner:SpawnFish(species)
    local population = self.ZoneConfig.Population
    local maxPop = population.MaxConcurrentFish

    if self._population >= maxPop then
        return nil
    end

    -- Check legendary cap
    if species.Rarity == "Legendary" and self._legendaryAlive then
        return nil
    end

    -- Generate spawn position
    local spawnPos = self:_getSpawnPosition(species)

    -- Check rare spawn conditions
    if species.Rarity == "Legendary" then
        if not self:_canSpawnLegendary(species) then
            return nil
        end
    elseif species.Rarity == "Rare" then
        -- Sunken Angler: check shipwreck visit conditions
        if species.Behavior == "Ambush" then
            local now = tick()
            local timeSinceVisit = now - self._lastShipwreckVisit
            local threshold = self.ZoneConfig.SpawnConditions.ZoneActivityThreshold or 300
            -- Angler always has a chance, but doubled if shipwreck unvisited
            -- (handled by ZoneService luck bonus)
        end
    end

    -- Create the NPC
    local waypoints = self:GetWaypointsForSpecies(species)
    local fish = FishNPC.new(species, spawnPos, {
        Waypoints = waypoints,
    })

    -- Create physical model
    local model = self:_createFishModel(species, spawnPos)
    fish:Initialize(model, self)

    -- Store
    self._fish[fish.Id] = fish
    self._population = self._population + 1

    -- Track legendary
    if species.Rarity == "Legendary" then
        self._legendaryAlive = true
    end

    -- Rare spawn bloom notification
    if species.Rarity == "Rare" or species.Rarity == "Legendary" then
        self:_fireRareSpawnBloom(spawnPos, species)
    end

    -- Auto-despawn timer for special fish
    if species.Key == "AbyssalLeviathan" then
        fish:SetDespawnTimer(60) -- 60s if not hooked
        self._leviathanSpawned = true
    end

    -- Notify via Knit signal if available
    self:_notifyFishSpawned(fish)

    return fish
end

-- ============================================================
-- Despawn a fish
-- ============================================================
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

    -- Track legendary removal
    if fish.Species.Rarity == "Legendary" then
        self._legendaryAlive = false
    end

    -- Clean dimmed angler tracking
    self._dimmedAnglers[fishId] = nil

    -- Destroy
    fish:Destroy()
    self._fish[fishId] = nil
    self._population = math.max(0, self._population - 1)

    -- Notify
    self:_notifyFishDespawned(fishId)
end

-- ============================================================
-- Spawn a school (for schooling species like Glowfin Minnow)
-- ============================================================
function FishSpawner:SpawnSchool(species, leaderFish)
    local schoolSize = 4 + math.random(0, 4) -- 4-8 fish
    local school = {}

    -- First fish is the leader
    if leaderFish then
        table.insert(school, leaderFish)
    else
        local leader = self:SpawnFish(species)
        if leader then
            table.insert(school, leader)
        else
            return school -- can't spawn leader, abort
        end
    end

    -- Spawn followers around leader
    local leader = school[1]
    local leaderPos = leader.Position

    for i = 2, schoolSize do
        -- Offset within 6-stud radius sphere of leader
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
        })
        local model = self:_createFishModel(species, followerPos)
        followerFish:Initialize(model, self)

        -- Followers use simplified AI (just follow leader)
        followerFish._isSchoolFollower = true
        followerFish._schoolLeader = leader

        self._fish[followerFish.Id] = followerFish
        self._population = self._population + 1
        table.insert(school, followerFish)
    end

    -- Store school reference on leader
    leader._school = school
    leader._isSchoolLeader = true

    return school
end

-- ============================================================
-- Population check: should respawn?
-- ============================================================
function FishSpawner:ShouldRespawn()
    local maxPop = self.ZoneConfig.Population.MaxConcurrentFish
    local deficit = maxPop - self._population

    -- Check special conditions only when population is low
    if deficit <= 0 then
        return false, 0
    end

    return true, deficit
end

-- ============================================================
-- Respawn cycle: fill population to cap
-- ============================================================
function FishSpawner:RunRespawnCycle(luckBonus)
    local maxPop = self.ZoneConfig.Population.MaxConcurrentFish
    local deficit = maxPop - self._population

    if deficit <= 0 then return end

    -- Get spawn table
    local spawnTable, totalWeight = FishSpecies.GetSpawnTable(luckBonus)

    -- Spawn up to 3 fish per cycle (avoid burst spawning)
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
            -- Legendary cap
            if selectedSpecies.Rarity == "Legendary" and self._legendaryAlive then
                -- Skip
            elseif selectedSpecies.Schooling then
                -- Spawn a school (counts as multiple fish toward cap)
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
    self._serverUptimeBonus = math.floor((tick() - self._serverStartTime) / self.ZoneConfig.SpawnConditions.ServerUptimeInterval)
        * self.ZoneConfig.SpawnConditions.ServerUptimeBonus
end

-- ============================================================
-- Rare spawn conditions check
-- ============================================================
function FishSpawner:_canSpawnLegendary(species)
    if self._legendaryAlive then return false end

    -- Spectral Ray: only at night (game day cycle)
    if species.Key == "SpectralRay" then
        return self:_isNightTime()
    end

    -- Abyssal Leviathan: only when population < 15
    if species.Key == "AbyssalLeviathan" then
        if self._leviathanSpawned then return false end
        return self._population < 15
    end

    return true
end

-- ============================================================
-- Day/Night check — game Lighting.ClockTime based
-- ============================================================
function FishSpawner:_isNightTime()
    -- Use Lighting.ClockTime: 18-6 is "night" (6pm to 6am)
    local clockTime = Lighting.ClockTime
    return clockTime >= 18 or clockTime < 6
end

-- ============================================================
-- Spawn position selection per species
-- ============================================================
function FishSpawner:_getSpawnPosition(species)
    -- Abyssal Leviathan: always Deep Reef Edge
    if species.Key == "AbyssalLeviathan" then
        for _, landmark in ipairs(self.ZoneConfig.Landmarks) do
            if landmark.Name == "Deep Reef Edge" then
                local center = landmark.CenterPosition
                local angle = math.random() * math.pi * 2
                local distance = math.random() * landmark.Radius
                return center + Vector3.new(
                    math.cos(angle) * distance,
                    math.random() * 3 - 1.5,
                    math.sin(angle) * distance
                )
            end
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
        -- Pick random landmark
        preferredLandmark = self.ZoneConfig.Landmarks[math.random(1, #self.ZoneConfig.Landmarks)]
    end

    -- Specific spawn positions for Angler
    if species.Behavior == "Ambush" and preferredLandmark.AnglerSpawnPoints then
        local points = preferredLandmark.AnglerSpawnPoints
        return points[math.random(1, #points)]
    end

    -- Random position within landmark
    local center = preferredLandmark.CenterPosition
    local angle = math.random() * math.pi * 2
    local distance = math.random() * preferredLandmark.Radius
    local offset = Vector3.new(
        math.cos(angle) * distance,
        math.random() * 5 - 2.5,
        math.sin(angle) * distance
    )

    return center + offset
end

-- ============================================================
-- Model creation — simple placeholder fish model
-- In production, this would use actual mesh parts.
-- ============================================================
function FishSpawner:_createFishModel(species, position)
    local scale = species.Scale or { Min = 1, Max = 1 }
    local sizeScale = scale.Min + math.random() * (scale.Max - scale.Min)

    -- For Legendary / Abyssal Leviathan, use 3-5x normal size
    if species.Key == "AbyssalLeviathan" then
        sizeScale = sizeScale * (3 + math.random() * 2)
    elseif species.Rarity == "Legendary" then
        sizeScale = sizeScale * 2 -- Spectral Ray is 2x player size
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

    -- Weld tail to body
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = body
    weld.Part1 = tail
    weld.Parent = tail

    -- Bioluminescent glow for species that have it
    if species.Bioluminescent and species.GlowColor then
        local glowLight = Instance.new("PointLight")
        glowLight.Name = "BioluminescentGlow"
        glowLight.Brightness = (species.Rarity == "Legendary") and 2 or 0.5
        glowLight.Range = (species.Rarity == "Legendary") and 15 or 6
        glowLight.Color = species.GlowColor
        glowLight.Shadows = false
        glowLight.Parent = body

        -- Angler: additional lure light on the head
        if species.Behavior == "Ambush" then
            local lureLight = Instance.new("PointLight")
            lureLight.Name = "Lure"
            lureLight.Brightness = 1.5
            lureLight.Range = 8
            lureLight.Color = species.GlowColor
            lureLight.Shadows = false
            lureLight.Parent = body

            -- Small lure orb part
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

        -- Abyssal Leviathan: large glowing aura
        if species.Key == "AbyssalLeviathan" then
            local auraLight = Instance.new("PointLight")
            auraLight.Name = "LeviathanAura"
            auraLight.Brightness = 5
            auraLight.Range = 30
            auraLight.Color = species.GlowColor or Color3.fromRGB(255, 100, 50)
            auraLight.Shadows = false
            auraLight.Parent = body

            -- Extra massive size feel: second body segment
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
    end

    -- PrimaryPart for AlignPosition/Orientation
    model.PrimaryPart = body

    -- Place in workspace
    model.Parent = workspace

    return model
end

-- ============================================================
-- Bobber registration (called by FishingService)
-- ============================================================
function FishSpawner:RegisterBobber(playerId, position)
    self._activeBobbers[playerId] = {
        position = position,
        castTime = tick(),
    }
end

function FishSpawner:UnregisterBobber(playerId)
    -- Don't remove immediately; fish might still be reacting.
    -- Instead mark as stale.
    if self._activeBobbers[playerId] then
        self._activeBobbers[playerId].stale = true
    end
end

-- ============================================================
-- Get nearby bobbers for fish awareness checks
-- ============================================================
function FishSpawner:GetNearbyBobbers(fishPosition, maxRadius)
    local nearby = {}
    local now = tick()

    for playerId, bobber in pairs(self._activeBobbers) do
        if not bobber.stale and now - bobber.castTime < 30 then -- bobbers expire after 30s
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

    -- Sort by distance
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
-- Find fish near a bobber (for FishingService integration)
-- ============================================================
function FishSpawner:GetFishNearBobber(bobberPosition, maxRadius)
    local nearby = {}

    for fishId, fish in pairs(self._fish) do
        -- Only consider fish that can be hooked
        if fish:IsHooked() then
            -- skip — already hooked by someone
        else
            local dist = (fish.Position - bobberPosition).Magnitude
            local interestRadius = fish:GetInterestRadius()
            local checkRadius = maxRadius or interestRadius

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

    -- Sort: bite-ready first, then by distance
    table.sort(nearby, function(a, b)
        if a.IsBiteReady ~= b.IsBiteReady then
            return a.IsBiteReady -- bite-ready prioritized
        end
        return a.Distance < b.Distance
    end)

    return nearby
end

-- ============================================================
-- State change callback from FishNPC
-- ============================================================
function FishSpawner:OnFishStateChanged(fish, oldState, newState)
    -- Handle school behavior: if leader is fleeing, followers flee too
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

    -- Handle school follower hooked: leader and others flee
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

    -- Track legendary despawns
    if newState == FishSignals.FishState.Despawning then
        if fish.Species.Rarity == "Legendary" then
            self._legendaryAlive = false
        end
        if fish.Species.Key == "AbyssalLeviathan" then
            self._leviathanSpawned = false
        end
    end
end

-- ============================================================
-- Angler dimming
-- ============================================================
function FishSpawner:OnAnglerDimmed(fish)
    local fishId = fish.Id
    local dimCooldown = fish.Species.DimCooldown or 30
    self._dimmedAnglers[fishId] = tick() + dimCooldown

    -- Visually dim the lure light
    if fish._model then
        local lure = fish._model:FindFirstChild("Lure", true)
        if lure and lure:IsA("PointLight") then
            lure.Brightness = 0.1
        end
    end

    -- Restore after cooldown
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

-- ============================================================
-- Shipwreck visit tracking (for Angler spawn bonus)
-- ============================================================
function FishSpawner:OnShipwreckVisited()
    self._lastShipwreckVisit = tick()
end

-- ============================================================
-- Rare spawn bloom notification
-- ============================================================
function FishSpawner:_fireRareSpawnBloom(position, species)
    -- Fire through Knit signal so AtmosphereHandler can pick it up
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
function FishSpawner:_notifyFishSpawned(fish)
    -- In full implementation, this would fire a Knit signal
    -- that clients listen to for creating client-side visual representations.
end

function FishSpawner:_notifyFishDespawned(fishId)
    -- In full implementation, notifies clients to clean up visual fish.
end

-- ============================================================
-- Update loop — called periodically by ZoneService
-- ============================================================
function FishSpawner:Update(dt)
    local now = tick()

    -- Check for fish that need auto-despawn
    local toRemove = {}
    for fishId, fish in pairs(self._fish) do
        if fish:CheckDespawn(now) then
            table.insert(toRemove, fishId)
        end

        -- Check if fish has fled beyond zone boundary
        local boundary = self.ZoneConfig.Population.DespawnBoundary or 60
        local zoneCenter = Vector3.zero -- MVP: zone center is 0,0,0
        local dist = (fish.Position - zoneCenter).Magnitude
        if dist > boundary then
            table.insert(toRemove, fishId)
        end
    end

    -- Clean up
    for _, fishId in ipairs(toRemove) do
        self:DespawnFish(fishId)
    end

    -- Clean stale bobbers
    for playerId, bobber in pairs(self._activeBobbers) do
        if bobber.stale and now - bobber.castTime > 10 then
            self._activeBobbers[playerId] = nil
        end
    end

    -- Update day/night
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
-- Get all active fish (for querying)
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
