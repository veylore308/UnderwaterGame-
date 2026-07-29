--[[
    Shared init.lua
    Deep Tide Studios
    Re-exports all shared constants for easy import:
        local Shared = require(game.ReplicatedStorage)
        local fish = Shared.Constants.FishSpecies.GetByKey("GlowfinMinnow")
]]

local Shared = {}

Shared.Constants = {
    FishSpecies = require(script.Constants.FishSpecies),
    RodTiers = require(script.Constants.RodTiers),
    SuitTiers = require(script.Constants.SuitTiers),
    RarityTiers = require(script.Constants.RarityTiers),
    ZoneConfigs = require(script.Constants.ZoneConfigs),
}

-- NPC signals
Shared.NPC = {
    FishSignals = require(script.NPC.FishSignals),
}

-- ============================================================
-- Currency definitions
-- ============================================================
Shared.Currency = {
    Coins = {
        Name = "Coins",
        Key = "Coins",
        IsSoftCurrency = true,
        Icon = "rbxassetid://--coin-icon",
    },
    Gems = {
        Name = "Gems",
        Key = "Gems",
        IsSoftCurrency = false,   -- Premium
        Icon = "rbxassetid://--gem-icon",
    },
}

-- ============================================================
-- Inventory defaults
-- ============================================================
Shared.Inventory = {
    BaseSlots = 20,             -- default fish inventory capacity
    MaxSlotsWithGamepass = 30,  -- with Extra Inventory gamepass
}

-- ============================================================
-- Oxygen defaults
-- ============================================================
Shared.Oxygen = {
    CriticalThreshold = 0.10,   -- 10% = screen pulse red
    DamagePerSecond = 0.10,     -- 10% max HP per second at 0 oxygen
    BlackoutDelay = 10,         -- seconds at 0% before respawn
    SprintMultiplier = 1.5,     -- oxygen drain multiplier when sprinting
    DepthPenaltyMultiplier = 3.0, -- below suit max depth
    DepthWarningDuration = 5,   -- seconds of warning before auto-ascend
}

-- ============================================================
-- Swimming / movement defaults
-- ============================================================
Shared.Swimming = {
    AccelerationTime = 0.3,     -- seconds to full speed
    DecelerationTime = 0.2,     -- seconds to stop
    BackwardSpeedRatio = 0.6,   -- 60% of forward speed
    AscendSpeedRatio = 0.8,     -- 80% of forward speed
    DescendSpeedRatio = 1.0,    -- 100% of forward speed
    SprintSpeedMultiplier = 1.5,
    SprintDuration = 3,         -- seconds
    SprintCooldown = 5,         -- seconds
    SprintFleeRadiusBonus = 1.5,-- 50% larger flee radius
    CameraBobAmplitude = 0.5,   -- studs
    CameraBobPeriod = 3,        -- seconds
}

-- ============================================================
-- Fishing mechanics defaults (GDD 7.3-7.5)
-- ============================================================
Shared.Fishing = {
    HookCircleDuration = { Min = 1.5, Max = 2.0 }, -- seconds
    TensionTickRate = 0.1,       -- 10 Hz update
    TensionMax = 100,
    TensionGreenZone = 50,       -- 0-50% safe
    TensionYellowZone = 80,      -- 50-80% warning
    TensionRedZone = 100,        -- 80-100% danger

    -- Tension formula (GDD 7.5):
    -- Tension_Increase = BaseReelRate * RodReelSpeed * (1.0 - (Progress/100) * 0.3)
    BaseReelRate = 10,           -- tension per second at 1.0x
    BaseReleaseRate = 8,         -- tension decrease per second at 1.0x
    ProgressDecayFactor = 0.3,   -- reduces tension gain as fish nears capture

    -- Hook result thresholds
    PerfectRatio = 0.30,         -- center 30% of sweet zone = perfect
    FleeChanceCommon = 0.30,     -- 30% flee on early hook for common
    FleeChanceUncommonPlus = 0.60, -- 60% for uncommon+
    FleeChanceLegendary = 1.00,  -- 100% for legendary (early = always flee)
}

-- ============================================================
-- Shop / Economy (GDD Section 5)
-- ============================================================
Shared.Shop = {
    Consumables = {
        {
            Name = "Luck Charm",
            Key = "LuckCharm",
            Cost = 50,           -- Gems
            CurrencyType = "Gems",
            Effect = { LuckBonus = 0.15 },
            Duration = 600,      -- 10 minutes
            IsAOE = true,        -- affects nearby players
        },
        {
            Name = "Oxygen Tank",
            Key = "OxygenTank",
            Cost = 25,           -- Gems
            CurrencyType = "Gems",
            Effect = { OxygenRefill = 1.0 },
            Duration = 0,        -- instant
        },
        {
            Name = "Bait Bundle",
            Key = "BaitBundle",
            Cost = 100,          -- Coins
            CurrencyType = "Coins",
            Effect = { BiteSpeedBonus = 0.30 },
            Uses = 5,
        },
        {
            Name = "Treasure Map",
            Key = "TreasureMap",
            Cost = 200,          -- Gems
            CurrencyType = "Gems",
            Effect = { RevealChest = true },
            Duration = 0,        -- one-time use
        },
    },

    -- Gamepasses (GDD 5.4)
    Gamepasses = {
        VIPDiver = {
            Name = "VIP Diver",
            Price = 499,         -- Robux
            Benefits = {
                LuckBonus = 0.10,
                OxygenBonus = 30,  -- +30s on all suits
                MonthlyGems = 100,
                ExclusiveSkin = "VIPRod",
            },
        },
        StarterBundle = {
            Name = "Starter Bundle",
            Price = 199,
            Benefits = {
                UnlockRod = "CoralRod",
                BonusCoins = 200,
                BonusGems = 50,
            },
        },
        ExtraInventory = {
            Name = "Extra Inventory",
            Price = 99,
            Benefits = {
                ExtraSlots = 10,
            },
        },
    },

    -- Gem pack pricing (GDD 5.3)
    GemPacks = {
        { Gems = 100, Robux = 99 },
        { Gems = 500, Robux = 399 },
        { Gems = 1200, Robux = 799 },
    },
}

-- ============================================================
-- Collection milestones (GDD 2.3 + Phase 2 GDD 7.3)
-- ============================================================
Shared.Milestones = {
    -- MVP Milestones
    {
        Name = "First Catch",
        Key = "FirstCatch",
        Requirement = { Type = "TotalCatches", Count = 1 },
        Reward = { Coins = 50, UnlockAnimation = "CollectionLog" },
    },
    {
        Name = "Reef Explorer",
        Key = "ReefExplorer",
        Requirement = { Type = "UniqueSpecies", Count = 5 },
        Reward = { Coins = 200, Title = "Reef Explorer" },
    },
    {
        Name = "Rare Collector",
        Key = "RareCollector",
        Requirement = { Type = "RareCatches", Count = 1 },
        Reward = { Gems = 100, UnlockRod = "CoralRod" },
    },
    {
        Name = "Sunken Master",
        Key = "SunkenMaster",
        Requirement = { Type = "CollectionComplete", Zone = "SunkenShallows" },
        Reward = { Coins = 500, ExclusiveSkin = "Sunken", UnlockRod = "TrenchmasterRod" },
    },
    {
        Name = "Weight Champion",
        Key = "WeightChampion",
        Requirement = { Type = "WeightOver", Kg = 10 },
        Reward = { Coins = 150, Title = "Heavy Hauler" },
    },
    {
        Name = "Lucky Day",
        Key = "LuckyDay",
        Requirement = { Type = "LegendaryCatches", Count = 1 },
        Reward = { Gems = 250, BadgeEffect = "BioluminescentGlow" },
    },

    -- Phase 2: Kelp Forest milestones (GDD 7.3)
    {
        Name = "Forest Newcomer",
        Key = "ForestNewcomer",
        Requirement = { Type = "UniqueSpeciesInZone", Zone = "KelpForest", Count = 1 },
        Reward = { Coins = 150, UnlockAnimation = "KelpForestCollection" },
    },
    {
        Name = "Canopy Dweller",
        Key = "CanopyDweller",
        Requirement = { Type = "UniqueSpeciesInZone", Zone = "KelpForest", Count = 3 },
        Reward = { Coins = 300, UnlockRod = "AbyssalRod" },
    },
    {
        Name = "Grotto Explorer",
        Key = "GrottoExplorer",
        Requirement = { Type = "SpecificCatch", SpeciesKey = "GrottoCrab" },
        Reward = { Gems = 100, Title = "Grotto Explorer" },
    },
    {
        Name = "Serpent's Bane",
        Key = "SerpentsBane",
        Requirement = { Type = "SpecificCatch", SpeciesKey = "KelpSerpent" },
        Reward = { Gems = 500, BadgeEffect = "SerpentineGreenAura" },
    },
    {
        Name = "Kelp Master",
        Key = "KelpMaster",
        Requirement = { Type = "CollectionComplete", Zone = "KelpForest" },
        Reward = { Coins = 1000, ExclusiveSkin = "KelpWarden", SuitSkin = "Emerald" },
    },
    {
        Name = "Jellyfish Whisperer",
        Key = "JellyfishWhisperer",
        Requirement = { Type = "SpecificCatchNoDamage", SpeciesKey = "VoidJellyfish" },
        Reward = { Gems = 250, Title = "Jellyfish Whisperer" },
    },
    {
        Name = "Forest Heavyweight",
        Key = "ForestHeavyweight",
        Requirement = { Type = "WeightOverInZone", Zone = "KelpForest", Kg = 20 },
        Reward = { Coins = 200, Title = "Forest Heavyweight" },
    },
}

return Shared
