--[[
    ZoneConfigs.lua
    Deep Tide Studios
    Zone definitions, depth boundaries, landmarks, fish populations.
    Source: GDD Section 6.
]]

local ZoneConfigs = {
    -- ============================================================
    -- The Sunken Shallows — 0m to 50m (MVP ONLY ZONE)
    -- ============================================================
    SunkenShallows = {
        Name = "The Sunken Shallows",
        Key = "SunkenShallows",
        DepthMin = 0,             -- meters from surface
        DepthMax = 50,
        IsMVP = true,

        -- Environmental parameters (GDD 6.2)
        Environment = {
            WaterColor = Color3.fromRGB(64, 180, 200),     -- Turquoise-blue surface
            DeepWaterColor = Color3.fromRGB(20, 40, 80),   -- Navy at 40m+
            Visibility = 65,          -- studs (clear)
            FogStart = 50,            -- studs (fog begins)
            GodRays = true,
            AmbientColor = Color3.fromRGB(30, 60, 120),
            MusicTrack = "rbxassetid://--ocean-ambient-calm",
        },

        -- Landmarks (GDD 6.3 / 6.4)
        Landmarks = {
            {
                Name = "Coral Gardens",
                DepthRange = { Min = 5, Max = 15 },
                Description = "Dense coral clusters with archways. Glowfin Minnows and Coral Snappers patrol here.",
                PrimaryFish = { "GlowfinMinnow", "CoralSnapper" },
                CenterPosition = Vector3.new(0, -10, 0),
                Radius = 40, -- studs
            },
            {
                Name = "Sandy Plains",
                DepthRange = { Min = 15, Max = 30 },
                Description = "Open sandy area with scattered rocks and seagrass. Reef Darts zip through here.",
                PrimaryFish = { "ReefDart" },
                CenterPosition = Vector3.new(30, -22, 20),
                Radius = 60,
            },
            {
                Name = "The Shipwreck",
                DepthRange = { Min = 30, Max = 45 },
                Description = "Broken wooden ship hull. Sunken Angler spawn point in dark interior.",
                PrimaryFish = { "SunkenAngler" },
                AnglerSpawnPoints = {
                    Vector3.new(15, -37, -10), -- Captain's quarters
                    Vector3.new(12, -35, -5),  -- Broken bow
                },
                CenterPosition = Vector3.new(10, -37, -8),
                Radius = 25,
            },
            {
                Name = "Deep Reef Edge",
                DepthRange = { Min = 45, Max = 50 },
                Description = "Rocky drop-off. Boundary wall. Spectral Ray patrol passes through.",
                PrimaryFish = { "SpectralRay" },
                CenterPosition = Vector3.new(-20, -47, -25),
                Radius = 30,
                IsBoundary = true,
            },
        },

        -- Fish population management (GDD 8.6)
        Population = {
            MaxConcurrentFish = 25,
            RespawnIntervalSeconds = 60,
            DespawnBoundary = 60,  -- studs from zone center
            LegendaryCap = 1,      -- only 1 Spectral Ray at a time
        },

        -- Spawn conditions (GDD 8.5)
        SpawnConditions = {
            DayCycleMinutes = 20,  -- full day cycle
            DuskDawnWindow = 3,    -- first/last 3 minutes = 2x Ray spawn
            PlayerCountBonus = 0.002, -- +0.2% per player (max +5%)
            MaxPlayerBonus = 0.05,
            ZoneActivityBonus = 2.0, -- double Angler spawn if shipwreck unvisited 5+ min
            ZoneActivityThreshold = 300, -- 5 minutes
            ServerUptimeBonus = 0.01, -- +1% per 30 min
            ServerUptimeInterval = 1800, -- 30 min in seconds
        },
    },

    -- ============================================================
    -- The Kelp Forest — 50m to 150m (PHASE 2)
    -- ============================================================
    KelpForest = {
        Name = "The Kelp Forest",
        Key = "KelpForest",
        DepthMin = 50,
        DepthMax = 150,
        IsMVP = false,
        IsFuture = false,

        -- Zone unlock gate (GDD 1.3)
        UnlockRequirement = {
            RequiredRod = "CoralRod",  -- Tier 2+
            TotalCatches = 50,
        },

        -- Environmental parameters (GDD 2.2-2.4)
        Environment = {
            WaterColor = Color3.fromRGB(40, 100, 50),          -- Deep teal at canopy
            DeepWaterColor = Color3.fromRGB(10, 25, 15),       -- Murky blue-green at 100m+
            AbyssWaterColor = Color3.fromRGB(3, 8, 10),         -- Near-black at 140m+
            Visibility = 40,          -- studs (limited vs. Shallows' 65)
            FogStart = 30,            -- studs (fog begins)
            DeepVisibility = 30,      -- studs below 100m
            DeepTransitionDepth = 100,-- meters
            GodRays = true,
            GodRaysSource = "CanopyFiltered",  -- dappled through kelp fronds
            AmbientColor = Color3.fromRGB(20, 50, 30),
            MusicTrack = "rbxassetid://--kelp-forest-ambient",

            -- Kelp entanglement hazard (GDD 2.4)
            KelpEntanglement = {
                SlowSpeedMultiplier = 0.60,     -- swimming through kelp at 60% speed
                SprintSnareDuration = 1.5,      -- seconds snared if sprinting
                DisturbRadius = 20,             -- studs, fish alerted on snare
                DisturbDuration = 10,           -- seconds fish stay alerted
            },

            -- The Clearing current hazard (GDD 2.6.2)
            ClearingCurrent = {
                Strength = 8,                      -- studs/s diagonal push
                ResistSpeedMultiplier = 0.40,       -- 40% speed when fighting current
                ResistOxygenMultiplier = 1.30,      -- 1.3x oxygen drain when resisting
                DeepDiverResistStrength = 5.2,       -- studs/s with 35% Current Resistance
                DeepDiverResistOxygenMultiplier = 1.15, -- with suit resistance
            },

            -- Oxygen drain at depth (GDD 4.2.3)
            OxygenDepthScaling = {
                { Depth = 50,  Multiplier = 1.0 },
                { Depth = 100, Multiplier = 1.0 },
                { Depth = 130, Multiplier = 1.15 },
                { Depth = 150, Multiplier = 1.3 },
            },
        },

        -- Landmarks (GDD 2.6)
        Landmarks = {
            -- ====================================================
            -- Kelp Canopy — 50–75m
            -- ====================================================
            {
                Name = "Kelp Canopy",
                DepthRange = { Min = 50, Max = 75 },
                Description = "Dense ceiling of towering kelp stalks. Frilled Seahorses cling to stalks, Kelp Darters zip between fronds, Void Jellyfish drift through.",
                PrimaryFish = { "FrilledSeahorse", "KelpDarter", "VoidJellyfish" },
                CenterPosition = Vector3.new(0, -62, 0),
                Radius = 80,
                IsScreenshotZone = true,
                KelpDensity = "High",
                HazardLevel = "Low",
            },
            -- ====================================================
            -- The Clearing — 75–100m
            -- ====================================================
            {
                Name = "The Clearing",
                DepthRange = { Min = 75, Max = 100 },
                Description = "Open water meadow surrounded by kelp walls. Strong diagonal current. Lantern Squids and Copper Scalebacks inhabit this area.",
                PrimaryFish = { "LanternSquid", "CopperScaleback", "KelpSerpent" },
                CenterPosition = Vector3.new(25, -87, 20),
                Radius = 55,
                IsHub = true,
                KelpDensity = "None",
                HazardLevel = "Medium",
                HasCurrent = true,
                CurrentDirection = Vector3.new(1, 0, -1).Unit, -- NW → SE diagonal
                CurrentStrength = 8,  -- studs/s
            },
            -- ====================================================
            -- Rocky Grotto — 100–130m
            -- ====================================================
            {
                Name = "Rocky Grotto",
                DepthRange = { Min = 100, Max = 130 },
                Description = "Jagged rock formations with bioluminescent lichen. Grotto Crabs in crevices, Kelp Stalkers camouflaged against rock. Darkest zone area.",
                PrimaryFish = { "GrottoCrab", "KelpStalker" },
                CenterPosition = Vector3.new(-15, -115, -10),
                Radius = 45,
                KelpDensity = "Sparse",
                HazardLevel = "High",
                RequiresDeepDiverSuit = true,

                -- Air pockets in caves (GDD 2.6.3)
                AirPockets = {
                    {
                        Name = "Grotto North Cave",
                        Position = Vector3.new(-20, -108, -5),
                        OxygenRefillPercent = 0.30,  -- 30% refill
                        CooldownSeconds = 120,       -- 2 minutes
                    },
                    {
                        Name = "Grotto South Crevice",
                        Position = Vector3.new(-8, -112, -18),
                        OxygenRefillPercent = 0.30,
                        CooldownSeconds = 120,
                    },
                },
            },
            -- ====================================================
            -- Abyss Edge — 130–150m
            -- ====================================================
            {
                Name = "Abyss Edge",
                DepthRange = { Min = 130, Max = 150 },
                Description = "Sheer cliff drop-off into the void. Void Jellyfish and Kelp Serpent patrol here. Foreshadows the Abyssal Trench (Phase 3).",
                PrimaryFish = { "VoidJellyfish", "KelpSerpent" },
                CenterPosition = Vector3.new(-30, -140, -35),
                Radius = 40,
                IsBoundary = true,
                KelpDensity = "None",
                HazardLevel = "Extreme",
                RequiresDeepDiverSuit = true,
                DiegeticBoundary = true,  -- invisible wall shown as shimmering current line
                ForeshadowText = "ABYSSAL TRENCH — OPENING SOON. DEEP DIVER SUIT REQUIRED BEYOND THIS POINT.",
            },
        },

        -- Fish population management (GDD 2.8)
        Population = {
            MaxConcurrentFish = 25,
            RespawnIntervalSeconds = 60,
            DespawnBoundary = 70,       -- studs from zone center
            LegendaryCap = 2,           -- 1 Void Jellyfish + 1 Kelp Serpent max
            SpawnRNGModifier = "HighestLuckInZone",
        },

        -- Spawn conditions (GDD 2.8, 3.4.7, 3.4.8)
        SpawnConditions = {
            -- Void Jellyfish spawn rules
            VoidJellyfish = {
                MaxSpawned = 1,
                MinServerPopulation = 10,
                MinZoneActiveMinutes = 5,
                DespawnIfUnengagedSeconds = 480, -- 8 minutes
                RespawnCooldownSeconds = 120,    -- 2 minutes
            },
            -- Kelp Serpent spawn rules
            KelpSerpent = {
                MaxSpawned = 1,
                SpawnChancePerDayCycle = 0.03,   -- 3% base
                PlayerCountBonus = 0.005,         -- +0.5% per player
                MaxPlayerBonus = 0.125,           -- +12.5% max (25 players)
                DayCycleMinutes = 20,             -- check once per game day
                DespawnIfUnengagedSeconds = 600,  -- 10 minutes
                RespawnCooldownSeconds = 300,     -- 5 minutes
            },
        },
    },

    -- ============================================================
    -- The Abyssal Trench — 100m to 200m (FUTURE)
    -- ============================================================
    AbyssalTrench = {
        Name = "The Abyssal Trench",
        Key = "AbyssalTrench",
        DepthMin = 100,
        DepthMax = 200,
        IsMVP = false,
        IsFuture = true,

        Environment = {
            WaterColor = Color3.fromRGB(5, 5, 20),
            DeepWaterColor = Color3.fromRGB(0, 0, 5),
            Visibility = 20,
            FogStart = 10,
            GodRays = false,
            AmbientColor = Color3.fromRGB(5, 5, 15),
        },

        Landmarks = {},
        Population = {
            MaxConcurrentFish = 25,
            RespawnIntervalSeconds = 60,
        },
        SpawnConditions = {},
    },


    -- ============================================================
    -- The Surface (Shared Ocean) — PHASE 3
    -- y = 0 waterline; boats drive here; surface fish live 0–8m below.
    -- Not an MVP zone — ZoneService loads it explicitly for Phase 3.
    -- ============================================================
    Surface = {
        Name = "The Open Ocean",
        Key = "Surface",
        IsSurface = true,
        IsMVP = false,

        -- World bounds (3,000 x 3,000 stud square, GDD 2.4)
        WorldBounds = { HalfSize = 1500 },

        -- Navigational markers (GDD 2.2 / 6.1): Outpost at origin, buoys outward
        SurfaceMarkers = {
            { Name = "The Outpost", Key = "Outpost", Position = Vector3.new(0, 0, 0), Color = Color3.fromRGB(255, 200, 80), MarkerType = "Dock" },
            { Name = "Shallows Buoy", Key = "ShallowsBuoy", Position = Vector3.new(0, 0, 400), Color = Color3.fromRGB(80, 220, 220), MarkerType = "Buoy", LinkedZone = "SunkenShallows" },
            { Name = "Kelp Buoy", Key = "KelpBuoy", Position = Vector3.new(0, 0, 900), Color = Color3.fromRGB(80, 220, 120), MarkerType = "Buoy", LinkedZone = "KelpForest" },
            { Name = "Trench Buoy", Key = "TrenchBuoy", Position = Vector3.new(0, 0, 1400), Color = Color3.fromRGB(160, 120, 255), MarkerType = "Buoy", LinkedZone = "AbyssalTrench", IsLocked = true },
        },

        -- Surface fish spawn across the open ocean; positions derive from
        -- nearby players (interest-based), not fixed landmarks.
        Landmarks = {
            {
                Name = "Open Ocean",
                DepthRange = { Min = 0, Max = 8 },
                Description = "The shared surface layer. Schools churn the water, predators stalk them.",
                PrimaryFish = { "SilverSkipjack", "BlueSardine", "FlyingFish", "Bonito", "MahiMahi", "Sailfish", "Moonfish", "StormMarlin" },
                CenterPosition = Vector3.new(0, -3, 0),
                Radius = 1400,
            },
        },

        -- Fish population management (GDD 4.6.3): 30/server, respawn every 45s,
        -- despawn beyond 150 studs of any player.
        Population = {
            MaxConcurrentFish = 30,
            RespawnIntervalSeconds = 45,
            DespawnBoundary = 150,     -- studs from nearest player (surface rule)
            LegendaryCap = 2,          -- 1 Moonfish + 1 Storm Marlin
            Surface = true,
        },

        SpawnConditions = {
            DayCycleMinutes = 20,
            DuskDawnWindow = 3,        -- Moonfish surfaces first/last 3 min of day
        },
    },
}


-- ============================================================
-- Helper: Get zone by key
-- ============================================================
function ZoneConfigs.GetByKey(key)
    return ZoneConfigs[key]
end

-- ============================================================
-- Helper: Get only MVP zones
-- ============================================================
function ZoneConfigs.GetMVPZones()
    local zones = {}
    for key, zone in pairs(ZoneConfigs) do
        if type(zone) == "table" and zone.IsMVP then
            zones[key] = zone
        end
    end
    return zones
end

-- ============================================================
-- Helper: Find which zone a depth belongs to
-- ============================================================
function ZoneConfigs.GetZoneAtDepth(depth)
    for _, zone in pairs(ZoneConfigs) do
        if type(zone) == "table" and zone.DepthMin and zone.DepthMax then
            if depth >= zone.DepthMin and depth <= zone.DepthMax then
                return zone
            end
        end
    end
    return nil
end

return ZoneConfigs
