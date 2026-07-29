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
	-- The Kelp Forest — 50m to 100m (FUTURE)
	-- ============================================================
	KelpForest = {
		Name = "The Kelp Forest",
		Key = "KelpForest",
		DepthMin = 50,
		DepthMax = 100,
		IsMVP = false,
		IsFuture = true,

		Environment = {
			WaterColor = Color3.fromRGB(40, 100, 50),
			DeepWaterColor = Color3.fromRGB(10, 30, 15),
			Visibility = 40,
			FogStart = 30,
			GodRays = false,
			AmbientColor = Color3.fromRGB(20, 50, 30),
		},

		Landmarks = {},
		Population = {
			MaxConcurrentFish = 25,
			RespawnIntervalSeconds = 60,
		},
		SpawnConditions = {},
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
