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
		UnlockCondition = "Default",
		Description = "Standard neoprene wetsuit. Good for shallow reef dives.",
	},

	-- ============================================================
	-- Tier 2: Reinforced Suit — 1,500 Coins
	-- ============================================================
	{
		Name = "Reinforced Suit",
		Key = "ReinforcedSuit",
		Tier = 2,
		Cost = 1500,
		MaxDepth = 50,           -- Same depth cap (MVP), better QoL
		SwimSpeed = 1.3,
		OxygenSeconds = 90,
		UnlockCondition = "Catch 10 fish total + own Coral Rod",
		UnlockRequirement = {
			Type = "TotalCatches",
			Count = 10,
			RequiredRod = "CoralRod",
		},
		Description = "Reinforced with durable polymers. Faster swimming and extended oxygen.",
	},

	-- ============================================================
	-- Tier 3: Pressurized Suit — 5,000 Coins (FUTURE)
	-- ============================================================
	{
		Name = "Pressurized Suit",
		Key = "PressurizedSuit",
		Tier = 3,
		Cost = 5000,
		MaxDepth = 200,
		SwimSpeed = 1.5,
		OxygenSeconds = 120,
		UnlockCondition = "Catch all Sunken Shallows species + own Reef King Rod",
		UnlockRequirement = {
			Type = "CollectionComplete",
			Zone = "SunkenShallows",
			RequiredRod = "ReefKingRod",
		},
		Description = "Rated for extreme depths. The key to the abyss.",
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
