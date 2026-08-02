--[[
	DivePassScreen.lua
	Deep Tide Studios — Client UI Module
	Dive Pass (Season Pass) UI: 50-tier horizontal track, progress bar,
	free/premium reward display, daily challenges, premium purchase flow.

	Design: Dark underwater glass-panel theme with bioluminescent accents.
	Slides in from bottom (differentiated from ShopScreen's right-slide).
	Mobile-friendly: minimum 48×48 touch targets on tier tiles.

	Data source: PlayerDataService (DivePass XP/tier, PremiumOwned, TiersClaimed).
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = require(ReplicatedStorage:WaitForChild("Shared"))
local Knit = require(ReplicatedStorage:WaitForChild("Knit"))

local DivePassScreen = {}
DivePassScreen.__index = DivePassScreen

-- ============================================================
-- Color palette (underwater theme — matches ShopScreen style)
-- ============================================================
local Palette = {
	Background = Color3.fromRGB(8, 14, 28),
	Panel = Color3.fromRGB(12, 22, 44),
	PanelBorder = Color3.fromRGB(40, 100, 160),
	TextPrimary = Color3.fromRGB(220, 235, 255),
	TextSecondary = Color3.fromRGB(140, 175, 210),
	Accent = Color3.fromRGB(60, 200, 220),
	Gold = Color3.fromRGB(255, 200, 50),
	Green = Color3.fromRGB(80, 220, 80),
	Red = Color3.fromRGB(255, 70, 70),
	RobuxGreen = Color3.fromRGB(0, 200, 80),
	ButtonPrimary = Color3.fromRGB(40, 150, 220),
	ButtonHover = Color3.fromRGB(60, 180, 245),
	CardBg = Color3.fromRGB(16, 30, 52),
	TierLocked = Color3.fromRGB(30, 40, 55),
	TierCurrent = Color3.fromRGB(40, 100, 180),
	TierCompleted = Color3.fromRGB(20, 60, 40),
	PremiumLocked = Color3.fromRGB(50, 40, 60),
	PremiumGold = Color3.fromRGB(255, 180, 30),
	XpBarBg = Color3.fromRGB(20, 30, 45),
	XpBarFill = Color3.fromRGB(60, 200, 220),
	ChallengeComplete = Color3.fromRGB(60, 200, 100),
	StreakOrange = Color3.fromRGB(255, 150, 40),
	BiolumCyan = Color3.fromRGB(40, 220, 240),
	BiolumPurple = Color3.fromRGB(140, 60, 240),
}

-- ============================================================
-- Constants
-- ============================================================
local MAX_TIER = 50
local TIER_TILE_SIZE = 78 -- px width per tier tile (touch-friendly)
local VISIBLE_TILES = 6   -- tiles visible without scrolling

-- ============================================================
-- Tier reward data (GDD Section 5.5 + 5.6)
-- ============================================================
local FREE_REWARDS = {
	[1]  = { Type = "Currency", Name = "100 Coins",       Icon = "🪙", Amount = 100, Currency = "Coins" },
	[3]  = { Type = "Consumable", Name = "5× Basic Bait",  Icon = "🪱", Amount = 5,   ItemKey = "BasicBait" },
	[5]  = { Type = "Title", Name = "Kelp Explorer",       Icon = "🏷️", Title = "Kelp Explorer" },
	[8]  = { Type = "Currency", Name = "200 Coins",       Icon = "🪙", Amount = 200, Currency = "Coins" },
	[10] = { Type = "Currency", Name = "25 Gems",         Icon = "💎", Amount = 25,  Currency = "Gems" },
	[12] = { Type = "Consumable", Name = "5× Basic Bait",  Icon = "🪱", Amount = 5,   ItemKey = "BasicBait" },
	[15] = { Type = "Cosmetic", Name = "Kelp Camo Rod Skin", Icon = "🎣", ItemKey = "RodSkin_KelpCamo", IsHero = true },
	[18] = { Type = "Currency", Name = "300 Coins",       Icon = "🪙", Amount = 300, Currency = "Coins" },
	[20] = { Type = "Currency", Name = "50 Gems",         Icon = "💎", Amount = 50,  Currency = "Gems" },
	[22] = { Type = "Consumable", Name = "10× Basic Bait", Icon = "🪱", Amount = 10,  ItemKey = "BasicBait" },
	[25] = { Type = "Title", Name = "Deep Diver",          Icon = "🏷️", Title = "Deep Diver" },
	[28] = { Type = "Currency", Name = "400 Coins",       Icon = "🪙", Amount = 400, Currency = "Coins" },
	[30] = { Type = "Consumable", Name = "3× Luck Charm",  Icon = "🍀", Amount = 3,   ItemKey = "LuckCharm" },
	[32] = { Type = "Consumable", Name = "10× Basic Bait", Icon = "🪱", Amount = 10,  ItemKey = "BasicBait" },
	[35] = { Type = "Currency", Name = "500 Coins",       Icon = "🪙", Amount = 500, Currency = "Coins" },
	[38] = { Type = "Currency", Name = "75 Gems",         Icon = "💎", Amount = 75,  Currency = "Gems" },
	[40] = { Type = "Consumable", Name = "5× Luck Charm",  Icon = "🍀", Amount = 5,   ItemKey = "LuckCharm" },
	[42] = { Type = "Currency", Name = "600 Coins",       Icon = "🪙", Amount = 600, Currency = "Coins" },
	[45] = { Type = "Cosmetic", Name = "Bioluminescent Rod", Icon = "🎣", ItemKey = "RodSkin_Biolum", IsHero = true },
	[48] = { Type = "Currency", Name = "100 Gems",        Icon = "💎", Amount = 100, Currency = "Gems" },
	[50] = { Type = "Cosmetic", Name = "Void Touched Title + Badge", Icon = "🌌", Title = "Void Touched", IsHero = true },
}

local PREMIUM_REWARDS = {
	["instant"] = { Type = "Boost", Name = "+20% Dive Pass XP", Icon = "⚡", IsPassive = true },
	[1]  = { Type = "Cosmetic", Name = "Abyssal Black Suit Skin", Icon = "🦺", ItemKey = "SuitSkin_AbyssalBlack" },
	[5]  = { Type = "Currency", Name = "50 Gems",       Icon = "💎", Amount = 50,  Currency = "Gems" },
	[10] = { Type = "Consumable", Name = "10× Premium Bait", Icon = "🦐", Amount = 10, ItemKey = "PremiumBait" },
	[15] = { Type = "Currency", Name = "100 Gems",      Icon = "💎", Amount = 100, Currency = "Gems" },
	[20] = { Type = "Cosmetic", Name = "Void Pulse Rod Skin", Icon = "🎣", ItemKey = "RodSkin_VoidPulse", IsHero = true },
	[25] = { Type = "Consumable", Name = "3× Treasure Map", Icon = "🗺️", Amount = 3, ItemKey = "TreasureMap" },
	[30] = { Type = "Currency", Name = "150 Gems",      Icon = "💎", Amount = 150, Currency = "Gems" },
	[35] = { Type = "Cosmetic", Name = "Bioluminescent Suit", Icon = "🦺", ItemKey = "SuitSkin_Biolum", IsHero = true },
	[40] = { Type = "Currency", Name = "200 Gems",      Icon = "💎", Amount = 200, Currency = "Gems" },
	[45] = { Type = "Consumable", Name = "5× Treasure Map + 20× Premium Bait", Icon = "🗺️", Amount = 5, ItemKey = "TreasureMap" },
	[50] = { Type = "Cosmetic", Name = "Mythic Creature Lure", Icon = "🌟", ItemKey = "MythicLure", IsHero = true },
}

-- Tier 50 hero reward: "Abyssal Sovereign" bundle
local HERO_REWARD = {
	Name = "Abyssal Sovereign",
	Description = "Legendary rod skin + animated diving suit + companion pet + glowing title + surface emote",
	Icon = "👑",
	Tier = 50,
}

-- ============================================================
-- Constructor
-- ============================================================
function DivePassScreen.new()
	local self = setmetatable({}, DivePassScreen)

	self._gui = nil
	self._backdrop = nil
	self._mainFrame = nil
	self._isOpen = false
	self._currentTab = "DivePass" -- DivePass | Challenges
	self._playerData = nil
	self._onCloseCallback = nil
	self._premiumOwned = false
	self._currentTier = 1
	self._totalXP = 0
	self._tierXP = 0
	self._tierXPRequired = 0
	self._tiersClaimed = {}
	self._dailyChallenges = {}
	self._dailyStreak = 0
	self._detailPopup = nil
	self._purchaseDialog = nil
		self._selectedChallengeId = nil

	self:_createGUI()
	self:_wireInput()

	return self
end

-- ============================================================
-- Create all UI elements
-- ============================================================
function DivePassScreen:_createGUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = playerGui:FindFirstChild("DeepTideUI")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "DeepTideUI"
		gui.ResetOnSpawn = false
		gui.Parent = playerGui
	end
	self._gui = gui

	-- ---- Full-screen backdrop ----
	local backdrop = Instance.new("Frame")
	backdrop.Name = "DivePassBackdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.Position = UDim2.new(0, 0, 0, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.Visible = false
	backdrop.ZIndex = 90
	backdrop.Parent = gui

	backdrop.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or
		   input.UserInputType == Enum.UserInputType.Touch then
			self:Close()
		end
	end)

	self._backdrop = backdrop

	-- ---- Main panel (slides from BOTTOM) ----
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "DivePassMain"
	mainFrame.Size = UDim2.new(0.92, 0, 0.88, 0)
	mainFrame.Position = UDim2.new(0.04, 0, 1, 0) -- Start off-screen below
	mainFrame.BackgroundColor3 = Palette.Panel
	mainFrame.BackgroundTransparency = 0.06
	mainFrame.BorderSizePixel = 0
	mainFrame.ZIndex = 95
	mainFrame.Parent = backdrop

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 24)
	panelCorner.Parent = mainFrame

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Palette.PanelBorder
	panelStroke.Thickness = 2
	panelStroke.Transparency = 0.3
	panelStroke.Parent = mainFrame

	self._mainFrame = mainFrame

	-- ---- HEADER SECTION ----
	self:_createHeader(mainFrame)

	-- ---- PROGRESS BAR SECTION ----
	self:_createProgressSection(mainFrame)

	-- ---- HORIZONTAL TIER TRACK ----
	self:_createTierTrack(mainFrame)

	-- ---- HERO REWARD SHOWCASE ----
	self:_createHeroShowcase(mainFrame)

	-- ---- PREMIUM CTA / PURCHASED SECTION ----
	self:_createCTASection(mainFrame)

	-- ---- TAB BAR (Dive Pass | Daily Challenges) ----
	self:_createTabBar(mainFrame)

	-- ---- DAILY CHALLENGES PANEL ----
	self:_createChallengesPanel(mainFrame)

	-- ---- TIER DETAIL POPUP ----
	self:_createDetailPopup(mainFrame)

	-- ---- PURCHASE CONFIRMATION DIALOG ----
	self:_createPurchaseDialog(mainFrame)
end

-- ============================================================
-- Header with season info + close button
-- ============================================================
function DivePassScreen:_createHeader(parent)
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, -32, 0, 52)
	header.Position = UDim2.new(0, 16, 0, 8)
	header.BackgroundTransparency = 1
	header.ZIndex = 96
	header.Parent = parent

	-- Season badge
	local seasonBadge = Instance.new("Frame")
	seasonBadge.Name = "SeasonBadge"
	seasonBadge.Size = UDim2.new(0, 140, 0, 28)
	seasonBadge.Position = UDim2.new(0, 0, 0, 4)
	seasonBadge.BackgroundColor3 = Palette.Accent
	seasonBadge.BackgroundTransparency = 0.6
	seasonBadge.BorderSizePixel = 0
	seasonBadge.ZIndex = 97
	seasonBadge.Parent = header

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 14)
	badgeCorner.Parent = seasonBadge

	local badgeLabel = Instance.new("TextLabel")
	badgeLabel.Size = UDim2.new(1, 0, 1, 0)
	badgeLabel.BackgroundTransparency = 1
	badgeLabel.Font = Enum.Font.GothamBold
	badgeLabel.TextSize = 12
	badgeLabel.Text = "SEASON 1: KELP FOREST"
	badgeLabel.TextColor3 = Palette.Accent
	badgeLabel.ZIndex = 97
	badgeLabel.Parent = seasonBadge

	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(0, 300, 0, 22)
	titleLabel.Position = UDim2.new(0, 150, 0, 4)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 18
	titleLabel.Text = "DIVE PASS"
	titleLabel.TextColor3 = Palette.TextPrimary
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.ZIndex = 97
	titleLabel.Parent = header

	-- Subtitle
	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "Subtitle"
	subLabel.Size = UDim2.new(0, 300, 0, 16)
	subLabel.Position = UDim2.new(0, 150, 0, 28)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = Enum.Font.Gotham
	subLabel.TextSize = 11
	subLabel.Text = "\"Descend into the Green\""
	subLabel.TextColor3 = Palette.TextSecondary
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.ZIndex = 97
	subLabel.Parent = header

	-- Days remaining
	self._daysRemainingLabel = Instance.new("TextLabel")
	self._daysRemainingLabel.Name = "DaysRemaining"
	self._daysRemainingLabel.Size = UDim2.new(0, 200, 0, 18)
	self._daysRemainingLabel.Position = UDim2.new(1, -248, 0, 6)
	self._daysRemainingLabel.BackgroundTransparency = 1
	self._daysRemainingLabel.Font = Enum.Font.GothamBold
	self._daysRemainingLabel.TextSize = 13
	self._daysRemainingLabel.Text = "42 days remaining"
	self._daysRemainingLabel.TextColor3 = Palette.Gold
	self._daysRemainingLabel.TextXAlignment = Enum.TextXAlignment.Right
	self._daysRemainingLabel.ZIndex = 97
	self._daysRemainingLabel.Parent = header

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 44, 0, 44)
	closeBtn.Position = UDim2.new(1, -44, 0, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.BackgroundTransparency = 0.85
	closeBtn.Text = "✕"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 24
	closeBtn.TextColor3 = Palette.TextSecondary
	closeBtn.ZIndex = 97
	closeBtn.Parent = header

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 12)
	closeCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		self:Close()
	end)

	self._headerFrame = header
end

-- ============================================================
-- Progress section: tier indicator + XP bar
-- ============================================================
function DivePassScreen:_createProgressSection(parent)
	local section = Instance.new("Frame")
	section.Name = "ProgressSection"
	section.Size = UDim2.new(1, -32, 0, 64)
	section.Position = UDim2.new(0, 16, 0, 64)
	section.BackgroundColor3 = Palette.CardBg
	section.BackgroundTransparency = 0.3
	section.BorderSizePixel = 0
	section.ZIndex = 96
	section.Parent = parent

	local sectionCorner = Instance.new("UICorner")
	sectionCorner.CornerRadius = UDim.new(0, 12)
	sectionCorner.Parent = section

	-- Tier badge (left side)
	local tierBadge = Instance.new("Frame")
	tierBadge.Name = "TierBadge"
	tierBadge.Size = UDim2.new(0, 56, 0, 48)
	tierBadge.Position = UDim2.new(0, 10, 0.5, -24)
	tierBadge.BackgroundColor3 = Palette.Accent
	tierBadge.BackgroundTransparency = 0.5
	tierBadge.BorderSizePixel = 0
	tierBadge.ZIndex = 97
	tierBadge.Parent = section

	local tierCorner = Instance.new("UICorner")
	tierCorner.CornerRadius = UDim.new(0, 12)
	tierCorner.Parent = tierBadge

	local tierNum = Instance.new("TextLabel")
	tierNum.Name = "TierNum"
	tierNum.Size = UDim2.new(1, 0, 0, 28)
	tierNum.Position = UDim2.new(0, 0, 0, 2)
	tierNum.BackgroundTransparency = 1
	tierNum.Font = Enum.Font.GothamBold
	tierNum.TextSize = 24
	tierNum.Text = "12"
	tierNum.TextColor3 = Palette.TextPrimary
	tierNum.ZIndex = 98
	tierNum.Parent = tierBadge
	self._tierNumLabel = tierNum

	local tierText = Instance.new("TextLabel")
	tierText.Name = "TierText"
	tierText.Size = UDim2.new(1, 0, 0, 14)
	tierText.Position = UDim2.new(0, 0, 0, 30)
	tierText.BackgroundTransparency = 1
	tierText.Font = Enum.Font.Gotham
	tierText.TextSize = 9
	tierText.Text = "TIER"
	tierText.TextColor3 = Palette.TextSecondary
	tierText.ZIndex = 98
	tierText.Parent = tierBadge

	-- XP Progress info (right of tier badge)
	local xpLabel = Instance.new("TextLabel")
	xpLabel.Name = "XPLabel"
	xpLabel.Size = UDim2.new(1, -166, 0, 18)
	xpLabel.Position = UDim2.new(0, 76, 0, 8)
	xpLabel.BackgroundTransparency = 1
	xpLabel.Font = Enum.Font.GothamBold
	xpLabel.TextSize = 14
	xpLabel.Text = "2,340 / 3,000 XP"
	xpLabel.TextColor3 = Palette.TextPrimary
	xpLabel.TextXAlignment = Enum.TextXAlignment.Left
	xpLabel.ZIndex = 97
	xpLabel.Parent = section
	self._xpLabel = xpLabel

	-- XP progress bar
	local xpBarBg = Instance.new("Frame")
	xpBarBg.Name = "XPBarBg"
	xpBarBg.Size = UDim2.new(1, -166, 0, 14)
	xpBarBg.Position = UDim2.new(0, 76, 0, 32)
	xpBarBg.BackgroundColor3 = Palette.XpBarBg
	xpBarBg.BorderSizePixel = 0
	xpBarBg.ZIndex = 97
	xpBarBg.Parent = section

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 7)
	barCorner.Parent = xpBarBg

	local xpBarFill = Instance.new("Frame")
	xpBarFill.Name = "XPBarFill"
	xpBarFill.Size = UDim2.new(0.58, 0, 1, 0)
	xpBarFill.Position = UDim2.new(0, 0, 0, 0)
	xpBarFill.BackgroundColor3 = Palette.XpBarFill
	xpBarFill.BorderSizePixel = 0
	xpBarFill.ZIndex = 98
	xpBarFill.Parent = xpBarBg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 7)
	fillCorner.Parent = xpBarFill
	self._xpBarFill = xpBarFill

	-- Percentage label
	local pctLabel = Instance.new("TextLabel")
	pctLabel.Name = "PercentLabel"
	pctLabel.Size = UDim2.new(0, 60, 0, 14)
	pctLabel.Position = UDim2.new(1, -68, 0, 32)
	pctLabel.BackgroundTransparency = 1
	pctLabel.Font = Enum.Font.GothamBold
	pctLabel.TextSize = 11
	pctLabel.Text = "78%"
	pctLabel.TextColor3 = Palette.XpBarFill
	pctLabel.TextXAlignment = Enum.TextXAlignment.Right
	pctLabel.ZIndex = 97
	pctLabel.Parent = section
	self._xpPctLabel = pctLabel

	-- Total XP label
	self._totalXPLabel = Instance.new("TextLabel")
	self._totalXPLabel.Name = "TotalXPLabel"
	self._totalXPLabel.Size = UDim2.new(0, 200, 0, 14)
	self._totalXPLabel.Position = UDim2.new(1, -208, 0, 8)
	self._totalXPLabel.BackgroundTransparency = 1
	self._totalXPLabel.Font = Enum.Font.Gotham
	self._totalXPLabel.TextSize = 11
	self._totalXPLabel.Text = "Total: 7,820 XP"
	self._totalXPLabel.TextColor3 = Palette.TextSecondary
	self._totalXPLabel.TextXAlignment = Enum.TextXAlignment.Right
	self._totalXPLabel.ZIndex = 97
	self._totalXPLabel.Parent = section

	self._progressSection = section
end

-- ============================================================
-- Horizontal tier track (50 tiers)
-- ============================================================
function DivePassScreen:_createTierTrack(parent)
	local trackContainer = Instance.new("Frame")
	trackContainer.Name = "TierTrackContainer"
	trackContainer.Size = UDim2.new(1, -24, 0, 112)
	trackContainer.Position = UDim2.new(0, 12, 0, 136)
	trackContainer.BackgroundTransparency = 1
	trackContainer.ZIndex = 96
	trackContainer.Parent = parent

	-- Section label
	local trackLabel = Instance.new("TextLabel")
	trackLabel.Name = "TrackLabel"
	trackLabel.Size = UDim2.new(0, 200, 0, 18)
	trackLabel.Position = UDim2.new(0, 8, 0, 0)
	trackLabel.BackgroundTransparency = 1
	trackLabel.Font = Enum.Font.GothamBold
	trackLabel.TextSize = 12
	trackLabel.Text = "TIERS"
	trackLabel.TextColor3 = Palette.TextSecondary
	trackLabel.TextXAlignment = Enum.TextXAlignment.Left
	trackLabel.ZIndex = 97
	trackLabel.Parent = trackContainer

	-- Legend
	local legendFree = Instance.new("Frame")
	legendFree.Name = "LegendFree"
	legendFree.Size = UDim2.new(0, 12, 0, 12)
	legendFree.Position = UDim2.new(0, 8, 0, 20)
	legendFree.BackgroundColor3 = Palette.XpBarFill
	legendFree.BorderSizePixel = 0
	legendFree.ZIndex = 97
	legendFree.Parent = trackContainer
	local freeCorner = Instance.new("UICorner")
	freeCorner.CornerRadius = UDim.new(0, 3)
	freeCorner.Parent = legendFree

	local legendFreeLabel = Instance.new("TextLabel")
	legendFreeLabel.Size = UDim2.new(0, 40, 0, 14)
	legendFreeLabel.Position = UDim2.new(0, 22, 0, 20)
	legendFreeLabel.BackgroundTransparency = 1
	legendFreeLabel.Font = Enum.Font.Gotham
	legendFreeLabel.TextSize = 10
	legendFreeLabel.Text = "FREE"
	legendFreeLabel.TextColor3 = Palette.TextSecondary
	legendFreeLabel.TextXAlignment = Enum.TextXAlignment.Left
	legendFreeLabel.ZIndex = 97
	legendFreeLabel.Parent = trackContainer

	local legendPremium = Instance.new("Frame")
	legendPremium.Name = "LegendPremium"
	legendPremium.Size = UDim2.new(0, 12, 0, 12)
	legendPremium.Position = UDim2.new(0, 72, 0, 20)
	legendPremium.BackgroundColor3 = Palette.PremiumGold
	legendPremium.BorderSizePixel = 0
	legendPremium.ZIndex = 97
	legendPremium.Parent = trackContainer
	local premCorner = Instance.new("UICorner")
	premCorner.CornerRadius = UDim.new(0, 3)
	premCorner.Parent = legendPremium

	local legendPremiumLabel = Instance.new("TextLabel")
	legendPremiumLabel.Size = UDim2.new(0, 80, 0, 14)
	legendPremiumLabel.Position = UDim2.new(0, 86, 0, 20)
	legendPremiumLabel.BackgroundTransparency = 1
	legendPremiumLabel.Font = Enum.Font.Gotham
	legendPremiumLabel.TextSize = 10
	legendPremiumLabel.Text = "PREMIUM"
	legendPremiumLabel.TextColor3 = Palette.TextSecondary
	legendPremiumLabel.TextXAlignment = Enum.TextXAlignment.Left
	legendPremiumLabel.ZIndex = 97
	legendPremiumLabel.Parent = trackContainer

	-- Horizontal scrolling tier track
	local tierScroll = Instance.new("ScrollingFrame")
	tierScroll.Name = "TierScroll"
	tierScroll.Size = UDim2.new(1, -8, 0, 70)
	tierScroll.Position = UDim2.new(0, 4, 0, 38)
	tierScroll.BackgroundColor3 = Palette.Background
	tierScroll.BackgroundTransparency = 0.5
	tierScroll.BorderSizePixel = 0
	tierScroll.ScrollBarThickness = 4
	tierScroll.ScrollBarImageColor3 = Palette.PanelBorder
	tierScroll.ScrollingDirection = Enum.ScrollingDirection.X
	tierScroll.CanvasSize = UDim2.new(0, (TIER_TILE_SIZE + 6) * MAX_TIER + 8, 0, 0)
	tierScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	tierScroll.ZIndex = 97
	tierScroll.Parent = trackContainer

	local scrollCorner = Instance.new("UICorner")
	scrollCorner.CornerRadius = UDim.new(0, 8)
	scrollCorner.Parent = tierScroll

	local tileLayout = Instance.new("UIListLayout")
	tileLayout.Name = "TileLayout"
	tileLayout.Padding = UDim.new(0, 4)
	tileLayout.FillDirection = Enum.FillDirection.Horizontal
	tileLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	tileLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tileLayout.Parent = tierScroll

	self._tierScroll = tierScroll
	self._tierTiles = {}
end

-- ============================================================
-- Hero reward showcase (Tier 50 "Abyssal Sovereign")
-- ============================================================
function DivePassScreen:_createHeroShowcase(parent)
	local heroSection = Instance.new("Frame")
	heroSection.Name = "HeroShowcase"
	heroSection.Size = UDim2.new(1, -32, 0, 72)
	heroSection.Position = UDim2.new(0, 16, 0, 256)
	heroSection.BackgroundColor3 = Palette.CardBg
	heroSection.BackgroundTransparency = 0.2
	heroSection.BorderSizePixel = 0
	heroSection.ZIndex = 96
	heroSection.Parent = parent

	local heroCorner = Instance.new("UICorner")
	heroCorner.CornerRadius = UDim.new(0, 12)
	heroCorner.Parent = heroSection

	local heroStroke = Instance.new("UIStroke")
	heroStroke.Color = Palette.PremiumGold
	heroStroke.Thickness = 1.5
	heroStroke.Transparency = 0.4
	heroStroke.Parent = heroSection

	-- Hero icon
	local heroIcon = Instance.new("TextLabel")
	heroIcon.Name = "HeroIcon"
	heroIcon.Size = UDim2.new(0, 52, 0, 52)
	heroIcon.Position = UDim2.new(0, 12, 0.5, -26)
	heroIcon.BackgroundTransparency = 1
	heroIcon.Font = Enum.Font.Gotham
	heroIcon.TextSize = 36
	heroIcon.Text = HERO_REWARD.Icon
	heroIcon.ZIndex = 97
	heroIcon.Parent = heroSection

	-- Hero info
	local heroName = Instance.new("TextLabel")
	heroName.Name = "HeroName"
	heroName.Size = UDim2.new(1, -180, 0, 20)
	heroName.Position = UDim2.new(0, 72, 0, 10)
	heroName.BackgroundTransparency = 1
	heroName.Font = Enum.Font.GothamBold
	heroName.TextSize = 16
	heroName.Text = "TIER 50 — " .. HERO_REWARD.Name
	heroName.TextColor3 = Palette.PremiumGold
	heroName.TextXAlignment = Enum.TextXAlignment.Left
	heroName.ZIndex = 97
	heroName.Parent = heroSection

	local heroDesc = Instance.new("TextLabel")
	heroDesc.Name = "HeroDesc"
	heroDesc.Size = UDim2.new(1, -180, 0, 28)
	heroDesc.Position = UDim2.new(0, 72, 0, 32)
	heroDesc.BackgroundTransparency = 1
	heroDesc.Font = Enum.Font.Gotham
	heroDesc.TextSize = 11
	heroDesc.Text = HERO_REWARD.Description
	heroDesc.TextColor3 = Palette.TextSecondary
	heroDesc.TextXAlignment = Enum.TextXAlignment.Left
	heroDesc.TextWrapped = true
	heroDesc.ZIndex = 97
	heroDesc.Parent = heroSection

	-- CTA on hero
	self._heroCTA = Instance.new("TextButton")
	self._heroCTA.Name = "HeroCTA"
	self._heroCTA.Size = UDim2.new(0, 130, 0, 36)
	self._heroCTA.Position = UDim2.new(1, -142, 0.5, -18)
	self._heroCTA.BackgroundColor3 = Palette.PremiumGold
	self._heroCTA.BackgroundTransparency = 0.3
	self._heroCTA.Text = "UNLOCK TIER 50"
	self._heroCTA.Font = Enum.Font.GothamBold
	self._heroCTA.TextSize = 10
	self._heroCTA.TextColor3 = Palette.PremiumGold
	self._heroCTA.ZIndex = 97
	self._heroCTA.Parent = heroSection

	local heroCTACorner = Instance.new("UICorner")
	heroCTACorner.CornerRadius = UDim.new(0, 8)
	heroCTACorner.Parent = self._heroCTA

	self._heroSection = heroSection
end

-- ============================================================
-- Premium CTA / Purchased section
-- ============================================================
function DivePassScreen:_createCTASection(parent)
	local ctaSection = Instance.new("Frame")
	ctaSection.Name = "CTASection"
	ctaSection.Size = UDim2.new(1, -32, 0, 52)
	ctaSection.Position = UDim2.new(0, 16, 0, 338)
	ctaSection.BackgroundTransparency = 1
	ctaSection.ZIndex = 96
	ctaSection.Parent = parent

	-- BUY PREMIUM button (default: shown when not owned)
	self._buyPremiumBtn = Instance.new("TextButton")
	self._buyPremiumBtn.Name = "BuyPremiumBtn"
	self._buyPremiumBtn.Size = UDim2.new(0.54, -4, 0, 44)
	self._buyPremiumBtn.Position = UDim2.new(0, 0, 0, 4)
	self._buyPremiumBtn.BackgroundColor3 = Palette.PremiumGold
	self._buyPremiumBtn.Text = ""
	self._buyPremiumBtn.Font = Enum.Font.GothamBold
	self._buyPremiumBtn.TextSize = 16
	self._buyPremiumBtn.TextColor3 = Color3.fromRGB(30, 20, 0)
	self._buyPremiumBtn.ZIndex = 97
	self._buyPremiumBtn.Parent = ctaSection

	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0, 12)
	buyCorner.Parent = self._buyPremiumBtn

	-- Premium icon + label inside CTA
	local premiumIcon = Instance.new("TextLabel")
	premiumIcon.Name = "PremiumIcon"
	premiumIcon.Size = UDim2.new(0, 32, 0, 32)
	premiumIcon.Position = UDim2.new(0, 12, 0.5, -16)
	premiumIcon.BackgroundTransparency = 1
	premiumIcon.Font = Enum.Font.Gotham
	premiumIcon.TextSize = 24
	premiumIcon.Text = "👑"
	premiumIcon.ZIndex = 98
	premiumIcon.Parent = self._buyPremiumBtn

	local premiumLabel = Instance.new("TextLabel")
	premiumLabel.Name = "PremiumLabel"
	premiumLabel.Size = UDim2.new(1, -56, 0, 22)
	premiumLabel.Position = UDim2.new(0, 48, 0.5, -11)
	premiumLabel.BackgroundTransparency = 1
	premiumLabel.Font = Enum.Font.GothamBold
	premiumLabel.TextSize = 15
	premiumLabel.Text = "BUY PREMIUM"
	premiumLabel.TextColor3 = Color3.fromRGB(30, 20, 0)
	premiumLabel.TextXAlignment = Enum.TextXAlignment.Left
	premiumLabel.ZIndex = 98
	premiumLabel.Parent = self._buyPremiumBtn

	local premiumPrice = Instance.new("TextLabel")
	premiumPrice.Name = "PremiumPrice"
	premiumPrice.Size = UDim2.new(0, 100, 0, 22)
	premiumPrice.Position = UDim2.new(1, -108, 0.5, -11)
	premiumPrice.BackgroundTransparency = 1
	premiumPrice.Font = Enum.Font.GothamBold
	premiumPrice.TextSize = 14
	premiumPrice.Text = "R$ 499"
	premiumPrice.TextColor3 = Color3.fromRGB(20, 80, 10)
	premiumPrice.TextXAlignment = Enum.TextXAlignment.Right
	premiumPrice.ZIndex = 98
	premiumPrice.Parent = self._buyPremiumBtn

	self._buyPremiumBtn.MouseButton1Click:Connect(function()
		self:_showPurchaseDialog("base")
	end)

	-- BUNDLE button (Premium + 15 tier skips)
	self._buyBundleBtn = Instance.new("TextButton")
	self._buyBundleBtn.Name = "BuyBundleBtn"
	self._buyBundleBtn.Size = UDim2.new(0.42, -4, 0, 44)
	self._buyBundleBtn.Position = UDim2.new(0.57, 0, 0, 4)
	self._buyBundleBtn.BackgroundColor3 = Palette.BiolumPurple
	self._buyBundleBtn.BackgroundTransparency = 0.4
	self._buyBundleBtn.Text = ""
	self._buyBundleBtn.Font = Enum.Font.GothamBold
	self._buyBundleBtn.TextSize = 14
	self._buyBundleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	self._buyBundleBtn.ZIndex = 97
	self._buyBundleBtn.Parent = ctaSection

	local bundleCorner = Instance.new("UICorner")
	bundleCorner.CornerRadius = UDim.new(0, 12)
	bundleCorner.Parent = self._buyBundleBtn

	local bundleStroke = Instance.new("UIStroke")
	bundleStroke.Color = Palette.BiolumPurple
	bundleStroke.Thickness = 1.5
	bundleStroke.Transparency = 0.2
	bundleStroke.Parent = self._buyBundleBtn

	local bundleLabel = Instance.new("TextLabel")
	bundleLabel.Size = UDim2.new(1, -16, 0, 18)
	bundleLabel.Position = UDim2.new(0, 8, 0, 4)
	bundleLabel.BackgroundTransparency = 1
	bundleLabel.Font = Enum.Font.GothamBold
	bundleLabel.TextSize = 13
	bundleLabel.Text = "PREMIUM + 15 TIERS"
	bundleLabel.TextColor3 = Palette.TextPrimary
	bundleLabel.ZIndex = 98
	bundleLabel.Parent = self._buyBundleBtn

	local bundlePrice = Instance.new("TextLabel")
	bundlePrice.Size = UDim2.new(0, 100, 0, 16)
	bundlePrice.Position = UDim2.new(1, -108, 0, 24)
	bundlePrice.BackgroundTransparency = 1
	bundlePrice.Font = Enum.Font.GothamBold
	bundlePrice.TextSize = 12
	bundlePrice.Text = "R$ 799"
	bundlePrice.TextColor3 = Palette.RobuxGreen
	bundlePrice.TextXAlignment = Enum.TextXAlignment.Right
	bundlePrice.ZIndex = 98
	bundlePrice.Parent = self._buyBundleBtn

	self._buyBundleBtn.MouseButton1Click:Connect(function()
		self:_showPurchaseDialog("bundle")
	end)

	-- ---- PURCHASED STATE (hidden by default) ----
	self._premiumActiveBadge = Instance.new("Frame")
	self._premiumActiveBadge.Name = "PremiumActiveBadge"
	self._premiumActiveBadge.Size = UDim2.new(0.5, 0, 0, 44)
	self._premiumActiveBadge.Position = UDim2.new(0.25, 0, 0, 4)
	self._premiumActiveBadge.BackgroundColor3 = Palette.Green
	self._premiumActiveBadge.BackgroundTransparency = 0.6
	self._premiumActiveBadge.BorderSizePixel = 0
	self._premiumActiveBadge.Visible = false
	self._premiumActiveBadge.ZIndex = 97
	self._premiumActiveBadge.Parent = ctaSection

	local activeCorner = Instance.new("UICorner")
	activeCorner.CornerRadius = UDim.new(0, 12)
	activeCorner.Parent = self._premiumActiveBadge

	local activeLabel = Instance.new("TextLabel")
	activeLabel.Size = UDim2.new(1, 0, 1, 0)
	activeLabel.BackgroundTransparency = 1
	activeLabel.Font = Enum.Font.GothamBold
	activeLabel.TextSize = 16
	activeLabel.Text = "👑 PREMIUM ACTIVE"
	activeLabel.TextColor3 = Palette.Green
	activeLabel.ZIndex = 98
	activeLabel.Parent = self._premiumActiveBadge

	self._ctaSection = ctaSection
end

-- ============================================================
-- Tab bar: Dive Pass | Daily Challenges
-- ============================================================
function DivePassScreen:_createTabBar(parent)
	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.Size = UDim2.new(0.55, 0, 0, 36)
	tabBar.Position = UDim2.new(0, 16, 0, 400)
	tabBar.BackgroundTransparency = 1
	tabBar.ZIndex = 96
	tabBar.Parent = parent

	local tabs = {
		{ Name = "Dive Pass", Key = "DivePass" },
		{ Name = "Daily Challenges", Key = "Challenges" },
	}
	self._tabButtons = {}

	for i, tab in ipairs(tabs) do
		local tabBtn = Instance.new("TextButton")
		tabBtn.Name = "Tab_" .. tab.Key
		tabBtn.Size = UDim2.new(0.47, 0, 1, 0)
		tabBtn.Position = UDim2.new((i - 1) * 0.53, 0, 0, 0)
		tabBtn.BackgroundColor3 = (tab.Key == self._currentTab) and Palette.Accent or Palette.TierLocked
		tabBtn.BackgroundTransparency = (tab.Key == self._currentTab) and 0.5 or 0.3
		tabBtn.Text = tab.Name
		tabBtn.Font = Enum.Font.GothamBold
		tabBtn.TextSize = 14
		tabBtn.TextColor3 = Palette.TextPrimary
		tabBtn.ZIndex = 97
		tabBtn.Parent = tabBar

		local tabCorner = Instance.new("UICorner")
		tabCorner.CornerRadius = UDim.new(0, 10)
		tabCorner.Parent = tabBtn

		tabBtn.MouseButton1Click:Connect(function()
			self:_switchTab(tab.Key)
		end)

		self._tabButtons[tab.Key] = tabBtn
	end

	self._tabBar = tabBar
end

-- ============================================================
-- Daily Challenges panel
-- ============================================================
function DivePassScreen:_createChallengesPanel(parent)
	local challengesPanel = Instance.new("Frame")
	challengesPanel.Name = "ChallengesPanel"
	challengesPanel.Size = UDim2.new(1, -32, 0, 200)
	challengesPanel.Position = UDim2.new(0, 16, 0, 444)
	challengesPanel.BackgroundTransparency = 1
	challengesPanel.Visible = false
	challengesPanel.ZIndex = 96
	challengesPanel.Parent = parent

	-- Time remaining
	self._challengeTimerLabel = Instance.new("TextLabel")
	self._challengeTimerLabel.Name = "ChallengeTimer"
	self._challengeTimerLabel.Size = UDim2.new(1, 0, 0, 18)
	self._challengeTimerLabel.Position = UDim2.new(0, 0, 0, 0)
	self._challengeTimerLabel.BackgroundTransparency = 1
	self._challengeTimerLabel.Font = Enum.Font.GothamBold
	self._challengeTimerLabel.TextSize = 13
	self._challengeTimerLabel.Text = "⏳ 14h 32m remaining"
	self._challengeTimerLabel.TextColor3 = Palette.TextSecondary
	self._challengeTimerLabel.TextXAlignment = Enum.TextXAlignment.Left
	self._challengeTimerLabel.ZIndex = 97
	self._challengeTimerLabel.Parent = challengesPanel

	-- Streak counter
	self._streakLabel = Instance.new("TextLabel")
	self._streakLabel.Name = "StreakLabel"
	self._streakLabel.Size = UDim2.new(0, 150, 0, 18)
	self._streakLabel.Position = UDim2.new(1, -150, 0, 0)
	self._streakLabel.BackgroundTransparency = 1
	self._streakLabel.Font = Enum.Font.GothamBold
	self._streakLabel.TextSize = 13
	self._streakLabel.Text = "🔥 0-Day Streak"
	self._streakLabel.TextColor3 = Palette.StreakOrange
	self._streakLabel.TextXAlignment = Enum.TextXAlignment.Right
	self._streakLabel.ZIndex = 97
	self._streakLabel.Parent = challengesPanel

	-- Reroll button
	local rerollBtn = Instance.new("TextButton")
	rerollBtn.Name = "RerollBtn"
	rerollBtn.Size = UDim2.new(0, 130, 0, 28)
	rerollBtn.Position = UDim2.new(1, -130, 0, 22)
	rerollBtn.BackgroundColor3 = Palette.TierLocked
	rerollBtn.BackgroundTransparency = 0.3
	rerollBtn.Text = "🔄 Reroll (1 free)"
	rerollBtn.Font = Enum.Font.Gotham
	rerollBtn.TextSize = 11
	rerollBtn.TextColor3 = Palette.TextSecondary
	rerollBtn.ZIndex = 97
	rerollBtn.Parent = challengesPanel

	local rerollCorner = Instance.new("UICorner")
	rerollCorner.CornerRadius = UDim.new(0, 8)
	rerollCorner.Parent = rerollBtn

	rerollBtn.MouseButton1Click:Connect(function()
		self:_onRerollClicked()
	end)
	self._rerollBtn = rerollBtn

	-- Challenge cards container
	local cardsFrame = Instance.new("Frame")
	cardsFrame.Name = "ChallengeCards"
	cardsFrame.Size = UDim2.new(1, 0, 0, 110)
	cardsFrame.Position = UDim2.new(0, 0, 0, 56)
	cardsFrame.BackgroundTransparency = 1
	cardsFrame.ZIndex = 96
	cardsFrame.Parent = challengesPanel

	local cardsLayout = Instance.new("UIListLayout")
	cardsLayout.Name = "CardsLayout"
	cardsLayout.Padding = UDim.new(0, 6)
	cardsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cardsLayout.Parent = cardsFrame

	self._challengeCardsFrame = cardsFrame
	self._challengeCards = {}

	-- Complete-all bonus
	self._completeAllLabel = Instance.new("TextLabel")
	self._completeAllLabel.Name = "CompleteAllLabel"
	self._completeAllLabel.Size = UDim2.new(1, 0, 0, 18)
	self._completeAllLabel.Position = UDim2.new(0, 0, 0, 172)
	self._completeAllLabel.BackgroundTransparency = 1
	self._completeAllLabel.Font = Enum.Font.Gotham
	self._completeAllLabel.TextSize = 11
	self._completeAllLabel.Text = "Complete all 3: +50 XP + 25 Gems"
	self._completeAllLabel.TextColor3 = Palette.TextSecondary
	self._completeAllLabel.TextXAlignment = Enum.TextXAlignment.Left
	self._completeAllLabel.ZIndex = 97
	self._completeAllLabel.Parent = challengesPanel

	self._challengesPanel = challengesPanel
end

-- ============================================================
-- Tier detail popup (appears on tier tile click)
-- ============================================================
function DivePassScreen:_createDetailPopup(parent)
	local dimOverlay = Instance.new("Frame")
	dimOverlay.Name = "DetailDim"
	dimOverlay.Size = UDim2.new(1, 0, 1, 0)
	dimOverlay.Position = UDim2.new(0, 0, 0, 0)
	dimOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	dimOverlay.BackgroundTransparency = 1
	dimOverlay.Visible = false
	dimOverlay.ZIndex = 199
	dimOverlay.Parent = parent
	self._detailDim = dimOverlay

	dimOverlay.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or
		   input.UserInputType == Enum.UserInputType.Touch then
			self:_hideDetailPopup()
		end
	end)

	local popup = Instance.new("Frame")
	popup.Name = "DetailPopup"
	popup.Size = UDim2.new(0.76, 0, 0, 220)
	popup.Position = UDim2.new(0.12, 0, 0.3, 0)
	popup.BackgroundColor3 = Palette.Panel
	popup.BackgroundTransparency = 0.04
	popup.BorderSizePixel = 0
	popup.Visible = false
	popup.ZIndex = 200
	popup.Parent = parent

	local popupCorner = Instance.new("UICorner")
	popupCorner.CornerRadius = UDim.new(0, 16)
	popupCorner.Parent = popup

	local popupStroke = Instance.new("UIStroke")
	popupStroke.Color = Palette.PanelBorder
	popupStroke.Thickness = 2
	popupStroke.Transparency = 0.2
	popupStroke.Parent = popup

	-- Tier number
	self._detailTierLabel = Instance.new("TextLabel")
	self._detailTierLabel.Name = "DetailTier"
	self._detailTierLabel.Size = UDim2.new(1, -24, 0, 28)
	self._detailTierLabel.Position = UDim2.new(0, 12, 0, 12)
	self._detailTierLabel.BackgroundTransparency = 1
	self._detailTierLabel.Font = Enum.Font.GothamBold
	self._detailTierLabel.TextSize = 20
	self._detailTierLabel.Text = "TIER 15"
	self._detailTierLabel.TextColor3 = Palette.PremiumGold
	self._detailTierLabel.ZIndex = 201
	self._detailTierLabel.Parent = popup

	-- Close popup button
	local popupCloseBtn = Instance.new("TextButton")
	popupCloseBtn.Name = "PopupCloseBtn"
	popupCloseBtn.Size = UDim2.new(0, 36, 0, 36)
	popupCloseBtn.Position = UDim2.new(1, -42, 0, 8)
	popupCloseBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	popupCloseBtn.BackgroundTransparency = 0.85
	popupCloseBtn.Text = "✕"
	popupCloseBtn.Font = Enum.Font.GothamBold
	popupCloseBtn.TextSize = 20
	popupCloseBtn.TextColor3 = Palette.TextSecondary
	popupCloseBtn.ZIndex = 201
	popupCloseBtn.Parent = popup

	popupCloseBtn.MouseButton1Click:Connect(function()
		self:_hideDetailPopup()
	end)

	-- Free reward section
	local freeSection = Instance.new("Frame")
	freeSection.Name = "FreeRewardSection"
	freeSection.Size = UDim2.new(0.46, 0, 0, 120)
	freeSection.Position = UDim2.new(0, 16, 0, 52)
	freeSection.BackgroundColor3 = Palette.CardBg
	freeSection.BackgroundTransparency = 0.3
	freeSection.BorderSizePixel = 0
	freeSection.ZIndex = 201
	freeSection.Parent = popup

	local freeCorner = Instance.new("UICorner")
	freeCorner.CornerRadius = UDim.new(0, 10)
	freeCorner.Parent = freeSection

	local freeHeader = Instance.new("TextLabel")
	freeHeader.Size = UDim2.new(1, -16, 0, 20)
	freeHeader.Position = UDim2.new(0, 8, 0, 6)
	freeHeader.BackgroundTransparency = 1
	freeHeader.Font = Enum.Font.GothamBold
	freeHeader.TextSize = 13
	freeHeader.Text = "🆓 FREE REWARD"
	freeHeader.TextColor3 = Palette.XpBarFill
	freeHeader.TextXAlignment = Enum.TextXAlignment.Left
	freeHeader.ZIndex = 202
	freeHeader.Parent = freeSection

	self._detailFreeIcon = Instance.new("TextLabel")
	self._detailFreeIcon.Name = "FreeIcon"
	self._detailFreeIcon.Size = UDim2.new(0, 40, 0, 40)
	self._detailFreeIcon.Position = UDim2.new(0, 8, 0, 32)
	self._detailFreeIcon.BackgroundTransparency = 1
	self._detailFreeIcon.Font = Enum.Font.Gotham
	self._detailFreeIcon.TextSize = 28
	self._detailFreeIcon.Text = "🎣"
	self._detailFreeIcon.ZIndex = 202
	self._detailFreeIcon.Parent = freeSection

	self._detailFreeLabel = Instance.new("TextLabel")
	self._detailFreeLabel.Name = "FreeLabel"
	self._detailFreeLabel.Size = UDim2.new(1, -56, 0, 40)
	self._detailFreeLabel.Position = UDim2.new(0, 50, 0, 32)
	self._detailFreeLabel.BackgroundTransparency = 1
	self._detailFreeLabel.Font = Enum.Font.Gotham
	self._detailFreeLabel.TextSize = 13
	self._detailFreeLabel.Text = "Kelp Camo Rod Skin"
	self._detailFreeLabel.TextColor3 = Palette.TextPrimary
	self._detailFreeLabel.TextXAlignment = Enum.TextXAlignment.Left
	self._detailFreeLabel.TextWrapped = true
	self._detailFreeLabel.ZIndex = 202
	self._detailFreeLabel.Parent = freeSection

	-- Premium reward section
	local premiumSection = Instance.new("Frame")
	premiumSection.Name = "PremiumRewardSection"
	premiumSection.Size = UDim2.new(0.46, 0, 0, 120)
	premiumSection.Position = UDim2.new(0.5, 8, 0, 52)
	premiumSection.BackgroundColor3 = Palette.PremiumLocked
	premiumSection.BackgroundTransparency = 0.4
	premiumSection.BorderSizePixel = 0
	premiumSection.ZIndex = 201
	premiumSection.Parent = popup

	local premiumCorner = Instance.new("UICorner")
	premiumCorner.CornerRadius = UDim.new(0, 10)
	premiumCorner.Parent = premiumSection
	self._detailPremiumSection = premiumSection

	local premiumHeader = Instance.new("TextLabel")
	premiumHeader.Size = UDim2.new(1, -16, 0, 20)
	premiumHeader.Position = UDim2.new(0, 8, 0, 6)
	premiumHeader.BackgroundTransparency = 1
	premiumHeader.Font = Enum.Font.GothamBold
	premiumHeader.TextSize = 13
	premiumHeader.Text = "👑 PREMIUM REWARD"
	premiumHeader.TextColor3 = Palette.PremiumGold
	premiumHeader.TextXAlignment = Enum.TextXAlignment.Left
	premiumHeader.ZIndex = 202
	premiumHeader.Parent = premiumSection
	self._detailPremiumHeader = premiumHeader

	self._detailPremiumIcon = Instance.new("TextLabel")
	self._detailPremiumIcon.Name = "PremiumIcon"
	self._detailPremiumIcon.Size = UDim2.new(0, 40, 0, 40)
	self._detailPremiumIcon.Position = UDim2.new(0, 8, 0, 32)
	self._detailPremiumIcon.BackgroundTransparency = 1
	self._detailPremiumIcon.Font = Enum.Font.Gotham
	self._detailPremiumIcon.TextSize = 28
	self._detailPremiumIcon.Text = "🔒"
	self._detailPremiumIcon.ZIndex = 202
	self._detailPremiumIcon.Parent = premiumSection

	self._detailPremiumLabel = Instance.new("TextLabel")
	self._detailPremiumLabel.Name = "PremiumLabel"
	self._detailPremiumLabel.Size = UDim2.new(1, -56, 0, 40)
	self._detailPremiumLabel.Position = UDim2.new(0, 50, 0, 32)
	self._detailPremiumLabel.BackgroundTransparency = 1
	self._detailPremiumLabel.Font = Enum.Font.Gotham
	self._detailPremiumLabel.TextSize = 13
	self._detailPremiumLabel.Text = "100 Gems"
	self._detailPremiumLabel.TextColor3 = Palette.TextPrimary
	self._detailPremiumLabel.TextXAlignment = Enum.TextXAlignment.Left
	self._detailPremiumLabel.TextWrapped = true
	self._detailPremiumLabel.ZIndex = 202
	self._detailPremiumLabel.Parent = premiumSection

	-- "Unlock with Premium" CTA (shown when premium is locked)
	self._detailUnlockCTA = Instance.new("TextButton")
	self._detailUnlockCTA.Name = "UnlockCTA"
	self._detailUnlockCTA.Size = UDim2.new(0, 200, 0, 36)
	self._detailUnlockCTA.Position = UDim2.new(0.5, -100, 0, 180)
	self._detailUnlockCTA.BackgroundColor3 = Palette.PremiumGold
	self._detailUnlockCTA.BackgroundTransparency = 0.3
	self._detailUnlockCTA.Text = "🔒 Unlock with Premium"
	self._detailUnlockCTA.Font = Enum.Font.GothamBold
	self._detailUnlockCTA.TextSize = 13
	self._detailUnlockCTA.TextColor3 = Palette.PremiumGold
	self._detailUnlockCTA.Visible = true
	self._detailUnlockCTA.ZIndex = 201
	self._detailUnlockCTA.Parent = popup

	local unlockCorner = Instance.new("UICorner")
	unlockCorner.CornerRadius = UDim.new(0, 8)
	unlockCorner.Parent = self._detailUnlockCTA

	self._detailUnlockCTA.MouseButton1Click:Connect(function()
		self:_showPurchaseDialog("base")
	end)

	-- "CLAIM" button (for unlocked/free rewards)
	self._detailClaimBtn = Instance.new("TextButton")
	self._detailClaimBtn.Name = "DetailClaimBtn"
	self._detailClaimBtn.Size = UDim2.new(0, 200, 0, 36)
	self._detailClaimBtn.Position = UDim2.new(0.5, -100, 0, 180)
	self._detailClaimBtn.BackgroundColor3 = Palette.ButtonPrimary
	self._detailClaimBtn.Text = "CLAIM REWARD"
	self._detailClaimBtn.Font = Enum.Font.GothamBold
	self._detailClaimBtn.TextSize = 14
	self._detailClaimBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	self._detailClaimBtn.Visible = false
	self._detailClaimBtn.ZIndex = 201
	self._detailClaimBtn.Parent = popup

	local claimCorner = Instance.new("UICorner")
	claimCorner.CornerRadius = UDim.new(0, 8)
	claimCorner.Parent = self._detailClaimBtn

	self._detailPopup = popup
	self._detailDimOverlay = dimOverlay
end

-- ============================================================
-- Purchase confirmation dialog
-- ============================================================
function DivePassScreen:_createPurchaseDialog(parent)
	local dimOverlay = Instance.new("Frame")
	dimOverlay.Name = "PurchaseDim"
	dimOverlay.Size = UDim2.new(1, 0, 1, 0)
	dimOverlay.Position = UDim2.new(0, 0, 0, 0)
	dimOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	dimOverlay.BackgroundTransparency = 1
	dimOverlay.Visible = false
	dimOverlay.ZIndex = 249
	dimOverlay.Parent = parent
	self._purchaseDim = dimOverlay

	local dialog = Instance.new("Frame")
	dialog.Name = "PurchaseDialog"
	dialog.Size = UDim2.new(0.7, 0, 0, 200)
	dialog.Position = UDim2.new(0.15, 0, 0.32, 0)
	dialog.BackgroundColor3 = Palette.Panel
	dialog.BackgroundTransparency = 0.04
	dialog.BorderSizePixel = 0
	dialog.Visible = false
	dialog.ZIndex = 250
	dialog.Parent = parent

	local dialogCorner = Instance.new("UICorner")
	dialogCorner.CornerRadius = UDim.new(0, 16)
	dialogCorner.Parent = dialog

	local dialogStroke = Instance.new("UIStroke")
	dialogStroke.Color = Palette.PremiumGold
	dialogStroke.Thickness = 2
	dialogStroke.Transparency = 0.2
	dialogStroke.Parent = dialog

	-- Title
	local dialogTitle = Instance.new("TextLabel")
	dialogTitle.Name = "DialogTitle"
	dialogTitle.Size = UDim2.new(1, -24, 0, 28)
	dialogTitle.Position = UDim2.new(0, 12, 0, 12)
	dialogTitle.BackgroundTransparency = 1
	dialogTitle.Font = Enum.Font.GothamBold
	dialogTitle.TextSize = 20
	dialogTitle.Text = "Unlock Premium Pass"
	dialogTitle.TextColor3 = Palette.PremiumGold
	dialogTitle.ZIndex = 251
	dialogTitle.Parent = dialog

	-- Message
	local dialogMsg = Instance.new("TextLabel")
	dialogMsg.Name = "DialogMsg"
	dialogMsg.Size = UDim2.new(1, -24, 0, 60)
	dialogMsg.Position = UDim2.new(0, 12, 0, 44)
	dialogMsg.BackgroundTransparency = 1
	dialogMsg.Font = Enum.Font.Gotham
	dialogMsg.TextSize = 13
	dialogMsg.Text = "Get instant access to all 50 tiers of premium rewards, including the exclusive Abyssal Sovereign bundle!"
	dialogMsg.TextColor3 = Palette.TextSecondary
	dialogMsg.TextWrapped = true
	dialogMsg.ZIndex = 251
	dialogMsg.Parent = dialog
	self._purchaseMsgLabel = dialogMsg

	-- Cancel button
	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Name = "CancelBtn"
	cancelBtn.Size = UDim2.new(0.42, 0, 0, 42)
	cancelBtn.Position = UDim2.new(0.04, 0, 0, 140)
	cancelBtn.BackgroundColor3 = Palette.TierLocked
	cancelBtn.BackgroundTransparency = 0.3
	cancelBtn.Text = "Cancel"
	cancelBtn.Font = Enum.Font.GothamBold
	cancelBtn.TextSize = 15
	cancelBtn.TextColor3 = Palette.TextPrimary
	cancelBtn.ZIndex = 251
	cancelBtn.Parent = dialog

	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 10)
	cancelCorner.Parent = cancelBtn

	cancelBtn.MouseButton1Click:Connect(function()
		self:_hidePurchaseDialog()
	end)

	-- Confirm button
	local confirmBtn = Instance.new("TextButton")
	confirmBtn.Name = "ConfirmBtn"
	confirmBtn.Size = UDim2.new(0.42, 0, 0, 42)
	confirmBtn.Position = UDim2.new(0.54, 0, 0, 140)
	confirmBtn.BackgroundColor3 = Palette.RobuxGreen
	confirmBtn.Text = "Buy R$ 499"
	confirmBtn.Font = Enum.Font.GothamBold
	confirmBtn.TextSize = 15
	confirmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	confirmBtn.ZIndex = 251
	confirmBtn.Parent = dialog

	local confirmCorner = Instance.new("UICorner")
	confirmCorner.CornerRadius = UDim.new(0, 10)
	confirmCorner.Parent = confirmBtn
	self._purchaseConfirmBtn = confirmBtn

	confirmBtn.MouseButton1Click:Connect(function()
		self:_executePurchase()
	end)

	self._purchaseDialog = dialog
	self._purchaseDialogDim = dimOverlay
	self._purchaseType = "base"
end

-- ============================================================
-- Input wiring
-- ============================================================
function DivePassScreen:_wireInput()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.P and self._isOpen then
			self:Close()
		end
	end)
end

-- ============================================================
-- Public API: Open
-- ============================================================
function DivePassScreen:Open(playerData, premiumOwned, onClose)
	self._playerData = playerData
	self._premiumOwned = premiumOwned or false
	self._onCloseCallback = onClose

	-- Read DivePass progress from PlayerDataService
	self:_readPlayerData()
		self:_fetchChallenges()

	if self._isOpen then
		self:_refreshAll()
		return
	end

	self._isOpen = true
	self._backdrop.Visible = true

	-- Slide in from BOTTOM
	local slideIn = TweenService:Create(
		self._mainFrame,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.04, 0, 0.06, 0) }
	)

	local fadeIn = TweenService:Create(
		self._backdrop,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.5 }
	)

	slideIn:Play()
	fadeIn:Play()

	self:_refreshAll()
	self:_switchTab(self._currentTab)
end

-- ============================================================
-- Public API: Close
-- ============================================================
function DivePassScreen:Close()
	if not self._isOpen then return end

	self:_hideDetailPopup()
	self:_hidePurchaseDialog()
	self._isOpen = false

	local slideOut = TweenService:Create(
		self._mainFrame,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(0.04, 0, 1, 0) }
	)

	local fadeOut = TweenService:Create(
		self._backdrop,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	)

	slideOut:Play()
	fadeOut:Play()

	slideOut.Completed:Connect(function()
		self._backdrop.Visible = false
	end)

	if self._onCloseCallback then
		self._onCloseCallback()
		self._onCloseCallback = nil
	end
end

-- ============================================================
-- Public API: Refresh
-- ============================================================
function DivePassScreen:Refresh(playerData, premiumOwned)
	self._playerData = playerData
	self._premiumOwned = premiumOwned or false
	self:_readPlayerData()
	if self._isOpen then
		self:_refreshAll()
	end
end

-- ============================================================
-- Read player data for DivePass state
-- ============================================================
function DivePassScreen:_readPlayerData()
	if self._playerData and self._playerData.DivePass then
		self._totalXP = self._playerData.DivePass.XP or 0
		self._premiumOwned = self._playerData.DivePass.PremiumOwned or false
		self._tiersClaimed = self._playerData.DivePass.TiersClaimed or {}
	else
		self._totalXP = 0
		self._tiersClaimed = {}
	end

	-- Calculate current tier from XP (using local XP curve)
	self._currentTier, self._tierXP, self._tierXPRequired = self:_calculateTierFromXP(self._totalXP)

	-- Read daily challenges if available
	if self._playerData and self._playerData.DailyChallenges then
		self._dailyStreak = self._playerData.DailyChallenges.Streak or 0
	end
end

-- ============================================================
-- XP curve calculation (local mirror of PlayerDataService)
-- ============================================================
local DIVE_PASS_XP_BASE = 400
local DIVE_PASS_XP_MAX = 1600

function DivePassScreen:_calculateTierFromXP(totalXP)
	local cumulative = 0
	for tier = 1, MAX_TIER do
		local ratio = tier / (MAX_TIER - 1)
		local xpForNext = DIVE_PASS_XP_BASE + (DIVE_PASS_XP_MAX - DIVE_PASS_XP_BASE) * ratio
		local nextThreshold = cumulative + math.floor(xpForNext)
		if totalXP < nextThreshold then
			return tier, totalXP - cumulative, math.floor(xpForNext)
		end
		cumulative = nextThreshold
	end
	return MAX_TIER, 0, 1
end

-- ============================================================
-- Full refresh of all UI elements
-- ============================================================
function DivePassScreen:_refreshAll()
	-- Refresh progress bar
	local pct = self._tierXPRequired > 0 and (self._tierXP / self._tierXPRequired) or 0
	self._tierNumLabel.Text = tostring(self._currentTier)
	self._xpLabel.Text = string.format("%d / %d XP", self._tierXP, self._tierXPRequired)
	self._xpPctLabel.Text = string.format("%d%%", math.floor(pct * 100))
	self._totalXPLabel.Text = "Total: " .. self:_formatNumber(self._totalXP) .. " XP"

	-- Animate bar width
	TweenService:Create(self._xpBarFill,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(math.min(pct, 1), 0, 1, 0) }
	):Play()

	-- Refresh CTA / purchased state
	self:_refreshCTASection()

	-- Refresh tier tiles
	self:_populateTierTiles()

	-- Refresh hero section
	self:_refreshHeroSection()

	-- Refresh daily challenges
	self:_populateDailyChallenges()
end

-- ============================================================
-- CTA section: show purchase buttons or "PREMIUM ACTIVE"
-- ============================================================
function DivePassScreen:_refreshCTASection()
	if self._premiumOwned then
		self._buyPremiumBtn.Visible = false
		self._buyBundleBtn.Visible = false
		self._premiumActiveBadge.Visible = true
	else
		self._buyPremiumBtn.Visible = true
		self._buyBundleBtn.Visible = true
		self._premiumActiveBadge.Visible = false

		-- Pulse animation on the buy button
		self:_pulseBuyButton()
	end
end

function DivePassScreen:_pulseBuyButton()
	local pulse = TweenService:Create(
		self._buyPremiumBtn,
		TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ BackgroundTransparency = 0.15 }
	)
	pulse:Play()
end

-- ============================================================
-- Hero section: update based on tier progress
-- ============================================================
function DivePassScreen:_refreshHeroSection()
	if self._currentTier >= 50 then
		self._heroCTA.Text = "CLAIMED ✓"
		self._heroCTA.BackgroundColor3 = Palette.Green
		self._heroCTA.BackgroundTransparency = 0.5
	elseif self._premiumOwned then
		self._heroCTA.Text = "CLAIM AT TIER 50"
		self._heroCTA.BackgroundColor3 = Palette.PremiumGold
		self._heroCTA.BackgroundTransparency = 0.3
	else
		self._heroCTA.Text = "UNLOCK TIER 50"
		self._heroCTA.BackgroundColor3 = Palette.PremiumGold
		self._heroCTA.BackgroundTransparency = 0.3
	end
end

-- ============================================================
-- Populate the horizontal tier track
-- ============================================================
function DivePassScreen:_populateTierTiles()
	-- Clear existing tiles
	for _, tile in pairs(self._tierTiles) do
		tile:Destroy()
	end
	self._tierTiles = {}

	for tier = 1, MAX_TIER do
		local tile = self:_createTierTile(tier)
		tile.Parent = self._tierScroll
		self._tierTiles[tier] = tile
	end

	-- Scroll to current tier
	self:_scrollToTier(self._currentTier)
end

function DivePassScreen:_createTierTile(tier)
	local tileSize = TIER_TILE_SIZE

	local tile = Instance.new("TextButton")
	tile.Name = "TierTile_" .. tier
	tile.Size = UDim2.new(0, tileSize, 0, tileSize - 8)
	tile.ZIndex = 97
	tile.AutoButtonColor = false

	-- Determine tile state
	local isCurrent = (tier == self._currentTier)
	local isCompleted = (tier < self._currentTier)
	local hasFree = (FREE_REWARDS[tier] ~= nil)
	local hasPremium = (PREMIUM_REWARDS[tier] ~= nil)

	-- Background color
	if isCurrent then
		tile.BackgroundColor3 = Palette.TierCurrent
		tile.BackgroundTransparency = 0.2
	elseif isCompleted then
		tile.BackgroundColor3 = Palette.TierCompleted
		tile.BackgroundTransparency = 0.4
	else
		tile.BackgroundColor3 = Palette.TierLocked
		tile.BackgroundTransparency = 0.7
	end
	tile.BorderSizePixel = 0

	local tileCorner = Instance.new("UICorner")
	tileCorner.CornerRadius = UDim.new(0, 10)
	tileCorner.Parent = tile

	-- Highlight stroke for current tier
	if isCurrent then
		local tileStroke = Instance.new("UIStroke")
		tileStroke.Color = Palette.Accent
		tileStroke.Thickness = 2.5
		tileStroke.Transparency = 0
		tileStroke.Parent = tile
	end

	-- Tier number
	local tierNum = Instance.new("TextLabel")
	tierNum.Name = "TierNum"
	tierNum.Size = UDim2.new(1, 0, 0, 18)
	tierNum.Position = UDim2.new(0, 0, 0, 4)
	tierNum.BackgroundTransparency = 1
	tierNum.Font = Enum.Font.GothamBold
	tierNum.TextSize = 14
	tierNum.Text = tostring(tier)
	tierNum.TextColor3 = isCurrent and Palette.TextPrimary or Palette.TextSecondary
	tierNum.ZIndex = 98
	tierNum.Parent = tile

	-- Free reward icon
	local freeIcon = Instance.new("TextLabel")
	freeIcon.Name = "FreeReward"
	freeIcon.Size = UDim2.new(0, 24, 0, 24)
	freeIcon.Position = UDim2.new(0.5, -26, 0, 26)
	freeIcon.BackgroundTransparency = 1
	freeIcon.Font = Enum.Font.Gotham
	freeIcon.TextSize = 16

	if hasFree then
		local freeReward = FREE_REWARDS[tier]
		freeIcon.Text = freeReward.Icon or "🎁"
		freeIcon.TextColor3 = isCompleted and Palette.Green or Palette.XpBarFill
	else
		freeIcon.Text = "—"
		freeIcon.TextColor3 = Palette.TierLocked
	end
	freeIcon.ZIndex = 98
	freeIcon.Parent = tile

	-- Premium reward icon
	local premiumIcon = Instance.new("TextLabel")
	premiumIcon.Name = "PremiumReward"
	premiumIcon.Size = UDim2.new(0, 24, 0, 24)
	premiumIcon.Position = UDim2.new(0.5, 2, 0, 26)
	premiumIcon.BackgroundTransparency = 1
	premiumIcon.Font = Enum.Font.Gotham
	premiumIcon.TextSize = 16

	if hasPremium then
		if self._premiumOwned then
			local premReward = PREMIUM_REWARDS[tier]
			premiumIcon.Text = premReward.Icon or "✨"
			premiumIcon.TextColor3 = isCompleted and Palette.Green or Palette.PremiumGold
		else
			-- Silhouetted/locked for non-buyers — "see what you're missing"
			premiumIcon.Text = "🔒"
			premiumIcon.TextColor3 = Palette.PremiumLocked
		end
	else
		premiumIcon.Text = "—"
		premiumIcon.TextColor3 = Palette.TierLocked
	end
	premiumIcon.ZIndex = 98
	premiumIcon.Parent = tile

	-- Click handler for detail popup
	tile.MouseButton1Click:Connect(function()
		self:_showDetailPopup(tier)
	end)

	return tile
end

function DivePassScreen:_scrollToTier(tier)
	local targetX = (tier - 1) * (TIER_TILE_SIZE + 4) -- approximate scroll
	self._tierScroll.CanvasPosition = Vector2.new(math.max(0, targetX - 40), 0)
end

-- ============================================================
-- Tier detail popup
-- ============================================================
function DivePassScreen:_showDetailPopup(tier)
	local freeReward = FREE_REWARDS[tier]
	local premiumReward = PREMIUM_REWARDS[tier]
	local isCompleted = tier < self._currentTier

	self._detailTierLabel.Text = "TIER " .. tostring(tier)

	-- Free reward
	if freeReward then
		self._detailFreeIcon.Text = freeReward.Icon or "🎁"
		self._detailFreeLabel.Text = freeReward.Name
	else
		self._detailFreeIcon.Text = "—"
		self._detailFreeLabel.Text = "No free reward at this tier"
	end

	-- Premium reward
	if premiumReward then
		if self._premiumOwned then
			self._detailPremiumIcon.Text = premiumReward.Icon or "✨"
			self._detailPremiumLabel.Text = premiumReward.Name
			self._detailPremiumIcon.TextColor3 = Palette.PremiumGold
			self._detailPremiumSection.BackgroundColor3 = Palette.CardBg
			self._detailPremiumSection.BackgroundTransparency = 0.2
			self._detailPremiumHeader.Text = "👑 PREMIUM REWARD"
			self._detailUnlockCTA.Visible = false
		else
			self._detailPremiumIcon.Text = "🔒"
			self._detailPremiumLabel.Text = premiumReward.Name .. "\n(Unlock with Premium)"
			self._detailPremiumIcon.TextColor3 = Palette.TextSecondary
			self._detailPremiumSection.BackgroundColor3 = Palette.PremiumLocked
			self._detailPremiumSection.BackgroundTransparency = 0.4
			self._detailPremiumHeader.Text = "🔒 PREMIUM REWARD"
			self._detailUnlockCTA.Visible = true
		end
	else
		self._detailPremiumIcon.Text = "—"
		self._detailPremiumLabel.Text = "No premium reward at this tier"
		self._detailPremiumIcon.TextColor3 = Palette.TextSecondary
		self._detailUnlockCTA.Visible = false
	end

	-- Claim button logic
	if isCompleted and freeReward and not self._tiersClaimed[tier] then
		self._detailClaimBtn.Visible = true
		self._detailClaimBtn.Text = "CLAIM REWARD"
		self._detailUnlockCTA.Visible = false
	elseif self._tiersClaimed[tier] then
		self._detailClaimBtn.Visible = true
		self._detailClaimBtn.Text = "✓ CLAIMED"
		self._detailClaimBtn.BackgroundColor3 = Palette.Green
		self._detailClaimBtn.BackgroundTransparency = 0.5
	elseif not isCompleted then
		self._detailClaimBtn.Visible = false
	end

	-- Show with animation
	self._detailDimOverlay.Visible = true
	self._detailPopup.Visible = true

	-- Fade in dim
	TweenService:Create(self._detailDimOverlay,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.5 }
	):Play()

	-- Pop-in popup
	self._detailPopup.Size = UDim2.new(0.76, 0, 0, 180)
	TweenService:Create(self._detailPopup,
		TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0.76, 0, 0, 220) }
	):Play()

	self._detailCurrentTier = tier
end

function DivePassScreen:_hideDetailPopup()
	if not self._detailPopup.Visible then return end

	TweenService:Create(self._detailDimOverlay,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	):Play()

	self._detailPopup.Visible = false
	self._detailDimOverlay.Visible = false
end

-- ============================================================
-- Daily challenges population
-- ============================================================
function DivePassScreen:_fetchChallenges()
    local service = Knit.GetService("ChallengeService")
    if service then
        local ok, result = pcall(function() return service.Client.GetChallenges:Call() end)
        if ok and result then self._dailyChallenges = result end
    end
end

function DivePassScreen:_populateDailyChallenges()
	-- Clear existing cards
	for _, card in pairs(self._challengeCards) do
		card:Destroy()
	end
	self._challengeCards = {}

	-- Get challenge data — in production this comes from ChallengeService
	-- For now, use placeholder data if playerData has active challenges
	local challenges = {}
	if self._playerData and self._playerData.DailyChallenges and self._playerData.DailyChallenges.Active then
		challenges = self._playerData.DailyChallenges.Active
	else
		-- Placeholders for development
		challenges = {
			{ Id = "Catch3Uncommon", Name = "Catch 3 Uncommon fish", Progress = 2, Target = 3, XP = 100, Coins = 50, Completed = false, Icon = "🐟" },
			{ Id = "CastRod25", Name = "Cast your rod 25 times", Progress = 18, Target = 25, XP = 100, Coins = 75, Completed = false, Icon = "🎣" },
			{ Id = "DiscoverSpecies", Name = "Discover a new species", Progress = 0, Target = 1, XP = 100, Coins = 150, Completed = false, Icon = "🔍" },
		}
	end

	for i, challenge in ipairs(challenges) do
		local card = self:_createChallengeCard(challenge, i)
		card.Parent = self._challengeCardsFrame
		self._challengeCards[i] = card
	end

	-- Update streak
	self._streakLabel.Text = "🔥 " .. tostring(self._dailyStreak) .. "-Day Streak"

	-- Check complete-all bonus
	local allComplete = true
	for _, c in ipairs(challenges) do
		if not c.Completed then allComplete = false end
	end
	if allComplete then
		self._completeAllLabel.Text = "✅ All complete! +50 XP + 25 Gems bonus earned!"
		self._completeAllLabel.TextColor3 = Palette.ChallengeComplete
	else
		self._completeAllLabel.Text = "Complete all 3: +50 XP + 25 Gems"
		self._completeAllLabel.TextColor3 = Palette.TextSecondary
	end
end

function DivePassScreen:_createChallengeCard(challenge, index)
	local cardHeight = 32

	local card = Instance.new("Frame")
	card.Name = "ChallengeCard_" .. index
	card.Size = UDim2.new(1, -8, 0, cardHeight)
	card.BackgroundColor3 = Palette.CardBg
	card.BackgroundTransparency = 0.35
	card.BorderSizePixel = 0
	card.ZIndex = 97

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 8)
	cardCorner.Parent = card

	if challenge.Completed then
		local cardStroke = Instance.new("UIStroke")
		cardStroke.Color = Palette.ChallengeComplete
		cardStroke.Thickness = 1
		cardStroke.Transparency = 0.3
		cardStroke.Parent = card
	end

	-- Icon
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 26, 0, 26)
	icon.Position = UDim2.new(0, 8, 0.5, -13)
	icon.BackgroundTransparency = 1
	icon.Font = Enum.Font.Gotham
	icon.TextSize = 18
	icon.Text = challenge.Icon or "🎯"
	icon.ZIndex = 98
	icon.Parent = card

	-- Status indicator
	local statusText
	if challenge.Completed then
		statusText = "✓"
	else
		statusText = "●"
	end

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Size = UDim2.new(0, 20, 0, 20)
	status.Position = UDim2.new(0, 8, 0.5, -10)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamBold
	status.TextSize = 12
	status.Text = statusText
	status.TextColor3 = challenge.Completed and Palette.ChallengeComplete or Palette.TextSecondary
	status.ZIndex = 98
	status.Parent = card

	-- Description + progress
	local descText = challenge.Name
	if not challenge.Completed then
		descText = descText .. string.format(" — %d/%d", challenge.Progress or 0, challenge.Target or 0)
	end

	local desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.Size = UDim2.new(1, -180, 0, 18)
	desc.Position = UDim2.new(0, 40, 0.5, -9)
	desc.BackgroundTransparency = 1
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 12
	desc.Text = descText
	desc.TextColor3 = challenge.Completed and Palette.ChallengeComplete or Palette.TextPrimary
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextTruncate = Enum.TextTruncate.AtEnd
	desc.ZIndex = 98
	desc.Parent = card

	-- Progress bar (mini)
	if not challenge.Completed and challenge.Target and challenge.Target > 1 then
		local miniBarBg = Instance.new("Frame")
		miniBarBg.Name = "MiniBarBg"
		miniBarBg.Size = UDim2.new(1, -160, 0, 6)
		miniBarBg.Position = UDim2.new(0, 40, 0.5, 10)
		miniBarBg.BackgroundColor3 = Palette.XpBarBg
		miniBarBg.BorderSizePixel = 0
		miniBarBg.ZIndex = 98
		miniBarBg.Parent = card

		local miniBarCorner = Instance.new("UICorner")
		miniBarCorner.CornerRadius = UDim.new(0, 3)
		miniBarCorner.Parent = miniBarBg

		local pct = math.min((challenge.Progress or 0) / challenge.Target, 1)
		local miniBarFill = Instance.new("Frame")
		miniBarFill.Name = "MiniBarFill"
		miniBarFill.Size = UDim2.new(pct, 0, 1, 0)
		miniBarFill.BackgroundColor3 = Palette.ChallengeComplete
		miniBarFill.BorderSizePixel = 0
		miniBarFill.ZIndex = 99
		miniBarFill.Parent = miniBarBg

		local miniFillCorner = Instance.new("UICorner")
		miniFillCorner.CornerRadius = UDim.new(0, 3)
		miniFillCorner.Parent = miniBarFill
	end

	-- XP reward
	local reward = Instance.new("TextLabel")
	reward.Name = "Reward"
	reward.Size = UDim2.new(0, 130, 0, 26)
	reward.Position = UDim2.new(1, -138, 0.5, -13)
	reward.BackgroundTransparency = 1
	reward.Font = Enum.Font.GothamBold
	reward.TextSize = 10
	reward.Text = "+" .. tostring(challenge.XP or 100) .. " XP + " .. tostring(challenge.Coins or 50) .. " 🪙"
	reward.TextColor3 = Palette.Gold
	reward.TextXAlignment = Enum.TextXAlignment.Right
	reward.ZIndex = 98
	reward.Parent = card

	return card
end

-- ============================================================
-- Reroll handler
-- ============================================================
function DivePassScreen:_onRerollClicked()
	-- TODO: Wire to ChallengeService to reroll a challenge
	print("[DivePassScreen] Reroll requested (stub)")
end

-- ============================================================
-- Purchase dialog
-- ============================================================
function DivePassScreen:_showPurchaseDialog(purchaseType)
	self._purchaseType = purchaseType

	if purchaseType == "bundle" then
		self._purchaseMsgLabel.Text = "Get Premium Pass + 15 tier skips! Jump ahead instantly and unlock all premium rewards for every tier you reach."
		self._purchaseConfirmBtn.Text = "Buy R$ 799"
	else
		self._purchaseMsgLabel.Text = "Get instant access to all 50 tiers of premium rewards, including the exclusive Abyssal Sovereign bundle at Tier 50!"
		self._purchaseConfirmBtn.Text = "Buy R$ 499"
	end

	self._purchaseDialogDim.Visible = true
	self._purchaseDialog.Visible = true

	TweenService:Create(self._purchaseDialogDim,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.5 }
	):Play()

	self._purchaseDialog.Size = UDim2.new(0.7, 0, 0, 180)
	TweenService:Create(self._purchaseDialog,
		TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0.7, 0, 0, 200) }
	):Play()
end

function DivePassScreen:_hidePurchaseDialog()
	if not self._purchaseDialog.Visible then return end

	TweenService:Create(self._purchaseDialogDim,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	):Play()

	self._purchaseDialog.Visible = false
	self._purchaseDialogDim.Visible = false
end

-- ============================================================
-- Execute purchase (delegates to EconomyService via callback)
-- ============================================================
function DivePassScreen:_executePurchase()
	print("[DivePassScreen] Executing purchase: " .. self._purchaseType)

	-- Hide purchase dialog
	self:_hidePurchaseDialog()

	-- Call the purchase callback
	if self._onPurchaseCallback then
		self._onPurchaseCallback(self._purchaseType)
	end

	-- Play success animation (premium rewards unlock cascade)
	self:_playUnlockCascade()
end

-- ============================================================
-- Post-purchase unlock cascade animation
-- ============================================================
function DivePassScreen:_playUnlockCascade()
	self._premiumOwned = true
	self:_refreshCTASection()

	-- Briefly highlight each premium tier tile in sequence
	for tier = 1, MAX_TIER do
		if PREMIUM_REWARDS[tier] then
			task.delay(tier * 0.03, function()
				local tile = self._tierTiles[tier]
				if tile then
					-- Flash the premium icon
					local premIcon = tile:FindFirstChild("PremiumReward")
					if premIcon then
						local premReward = PREMIUM_REWARDS[tier]
						premIcon.Text = premReward.Icon or "✨"
						premIcon.TextColor3 = Palette.PremiumGold

						local flash = TweenService:Create(premIcon,
							TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
							{ TextSize = 28 }
						)
						flash:Play()
						flash.Completed:Connect(function()
							TweenService:Create(premIcon,
								TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
								{ TextSize = 16 }
							):Play()
						end)
					end
				end
			end)
		end
	end

	-- Refresh full tier track after cascade
	task.delay(2.0, function()
		self:_populateTierTiles()
		self:_refreshHeroSection()
	end)
end

-- ============================================================
-- Tab switching
-- ============================================================
function DivePassScreen:_switchTab(tabKey)
	self._currentTab = tabKey

	for key, btn in pairs(self._tabButtons) do
		btn.BackgroundColor3 = (key == tabKey) and Palette.Accent or Palette.TierLocked
		btn.BackgroundTransparency = (key == tabKey) and 0.5 or 0.3
	end

	-- Show/hide tier track vs challenges
	if tabKey == "Challenges" then
		self._tierScroll.Parent.Visible = false
		self._heroSection.Visible = false
		self._progressSection.Visible = false
		self._challengesPanel.Visible = true
		self:_populateDailyChallenges()
	else
		self._tierScroll.Parent.Visible = true
		self._heroSection.Visible = true
		self._progressSection.Visible = true
		self._challengesPanel.Visible = false
	end
end

-- ============================================================
-- Callbacks for UIController
-- ============================================================
function DivePassScreen:SetPurchaseCallback(cb)
	self._onPurchaseCallback = cb
end

-- ============================================================
-- Helpers
-- ============================================================
function DivePassScreen:_formatNumber(num)
	if num >= 1000000 then
		return string.format("%.1fM", num / 1000000)
	elseif num >= 10000 then
		return string.format("%.1fK", num / 1000)
	else
		return string.format("%d", num)
	end
end

-- ============================================================
-- Cleanup
-- ============================================================
function DivePassScreen:IsOpen()
	return self._isOpen
end

function DivePassScreen:Destroy()
	self:_hideDetailPopup()
	self:_hidePurchaseDialog()
	if self._backdrop then
		self._backdrop:Destroy()
		self._backdrop = nil
	end
end

return DivePassScreen
