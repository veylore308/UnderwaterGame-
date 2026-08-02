--[[
	BoatHUD.lua
	Deep Tide Studios — Client UI (Phase 3)
	Boat HUD: speed indicator, anchor status, storage count, compass bar
	with buoy bearings, weather icon + announcements, dock/rod prompts,
	and a minimap showing dive markers and other boats (200-stud radius).

	Driven by BoatHandler; created once and updated per boat state tick.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))

local BoatHUD = {}
BoatHUD.__index = BoatHUD

local WEATHER_ICONS = {
	Calm = "☀ CALM",
	Rain = "🌧 RAIN",
	Storm = "⛈ STORM",
}
local WEATHER_COLORS = {
	Calm = Color3.fromRGB(255, 230, 140),
	Rain = Color3.fromRGB(150, 180, 220),
	Storm = Color3.fromRGB(220, 90, 90),
}

function BoatHUD.new()
	local self = setmetatable({}, BoatHUD)
	self._markers = Shared.Constants.ZoneConfigs.Surface and Shared.Constants.ZoneConfigs.Surface.SurfaceMarkers or {}
	self:_createGUI()
	return self
end

-- ============================================================
-- GUI construction
-- ============================================================
function BoatHUD:_createGUI()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "BoatHUD"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui
	self._gui = gui

	local function makeLabel(parent, name, pos, size, text, color, textSize)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.Position = pos
		label.Size = size
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextColor3 = color or Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.2
		label.Font = Enum.Font.GothamBold
		label.TextSize = textSize or 18
		label.Parent = parent
		return label
	end

	-- ==== Boat status panel (bottom-left) ====
	local statusPanel = Instance.new("Frame")
	statusPanel.Name = "StatusPanel"
	statusPanel.AnchorPoint = Vector2.new(0, 1)
	statusPanel.Position = UDim2.new(0, 12, 1, -12)
	statusPanel.Size = UDim2.new(0, 180, 0, 96)
	statusPanel.BackgroundTransparency = 0.4
	statusPanel.BackgroundColor3 = Color3.fromRGB(10, 20, 40)
	statusPanel.BorderSizePixel = 0
	statusPanel.Parent = gui

	makeLabel(statusPanel, "Speed", UDim2.new(0, 8, 0, 4), UDim2.new(0, 80, 0, 26), "0.0 s/s", Color3.new(1, 1, 1), 20)
	makeLabel(statusPanel, "Anchor", UDim2.new(0, 96, 0, 4), UDim2.new(0, 80, 0, 26), "⚓ ANCHORED", Color3.fromRGB(120, 220, 160), 14)
	makeLabel(statusPanel, "Storage", UDim2.new(0, 8, 0, 34), UDim2.new(0, 164, 0, 22), "HOLD 0/0", Color3.fromRGB(180, 200, 230), 14)
	makeLabel(statusPanel, "Wind", UDim2.new(0, 8, 0, 60), UDim2.new(0, 164, 0, 22), "WIND 0 s/s", Color3.fromRGB(150, 170, 200), 12)

	self._speedLabel = statusPanel:FindFirstChild("Speed")
	self._anchorLabel = statusPanel:FindFirstChild("Anchor")
	self._storageLabel = statusPanel:FindFirstChild("Storage")
	self._windLabel = statusPanel:FindFirstChild("Wind")

	-- ==== Weather (top-center, under compass) ====
	makeLabel(gui, "Weather", UDim2.new(0.5, -70, 0, 34), UDim2.new(0, 140, 0, 24), "☀ CALM", WEATHER_COLORS.Calm, 16)
	self._weatherLabel = gui:FindFirstChild("Weather")

	-- ==== Compass bar (top-center) ====
	local compass = Instance.new("Frame")
	compass.Name = "Compass"
	compass.AnchorPoint = Vector2.new(0.5, 0)
	compass.Position = UDim2.new(0.5, 0, 0, 4)
	compass.Size = UDim2.new(0, 320, 0, 30)
	compass.BackgroundTransparency = 0.3
	compass.BackgroundColor3 = Color3.fromRGB(10, 20, 40)
	compass.BorderSizePixel = 0
	compass.Parent = gui

	self._compass = {}
	for _, name in ipairs({ { "N", -1 }, { "E", 1 }, { "S", 1 }, { "W", -1 } }) do
		local tickLabel = makeLabel(compass, name[1], UDim2.new(0.5, 0, 0, 0), UDim2.new(0, 24, 0, 18), name[1], Color3.new(1, 1, 1), 13)
		tickLabel.TextXAlignment = Enum.TextXAlignment.Center
		self._compass[name[1]] = tickLabel
	end
	makeLabel(compass, "Heading", UDim2.new(0, 4, 0, 18), UDim2.new(0, 312, 0, 12), "000°", Color3.fromRGB(255, 200, 80), 12)
	self._headingLabel = compass:FindFirstChild("Heading")

	-- ==== Minimap (bottom-right) ====
	local minimap = Instance.new("Frame")
	minimap.Name = "Minimap"
	minimap.AnchorPoint = Vector2.new(1, 1)
	minimap.Position = UDim2.new(1, -12, 1, -12)
	minimap.Size = UDim2.new(0, 180, 0, 180)
	minimap.BackgroundTransparency = 0.45
	minimap.BackgroundColor3 = Color3.fromRGB(10, 20, 40)
	minimap.BorderSizePixel = 0
	minimap.Parent = gui
	self._minimap = minimap
	self._mapPoints = {} -- { [key] = ImageLabel/Frame }

	-- ==== Prompt (center-bottom) ====
	self._promptLabel = makeLabel(gui, "Prompt", UDim2.new(0.5, -200, 1, -70), UDim2.new(0, 400, 0, 30), "", Color3.fromRGB(255, 255, 255), 16)
	self._promptLabel.BackgroundTransparency = 0.5
	self._promptLabel.BackgroundColor3 = Color3.fromRGB(20, 40, 60)
	self._promptLabel.TextTransparency = 1
	self._promptLabel.Visible = false

	-- ==== Announcement (center) ====
	self._announceLabel = makeLabel(gui, "Announce", UDim2.new(0.5, -250, 0.35, 0), UDim2.new(0, 500, 0, 44), "", Color3.new(1, 1, 1), 30)
	self._announceLabel.TextTransparency = 1

	self:SetVisible(false)
end

-- ============================================================
-- Updates
-- ============================================================
function BoatHUD:UpdateBoat(state)
	if not state then return end

	if self._speedLabel then
		self._speedLabel.Text = string.format("%.1f s/s", state.Speed or 0)
	end
	if self._anchorLabel then
		if state.Anchored then
			self._anchorLabel.Text = "⚓ ANCHORED"
			self._anchorLabel.TextColor3 = Color3.fromRGB(120, 220, 160)
		else
			self._anchorLabel.Text = "⛵ UNDERWAY"
			self._anchorLabel.TextColor3 = Color3.fromRGB(255, 200, 120)
		end
	end
	if self._storageLabel then
		local cap = state.StorageCapacity or 0
		self._storageLabel.Text = cap > 0 and ("HOLD " .. (state.StorageCount or 0) .. "/" .. cap) or "HOLD — personal inventory"
	end
	if self._windLabel then
		self._windLabel.Text = string.format("WIND %d s/s", state.WindPush or 0)
	end
	if self._headingLabel then
		local deg = math.floor((state.Heading or 0) * 180 / math.pi) % 360
		self._headingLabel.Text = string.format("%03d°", deg)
	end

	self:_updateCompass(state.Heading or 0)
	self:_updateMinimap(state.Position, state.Heading or 0)
end

function BoatHUD:_updateCompass(heading)
	for _, name in ipairs({ "N", "E", "S", "W" }) do
		local label = self._compass[name]
		if label then
			local angle = 0
			if name == "E" then angle = math.pi / 2
			elseif name == "S" then angle = math.pi
			elseif name == "W" then angle = -math.pi / 2 end
			local rel = (angle - heading) % (math.pi * 2)
			if rel > math.pi then rel = rel - math.pi * 2 end
			label.Position = UDim2.new(0.5, rel / math.pi * 150 - 12, 0, 0)
		end
	end
end

function BoatHUD:_updateMinimap(boatPos, heading)
	if not self._minimap or not boatPos then return end
	local MAP_STUDS = 200
	local HALF = 90

	-- Clear old map points
	for _, p in pairs(self._mapPoints) do
		p:Destroy()
	end
	self._mapPoints = {}

	-- Center arrow (player boat)
	local arrow = Instance.new("Frame")
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.new(0.5, 0, 0.5, 0)
	arrow.Size = UDim2.new(0, 6, 0, 6)
	arrow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	arrow.BorderSizePixel = 0
	arrow.Rotation = -heading * 180 / math.pi
	arrow.Parent = self._minimap
	self._mapPoints["self"] = arrow

	local function addPoint(worldPos, color, size, labelText)
		local dx = worldPos.X - boatPos.X
		local dz = worldPos.Z - boatPos.Z
		local dist = math.sqrt(dx * dx + dz * dz)
		if dist > MAP_STUDS then return end
		local point = Instance.new("Frame")
		point.AnchorPoint = Vector2.new(0.5, 0.5)
		point.Position = UDim2.new(0.5, dx / MAP_STUDS * HALF, 0.5, dz / MAP_STUDS * HALF)
		point.Size = UDim2.new(0, size, 0, size)
		point.BackgroundColor3 = color
		point.BorderSizePixel = 0
		point.Parent = self._minimap
		self._mapPoints[#self._mapPoints + 1] = point
		if labelText then
			local lbl = Instance.new("TextLabel")
			lbl.AnchorPoint = Vector2.new(0.5, 1)
			lbl.Position = UDim2.new(0.5, 0, 0, -2)
			lbl.Size = UDim2.new(0, 60, 0, 12)
			lbl.BackgroundTransparency = 1
			lbl.Text = labelText
			lbl.TextColor3 = color
			lbl.TextScaled = true
			lbl.Font = Enum.Font.GothamBold
			lbl.Parent = point
		end
	end

	-- Dive markers + Outpost (from Surface zone config)
	for _, marker in ipairs(self._markers) do
		addPoint(marker.Position, marker.Color, marker.MarkerType == "Dock" and 8 or 6, marker.Name)
	end

	-- Other boats (workspace replication)
	local boatsFolder = workspace:FindFirstChild("Boats")
	if boatsFolder then
		for _, boat in ipairs(boatsFolder:GetChildren()) do
			if boat:IsA("Model") and boat.PrimaryPart then
				addPoint(boat.PrimaryPart.Position, Color3.fromRGB(255, 255, 255), 4)
			end
		end
	end
end

-- ============================================================
-- Weather + announcements
-- ============================================================
function BoatHUD:SetWeather(state)
	if not self._weatherLabel then return end
	self._weatherLabel.Text = WEATHER_ICONS[state] or ("☀ " .. tostring(state))
	self._weatherLabel.TextColor3 = WEATHER_COLORS[state] or Color3.new(1, 1, 1)
end

function BoatHUD:ShowAnnouncement(message, color, duration)
	if not self._announceLabel then return end
	duration = duration or 4
	self._announceLabel.Text = message
	self._announceLabel.TextColor3 = color or Color3.new(1, 1, 1)
	self._announceLabel.TextTransparency = 0

	task.delay(duration, function()
		if self._announceLabel then
			local tween = TweenService:Create(self._announceLabel,
				TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ TextTransparency = 1 })
			tween:Play()
		end
	end)
end

function BoatHUD:ShowPrompt(text)
	if not self._promptLabel then return end
	self._promptLabel.Text = text
	self._promptLabel.Visible = true
	self._promptLabel.TextTransparency = 0
end

function BoatHUD:HidePrompt()
	if self._promptLabel then
		self._promptLabel.Visible = false
		self._promptLabel.TextTransparency = 1
	end
end

-- ============================================================
-- Visibility / cleanup
-- ============================================================
function BoatHUD:SetVisible(visible)
	if self._gui then
		self._gui.Enabled = visible
	end
end

function BoatHUD:IsVisible()
	return self._gui and self._gui.Enabled
end

function BoatHUD:Destroy()
	if self._gui then
		self._gui:Destroy()
		self._gui = nil
	end
end

return BoatHUD
