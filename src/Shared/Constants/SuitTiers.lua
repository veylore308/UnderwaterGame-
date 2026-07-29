--[[
    SuitTiers.lua
    Deep Tide Studios
    Diving suit definitions and stats.
    Source: GDD Section 4.2 & Appendix B.
]]

local SuitTiers = {
    -- ============================================================
    -- Tier 1: Basic Wetsuit — Free starter
    -- ============================================================
    {
        Name = "Basic Wetsuit",
        Key = "BasicWetsuit",
        Tier = 1,
        Cost = 0,
        MaxDepth = 50,           -- meters
        SwimSpeed = 1.0,         -- multiplier
        OxygenSeconds = 60,      -- seconds
        CurrentResistance = 0.0, -- Phase 2 new stat
        UnlockCondition = "Default",
        Description = "Standard neoprene wetsuit. Good for shallow reef dives.",
    },

    -- ============================================================
    -- Tier 2: Reinforced Suit — 1,500 Coins
    -- Phase 2 patch: MaxDepth increased from 50m → 100m
    -- ============================================================
    {
        Name = "Reinforced Suit",
        Key = "ReinforcedSuit",
        Tier = 2,
        Cost = 1500,
        MaxDepth = 100,          -- Patched for Phase 2: was 50m, now 100m
        SwimSpeed = 1.3,
        OxygenSeconds = 90,
        CurrentResistance = 0.0, -- Phase 2 new stat
        UnlockCondition = "Catch 10 fish total + own Coral Rod",
        UnlockRequirement = {
            Type = "TotalCatches",
            Count = 10,
            RequiredRod = "CoralRod",
        },
        Description = "Reinforced with durable polymers. Rated for the upper Kelp Forest. Faster swimming and extended oxygen.",
    },

    -- ============================================================
    -- Tier 3: Deep Diver Suit — 6,000 Coins (PHASE 2)
    -- Required for 100m+. First suit with Current Resistance.
    -- ============================================================
    {
        Name = "Deep Diver Suit",
        Key = "DeepDiverSuit",
        Tier = 3,
        Cost = 6000,
        MaxDepth = 150,          -- meters (full Kelp Forest)
        SwimSpeed = 1.4,         -- multiplier
        OxygenSeconds = 110,     -- seconds
        CurrentResistance = 0.35, -- 35% current push reduction
        UnlockCondition = "Reach 100m depth + own Reef King Rod",
        UnlockRequirement = {
            Type = "DepthReached",
            Depth = 100,
            RequiredRod = "ReefKingRod",
        },
        Description = "Engineered for the deep kelp. Counteracts strong currents and extends your range to 150 meters.",
    },

    -- ============================================================
    -- Tier 4: Pressurized Suit — 10,000 Coins (FUTURE — Phase 3)
    -- ============================================================
    {
        Name = "Pressurized Suit",
        Key = "PressurizedSuit",
        Tier = 4,
        Cost = 10000,
        MaxDepth = 200,
        SwimSpeed = 1.6,
        OxygenSeconds = 140,
        CurrentResistance = 0.60,
        UnlockCondition = "Complete Sunken Shallows + Kelp Forest collections",
        UnlockRequirement = {
            Type = "CollectionComplete",
            Zone = "SunkenShallows",
            AndZone = "KelpForest",
        },
        Description = "Rated for the crushing depths of the Abyssal Trench. The ultimate diving apparatus.",
        IsFuture = true,
    },
}

-- ============================================================
-- Helper: Get suit by key
-- ============================================================
function SuitTiers.GetByKey(key)
    for _, suit in ipairs(SuitTiers) do
        if suit.Key == key then
            return suit
        end
    end
    return nil
end

-- ============================================================
-- Helper: Get suit by tier
-- ============================================================
function SuitTiers.GetByTier(tier)
    for _, suit in ipairs(SuitTiers) do
        if suit.Tier == tier then
            return suit
        end
    end
    return nil
end

-- ============================================================
-- Helper: Get MVP suits (non-future)
-- ============================================================
function SuitTiers.GetMVPSuits()
    local suits = {}
    for _, suit in ipairs(SuitTiers) do
        if not suit.IsFuture then
            suits[#suits + 1] = suit
        end
    end
    return suits
end

return SuitTiers
