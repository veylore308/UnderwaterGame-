--[[
    PlayerDataService.lua
    Deep Tide Studios — Server Service
    Manages player data persistence using DataStore2 pattern.
    Handles: coins, gems, inventory, collection log, owned gear, milestones.
]]

local Knit = require(game:GetService("ReplicatedStorage"):WaitForChild("Knit"))
-- DataStore2 is synced to ServerScriptService.DataStore2 by Rojo
local DataStore2 = require(game:GetService("ServerScriptService"):WaitForChild("DataStore2"))
local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))

local PlayerDataService = Knit.CreateService({
    Name = "PlayerDataService",
    Client = {
        -- Remote functions the client can call
        GetPlayerData = Knit.CreateSignal(),   -- (player) -> data
        DataUpdated = Knit.CreateSignal(),     -- (data) -> nil (fired to client on change)
    },
})

-- ============================================================
-- Default player data template
-- ============================================================
local DEFAULT_DATA = {
    Currency = {
        Coins = 0,
        Gems = 0,
    },
    Inventory = {
        Fish = {},            -- { { SpeciesKey, Weight, SellPrice, Timestamp }, ... }
        MaxSlots = Shared.Inventory.BaseSlots,
    },
    CollectionLog = {
        Species = {},         -- { ["GlowfinMinnow"] = { Caught=true, BiggestWeight=1.2, Count=5 }, ... }
    },
    Gear = {
        EquippedRod = "BambooRod",
        EquippedSuit = "BasicWetsuit",
        OwnedRods = { BambooRod = true },
        OwnedSuits = { BasicWetsuit = true },
        -- Phase 3: Surface rod track (separate from underwater rods)
        EquippedSurfaceRod = "CastingRod",
        OwnedSurfaceRods = { CastingRod = true },
    },
    Progression = {
        Level = 1,
        XP = 0,
        TotalCatches = 0,
        Milestones = {},      -- { ["FirstCatch"] = true, ... }
    },
    DivePass = {
        XP = 0,               -- Season XP (separate from player level XP)
        Season = 1,
        PremiumOwned = false,
        TiersClaimed = {},    -- { [1] = true, [3] = true, ... }
    },
    DailyChallenges = {
        LastResetDate = 0,    -- midnight UTC timestamp
        Streak = 0,
    },
    Stats = {
        TotalCoinsEarned = 0,
        TotalFishCaught = 0,
        BiggestCatch = 0,     -- kg
        PlayTime = 0,         -- seconds
    },
    boatData = { OwnedBoats = { Raft = true }, EquippedBoat = "Raft", BoatCosmetics = { Skins = {}, Flags = {}, Trails = {}, HullGlows = {} } },
    captainData = { CaptainXP = 0, CaptainRank = "Deckhand", RankUnlocks = {} },
    tradeData = { ActiveListings = {}, TradeHistory = {}, VerifiedTrader = false, ListingSlots = 2 },
    GuildId = nil,
    Settings = {
        AudioCueEnabled = false, -- accessibility: beep for hook sweet zone
    },
}

-- ============================================================
-- DataStore2 setup
-- ============================================================
local DATASTORE_KEY = "PlayerData_v1"

function PlayerDataService:CreateDataStore(player)
    local dataStore = DataStore2(DATASTORE_KEY, player)

    -- Combine default data with saved data
    local function mergeDefaults(saved)
        local merged = {}
        for k, v in pairs(DEFAULT_DATA) do
            if type(v) == "table" then
                merged[k] = {}
                for sk, sv in pairs(v) do
                    if saved[k] and saved[k][sk] ~= nil then
                        merged[k][sk] = saved[k][sk]
                    else
                        merged[k][sk] = sv
                    end
                end
            else
                merged[k] = (saved[k] ~= nil) and saved[k] or v
            end
        end
        return merged
    end

    -- Get or initialize
    local data = dataStore:Get(DEFAULT_DATA)
    if not data or type(data) ~= "table" then
        data = DEFAULT_DATA
    else
        data = mergeDefaults(data)
    end

    return dataStore, data
end

-- ============================================================
-- Service lifecycle
-- ============================================================
function PlayerDataService:KnitStart()
    -- Data stores are created per-player in PlayerAdded
    print("[PlayerDataService] Started — waiting for players")
end

function PlayerDataService:KnitInit()
    -- Player added: create their data store
    game:GetService("Players").PlayerAdded:Connect(function(player)
        self:OnPlayerAdded(player)
    end)

    -- Player leaving: save and cleanup
    game:GetService("Players").PlayerRemoving:Connect(function(player)
        self:OnPlayerRemoving(player)
    end)
end

-- ============================================================
-- Player lifecycle
-- ============================================================
function PlayerDataService:OnPlayerAdded(player)
    local dataStore, data = self:CreateDataStore(player)
    self._playerData[player] = {
        Store = dataStore,
        Data = data,
    }
    self.Client.GetPlayerData:Fire(player, data)

    -- Award starter gear if first session
    if data.Stats.PlayTime == 0 then
        print("[PlayerDataService] First-time player:", player.Name)
    end
end

function PlayerDataService:OnPlayerRemoving(player)
    local entry = self._playerData[player]
    if entry then
        -- Save final state
        entry.Store:Set(entry.Data)
        self._playerData[player] = nil
    end
end

-- ============================================================
-- Data accessors (called by other services)
-- ============================================================

function PlayerDataService:GetData(player)
    local entry = self._playerData[player]
    return entry and entry.Data
end

function PlayerDataService:SaveData(player)
    local entry = self._playerData[player]
    if entry then
        entry.Store:Set(entry.Data)
        self.Client.DataUpdated:Fire(player, entry.Data)
    end
end

--- Add coins to player
function PlayerDataService:AddCoins(player, amount)
    local data = self:GetData(player)
    if not data then return end
    data.Currency.Coins = data.Currency.Coins + amount
    data.Stats.TotalCoinsEarned = data.Stats.TotalCoinsEarned + amount
    self:SaveData(player)
end

--- Add gems to player
function PlayerDataService:AddGems(player, amount)
    local data = self:GetData(player)
    if not data then return end
    data.Currency.Gems = data.Currency.Gems + amount
    self:SaveData(player)
end

--- Add XP to player
function PlayerDataService:AddXP(player, amount)
    local data = self:GetData(player)
    if not data then return end
    data.Progression.XP = data.Progression.XP + amount

    -- Level-up check (simple: 100 XP per level, cap 20 for MVP)
    local newLevel = math.floor(data.Progression.XP / 100) + 1
    if newLevel > 20 then newLevel = 20 end
    if newLevel > data.Progression.Level then
        data.Progression.Level = newLevel
        -- Level-up reward: 25 coins per level
        data.Currency.Coins = data.Currency.Coins + (25 * (newLevel - (data.Progression.Level - 1)))
    end

    self:SaveData(player)
end

--- Add a fish to the player's inventory
function PlayerDataService:AddFish(player, speciesKey, weight, sellPrice)
    local data = self:GetData(player)
    if not data then return false end

    -- Check inventory space
    if #data.Inventory.Fish >= data.Inventory.MaxSlots then
        return false, "InventoryFull"
    end

    -- Add to inventory
    table.insert(data.Inventory.Fish, {
        SpeciesKey = speciesKey,
        Weight = weight,
        SellPrice = sellPrice,
        Timestamp = os.time(),
    })

    -- Update collection log
    if not data.CollectionLog.Species[speciesKey] then
        data.CollectionLog.Species[speciesKey] = {
            Caught = true,
            BiggestWeight = weight,
            Count = 1,
            FirstCatchTime = os.time(),
        }
    else
        local log = data.CollectionLog.Species[speciesKey]
        log.Count = log.Count + 1
        if weight > log.BiggestWeight then
            log.BiggestWeight = weight
        end
    end

    -- Update stats
    data.Stats.TotalFishCaught = data.Stats.TotalFishCaught + 1
    if weight > data.Stats.BiggestCatch then
        data.Stats.BiggestCatch = weight
    end

    data.Progression.TotalCatches = data.Progression.TotalCatches + 1

    -- Check milestones (fired via event for MilestoneService to handle)
    self:_checkMilestones(data)

    self:SaveData(player)
    return true, "Success"
end

--- Remove a fish from inventory (used when selling)
function PlayerDataService:RemoveFish(player, inventoryIndex)
    local data = self:GetData(player)
    if not data then return false end

    if inventoryIndex < 1 or inventoryIndex > #data.Inventory.Fish then
        return false
    end

    local fish = data.Inventory.Fish[inventoryIndex]
    table.remove(data.Inventory.Fish, inventoryIndex)

    self:SaveData(player)
    return true, fish
end

--- Check if player owns a rod
function PlayerDataService:OwnsRod(player, rodKey)
    local data = self:GetData(player)
    return data and data.Gear.OwnedRods[rodKey] == true
end

--- Grant rod ownership
function PlayerDataService:GrantRod(player, rodKey)
    local data = self:GetData(player)
    if not data then return end
    data.Gear.OwnedRods[rodKey] = true
    self:SaveData(player)
end

--- Equip a rod
function PlayerDataService:EquipRod(player, rodKey)
    local data = self:GetData(player)
    if not data then return false end
    if not data.Gear.OwnedRods[rodKey] then
        return false, "NotOwned"
    end
    data.Gear.EquippedRod = rodKey
    self:SaveData(player)
    return true
end

--- Grant suit ownership
function PlayerDataService:GrantSuit(player, suitKey)
    local data = self:GetData(player)
    if not data then return end
    data.Gear.OwnedSuits[suitKey] = true
    self:SaveData(player)
end

--- Equip a suit
function PlayerDataService:EquipSuit(player, suitKey)
    local data = self:GetData(player)
    if not data then return false end
    if not data.Gear.OwnedSuits[suitKey] then
        return false, "NotOwned"
    end
    data.Gear.EquippedSuit = suitKey
    self:SaveData(player)
    return true
end

-- ============================================================
-- Phase 3: Surface rod track (separate from underwater rods)
-- ============================================================

--- Check if player owns a surface rod
function PlayerDataService:OwnsSurfaceRod(player, rodKey)
    local data = self:GetData(player)
    return data and data.Gear.OwnedSurfaceRods and data.Gear.OwnedSurfaceRods[rodKey] == true
end

--- Grant surface rod ownership
function PlayerDataService:GrantSurfaceRod(player, rodKey)
    local data = self:GetData(player)
    if not data then return end
    data.Gear.OwnedSurfaceRods = data.Gear.OwnedSurfaceRods or { CastingRod = true }
    data.Gear.OwnedSurfaceRods[rodKey] = true
    self:SaveData(player)
end

--- Equip a surface rod
function PlayerDataService:EquipSurfaceRod(player, rodKey)
    local data = self:GetData(player)
    if not data then return false end
    if not data.Gear.OwnedSurfaceRods or not data.Gear.OwnedSurfaceRods[rodKey] then
        return false, "NotOwned"
    end
    data.Gear.EquippedSurfaceRod = rodKey
    self:SaveData(player)
    return true
end

--- Check milestone completion
function PlayerDataService:IsMilestoneComplete(player, milestoneKey)
    local data = self:GetData(player)
    return data and data.Progression.Milestones[milestoneKey] == true
end

--- Complete a milestone
function PlayerDataService:CompleteMilestone(player, milestoneKey)
    local data = self:GetData(player)
    if not data then return end
    data.Progression.Milestones[milestoneKey] = true
    self:SaveData(player)
end

-- ============================================================
-- Dive Pass XP System (GDD Section 5)
-- ============================================================

-- 50-tier XP curve: Tier 1 = 400 XP, linear increase to Tier 50 = 1,600 XP
-- Cumulative: ~50,000 XP total for Tier 50
local DIVE_PASS_MAX_TIER = 50
local DIVE_PASS_XP_BASE = 400      -- Tier 1 XP
local DIVE_PASS_XP_MAX = 1600      -- Tier 50 XP
local DIVE_PASS_TOTAL_XP = 50000   -- Approximate total for all 50 tiers

--- Calculate XP required to reach a given tier (tier 1 = 0 XP, tier 2+ = cumulative)
local function getXPForTier(tier)
    if tier <= 1 then return 0 end
    -- Linear interpolation: Tier N requires N * interpolated XP
    -- Base 400 at tier 1-2, linear ramp to 1600 at tier 49-50
    local ratio = (tier - 1) / (DIVE_PASS_MAX_TIER - 1)
    local xpPerTier = DIVE_PASS_XP_BASE + (DIVE_PASS_XP_MAX - DIVE_PASS_XP_BASE) * ratio
    -- Return floor of interpolated XP for this tier threshold
    return math.floor(xpPerTier)
end

--- Add Dive Pass XP (separate from player level XP)
function PlayerDataService:AddDivePassXP(player, amount)
    local data = self:GetData(player)
    if not data then return end
    data.DivePass.XP = data.DivePass.XP + amount
    self:SaveData(player)
end

--- Get current Dive Pass tier (1-50)
function PlayerDataService:GetDivePassTier(player)
    local data = self:GetData(player)
    if not data then return 1 end

    local xp = data.DivePass.XP or 0
    local cumulative = 0
    for tier = 1, DIVE_PASS_MAX_TIER do
        local needed = getXPForTier(tier + 1)
        if xp < needed then
            return math.min(tier, DIVE_PASS_MAX_TIER)
        end
        cumulative = needed
    end
    return DIVE_PASS_MAX_TIER
end

--- Get Dive Pass progress as { CurrentTier, XPInTier, XPRequiredForTier, TotalXP }
function PlayerDataService:GetDivePassProgress(player)
    local data = self:GetData(player)
    if not data then
        return { CurrentTier = 1, XPInTier = 0, XPRequiredForTier = getXPForTier(2), TotalXP = 0 }
    end

    local xp = data.DivePass.XP or 0
    local cumulative = 0

    for tier = 1, DIVE_PASS_MAX_TIER do
        local nextThreshold = getXPForTier(tier + 1)
        if xp < nextThreshold then
            local xpInTier = xp - cumulative
            local xpForTier = nextThreshold - cumulative
            return {
                CurrentTier = tier,
                XPInTier = math.max(0, xpInTier),
                XPRequiredForTier = xpForTier,
                TotalXP = xp,
            }
        end
        cumulative = nextThreshold
    end

    return {
        CurrentTier = DIVE_PASS_MAX_TIER,
        XPInTier = 0,
        XPRequiredForTier = 1,
        TotalXP = xp,
    }
end

--- Award Dive Pass XP based on fish rarity (GDD 5.4)
-- Uncommon = 10, Rare = 30, Legendary = 80
function PlayerDataService:AddDivePassXPForCatch(player, rarity)
    local xpMap = {
        Common = 10,
        Uncommon = 10,
        Rare = 30,
        Legendary = 80,
    }
    local amount = xpMap[rarity] or 10
    self:AddDivePassXP(player, amount)
end

-- ============================================================
-- Internal: milestone checks
-- ============================================================
function PlayerDataService:_checkMilestones(data)
    for _, milestone in ipairs(Shared.Milestones) do
        if not data.Progression.Milestones[milestone.Key] then
            local met = false
            local req = milestone.Requirement

            if req.Type == "TotalCatches" and data.Progression.TotalCatches >= req.Count then
                met = true
            elseif req.Type == "RareCatches" then
                local rareCount = 0
                for key, log in pairs(data.CollectionLog.Species) do
                    local species = Shared.Constants.FishSpecies.GetByKey(key)
                    if species and species.Rarity == "Rare" then
                        rareCount = rareCount + log.Count
                    end
                end
                met = rareCount >= req.Count
            elseif req.Type == "LegendaryCatches" then
                local legCount = 0
                for key, log in pairs(data.CollectionLog.Species) do
                    local species = Shared.Constants.FishSpecies.GetByKey(key)
                    if species and species.Rarity == "Legendary" then
                        legCount = legCount + log.Count
                    end
                end
                met = legCount >= req.Count
            elseif req.Type == "UniqueSpecies" then
                local unique = 0
                for _, _ in pairs(data.CollectionLog.Species) do
                    unique = unique + 1
                end
                met = unique >= req.Count
            elseif req.Type == "UniqueSpeciesInZone" then
                local unique = 0
                for key, log in pairs(data.CollectionLog.Species) do
                    if Shared.Constants.FishSpecies.IsInZone(key, req.Zone) then
                        unique = unique + 1
                    end
                end
                met = unique >= req.Count
            elseif req.Type == "SpecificCatch" then
                local speciesLog = data.CollectionLog.Species[req.SpeciesKey]
                met = speciesLog and speciesLog.Caught
            elseif req.Type == "CollectionComplete" then
                local zoneSpecies = Shared.Constants.FishSpecies.GetForZone(req.Zone)
                local allCaught = true
                for _, species in ipairs(zoneSpecies) do
                    local log = data.CollectionLog.Species[species.Key]
                    if not log or not log.Caught then
                        allCaught = false
                        break
                    end
                end
                met = allCaught and #zoneSpecies > 0
            elseif req.Type == "WeightOver" and data.Stats.BiggestCatch >= req.Kg then
                met = true
            elseif req.Type == "WeightOverInZone" then
                local zoneSpecies = Shared.Constants.FishSpecies.GetForZone(req.Zone)
                for _, species in ipairs(zoneSpecies) do
                    local log = data.CollectionLog.Species[species.Key]
                    if log and log.BiggestWeight and log.BiggestWeight >= req.Kg then
                        met = true
                        break
                    end
                end
            end

            if met then
                data.Progression.Milestones[milestone.Key] = true
            end
        end
    end
end

-- ============================================================
-- Internal state (keyed by Player)
-- ============================================================
PlayerDataService._playerData = {}

return PlayerDataService
