--[[
    RodTiers.lua
    Deep Tide Studios
    Fishing rod definitions and stats.
    Source: GDD Section 4.1 & Appendix B.
]]

local RodTiers = {
    -- ============================================================
    -- Tier 1: Bamboo Rod — Free starter rod
    -- ============================================================
    {
        Name = "Bamboo Rod",
        Key = "BambooRod",
        Tier = 1,
        Cost = 0,                -- Free (starter)
        CastRange = 15,          -- studs
        ReelSpeed = 1.0,         -- multiplier
        LuckBonus = 0.0,         -- +0%
        HookWindow = 0.40,       -- 40% of circle (generous for beginners)
        UnlockCondition = "Default",
        Description = "A simple bamboo rod. Gets the job done, but won't reach the shy ones.",
    },

    -- ============================================================
    -- Tier 2: Coral Rod — 500 Coins
    -- ============================================================
    {
        Name = "Coral Rod",
        Key = "CoralRod",
        Tier = 2,
        Cost = 500,
        CastRange = 22,
        ReelSpeed = 1.3,
        LuckBonus = 0.05,        -- +5%
        HookWindow = 0.35,       -- 35%
        UnlockCondition = "Catch 5 fish total",
        UnlockRequirement = {
            Type = "TotalCatches",
            Count = 5,
        },
        Description = "Crafted from vibrant reef coral. Extends your reach and improves your odds.",
    },

    -- ============================================================
    -- Tier 3: Reef King Rod — 2,000 Coins
    -- ============================================================
    {
        Name = "Reef King Rod",
        Key = "ReefKingRod",
        Tier = 3,
        Cost = 2000,
        CastRange = 30,
        ReelSpeed = 1.6,
        LuckBonus = 0.10,        -- +10%
        HookWindow = 0.30,       -- 30%
        UnlockCondition = "Catch 1 Rare fish",
        UnlockRequirement = {
            Type = "RareCatches",
            Count = 1,
        },
        Description = "The rod of reef royalty. Dominates the shallows with superior range and speed.",
    },

    -- ============================================================
    -- Tier 4: Abyssal Rod — 7,500 Coins
    -- First rod with Sonar Range. Unlocks after catching 3 Kelp Forest species.
    -- ============================================================
    {
        Name = "Abyssal Rod",
        Key = "AbyssalRod",
        Tier = 4,
        Cost = 7500,
        CastRange = 40,
        ReelSpeed = 2.0,
        LuckBonus = 0.15,        -- +15%
        HookWindow = 0.25,       -- 25%
        SonarRange = 25,         -- studs (ping every 3s reveals fish silhouettes)
        SonarPingInterval = 3.0, -- seconds
        UnlockCondition = "Catch 3 different Kelp Forest species",
        UnlockRequirement = {
            Type = "UniqueSpeciesInZone",
            Zone = "KelpForest",
            Count = 3,
        },
        Description = "Equipped with experimental sonar. Reveals hidden fish in the deep. Built for the abyss.",
    },

    -- ============================================================
    -- Tier 5: Trenchmaster Rod — 25,000 Coins (FUTURE)
    -- ============================================================
    {
        Name = "Trenchmaster Rod",
        Key = "TrenchmasterRod",
        Tier = 5,
        Cost = 25000,
        CastRange = 55,
        ReelSpeed = 2.5,
        LuckBonus = 0.25,        -- +25%
        HookWindow = 0.20,       -- 20%
        UnlockCondition = "Complete Sunken Shallows collection (all 5 species)",
        UnlockRequirement = {
            Type = "CollectionComplete",
            Zone = "SunkenShallows",
        },
        Description = "The pinnacle of fishing engineering. Nothing in the deep can resist.",
        IsFuture = true,
    },
}

-- ============================================================
-- Helper: Get rod by key
-- ============================================================
function RodTiers.GetByKey(key)
    for _, rod in ipairs(RodTiers) do
        if rod.Key == key then
            return rod
        end
    end
    return nil
end

-- ============================================================
-- Helper: Get rod by tier
-- ============================================================
function RodTiers.GetByTier(tier)
    for _, rod in ipairs(RodTiers) do
        if rod.Tier == tier then
            return rod
        end
    end
    return nil
end

-- ============================================================
-- Helper: Get all rods available in MVP (tiers 1-3, plus 5
--          which unlocks via MVP content)
-- ============================================================
function RodTiers.GetMVPRods()
    local mvprods = {}
    for _, rod in ipairs(RodTiers) do
        if not rod.IsFuture or rod.Key == "TrenchmasterRod" then
            -- Trenchmaster unlocks via MVP collection, so include it
            mvprods[#mvprods + 1] = rod
        end
    end
    return mvprods
end

return RodTiers
