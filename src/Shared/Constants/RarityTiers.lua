--[[
	RarityTiers.lua
	Deep Tide Studios
	Rarity definitions, colors, percentages, and related constants.
	Source: GDD Section 3.3 & Appendix B.
]]

local RarityTiers = {
	-- ============================================================
	-- Rarity definitions (ascending order)
	-- ============================================================
	Common = {
		Name = "Common",
		Color = Color3.fromRGB(150, 150, 150),     -- Grey
		TextColor = Color3.fromRGB(180, 180, 180),
		SortOrder = 1,
		XPValue = 10,
	},
	Uncommon = {
		Name = "Uncommon",
		Color = Color3.fromRGB(80, 200, 80),        -- Green
		TextColor = Color3.fromRGB(100, 255, 100),
		SortOrder = 2,
		XPValue = 25,
	},
	Rare = {
		Name = "Rare",
		Color = Color3.fromRGB(80, 80, 255),        -- Blue
		TextColor = Color3.fromRGB(130, 130, 255),
		SortOrder = 3,
		XPValue = 60,
	},
	Legendary = {
		Name = "Legendary",
		Color = Color3.fromRGB(255, 180, 0),        -- Gold/Orange
		TextColor = Color3.fromRGB(255, 200, 50),
		SortOrder = 4,
		XPValue = 150,
	},
	-- Future tier
	Mythic = {
		Name = "Mythic",
		Color = Color3.fromRGB(255, 50, 50),        -- Red
		TextColor = Color3.fromRGB(255, 100, 100),
		SortOrder = 5,
		XPValue = 400,
	},
}

-- ============================================================
-- Global spawn distribution (for zone without modifiers)
-- ============================================================
RarityTiers.DefaultDistribution = {
	Common = 0.80,      -- 80%
	Uncommon = 0.14,    -- 14%
	Rare = 0.05,        -- 5%
	Legendary = 0.01,   -- 1%
}

-- ============================================================
-- Weight bonus: top 5% of weight range = +50% sell price
-- ============================================================
RarityTiers.WeightBonus = {
	PercentileThreshold = 0.95,  -- top 5%
	PriceMultiplier = 1.5,       -- +50%
}

-- ============================================================
-- Player XP per catch by rarity
-- ============================================================
RarityTiers.GetXPValue = function(rarityName)
	local tier = RarityTiers[rarityName]
	if tier then
		return tier.XPValue
	end
	return 0
end

-- ============================================================
-- Helper: Get Color3 for a rarity
-- ============================================================
function RarityTiers.GetColor(rarityName)
	local tier = RarityTiers[rarityName]
	if tier then
		return tier.Color
	end
	return Color3.fromRGB(255, 255, 255) -- fallback white
end

return RarityTiers
