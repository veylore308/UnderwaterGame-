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
-- KELP FOREST SPECIES (Phase 2 — 8 new species)
-- Source: GDD Section 3.2–3.4
-- ============================================================

-- ============================================================
-- Frilled Seahorse — Uncommon (22%)
-- Clinger, Curious. Welcomes players to the Kelp Forest.
-- ============================================================
{
    Name = "Frilled Seahorse",
    Key = "FrilledSeahorse",
    Rarity = "Uncommon",
    SpawnRate = 0.22,
    BaseSellPrice = { Min = 80, Max = 140 },
    WeightRange = { Min = 0.3, Max = 1.2 },
    Behavior = "Clinger",
    Temperament = "Curious",
    Zone = "KelpForest",

    IdleSpeed = 0,              -- clinging to stalk
    PatrolSpeed = 3,            -- studs/s (stalk-to-stalk)
    FleeSpeed = 0,              -- hides in place
    AwarenessRadius = 15,
    CuriosityRadius = 12,       -- approaches slowly
    FleeTriggerDistance = 12,   -- only if player sprints
    BobberInterestRadius = 6,
    BiteDelayMin = 2.5,
    BiteDelayMax = 4.0,
    FleeCooldown = 10,          -- unhookable for 10s if spooked
    Schooling = false,

    -- Specific: only spawns within 5 studs of kelp stalk
    RequiresKelpStalk = true,
    KelpStalkRadius = 5,
    ClingDuration = { Min = 10, Max = 30 },  -- seconds per cling
    DisplayAnimation = true,    -- unfurls frills if player approaches slowly

    HookWindowSize = 0.22,
    ReelDifficulty = "Easy-Medium",
    TensionBuildRate = 0.6,
    TugCount = { Min = 2, Max = 3 },
    TugStrength = 0.15,

    Scale = { Min = 0.8, Max = 1.2 },
    Bioluminescent = false,
    GlowColor = nil,
},

-- ============================================================
-- Copper Scaleback — Uncommon (20%)
-- Bottom-feeder, armored. Tank fish with grinding reel.
-- ============================================================
{
    Name = "Copper Scaleback",
    Key = "CopperScaleback",
    Rarity = "Uncommon",
    SpawnRate = 0.20,
    BaseSellPrice = { Min = 90, Max = 160 },
    WeightRange = { Min = 2.0, Max = 6.0 },
    Behavior = "BottomFeeder",
    Temperament = "Indifferent",
    Zone = "KelpForest",

    IdleSpeed = 2,
    PatrolSpeed = 4,
    FleeSpeed = 8,
    AwarenessRadius = 10,
    CuriosityRadius = 0,
    FleeTriggerDistance = 4,
    BobberInterestRadius = 8,
    BiteDelayMin = 3.0,
    BiteDelayMax = 5.0,
    FleeCooldown = 12,
    Schooling = false,

    -- Specific: hugs sea floor, resists clearing current
    MaxHeightFromFloor = 3,       -- studs above sea floor
    CurrentImmune = true,
    ArmoredMechanic = true,       -- slower tension build, endurance test

    HookWindowSize = 0.25,
    ReelDifficulty = "Medium",
    TensionBuildRate = 0.5,       -- armored: hard to reel
    TugCount = { Min = 3, Max = 5 },
    TugStrength = 0.20,           -- sustained low-intensity pulls
    TugDuration = { Min = 1.5, Max = 2.5 },

    Scale = { Min = 1.2, Max = 1.8 },
    Bioluminescent = false,
    GlowColor = nil,
},

-- ============================================================
-- Kelp Darter — Uncommon (13%)
-- Erratic, skittish, cover-using. Skill check — hides in fronds.
-- ============================================================
{
    Name = "Kelp Darter",
    Key = "KelpDarter",
    Rarity = "Uncommon",
    SpawnRate = 0.13,
    BaseSellPrice = { Min = 100, Max = 180 },
    WeightRange = { Min = 0.4, Max = 1.8 },
    Behavior = "CoverUser",
    Temperament = "Skittish",
    Zone = "KelpForest",

    IdleSpeed = 0,              -- hovers inside frond
    PatrolSpeed = 20,           -- studs/s dart burst
    FleeSpeed = 25,
    AwarenessRadius = 20,
    CuriosityRadius = 0,
    FleeTriggerDistance = 10,
    BobberInterestRadius = 3,   -- must be IN the frond cluster
    BiteDelayMin = 1.0,
    BiteDelayMax = 2.0,
    FleeCooldown = 15,
    Schooling = false,

    -- Cover mechanic: 40% harder to see in fronds
    CoverStealthPercent = 0.40,
    FrondPositionUpdateInterval = { Min = 2, Max = 4 },  -- seconds
    IfSprintedFleeDistance = 30,

    HookWindowSize = 0.18,
    ReelDifficulty = "Medium-Hard",
    TensionBuildRate = 1.0,
    TugCount = { Min = 5, Max = 6 },
    TugStrength = 0.125,        -- 10-15% rapid tugs

    Scale = { Min = 0.7, Max = 1.0 },
    Bioluminescent = true,
    GlowColor = Color3.fromRGB(100, 255, 150), -- Green flash on dart
},

-- ============================================================
-- Kelp Stalker — Rare (15%)
-- Ambush predator, camouflage. Zone's signature challenge.
-- ============================================================
{
    Name = "Kelp Stalker",
    Key = "KelpStalker",
    Rarity = "Rare",
    SpawnRate = 0.15,
    BaseSellPrice = { Min = 300, Max = 600 },
    WeightRange = { Min = 4.0, Max = 10.0 },
    Behavior = "Camouflage",
    Temperament = "Ambush",
    Zone = "KelpForest",

    IdleSpeed = 0,              -- perfectly still against stalk
    PatrolSpeed = 3,            -- slow stalk-to-stalk drift
    FleeSpeed = 30,             -- extreme burst if discovered
    AwarenessRadius = 20,
    CuriosityRadius = 0,
    FleeTriggerDistance = 4,    -- only flees when very close without casting
    BobberInterestRadius = 8,
    BiteDelayMin = 4.0,
    BiteDelayMax = 7.0,
    FleeCooldown = 20,
    Schooling = false,

    -- Camouflage mechanic (GDD 3.4.4)
    CamouflageTransparency = {
        Far = 0.85,    -- >15 studs: 85% transparent
        Mid = 0.50,    -- 8-15 studs: 50% blended
        Near = 0.20,   -- <8 studs: 20% blended
    },
    ShimmerInterval = { Min = 3, Max = 5 },  -- seconds between shimmer tells
    AmbushDuration = { Min = 30, Max = 90 },  -- seconds per stalk position
    SonarDetectable = true,    -- Abyssal Rod Sonar bypasses camouflage

    HookWindowSize = 0.15,
    ReelDifficulty = "Hard",
    TensionBuildRate = 1.3,
    TugCount = { Min = 3, Max = 5 },
    TugStrength = 0.40,
    -- Feint mechanic: alternating pull then sudden tension drop
    FeintPattern = true,

    Scale = { Min = 1.5, Max = 2.2 },
    Bioluminescent = false,
    GlowColor = nil,
},

-- ============================================================
-- Grotto Crab — Rare (12%)
-- Bottom-dweller, burrower. Bait mechanic — "puzzle fish."
-- ============================================================
{
    Name = "Grotto Crab",
    Key = "GrottoCrab",
    Rarity = "Rare",
    SpawnRate = 0.12,
    BaseSellPrice = { Min = 350, Max = 700 },
    WeightRange = { Min = 3.0, Max = 12.0 },
    Behavior = "Burrower",
    Temperament = "Defensive",
    Zone = "KelpForest",

    IdleSpeed = 2,
    PatrolSpeed = 4,
    FleeSpeed = 15,             -- scuttles to crevice
    AwarenessRadius = 15,
    CuriosityRadius = 0,
    FleeTriggerDistance = 15,   -- enters crevice when player nearby
    BobberInterestRadius = 0,   -- not bobber-based; bait only
    BiteDelayMin = 5.0,         -- emergence time after bait placed
    BiteDelayMax = 10.0,
    FleeCooldown = 0,
    Schooling = false,

    -- Bait mechanic (GDD 3.4.5)
    CatchMechanic = "Bait",     -- requires bait placement, not casting
    BaitRequired = true,
    BaitPlacementRadius = 5,    -- studs from crevice
    HookWindowType = "Timing",   -- 0.8s visual timing window (not shrinking circle)
    HookWindowDuration = 0.8,
    EmergeOnBaitDelay = { Min = 5, Max = 10 },
    RetreatCooldown = 45,        -- seconds if spooked

    HookWindowSize = 0.0,       -- N/A (uses timing window)
    ReelDifficulty = "Hard",
    TensionBuildRate = 1.5,
    TugCount = { Min = 4, Max = 6 },
    TugStrength = 0.30,         -- sharp, powerful claw snaps

    Scale = { Min = 1.5, Max = 2.5 },
    Bioluminescent = true,
    GlowColor = Color3.fromRGB(255, 140, 30), -- Orange eye glow
},

-- ============================================================
-- Lantern Squid — Rare (8%)
-- Floater, light-attracted. "Reward for patience" — comes to you.
-- ============================================================
{
    Name = "Lantern Squid",
    Key = "LanternSquid",
    Rarity = "Rare",
    SpawnRate = 0.08,
    BaseSellPrice = { Min = 400, Max = 750 },
    WeightRange = { Min = 2.0, Max = 5.0 },
    Behavior = "Floater",
    Temperament = "Curious",
    Zone = "KelpForest",

    IdleSpeed = 2,              -- drifts with current
    PatrolSpeed = 2,            -- drifter, not active patrol
    FleeSpeed = 25,             -- jets away if sprinted at
    AwarenessRadius = 25,
    CuriosityRadius = 20,       -- attracted to player light
    FleeTriggerDistance = 8,
    BobberInterestRadius = 8,
    BiteDelayMin = 2.0,
    BiteDelayMax = 3.5,
    FleeCooldown = 10,
    Schooling = false,

    -- Light-attracted mechanic (GDD 3.4.6)
    LightAttracted = true,
    LightAttractionSpeed = 1.0,     -- normal drift toward player
    SonarAttractionMultiplier = 2.0, -- doubled with Abyssal Rod Sonar
    BioluminescentPulse = true,
    PulseCycleSeconds = 3.0,        -- bright→dim→bright
    AttractOtherFish = true,        -- its glow attracts other fish
    InkMechanic = true,             -- ink burst obscures tension meter

    HookWindowSize = 0.20,
    ReelDifficulty = "Medium",
    TensionBuildRate = 0.9,
    TugCount = { Min = 3, Max = 4 },
    TugStrength = 0.20,
    InkBurstDuration = 1.0,    -- seconds meter is obscured

    Scale = { Min = 1.0, Max = 1.5 },
    Bioluminescent = true,
    GlowColor = Color3.fromRGB(255, 200, 80), -- Warm golden-orange
},

-- ============================================================
-- Void Jellyfish — Legendary (7%)
-- Drifter, bioluminescent pulse. Tentacle hazard. "Spectacle fish."
-- ============================================================
{
    Name = "Void Jellyfish",
    Key = "VoidJellyfish",
    Rarity = "Legendary",
    SpawnRate = 0.07,
    BaseSellPrice = { Min = 1500, Max = 3500 },
    WeightRange = { Min = 10.0, Max = 25.0 },
    Behavior = "Drifter",
    Temperament = "PassiveHazard",
    Zone = "KelpForest",

    IdleSpeed = 3,
    PatrolSpeed = 3,
    FleeSpeed = 0,              -- doesn't flee
    AwarenessRadius = 30,
    CuriosityRadius = 0,
    FleeTriggerDistance = 0,    -- unfazed by player
    BobberInterestRadius = 3,   -- must land near bell rim (visual target)
    BiteDelayMin = 5.0,
    BiteDelayMax = 8.0,
    FleeCooldown = 0,
    Schooling = false,

    -- Specific spawn conditions
    SpawnMaxPerServer = 1,
    SpawnPopulationCap = 10,    -- server must have ≥10 players
    SpawnMinZoneAge = 300,      -- zone must be active 5+ minutes
    DespawnTimer = 480,         -- 8 min if unengaged
    RespawnCooldown = 120,

    -- Tentacle hazard (GDD 3.4.7)
    TentacleLength = { Min = 30, Max = 40 },  -- studs
    TentacleContactDamage = 0.15,              -- 15% max HP
    TentacleOxygenPenalty = 2.0,               -- 2x drain for 3s
    TentacleOxygenPenaltyDuration = 3.0,
    PulseCycleSeconds = 4.0,                   -- normal
    AgitatedPulseCycleSeconds = 1.5,
    AgitatedDuration = 10.0,

    HookWindowSize = 0.10,      -- tiny
    ReelDifficulty = "Extreme",
    TensionBuildRate = 1.8,
    TugCount = { Min = 5, Max = 8 },
    TugStrength = 0.35,         -- undulating wave pulls
    TugDuration = { Min = 2.0, Max = 3.0 },
    ReelDuration = { Min = 20, Max = 28 },

    Scale = { Min = 2.5, Max = 3.5 },
    Bioluminescent = true,
    GlowColor = Color3.fromRGB(100, 150, 255), -- Deep purple-blue → cyan
},

-- ============================================================
-- Kelp Serpent — Legendary (3%)
-- Apex, zone-roaming. Aspirational catch — "story fish."
-- ============================================================
{
    Name = "Kelp Serpent",
    Key = "KelpSerpent",
    Rarity = "Legendary",
    SpawnRate = 0.03,
    BaseSellPrice = { Min = 2500, Max = 5000 },
    WeightRange = { Min = 15.0, Max = 40.0 },
    Behavior = "ApexRoaming",
    Temperament = "Apex",
    Zone = "KelpForest",

    IdleSpeed = 6,
    PatrolSpeed = 6,            -- deliberate, unhurried
    FleeSpeed = 12,             -- enraged acceleration
    AwarenessRadius = 50,       -- sees everything
    CuriosityRadius = 0,
    FleeTriggerDistance = 0,    -- doesn't flee (warning display at 10)
    BobberInterestRadius = 5,   -- must land near HEAD (lead the target)
    BiteDelayMin = 6.0,
    BiteDelayMax = 12.0,
    FleeCooldown = 0,
    Schooling = false,

    -- Specific spawn conditions (GDD 3.4.8)
    SpawnMaxPerServer = 1,
    SpawnDayCycleOnly = true,   -- check once per game day
    DespawnTimer = 600,         -- 10 min if unengaged
    RespawnCooldown = 300,
    PlayerCountBonus = 0.005,
    MaxPlayerBonus = 0.125,

    -- Apex presence (GDD 3.4.8)
    ApexPresence = true,
    ApexAlertRadius = 40,       -- studs, all fish alerted
    ApexAlertAfterDuration = 10,-- seconds after Serpent leaves
    WarningDisplayDistance = 10,-- studs from head → warning display
    WarningPushBack = 8,        -- studs pushed back
    EnragedAcceleration = 12,   -- studs/s on failed hook
    EnragedDuration = 20,       -- seconds

    HookWindowSize = 0.06,      -- extremely tiny
    ReelDifficulty = "Extreme+",
    TensionBuildRate = 2.2,
    TugCount = { Min = 6, Max = 10 },
    TugStrength = 0.45,         -- sustained runs
    ReelDuration = { Min = 25, Max = 40 },
    -- Coil mechanic: tension drops to bait over-reeling
    CoilMechanic = true,
    CoilTensionPunish = 0.75,   -- next shake at 75% if reeling during coil

    Scale = { Min = 3.5, Max = 5.0 },
    Bioluminescent = true,
    GlowColor = Color3.fromRGB(255, 80, 30), -- Dull orange-red lure spots
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
        -- Phase 2: filter by Zone field; MVP species get "SunkenShallows"
        local result = {}
        for _, species in ipairs(FishSpecies) do
            local speciesZone = species.Zone or "SunkenShallows"  -- MVP default
            if speciesZone == zoneKey then
                result[#result + 1] = species
            end
        end
        return result
    end

    -- ============================================================
    -- Helper: Get spawn table (cumulative probabilities)
    -- ============================================================
    function FishSpecies.GetSpawnTable(luckBonus, zoneKey)
        luckBonus = luckBonus or 0
        zoneKey = zoneKey or "SunkenShallows"

        local tbl = {}
        local cumulative = 0

        for _, species in ipairs(FishSpecies) do
            local speciesZone = species.Zone or "SunkenShallows"
            if speciesZone == zoneKey then
                local adjustedRate = species.SpawnRate
                if species.Rarity == "Rare" or species.Rarity == "Legendary" then
                    adjustedRate = adjustedRate * (1.0 + luckBonus)
                end
                cumulative = cumulative + adjustedRate
                tbl[#tbl + 1] = {
                    Species = species,
                    CumulativeWeight = cumulative,
                }
            end
        end

        return tbl, cumulative -- total weight for normalization
    end

    -- ============================================================
    -- Helper: Check if a species belongs to a zone
    -- ============================================================
    function FishSpecies.IsInZone(speciesKey, zoneKey)
        local species = FishSpecies.GetByKey(speciesKey)
        if not species then return false end
        local speciesZone = species.Zone or "SunkenShallows"
        return speciesZone == zoneKey
    end

    return FishSpecies
