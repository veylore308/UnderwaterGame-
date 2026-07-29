--[[
    FishSpecies.lua
    Deep Tide Studios
    All fish species definitions for The Sunken Shallows (MVP).
    Source: GDD Section 3 & Appendix B.
]]

local FishSpecies = {
    -- ============================================================
    -- Glowfin Minnow — Common (50% spawn rate)
    -- Tutorial fish. Swarm behavior, easy to catch.
    -- ============================================================
    {
        Name = "Glowfin Minnow",
        Key = "GlowfinMinnow",
        Rarity = "Common",
        SpawnRate = 0.50,
        BaseSellPrice = { Min = 15, Max = 30 },
        WeightRange = { Min = 0.2, Max = 1.5 },
        Behavior = "Swarm",
        Temperament = "Passive",

        -- AI Parameters (GDD Section 8.3)
        IdleSpeed = 2,           -- studs/s
        PatrolSpeed = 4,         -- studs/s
        FleeSpeed = 10,          -- studs/s
        AwarenessRadius = 15,    -- studs
        CuriosityRadius = 0,     -- N/A
        FleeTriggerDistance = 5, -- studs
        BobberInterestRadius = 8,-- studs
        BiteDelayMin = 1.0,      -- seconds
        BiteDelayMax = 1.5,      -- seconds
        FleeCooldown = 8,        -- seconds
        Schooling = true,        -- 4-8 fish per school

        -- Hook / Reel Parameters (GDD Appendix B)
        HookWindowSize = 0.40,   -- 40% of circle
        ReelDifficulty = "Easy",
        TensionBuildRate = 0.5,  -- multiplier
        TugCount = { Min = 1, Max = 2 },
        TugStrength = 0.15,      -- 15% tension per tug

        -- Visual
        Scale = { Min = 0.8, Max = 1.2 },
        Bioluminescent = true,
        GlowColor = Color3.fromRGB(0, 255, 255), -- Cyan
    },

    -- ============================================================
    -- Coral Snapper — Common (30% spawn rate)
    -- Standard fish. Curious behavior, patrols coral edges.
    -- ============================================================
    {
        Name = "Coral Snapper",
        Key = "CoralSnapper",
        Rarity = "Common",
        SpawnRate = 0.30,
        BaseSellPrice = { Min = 25, Max = 50 },
        WeightRange = { Min = 1.0, Max = 4.0 },
        Behavior = "Patrol",
        Temperament = "Curious",

        IdleSpeed = 4,
        PatrolSpeed = 6,
        FleeSpeed = 14,
        AwarenessRadius = 20,
        CuriosityRadius = 15,
        FleeTriggerDistance = 6,
        BobberInterestRadius = 10,
        BiteDelayMin = 2.0,
        BiteDelayMax = 4.0,
        FleeCooldown = 12,
        Schooling = false,

        HookWindowSize = 0.25,
        ReelDifficulty = "Easy-Medium",
        TensionBuildRate = 0.7,
        TugCount = { Min = 2, Max = 3 },
        TugStrength = 0.25,

        Scale = { Min = 1.0, Max = 1.5 },
        Bioluminescent = false,
        GlowColor = nil,
    },

    -- ============================================================
    -- Reef Dart — Uncommon (14% spawn rate)
    -- Erratic, skittish. Skill check for the starter zone.
    -- ============================================================
    {
        Name = "Reef Dart",
        Key = "ReefDart",
        Rarity = "Uncommon",
        SpawnRate = 0.14,
        BaseSellPrice = { Min = 60, Max = 120 },
        WeightRange = { Min = 0.5, Max = 2.5 },
        Behavior = "Erratic",
        Temperament = "Skittish",

        IdleSpeed = 0,            -- stays still in bursts
        PatrolSpeed = 12,         -- burst speed
        FleeSpeed = 22,
        AwarenessRadius = 25,
        CuriosityRadius = 0,
        FleeTriggerDistance = 12,
        BobberInterestRadius = 6,
        BiteDelayMin = 1.5,
        BiteDelayMax = 2.5,
        FleeCooldown = 15,
        Schooling = false,

        HookWindowSize = 0.15,
        ReelDifficulty = "Medium",
        TensionBuildRate = 1.0,
        TugCount = { Min = 4, Max = 5 },
        TugStrength = 0.125,      -- 10-15%

        Scale = { Min = 0.7, Max = 1.1 },
        Bioluminescent = true,
        GlowColor = Color3.fromRGB(100, 200, 255), -- Blue-green shimmer
    },

    -- ============================================================
    -- Sunken Angler — Rare (5% spawn rate)
    -- Ambush predator. Hard to find, harder to catch.
    -- ============================================================
    {
        Name = "Sunken Angler",
        Key = "SunkenAngler",
        Rarity = "Rare",
        SpawnRate = 0.05,
        BaseSellPrice = { Min = 200, Max = 500 },
        WeightRange = { Min = 3.0, Max = 8.0 },
        Behavior = "Ambush",
        Temperament = "Luring",

        IdleSpeed = 0,            -- stationary ambush
        PatrolSpeed = 0,          -- doesn't patrol
        FleeSpeed = 0,            -- doesn't flee
        AwarenessRadius = 12,
        CuriosityRadius = 0,
        FleeTriggerDistance = 0,  -- N/A (backs into crevice instead)
        BobberInterestRadius = 8,
        BiteDelayMin = 3.0,
        BiteDelayMax = 6.0,
        FleeCooldown = 0,
        Schooling = false,

        -- Specific: dims lure if player within 8 studs without casting
        DimDistance = 8,
        DimCooldown = 30,

        HookWindowSize = 0.15,
        ReelDifficulty = "Hard",
        TensionBuildRate = 1.4,
        TugCount = { Min = 3, Max = 4 },
        TugStrength = 0.40,       -- sustained pulls
        TugDuration = { Min = 1.5, Max = 2.0 },

        Scale = { Min = 1.5, Max = 2.0 },
        Bioluminescent = true,
        GlowColor = Color3.fromRGB(200, 255, 50), -- Yellow-green lure
    },

    -- ============================================================
    -- Abyssal Leviathan — Legendary (1% spawn rate)
    -- The terror of the deep. Only spawns when population is low.
    -- Massive, slow, with a 60s despawn timer if not hooked.
    -- ============================================================
    {
        Name = "Abyssal Leviathan",
        Key = "AbyssalLeviathan",
        Rarity = "Legendary",
        SpawnRate = 0.01,
        BaseSellPrice = { Min = 2000, Max = 5000 },
        WeightRange = { Min = 15.0, Max = 50.0 },
        Behavior = "Terrifying",
        Temperament = "Apex",

        IdleSpeed = 2,             -- slow but menacing
        PatrolSpeed = 3,           -- deliberate patrol
        FleeSpeed = 0,             -- doesn't flee, it's the apex
        AwarenessRadius = 50,      -- sees everything
        CuriosityRadius = 0,
        FleeTriggerDistance = 0,   -- doesn't flee
        BobberInterestRadius = 10,
        BiteDelayMin = 5.0,
        BiteDelayMax = 10.0,
        FleeCooldown = 0,
        Schooling = false,

        -- Specific: only spawns when population < 15
        -- Has 60s despawn timer if not hooked
        -- Spawns server-wide particle bloom
        SpawnMaxPerServer = 1,
        SpawnPopulationCap = 15,
        DespawnTimer = 60,
        MassiveScale = { Min = 3, Max = 5 }, -- 3-5x normal size

        HookWindowSize = 0.06,     -- extremely tiny
        ReelDifficulty = "Extreme",
        TensionBuildRate = 2.5,
        TugCount = { Min = 6, Max = 10 },
        TugStrength = 0.60,
        ReelDuration = { Min = 25, Max = 40 },

        Scale = { Min = 3.0, Max = 5.0 },
        Bioluminescent = true,
        GlowColor = Color3.fromRGB(255, 80, 30), -- Deep red-orange aura
    },

    -- ============================================================
    -- Spectral Ray — Legendary (1% spawn rate)
    -- The aspirational chase. Ultra-rare, extreme difficulty.
    -- Only spawns during night in the game day cycle.
    -- ============================================================
    {
        Name = "Spectral Ray",
        Key = "SpectralRay",
        Rarity = "Legendary",
        SpawnRate = 0.01,
        BaseSellPrice = { Min = 1000, Max = 3000 },
        WeightRange = { Min = 8.0, Max = 20.0 },
        Behavior = "Graceful",
        Temperament = "Elusive",

        IdleSpeed = 6,
        PatrolSpeed = 8,
        FleeSpeed = 16,           -- spooked speed 2x = 32
        AwarenessRadius = 40,
        CuriosityRadius = 0,
        FleeTriggerDistance = 0,  -- N/A, doesn't flee normally
        BobberInterestRadius = 5,
        BiteDelayMin = 4.0,
        BiteDelayMax = 8.0,
        FleeCooldown = 0,
        Schooling = false,

        -- Specific spawn conditions
        SpawnMaxPerServer = 1,
        SpawnDayCycleOnly = true,  -- once per 20-min day
        DespawnTimer = 300,        -- 5 min if unengaged
        SpookedAcceleration = 2.0,
        SpookedShiftDistance = 80,

        HookWindowSize = 0.08,
        ReelDifficulty = "Extreme",
        TensionBuildRate = 2.0,
        TugCount = { Min = 5, Max = 8 },
        TugStrength = 0.50,
        ReelDuration = { Min = 20, Max = 30 },

        Scale = { Min = 2.0, Max = 2.5 },
        Bioluminescent = true,
        GlowColor = Color3.fromRGB(180, 220, 255), -- Ghostly white-blue
    },
}

-- ============================================================
-- Helper: Get species by key
-- ============================================================
function FishSpecies.GetByKey(key)
    for _, species in ipairs(FishSpecies) do
        if species.Key == key then
            return species
        end
    end
    return nil
end

-- ============================================================
-- Helper: Get all species for a zone
-- ============================================================
function FishSpecies.GetForZone(zoneKey)
    -- MVP: all species are in The Sunken Shallows
    return FishSpecies
end

-- ============================================================
-- Helper: Get spawn table (cumulative probabilities)
-- ============================================================
function FishSpecies.GetSpawnTable(luckBonus)
    luckBonus = luckBonus or 0
    local table = {}
    local cumulative = 0

    for _, species in ipairs(FishSpecies) do
        local adjustedRate = species.SpawnRate
        if species.Rarity == "Rare" or species.Rarity == "Legendary" then
            adjustedRate = adjustedRate * (1.0 + luckBonus)
        end
        cumulative = cumulative + adjustedRate
        table[#table + 1] = {
            Species = species,
            CumulativeWeight = cumulative,
        }
    end

    return table, cumulative -- total weight for normalization
end

return FishSpecies
