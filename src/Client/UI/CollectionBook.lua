--[[
    CollectionBook.lua
    Deep Tide Studios — Client UI Module
    Bestiary/collection log: grid of fish species with discovery states,
    rarity-colored borders, completion tracking, detail view, filters,
    and new-discovery notifications.

    Design: Dark underwater glass-panel theme with bioluminescent accents.
    Mobile-friendly: minimum 48x48 touch targets.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))

local CollectionBook = {}
CollectionBook.__index = CollectionBook

-- ============================================================
-- Color palette (underwater theme)
-- ============================================================
local Palette = {
    Background = Color3.fromRGB(8, 14, 28),        -- Deep navy
    Panel = Color3.fromRGB(12, 22, 44),             -- Dark blue glass
    PanelBorder = Color3.fromRGB(40, 100, 160),     -- Bioluminescent blue
    TextPrimary = Color3.fromRGB(220, 235, 255),    -- Pale blue-white
    TextSecondary = Color3.fromRGB(140, 175, 210),  -- Muted blue
    Accent = Color3.fromRGB(60, 200, 220),          -- Cyan highlight
    TabActive = Color3.fromRGB(30, 150, 200),       -- Active tab blue
    TabInactive = Color3.fromRGB(20, 40, 60),       -- Inactive tab
    Gold = Color3.fromRGB(255, 200, 50),            -- Gold accent
    Red = Color3.fromRGB(255, 70, 70),              -- Alert/danger
    UnknownSilhouette = Color3.fromRGB(30, 50, 70), -- Dark silhouette
    NewBadge = Color3.fromRGB(255, 180, 0),         -- Orange-gold badge
    FilterBg = Color3.fromRGB(16, 30, 52),
}

-- ============================================================
-- Constructor
-- ============================================================
function CollectionBook.new()
    local self = setmetatable({}, CollectionBook)

    self._gui = nil
    self._mainFrame = nil
    self._isOpen = false
    self._currentFilter = "All" -- All | Discovered | Undiscovered
    self._collectionData = {}   -- { [speciesKey] = { Caught = bool, Weight = number, Count = number } }
    self._playerData = nil
    self._tiles = {}             -- speciesKey -> { frame, stateLabel, nameLabel, weightLabel, glowStroke }
    self._detailFrame = nil
    self._discoveryQueue = {}    -- queue of fish to show "New!" for
    self._onCloseCallback = nil

    self:_createGUI()
    self:_wireInput()

    return self
end

-- ============================================================
-- Create all UI elements
-- ============================================================
function CollectionBook:_createGUI()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    -- Find or create our main ScreenGui
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
    backdrop.Name = "CollectionBackdrop"
    backdrop.Size = UDim2.new(1, 0, 1, 0)
    backdrop.Position = UDim2.new(0, 0, 0, 0)
    backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    backdrop.BackgroundTransparency = 1  -- starts fully transparent
    backdrop.Visible = false
    backdrop.ZIndex = 90
    backdrop.Parent = gui

    -- Click-to-close on backdrop
    backdrop.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or
           input.UserInputType == Enum.UserInputType.Touch then
            self:Close()
        end
    end)

    self._backdrop = backdrop

    -- ---- Main panel (slides from right) ----
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "CollectionMain"
    mainFrame.Size = UDim2.new(0.85, 0, 1, 0)
    mainFrame.Position = UDim2.new(1, 0, 0, 0) -- off-screen right
    mainFrame.BackgroundColor3 = Palette.Panel
    mainFrame.BackgroundTransparency = 0.08
    mainFrame.BorderSizePixel = 0
    mainFrame.ZIndex = 95
    mainFrame.Parent = backdrop

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, 20)
    panelCorner.Parent = mainFrame

    local panelStroke = Instance.new("UIStroke")
    panelStroke.Color = Palette.PanelBorder
    panelStroke.Thickness = 2
    panelStroke.Transparency = 0.3
    panelStroke.Parent = mainFrame

    self._mainFrame = mainFrame

    -- ---- HEADER ----
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, -40, 0, 60)
    header.Position = UDim2.new(0, 20, 0, 15)
    header.BackgroundTransparency = 1
    header.ZIndex = 96
    header.Parent = mainFrame

    -- Close button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "CloseButton"
    closeBtn.Size = UDim2.new(0, 48, 0, 48)
    closeBtn.Position = UDim2.new(1, -48, 0, 6)
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

    -- Title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(0, 300, 0, 36)
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 28
    titleLabel.Text = "COLLECTION LOG"
    titleLabel.TextColor3 = Palette.TextPrimary
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.ZIndex = 96
    titleLabel.Parent = header

    -- Completion tracker
    local trackerLabel = Instance.new("TextLabel")
    trackerLabel.Name = "CompletionTracker"
    trackerLabel.Size = UDim2.new(0, 300, 0, 20)
    trackerLabel.Position = UDim2.new(0, 0, 0, 38)
    trackerLabel.BackgroundTransparency = 1
    trackerLabel.Font = Enum.Font.Gotham
    trackerLabel.TextSize = 15
    trackerLabel.Text = ""
    trackerLabel.TextColor3 = Palette.Accent
    trackerLabel.TextXAlignment = Enum.TextXAlignment.Left
    trackerLabel.ZIndex = 96
    trackerLabel.Parent = header
    self._trackerLabel = trackerLabel

    -- ---- FILTER TABS ----
    local filterFrame = Instance.new("Frame")
    filterFrame.Name = "FilterTabs"
    filterFrame.Size = UDim2.new(1, -40, 0, 40)
    filterFrame.Position = UDim2.new(0, 20, 0, 80)
    filterFrame.BackgroundTransparency = 1
    filterFrame.ZIndex = 96
    filterFrame.Parent = mainFrame

    local filterTabs = {"All", "Discovered", "Undiscovered"}
    self._filterButtons = {}

    for i, tabName in ipairs(filterTabs) do
        local tabBtn = Instance.new("TextButton")
        tabBtn.Name = "Filter_" .. tabName
        tabBtn.Size = UDim2.new(0.31, 0, 1, 0)
        tabBtn.Position = UDim2.new((i - 1) * 0.345, 0, 0, 0)
        tabBtn.BackgroundColor3 = (tabName == self._currentFilter) and Palette.TabActive or Palette.TabInactive
        tabBtn.Text = tabName
        tabBtn.Font = Enum.Font.GothamBold
        tabBtn.TextSize = 16
        tabBtn.TextColor3 = Palette.TextPrimary
        tabBtn.ZIndex = 96
        tabBtn.Parent = filterFrame

        local tabCorner = Instance.new("UICorner")
        tabCorner.CornerRadius = UDim.new(0, 10)
        tabCorner.Parent = tabBtn

        local tabStroke = Instance.new("UIStroke")
        tabStroke.Color = Palette.PanelBorder
        tabStroke.Thickness = 1
        tabStroke.Transparency = 0.5
        tabStroke.Parent = tabBtn

        tabBtn.MouseButton1Click:Connect(function()
            self:_setFilter(tabName)
        end)

        self._filterButtons[tabName] = tabBtn
    end

    -- ---- GRID CONTAINER (scrollable) ----
    local gridScroll = Instance.new("ScrollingFrame")
    gridScroll.Name = "GridScroll"
    gridScroll.Size = UDim2.new(1, -40, 1, -140)
    gridScroll.Position = UDim2.new(0, 20, 0, 130)
    gridScroll.BackgroundColor3 = Palette.Background
    gridScroll.BackgroundTransparency = 0.3
    gridScroll.BorderSizePixel = 0
    gridScroll.ScrollBarThickness = 6
    gridScroll.ScrollBarImageColor3 = Palette.PanelBorder
    gridScroll.CanvasSize = UDim2.new(0, 0, 0, 600)
    gridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    gridScroll.ZIndex = 96
    gridScroll.Parent = mainFrame

    local scrollCorner = Instance.new("UICorner")
    scrollCorner.CornerRadius = UDim.new(0, 12)
    scrollCorner.Parent = gridScroll

    -- Grid layout using UIListLayout + UIGridStyleLayout or manual
    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.Name = "GridLayout"
    gridLayout.CellSize = UDim2.new(0, 155, 0, 180)
    gridLayout.CellPadding = UDim2.new(0, 12, 0, 12)
    gridLayout.FillDirection = Enum.FillDirection.Horizontal
    gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    gridLayout.Parent = gridScroll

    self._gridScroll = gridScroll
    self._gridLayout = gridLayout

    -- ---- DETAIL VIEW (hidden by default) ----
    self:_createDetailView(mainFrame)

    -- ---- NEW DISCOVERY NOTIFICATION ----
    self:_createDiscoveryNotification(gui)
end

-- ============================================================
-- Detail View overlay
-- ============================================================
function CollectionBook:_createDetailView(parent)
    local frame = Instance.new("Frame")
    frame.Name = "DetailView"
    frame.Size = UDim2.new(1, -40, 1, -140)
    frame.Position = UDim2.new(0, 20, 0, 130)
    frame.BackgroundColor3 = Palette.Panel
    frame.BackgroundTransparency = 0.05
    frame.BorderSizePixel = 0
    frame.Visible = false
    frame.ZIndex = 97
    frame.Parent = parent

    local detailCorner = Instance.new("UICorner")
    detailCorner.CornerRadius = UDim.new(0, 16)
    detailCorner.Parent = frame

    local detailStroke = Instance.new("UIStroke")
    detailStroke.Color = Palette.PanelBorder
    detailStroke.Thickness = 2
    detailStroke.Transparency = 0.2
    detailStroke.Parent = frame

    -- Back button
    local backBtn = Instance.new("TextButton")
    backBtn.Name = "DetailBack"
    backBtn.Size = UDim2.new(0, 100, 0, 36)
    backBtn.Position = UDim2.new(0, 15, 0, 15)
    backBtn.BackgroundColor3 = Palette.TabInactive
    backBtn.Text = "← Back"
    backBtn.Font = Enum.Font.GothamBold
    backBtn.TextSize = 16
    backBtn.TextColor3 = Palette.TextPrimary
    backBtn.ZIndex = 98
    backBtn.Parent = frame

    local backCorner = Instance.new("UICorner")
    backCorner.CornerRadius = UDim.new(0, 10)
    backCorner.Parent = backBtn

    backBtn.MouseButton1Click:Connect(function()
        self:_hideDetailView()
    end)

    -- Fish art placeholder (centered)
    local artFrame = Instance.new("Frame")
    artFrame.Name = "DetailArt"
    artFrame.Size = UDim2.new(0, 180, 0, 180)
    artFrame.Position = UDim2.new(0.5, -90, 0, 70)
    artFrame.BackgroundColor3 = Palette.UnknownSilhouette
    artFrame.BorderSizePixel = 0
    artFrame.ZIndex = 98
    artFrame.Parent = frame

    local artCorner = Instance.new("UICorner")
    artCorner.CornerRadius = UDim.new(0, 20)
    artCorner.Parent = artFrame

    -- Glow stroke for art (rarity-colored)
    local artGlow = Instance.new("UIStroke")
    artGlow.Name = "DetailArtGlow"
    artGlow.Color = Palette.PanelBorder
    artGlow.Thickness = 3
    artGlow.Transparency = 0.2
    artGlow.Parent = artFrame

    self._detailArtFrame = artFrame
    self._detailArtGlow = artGlow

    -- Fish name
    local detailName = Instance.new("TextLabel")
    detailName.Name = "DetailName"
    detailName.Size = UDim2.new(0.8, 0, 0, 32)
    detailName.Position = UDim2.new(0.1, 0, 0, 265)
    detailName.BackgroundTransparency = 1
    detailName.Font = Enum.Font.GothamBold
    detailName.TextSize = 24
    detailName.Text = ""
    detailName.TextColor3 = Palette.TextPrimary
    detailName.ZIndex = 98
    detailName.Parent = frame
    self._detailNameLabel = detailName

    -- Rarity label
    local detailRarity = Instance.new("TextLabel")
    detailRarity.Name = "DetailRarity"
    detailRarity.Size = UDim2.new(0.8, 0, 0, 24)
    detailRarity.Position = UDim2.new(0.1, 0, 0, 298)
    detailRarity.BackgroundTransparency = 1
    detailRarity.Font = Enum.Font.GothamBold
    detailRarity.TextSize = 18
    detailRarity.Text = ""
    detailRarity.TextColor3 = Palette.TextSecondary
    detailRarity.ZIndex = 98
    detailRarity.Parent = frame
    self._detailRarityLabel = detailRarity

    -- Stat grid
    local stats = {
        { label = "Weight Range", key = "WeightRange" },
        { label = "Record Catch", key = "RecordCatch" },
        { label = "Sell Price", key = "SellPrice" },
        { label = "Times Caught", key = "CatchCount" },
    }

    self._detailStatLabels = {}

    for i, stat in ipairs(stats) do
        local yPos = 340 + (i - 1) * 36

        local statLabel = Instance.new("TextLabel")
        statLabel.Name = "StatLabel_" .. stat.key
        statLabel.Size = UDim2.new(0.35, 0, 0, 28)
        statLabel.Position = UDim2.new(0.1, 0, 0, yPos)
        statLabel.BackgroundTransparency = 1
        statLabel.Font = Enum.Font.Gotham
        statLabel.TextSize = 14
        statLabel.Text = stat.label
        statLabel.TextColor3 = Palette.TextSecondary
        statLabel.TextXAlignment = Enum.TextXAlignment.Left
        statLabel.ZIndex = 98
        statLabel.Parent = frame

        local statValue = Instance.new("TextLabel")
        statValue.Name = "StatValue_" .. stat.key
        statValue.Size = UDim2.new(0.55, 0, 0, 28)
        statValue.Position = UDim2.new(0.45, 0, 0, yPos)
        statValue.BackgroundTransparency = 1
        statValue.Font = Enum.Font.GothamBold
        statValue.TextSize = 14
        statValue.Text = "—"
        statValue.TextColor3 = Palette.TextPrimary
        statValue.TextXAlignment = Enum.TextXAlignment.Left
        statValue.ZIndex = 98
        statValue.Parent = frame

        self._detailStatLabels[stat.key] = statValue
    end

    -- Flavor text
    local flavorLabel = Instance.new("TextLabel")
    flavorLabel.Name = "DetailFlavor"
    flavorLabel.Size = UDim2.new(0.8, 0, 0, 50)
    flavorLabel.Position = UDim2.new(0.1, 0, 0, 500)
    flavorLabel.BackgroundTransparency = 1
    flavorLabel.Font = Enum.Font.Gotham
    flavorLabel.TextSize = 13
    flavorLabel.Text = ""
    flavorLabel.TextColor3 = Palette.TextSecondary
    flavorLabel.TextXAlignment = Enum.TextXAlignment.Left
    flavorLabel.TextWrapped = true
    flavorLabel.ZIndex = 98
    flavorLabel.Parent = frame
    self._detailFlavorLabel = flavorLabel

    self._detailFrame = frame
end

-- ============================================================
-- Discovery notification
-- ============================================================
function CollectionBook:_createDiscoveryNotification(parent)
    local notif = Instance.new("Frame")
    notif.Name = "DiscoveryNotification"
    notif.Size = UDim2.new(0, 240, 0, 50)
    notif.Position = UDim2.new(0.5, -120, 0.1, 0)
    notif.BackgroundColor3 = Palette.Panel
    notif.BackgroundTransparency = 0.05
    notif.BorderSizePixel = 0
    notif.Visible = false
    notif.ZIndex = 200
    notif.Parent = parent

    local notifCorner = Instance.new("UICorner")
    notifCorner.CornerRadius = UDim.new(0, 14)
    notifCorner.Parent = notif

    local notifGlow = Instance.new("UIStroke")
    notifGlow.Name = "NotifGlow"
    notifGlow.Color = Palette.NewBadge
    notifGlow.Thickness = 2
    notifGlow.Transparency = 0
    notifGlow.Parent = notif

    -- Badge
    local badge = Instance.new("TextLabel")
    badge.Name = "Badge"
    badge.Size = UDim2.new(0, 70, 0, 24)
    badge.Position = UDim2.new(0, 12, 0, 13)
    badge.BackgroundColor3 = Palette.NewBadge
    badge.Text = "NEW ENTRY!"
    badge.Font = Enum.Font.GothamBold
    badge.TextSize = 12
    badge.TextColor3 = Color3.fromRGB(0, 0, 0)
    badge.ZIndex = 201
    badge.Parent = notif

    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = UDim.new(0, 6)
    badgeCorner.Parent = badge

    -- Fish name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NotifName"
    nameLabel.Size = UDim2.new(0, 140, 0, 20)
    nameLabel.Position = UDim2.new(0, 90, 0, 15)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 16
    nameLabel.Text = ""
    nameLabel.TextColor3 = Palette.TextPrimary
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.ZIndex = 201
    nameLabel.Parent = notif
    self._notifNameLabel = nameLabel

    self._notifFrame = notif
    self._notifGlow = notifGlow
end

-- ============================================================
-- Input wiring (keyboard shortcuts)
-- ============================================================
function CollectionBook:_wireInput()
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.B and self._isOpen then
            self:Close()
        end
    end)
end

-- ============================================================
-- Public API: Open with player data
-- ============================================================
function CollectionBook:Open(playerData, onClose)
    self._playerData = playerData
    self._collectionData = playerData and playerData.CollectionLog and playerData.CollectionLog.Species or {}
    self._onCloseCallback = onClose

    if self._isOpen then return end
    self._isOpen = true

    -- Show backdrop
    self._backdrop.Visible = true

    -- Slide in main panel
    local slideIn = TweenService:Create(
        self._mainFrame,
        TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Position = UDim2.new(0.15, 0, 0, 0) }
    )

    -- Fade in backdrop
    local fadeIn = TweenService:Create(
        self._backdrop,
        TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { BackgroundTransparency = 0.5 }
    )

    slideIn:Play()
    fadeIn:Play()

    -- Populate
    self:_setFilter("All")
    self:_updateCompletionTracker()

    -- Process discovery queue
    self:_processDiscoveryQueue()
end

-- ============================================================
-- Public API: Close
-- ============================================================
function CollectionBook:Close()
    if not self._isOpen then return end
    self._isOpen = false

    -- Hide detail view first
    self:_hideDetailView()

    -- Slide out
    local slideOut = TweenService:Create(
        self._mainFrame,
        TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { Position = UDim2.new(1, 0, 0, 0) }
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
-- Public API: Notify new discovery (can be called while closed)
-- ============================================================
function CollectionBook:NotifyDiscovery(speciesData, weight)
    table.insert(self._discoveryQueue, {
        Species = speciesData,
        Weight = weight,
    })

    if not self._isOpen then
        -- Show the popup notification even when book is closed
        self:_showDiscoveryPopup(speciesData)
    end
end

-- ============================================================
-- Filter tabs
-- ============================================================
function CollectionBook:_setFilter(filterName)
    self._currentFilter = filterName

    -- Update tab visuals
    for name, btn in pairs(self._filterButtons) do
        btn.BackgroundColor3 = (name == filterName) and Palette.TabActive or Palette.TabInactive
    end

    -- Repopulate grid
    self:_populateGrid()
end

-- ============================================================
-- Populate the fish grid
-- ============================================================
function CollectionBook:_populateGrid()
    -- Clear existing tiles
    for _, tile in pairs(self._tiles) do
        tile.frame:Destroy()
    end
    self._tiles = {}

    local speciesList = Shared.Constants.FishSpecies
    local displayedCount = 0

    for i, species in ipairs(speciesList) do
        local logEntry = self._collectionData[species.Key] or {}
        local caught = logEntry.Caught or false
        local recordWeight = logEntry.BiggestWeight or 0
        local catchCount = logEntry.Count or 0

        -- Apply filter
        if self._currentFilter == "Discovered" and not caught then
            continue
        end
        if self._currentFilter == "Undiscovered" and caught then
            continue
        end

        -- Create tile
        local tile = self:_createTile(species, caught, recordWeight, catchCount)
        tile.LayoutOrder = i
        tile.Parent = self._gridScroll

        self._tiles[species.Key] = {
            frame = tile,
            species = species,
            caught = caught,
        }

        displayedCount = displayedCount + 1
    end

    -- Adjust canvas size for grid
    self._gridScroll.CanvasSize = UDim2.new(0, 0, 0, math.ceil(displayedCount / 2) * 195)
end

-- ============================================================
-- Create a single fish tile
-- ============================================================
function CollectionBook:_createTile(species, caught, recordWeight, catchCount)
    local rarityTier = Shared.Constants.RarityTiers[species.Rarity]
    local rarityColor = rarityTier and rarityTier.Color or Color3.fromRGB(255, 255, 255)

    local tile = Instance.new("Frame")
    tile.Name = "Tile_" .. species.Key
    tile.BackgroundColor3 = Palette.FilterBg
    tile.BackgroundTransparency = 0.15
    tile.BorderSizePixel = 0
    tile.Size = UDim2.new(0, 155, 0, 180)
    tile.ClipsDescendants = true

    local tileCorner = Instance.new("UICorner")
    tileCorner.CornerRadius = UDim.new(0, 14)
    tileCorner.Parent = tile

    -- Rarity-colored border glow
    local tileGlow = Instance.new("UIStroke")
    tileGlow.Name = "RarityGlow"
    tileGlow.Color = caught and rarityColor or Palette.UnknownSilhouette
    tileGlow.Thickness = caught and 2.5 or 1.5
    tileGlow.Transparency = caught and 0.1 or 0.5
    tileGlow.Parent = tile

    -- Fish art area
    local artFrame = Instance.new("Frame")
    artFrame.Name = "Art"
    artFrame.Size = UDim2.new(0, 100, 0, 100)
    artFrame.Position = UDim2.new(0.5, -50, 0, 15)
    artFrame.BackgroundColor3 = caught and rarityColor or Palette.UnknownSilhouette
    artFrame.BackgroundTransparency = caught and 0.7 or 0.85
    artFrame.BorderSizePixel = 0
    artFrame.Parent = tile

    local artCorner = Instance.new("UICorner")
    artCorner.CornerRadius = UDim.new(0, 16)
    artCorner.Parent = artFrame

    -- Silhouette or species initial
    local artIcon = Instance.new("TextLabel")
    artIcon.Name = "ArtIcon"
    artIcon.Size = UDim2.new(1, 0, 1, 0)
    artIcon.BackgroundTransparency = 1
    artIcon.Font = Enum.Font.GothamBold
    artIcon.TextSize = caught and 36 or 42
    artIcon.Text = caught and "🐟" or "?"
    artIcon.TextColor3 = caught and rarityColor or Palette.TextSecondary
    artIcon.Parent = artFrame

    -- Bioluminescent inner glow (if applicable)
    if species.Bioluminescent and caught then
        local glow = Instance.new("UIStroke")
        glow.Color = species.GlowColor or rarityColor
        glow.Thickness = 2
        glow.Transparency = 0.3
        glow.Parent = artFrame
    end

    -- Fish name or ???
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "Name"
    nameLabel.Size = UDim2.new(1, -16, 0, 22)
    nameLabel.Position = UDim2.new(0, 8, 0, 120)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 14
    nameLabel.Text = caught and species.Name or "???"
    nameLabel.TextColor3 = caught and Palette.TextPrimary or Palette.TextSecondary
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Parent = tile

    -- Weight record or "Undiscovered"
    local weightLabel = Instance.new("TextLabel")
    weightLabel.Name = "Weight"
    weightLabel.Size = UDim2.new(1, -16, 0, 18)
    weightLabel.Position = UDim2.new(0, 8, 0, 142)
    weightLabel.BackgroundTransparency = 1
    weightLabel.Font = Enum.Font.Gotham
    weightLabel.TextSize = 12
    if caught then
        weightLabel.Text = string.format("Best: %.1f kg", recordWeight)
        weightLabel.TextColor3 = Palette.Accent
    else
        weightLabel.Text = "Undiscovered"
        weightLabel.TextColor3 = Palette.TextSecondary
    end
    weightLabel.Parent = tile

    -- Rarity badge
    local rarityBadge = Instance.new("TextLabel")
    rarityBadge.Name = "RarityBadge"
    rarityBadge.Size = UDim2.new(0, 70, 0, 18)
    rarityBadge.Position = UDim2.new(0.5, -35, 0, 160)
    rarityBadge.BackgroundColor3 = rarityColor
    rarityBadge.BackgroundTransparency = 0.3
    rarityBadge.Text = species.Rarity:upper()
    rarityBadge.Font = Enum.Font.GothamBold
    rarityBadge.TextSize = 11
    rarityBadge.TextColor3 = rarityColor
    rarityBadge.Parent = tile

    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = UDim.new(0, 5)
    badgeCorner.Parent = rarityBadge

    -- Click handler
    local clickDetector = Instance.new("TextButton")
    clickDetector.Name = "ClickArea"
    clickDetector.Size = UDim2.new(1, 0, 1, 0)
    clickDetector.BackgroundTransparency = 1
    clickDetector.Text = ""
    clickDetector.Parent = tile

    clickDetector.MouseButton1Click:Connect(function()
        if caught then
            self:_showDetailView(species, recordWeight, catchCount, rarityColor)
        else
            -- Subtle shake animation for undiscovered
            self:_shakeTile(tile)
        end
    end)

    return tile
end

-- ============================================================
-- Shake animation for undiscovered tiles
-- ============================================================
function CollectionBook:_shakeTile(tile)
    local origPos = tile.Position
    local shakeTween = TweenService:Create(
        tile,
        TweenInfo.new(0.05, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
        { Position = origPos + UDim2.new(0, 4, 0, 0) }
    )
    local shakeBack = TweenService:Create(
        tile,
        TweenInfo.new(0.05, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
        { Position = origPos - UDim2.new(0, 4, 0, 0) }
    )
    local shakeReset = TweenService:Create(
        tile,
        TweenInfo.new(0.05, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
        { Position = origPos }
    )

    shakeTween:Play()
    shakeTween.Completed:Connect(function()
        shakeBack:Play()
        shakeBack.Completed:Connect(function()
            shakeReset:Play()
        end)
    end)
end

-- ============================================================
-- Detail View
-- ============================================================
function CollectionBook:_showDetailView(species, recordWeight, catchCount, rarityColor)
    self._detailFrame.Visible = true
    self._gridScroll.Visible = false

    -- Fade in detail
    self._detailFrame.BackgroundTransparency = 0.2
    local fadeIn = TweenService:Create(
        self._detailFrame,
        TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { BackgroundTransparency = 0.05 }
    )
    fadeIn:Play()

    -- Populate
    self._detailArtFrame.BackgroundColor3 = rarityColor
    self._detailArtFrame.BackgroundTransparency = 0.7
    self._detailArtGlow.Color = rarityColor

    self._detailNameLabel.Text = species.Name
    self._detailNameLabel.TextColor3 = rarityColor

    self._detailRarityLabel.Text = species.Rarity:upper()
    self._detailRarityLabel.TextColor3 = rarityColor

    self._detailStatLabels["WeightRange"].Text = string.format("%.1f – %.1f kg", species.WeightRange.Min, species.WeightRange.Max)
    self._detailStatLabels["RecordCatch"].Text = string.format("%.1f kg", recordWeight)
    self._detailStatLabels["SellPrice"].Text = string.format("💰 %d – %d Coins", species.BaseSellPrice.Min, species.BaseSellPrice.Max)
    self._detailStatLabels["CatchCount"].Text = tostring(catchCount)

    -- Flavor text per species
    local flavorTexts = {
        GlowfinMinnow = "A tiny beacon in the shallows. Their gentle glow guides novice anglers through the coral gardens.",
        CoralSnapper = "Stocky and bold, the Coral Snapper patrols the reef with the confidence of a fish twice its size.",
        ReefDart = "A flash of blue-green lightning. Only the quickest anglers can match its erratic rhythm.",
        SunkenAngler = "The hidden terror of the shipwreck. Its hypnotic lure has fooled many — and the creature behind it waits patiently.",
        SpectralRay = "A ghost of the deep. Sailors whisper of its ethereal beauty, but few have ever touched one.",
    }
    self._detailFlavorLabel.Text = flavorTexts[species.Key] or ""
end

function CollectionBook:_hideDetailView()
    if not self._detailFrame.Visible then return end

    self._detailFrame.Visible = false
    self._gridScroll.Visible = true
end

-- ============================================================
-- Completion tracker
-- ============================================================
function CollectionBook:_updateCompletionTracker()
    local speciesList = Shared.Constants.FishSpecies
    local totalSpecies = #speciesList
    local discovered = 0

    for _, species in ipairs(speciesList) do
        local logEntry = self._collectionData[species.Key]
        if logEntry and logEntry.Caught then
            discovered = discovered + 1
        end
    end

    local percent = totalSpecies > 0 and math.floor(discovered / totalSpecies * 100) or 0
    self._trackerLabel.Text = string.format("%d/%d Discovered  •  %d%% Complete", discovered, totalSpecies, percent)

    -- Color: gold at 100%, cyan otherwise
    if percent >= 100 then
        self._trackerLabel.TextColor3 = Palette.Gold
    else
        self._trackerLabel.TextColor3 = Palette.Accent
    end
end

-- ============================================================
-- Discovery popup (for when book is closed)
-- ============================================================
function CollectionBook:_showDiscoveryPopup(speciesData)
    local rarityTier = Shared.Constants.RarityTiers[speciesData.Rarity]
    local rarityColor = rarityTier and rarityTier.Color or Color3.fromRGB(255, 255, 255)

    self._notifNameLabel.Text = speciesData.Name
    self._notifGlow.Color = rarityColor
    self._notifFrame.Visible = true

    -- Slide down + pulse
    self._notifFrame.Position = UDim2.new(0.5, -120, -0.1, 0)
    local slideDown = TweenService:Create(
        self._notifFrame,
        TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Position = UDim2.new(0.5, -120, 0.08, 0) }
    )

    -- Pulse the glow
    local pulseOn = TweenService:Create(
        self._notifGlow,
        TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { Transparency = 0.6 }
    )

    slideDown:Play()
    pulseOn:Play()

    -- Auto-dismiss after 3.5 seconds
    task.delay(3.5, function()
        local fadeAway = TweenService:Create(
            self._notifFrame,
            TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Position = UDim2.new(0.5, -120, -0.1, 0) }
        )
        pulseOn:Cancel()
        fadeAway:Play()
        fadeAway.Completed:Connect(function()
            self._notifFrame.Visible = false
        end)
    end)
end

-- ============================================================
-- Process discovery queue (called on open)
-- ============================================================
function CollectionBook:_processDiscoveryQueue()
    if #self._discoveryQueue == 0 then return end

    for _, discovery in ipairs(self._discoveryQueue) do
        self:_showDiscoveryPopup(discovery.Species)
    end
    self._discoveryQueue = {}
end

-- ============================================================
-- Refresh from updated player data
-- ============================================================
function CollectionBook:Refresh(playerData)
    self._playerData = playerData
    self._collectionData = playerData and playerData.CollectionLog and playerData.CollectionLog.Species or {}

    if self._isOpen then
        self:_populateGrid()
        self:_updateCompletionTracker()
    end
end

-- ============================================================
-- Cleanup
-- ============================================================
function CollectionBook:Destroy()
    self:HideDetailView()
    if self._backdrop then
        self._backdrop:Destroy()
        self._backdrop = nil
    end
end

function CollectionBook:IsOpen()
    return self._isOpen
end

return CollectionBook
