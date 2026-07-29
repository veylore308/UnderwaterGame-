--[[
    ShopScreen.lua
    Deep Tide Studios — Client UI Module
    Shop UI: tabbed layout (Rods, Consumables, Gamepasses), rod stat
    comparison, purchase confirmation dialog, persistent currency display.

    Design: Dark underwater glass-panel theme with bioluminescent accents.
    Mobile-friendly: minimum 48x48 touch targets.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))

local ShopScreen = {}
ShopScreen.__index = ShopScreen

-- ============================================================
-- Color palette (underwater theme)
-- ============================================================
local Palette = {
    Background = Color3.fromRGB(8, 14, 28),
    Panel = Color3.fromRGB(12, 22, 44),
    PanelBorder = Color3.fromRGB(40, 100, 160),
    TextPrimary = Color3.fromRGB(220, 235, 255),
    TextSecondary = Color3.fromRGB(140, 175, 210),
    Accent = Color3.fromRGB(60, 200, 220),
    TabActive = Color3.fromRGB(30, 150, 200),
    TabInactive = Color3.fromRGB(20, 40, 60),
    Gold = Color3.fromRGB(255, 200, 50),
    Green = Color3.fromRGB(80, 220, 80),
    Red = Color3.fromRGB(255, 70, 70),
    RobuxGreen = Color3.fromRGB(0, 200, 80),
    ButtonPrimary = Color3.fromRGB(40, 150, 220),
    ButtonDisabled = Color3.fromRGB(60, 60, 60),
    ButtonHover = Color3.fromRGB(60, 180, 245),
    StatBetter = Color3.fromRGB(80, 220, 100),
    StatWorse = Color3.fromRGB(220, 80, 80),
    StatEqual = Color3.fromRGB(200, 200, 200),
    CardBg = Color3.fromRGB(16, 30, 52),
    BalanceBg = Color3.fromRGB(10, 18, 36),
}

-- ============================================================
-- Constructor
-- ============================================================
function ShopScreen.new()
    local self = setmetatable({}, ShopScreen)

    self._gui = nil
    self._backdrop = nil
    self._mainFrame = nil
    self._isOpen = false
    self._currentTab = "Rods"  -- Rods | Consumables | Gamepasses
    self._playerData = nil
    self._onCloseCallback = nil
    self._equippedRodKey = "BambooRod"
    self._rodCards = {}        -- rodKey -> { frame, buyBtn, ... }
    self._consumableCards = {} -- itemKey -> { frame, qtyLabel, buyBtn }
    self._gamepassCards = {}   -- passKey -> { frame, buyBtn }
    self._confirmDialog = nil

    self:_createGUI()
    self:_wireInput()

    return self
end

-- ============================================================
-- Create all UI elements
-- ============================================================
function ShopScreen:_createGUI()
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
    backdrop.Name = "ShopBackdrop"
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

    -- ---- Main panel (slides from right) ----
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "ShopMain"
    mainFrame.Size = UDim2.new(0.85, 0, 1, 0)
    mainFrame.Position = UDim2.new(1, 0, 0, 0)
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

    -- ---- CURRENCY BAR (persistent in panel) ----
    self:_createCurrencyBar(mainFrame)

    -- ---- HEADER ----
    local header = Instance.new("Frame")
    header.Name = "ShopHeader"
    header.Size = UDim2.new(1, -40, 0, 50)
    header.Position = UDim2.new(0, 20, 0, 50)
    header.BackgroundTransparency = 1
    header.ZIndex = 96
    header.Parent = mainFrame

    -- Close button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "CloseButton"
    closeBtn.Size = UDim2.new(0, 48, 0, 48)
    closeBtn.Position = UDim2.new(1, -48, 0, 0)
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
    titleLabel.Name = "ShopTitle"
    titleLabel.Size = UDim2.new(0, 200, 0, 36)
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 28
    titleLabel.Text = "SHOP"
    titleLabel.TextColor3 = Palette.TextPrimary
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.ZIndex = 96
    titleLabel.Parent = header

    -- ---- TAB BAR ----
    self:_createTabBar(mainFrame)

    -- ---- CONTENT AREA (scrollable) ----
    local contentScroll = Instance.new("ScrollingFrame")
    contentScroll.Name = "ContentScroll"
    contentScroll.Size = UDim2.new(1, -40, 1, -165)
    contentScroll.Position = UDim2.new(0, 20, 0, 150)
    contentScroll.BackgroundColor3 = Palette.Background
    contentScroll.BackgroundTransparency = 0.3
    contentScroll.BorderSizePixel = 0
    contentScroll.ScrollBarThickness = 6
    contentScroll.ScrollBarImageColor3 = Palette.PanelBorder
    contentScroll.CanvasSize = UDim2.new(0, 0, 0, 800)
    contentScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    contentScroll.ZIndex = 96
    contentScroll.Parent = mainFrame

    local scrollCorner = Instance.new("UICorner")
    scrollCorner.CornerRadius = UDim.new(0, 12)
    scrollCorner.Parent = contentScroll

    -- List layout for content
    local contentLayout = Instance.new("UIListLayout")
    contentLayout.Name = "ContentLayout"
    contentLayout.Padding = UDim.new(0, 12)
    contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
    contentLayout.Parent = contentScroll

    self._contentScroll = contentScroll
    self._contentLayout = contentLayout

    -- ---- PURCHASE CONFIRMATION DIALOG ----
    self:_createConfirmDialog(mainFrame)
end

-- ============================================================
-- Currency bar (top of shop panel)
-- ============================================================
function ShopScreen:_createCurrencyBar(parent)
    local bar = Instance.new("Frame")
    bar.Name = "CurrencyBar"
    bar.Size = UDim2.new(1, -40, 0, 44)
    bar.Position = UDim2.new(0, 20, 0, 4)
    bar.BackgroundColor3 = Palette.BalanceBg
    bar.BackgroundTransparency = 0.2
    bar.BorderSizePixel = 0
    bar.ZIndex = 96
    bar.Parent = parent

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 10)
    barCorner.Parent = bar

    -- Coin display
    local coinFrame = Instance.new("Frame")
    coinFrame.Name = "CoinDisplay"
    coinFrame.Size = UDim2.new(0.32, 0, 1, -8)
    coinFrame.Position = UDim2.new(0, 8, 0, 4)
    coinFrame.BackgroundTransparency = 1
    coinFrame.ZIndex = 97
    coinFrame.Parent = bar

    local coinIcon = Instance.new("TextLabel")
    coinIcon.Name = "CoinIcon"
    coinIcon.Size = UDim2.new(0, 28, 0, 28)
    coinIcon.Position = UDim2.new(0, 0, 0.5, -14)
    coinIcon.BackgroundTransparency = 1
    coinIcon.Font = Enum.Font.Gotham
    coinIcon.TextSize = 20
    coinIcon.Text = "🪙"
    coinIcon.ZIndex = 97
    coinIcon.Parent = coinFrame

    local coinLabel = Instance.new("TextLabel")
    coinLabel.Name = "CoinLabel"
    coinLabel.Size = UDim2.new(1, -32, 0, 28)
    coinLabel.Position = UDim2.new(0, 30, 0.5, -14)
    coinLabel.BackgroundTransparency = 1
    coinLabel.Font = Enum.Font.GothamBold
    coinLabel.TextSize = 16
    coinLabel.Text = "0"
    coinLabel.TextColor3 = Palette.Gold
    coinLabel.TextXAlignment = Enum.TextXAlignment.Left
    coinLabel.ZIndex = 97
    coinLabel.Parent = coinFrame
    self._coinLabel = coinLabel

    -- Gem display
    local gemFrame = Instance.new("Frame")
    gemFrame.Name = "GemDisplay"
    gemFrame.Size = UDim2.new(0.32, 0, 1, -8)
    gemFrame.Position = UDim2.new(0.34, 0, 0, 4)
    gemFrame.BackgroundTransparency = 1
    gemFrame.ZIndex = 97
    gemFrame.Parent = bar

    local gemIcon = Instance.new("TextLabel")
    gemIcon.Name = "GemIcon"
    gemIcon.Size = UDim2.new(0, 28, 0, 28)
    gemIcon.Position = UDim2.new(0, 0, 0.5, -14)
    gemIcon.BackgroundTransparency = 1
    gemIcon.Font = Enum.Font.Gotham
    gemIcon.TextSize = 20
    gemIcon.Text = "💎"
    gemIcon.ZIndex = 97
    gemIcon.Parent = gemFrame

    local gemLabel = Instance.new("TextLabel")
    gemLabel.Name = "GemLabel"
    gemLabel.Size = UDim2.new(1, -32, 0, 28)
    gemLabel.Position = UDim2.new(0, 30, 0.5, -14)
    gemLabel.BackgroundTransparency = 1
    gemLabel.Font = Enum.Font.GothamBold
    gemLabel.TextSize = 16
    gemLabel.Text = "0"
    gemLabel.TextColor3 = Palette.Accent
    gemLabel.TextXAlignment = Enum.TextXAlignment.Left
    gemLabel.ZIndex = 97
    gemLabel.Parent = gemFrame
    self._gemLabel = gemLabel

    self._currencyBar = bar
end

-- ============================================================
-- Tab bar
-- ============================================================
function ShopScreen:_createTabBar(parent)
    local tabBar = Instance.new("Frame")
    tabBar.Name = "TabBar"
    tabBar.Size = UDim2.new(0.55, 0, 0, 40)
    tabBar.Position = UDim2.new(0, 20, 0, 100)
    tabBar.BackgroundTransparency = 1
    tabBar.ZIndex = 96
    tabBar.Parent = parent

    local tabs = {"Rods", "Consumables", "Gamepasses"}
    self._tabButtons = {}

    for i, tabName in ipairs(tabs) do
        local tabBtn = Instance.new("TextButton")
        tabBtn.Name = "Tab_" .. tabName
        tabBtn.Size = UDim2.new(0.31, 0, 1, 0)
        tabBtn.Position = UDim2.new((i - 1) * 0.345, 0, 0, 0)
        tabBtn.BackgroundColor3 = (tabName == self._currentTab) and Palette.TabActive or Palette.TabInactive
        tabBtn.Text = tabName
        tabBtn.Font = Enum.Font.GothamBold
        tabBtn.TextSize = 16
        tabBtn.TextColor3 = Palette.TextPrimary
        tabBtn.ZIndex = 96
        tabBtn.Parent = tabBar

        local tabCorner = Instance.new("UICorner")
        tabCorner.CornerRadius = UDim.new(0, 10)
        tabCorner.Parent = tabBtn

        local tabStroke = Instance.new("UIStroke")
        tabStroke.Color = Palette.PanelBorder
        tabStroke.Thickness = 1
        tabStroke.Transparency = 0.5
        tabStroke.Parent = tabBtn

        tabBtn.MouseButton1Click:Connect(function()
            self:_switchTab(tabName)
        end)

        self._tabButtons[tabName] = tabBtn
    end
end

-- ============================================================
-- Confirmation dialog
-- ============================================================
function ShopScreen:_createConfirmDialog(parent)
    local dialog = Instance.new("Frame")
    dialog.Name = "ConfirmDialog"
    dialog.Size = UDim2.new(0.7, 0, 0, 180)
    dialog.Position = UDim2.new(0.15, 0, 0.35, 0)
    dialog.BackgroundColor3 = Palette.Panel
    dialog.BackgroundTransparency = 0.05
    dialog.BorderSizePixel = 0
    dialog.Visible = false
    dialog.ZIndex = 200
    dialog.Parent = parent

    local dialogCorner = Instance.new("UICorner")
    dialogCorner.CornerRadius = UDim.new(0, 16)
    dialogCorner.Parent = dialog

    local dialogStroke = Instance.new("UIStroke")
    dialogStroke.Color = Palette.PanelBorder
    dialogStroke.Thickness = 2
    dialogStroke.Transparency = 0.2
    dialogStroke.Parent = dialog

    -- Dim overlay behind dialog
    local dimOverlay = Instance.new("Frame")
    dimOverlay.Name = "DimOverlay"
    dimOverlay.Size = UDim2.new(1, 0, 1, 0)
    dimOverlay.Position = UDim2.new(0, 0, 0, 0)
    dimOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    dimOverlay.BackgroundTransparency = 1
    dimOverlay.Visible = false
    dimOverlay.ZIndex = 199
    dimOverlay.Parent = parent
    self._dimOverlay = dimOverlay

    -- Title
    local dialogTitle = Instance.new("TextLabel")
    dialogTitle.Name = "DialogTitle"
    dialogTitle.Size = UDim2.new(1, -24, 0, 28)
    dialogTitle.Position = UDim2.new(0, 12, 0, 12)
    dialogTitle.BackgroundTransparency = 1
    dialogTitle.Font = Enum.Font.GothamBold
    dialogTitle.TextSize = 20
    dialogTitle.Text = "Confirm Purchase"
    dialogTitle.TextColor3 = Palette.TextPrimary
    dialogTitle.ZIndex = 201
    dialogTitle.Parent = dialog

    -- Message
    local dialogMsg = Instance.new("TextLabel")
    dialogMsg.Name = "DialogMsg"
    dialogMsg.Size = UDim2.new(1, -24, 0, 40)
    dialogMsg.Position = UDim2.new(0, 12, 0, 44)
    dialogMsg.BackgroundTransparency = 1
    dialogMsg.Font = Enum.Font.Gotham
    dialogMsg.TextSize = 14
    dialogMsg.Text = ""
    dialogMsg.TextColor3 = Palette.TextSecondary
    dialogMsg.TextWrapped = true
    dialogMsg.ZIndex = 201
    dialogMsg.Parent = dialog
    self._dialogMsgLabel = dialogMsg

    -- Cancel button
    local cancelBtn = Instance.new("TextButton")
    cancelBtn.Name = "CancelBtn"
    cancelBtn.Size = UDim2.new(0.42, 0, 0, 42)
    cancelBtn.Position = UDim2.new(0.04, 0, 0, 120)
    cancelBtn.BackgroundColor3 = Palette.TabInactive
    cancelBtn.Text = "Cancel"
    cancelBtn.Font = Enum.Font.GothamBold
    cancelBtn.TextSize = 16
    cancelBtn.TextColor3 = Palette.TextPrimary
    cancelBtn.ZIndex = 201
    cancelBtn.Parent = dialog

    local cancelCorner = Instance.new("UICorner")
    cancelCorner.CornerRadius = UDim.new(0, 10)
    cancelCorner.Parent = cancelBtn

    cancelBtn.MouseButton1Click:Connect(function()
        self:_hideConfirmDialog()
    end)

    -- Confirm button
    local confirmBtn = Instance.new("TextButton")
    confirmBtn.Name = "ConfirmBtn"
    confirmBtn.Size = UDim2.new(0.42, 0, 0, 42)
    confirmBtn.Position = UDim2.new(0.54, 0, 0, 120)
    confirmBtn.BackgroundColor3 = Palette.ButtonPrimary
    confirmBtn.Text = "Buy"
    confirmBtn.Font = Enum.Font.GothamBold
    confirmBtn.TextSize = 16
    confirmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    confirmBtn.ZIndex = 201
    confirmBtn.Parent = dialog

    local confirmCorner = Instance.new("UICorner")
    confirmCorner.CornerRadius = UDim.new(0, 10)
    confirmCorner.Parent = confirmBtn
    self._confirmBtn = confirmBtn

    self._confirmDialog = dialog
    self._dialogTitleLabel = dialogTitle
end

-- ============================================================
-- Input wiring
-- ============================================================
function ShopScreen:_wireInput()
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.S and self._isOpen then
            self:Close()
        end
    end)
end

-- ============================================================
-- Public API: Open
-- ============================================================
function ShopScreen:Open(playerData, onClose)
    self._playerData = playerData
    self._onCloseCallback = onClose

    -- Determine equipped rod
    if playerData and playerData.Gear and playerData.Gear.EquippedRod then
        self._equippedRodKey = playerData.Gear.EquippedRod
    end

    if self._isOpen then
        -- Already open, just refresh
        self:_switchTab(self._currentTab)
        self:_updateCurrencyDisplay()
        return
    end

    self._isOpen = true
    self._backdrop.Visible = true

    -- Slide in main panel
    local slideIn = TweenService:Create(
        self._mainFrame,
        TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Position = UDim2.new(0.15, 0, 0, 0) }
    )

    local fadeIn = TweenService:Create(
        self._backdrop,
        TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { BackgroundTransparency = 0.5 }
    )

    slideIn:Play()
    fadeIn:Play()

    self:_updateCurrencyDisplay()
    self:_switchTab(self._currentTab)
end

-- ============================================================
-- Public API: Close
-- ============================================================
function ShopScreen:Close()
    if not self._isOpen then return end

    self:_hideConfirmDialog()
    self._isOpen = false

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
-- Public API: Refresh data
-- ============================================================
function ShopScreen:Refresh(playerData)
    self._playerData = playerData
    if playerData and playerData.Gear and playerData.Gear.EquippedRod then
        self._equippedRodKey = playerData.Gear.EquippedRod
    end
    if self._isOpen then
        self:_updateCurrencyDisplay()
        self:_switchTab(self._currentTab)
    end
end

-- ============================================================
-- Currency display
-- ============================================================
function ShopScreen:_updateCurrencyDisplay()
    local data = self._playerData
    local coins = (data and data.Currency and data.Currency.Coins) or 0
    local gems = (data and data.Currency and data.Currency.Gems) or 0

    self._coinLabel.Text = tostring(coins)
    self._gemLabel.Text = tostring(gems)
end

-- ============================================================
-- Tab switching
-- ============================================================
function ShopScreen:_switchTab(tabName)
    self._currentTab = tabName

    for name, btn in pairs(self._tabButtons) do
        btn.BackgroundColor3 = (name == tabName) and Palette.TabActive or Palette.TabInactive
    end

    -- Clear content
    for _, child in ipairs(self._contentScroll:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextButton") or child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    if tabName == "Rods" then
        self:_populateRods()
    elseif tabName == "Consumables" then
        self:_populateConsumables()
    elseif tabName == "Gamepasses" then
        self:_populateGamepasses()
    end
end

-- ============================================================
-- RODS TAB
-- ============================================================
function ShopScreen:_populateRods()
    local rods = Shared.Constants.RodTiers.GetMVPRods()
    local equippedRod = Shared.Constants.RodTiers.GetByKey(self._equippedRodKey)
    local playerCoins = (self._playerData and self._playerData.Currency and self._playerData.Currency.Coins) or 0

    for i, rod in ipairs(rods) do
        local isOwned = self:_isRodOwned(rod)
        local isEquipped = (rod.Key == self._equippedRodKey)
        local isLevelLocked = self:_isRodLocked(rod)
        local canAfford = playerCoins >= rod.Cost

        -- Rod card
        local card = Instance.new("Frame")
        card.Name = "RodCard_" .. rod.Key
        card.Size = UDim2.new(1, -16, 0, 180)
        card.BackgroundColor3 = Palette.CardBg
        card.BackgroundTransparency = 0.2
        card.BorderSizePixel = 0
        card.ZIndex = 96
        card.Parent = self._contentScroll

        local cardCorner = Instance.new("UICorner")
        cardCorner.CornerRadius = UDim.new(0, 14)
        cardCorner.Parent = card

        local cardStroke = Instance.new("UIStroke")
        cardStroke.Color = isEquipped and Palette.Gold or Palette.PanelBorder
        cardStroke.Thickness = isEquipped and 2 or 1
        cardStroke.Transparency = 0.3
        cardStroke.Parent = card

        -- Rod name + badge
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "RodName"
        nameLabel.Size = UDim2.new(0, 250, 0, 26)
        nameLabel.Position = UDim2.new(0, 14, 0, 10)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextSize = 18
        nameLabel.Text = rod.Name
        nameLabel.TextColor3 = Palette.TextPrimary
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.ZIndex = 97
        nameLabel.Parent = card

        -- Badge (Equipped / Owned)
        local badgeText = ""
        local badgeColor = Palette.TextSecondary
        if isEquipped then
            badgeText = "EQUIPPED"
            badgeColor = Palette.Gold
        elseif isOwned then
            badgeText = "OWNED"
            badgeColor = Palette.Green
        end

        if badgeText ~= "" then
            local badge = Instance.new("TextLabel")
            badge.Name = "Badge"
            badge.Size = UDim2.new(0, 80, 0, 20)
            badge.Position = UDim2.new(1, -90, 0, 13)
            badge.BackgroundColor3 = badgeColor
            badge.BackgroundTransparency = 0.4
            badge.Text = badgeText
            badge.Font = Enum.Font.GothamBold
            badge.TextSize = 10
            badge.TextColor3 = badgeColor
            badge.ZIndex = 97
            badge.Parent = card

            local badgeCorner = Instance.new("UICorner")
            badgeCorner.CornerRadius = UDim.new(0, 5)
            badgeCorner.Parent = badge
        end

        -- Description
        local descLabel = Instance.new("TextLabel")
        descLabel.Name = "Description"
        descLabel.Size = UDim2.new(1, -28, 0, 20)
        descLabel.Position = UDim2.new(0, 14, 0, 36)
        descLabel.BackgroundTransparency = 1
        descLabel.Font = Enum.Font.Gotham
        descLabel.TextSize = 12
        descLabel.Text = rod.Description
        descLabel.TextColor3 = Palette.TextSecondary
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.TextWrapped = true
        descLabel.ZIndex = 97
        descLabel.Parent = card

        -- Stats comparison
        local statY = 62
        local stats = {
            { name = "Cast Range", key = "CastRange", suffix = " studs", format = "%d" },
            { name = "Reel Speed", key = "ReelSpeed", suffix = "×", format = "%.1f" },
            { name = "Luck Bonus", key = "LuckBonus", suffix = "%%", format = "%d" },
            { name = "Hook Window", key = "HookWindow", suffix = "%%", format = "%d" },
        }

        for _, stat in ipairs(stats) do
            local statName = Instance.new("TextLabel")
            statName.Name = "StatName_" .. stat.key
            statName.Size = UDim2.new(0, 100, 0, 18)
            statName.Position = UDim2.new(0, 14, 0, statY)
            statName.BackgroundTransparency = 1
            statName.Font = Enum.Font.Gotham
            statName.TextSize = 12
            statName.Text = stat.name
            statName.TextColor3 = Palette.TextSecondary
            statName.TextXAlignment = Enum.TextXAlignment.Left
            statName.ZIndex = 97
            statName.Parent = card

            local currentVal = equippedRod and equippedRod[stat.key] or 0
            local rodVal = rod[stat.key]

            -- Format values
            local currentStr, rodStr
            if stat.key == "LuckBonus" or stat.key == "HookWindow" then
                currentStr = string.format(stat.format, currentVal * 100) .. stat.suffix
                rodStr = string.format(stat.format, rodVal * 100) .. stat.suffix
            else
                currentStr = string.format(stat.format, currentVal) .. stat.suffix
                rodStr = string.format(stat.format, rodVal) .. stat.suffix
            end

            local compColor = Palette.StatEqual
            if rodVal > currentVal then
                compColor = Palette.StatBetter
                rodStr = rodStr .. " ▲"
            elseif rodVal < currentVal then
                compColor = Palette.StatWorse
                rodStr = rodStr .. " ▼"
            end

            local statValue = Instance.new("TextLabel")
            statValue.Name = "StatValue_" .. stat.key
            statValue.Size = UDim2.new(1, -128, 0, 18)
            statValue.Position = UDim2.new(0, 114, 0, statY)
            statValue.BackgroundTransparency = 1
            statValue.Font = Enum.Font.GothamBold
            statValue.TextSize = 12
            statValue.Text = rodStr
            statValue.TextColor3 = compColor
            statValue.TextXAlignment = Enum.TextXAlignment.Left
            statValue.ZIndex = 97
            statValue.Parent = card

            statY = statY + 20
        end

        -- Purchase button
        local buyBtn = Instance.new("TextButton")
        buyBtn.Name = "BuyBtn"
        buyBtn.Size = UDim2.new(0, 130, 0, 38)
        buyBtn.Position = UDim2.new(1, -144, 1, -48)
        buyBtn.ZIndex = 97
        buyBtn.Parent = card

        local buyCorner = Instance.new("UICorner")
        buyCorner.CornerRadius = UDim.new(0, 8)
        buyCorner.Parent = buyBtn

        if isEquipped then
            buyBtn.Text = "Equipped"
            buyBtn.BackgroundColor3 = Palette.ButtonDisabled
            buyBtn.TextColor3 = Palette.TextSecondary
            buyBtn.Font = Enum.Font.GothamBold
            buyBtn.TextSize = 14
        elseif isLevelLocked then
            buyBtn.Text = "🔒 " .. rod.UnlockCondition
            buyBtn.BackgroundColor3 = Palette.ButtonDisabled
            buyBtn.TextColor3 = Palette.TextSecondary
            buyBtn.Font = Enum.Font.Gotham
            buyBtn.TextSize = 11
        elseif isOwned then
            buyBtn.Text = "Equip"
            buyBtn.BackgroundColor3 = Palette.Green
            buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            buyBtn.Font = Enum.Font.GothamBold
            buyBtn.TextSize = 14

            buyBtn.MouseButton1Click:Connect(function()
                self:_equipRod(rod)
            end)
        else
            buyBtn.Text = "💰 " .. tostring(rod.Cost)
            buyBtn.BackgroundColor3 = canAfford and Palette.ButtonPrimary or Palette.Red
            buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            buyBtn.Font = Enum.Font.GothamBold
            buyBtn.TextSize = 14

            buyBtn.MouseButton1Click:Connect(function()
                if rod.Cost == 0 then
                    -- Free starter rod — just equip it
                    self:_equipRod(rod)
                else
                    self:_showConfirmDialog("rod", rod, rod.Cost, "Coins")
                end
            end)
        end

        self._rodCards[rod.Key] = { frame = card, buyBtn = buyBtn }
    end
end

-- ============================================================
-- CONSUMABLES TAB
-- ============================================================
function ShopScreen:_populateConsumables()
    local consumables = Shared.Shop.Consumables
    local data = self._playerData
    local playerCoins = (data and data.Currency and data.Currency.Coins) or 0
    local playerGems = (data and data.Currency and data.Currency.Gems) or 0

    for i, item in ipairs(consumables) do
        local isCoinItem = (item.CurrencyType == "Coins")
        local price = item.Cost
        local currencyIcon = isCoinItem and "🪙" or "💎"
        local canAfford = isCoinItem and (playerCoins >= price) or (playerGems >= price)

        local card = Instance.new("Frame")
        card.Name = "ConsumableCard_" .. item.Key
        card.Size = UDim2.new(1, -16, 0, 100)
        card.BackgroundColor3 = Palette.CardBg
        card.BackgroundTransparency = 0.2
        card.BorderSizePixel = 0
        card.ZIndex = 96
        card.Parent = self._contentScroll

        local cardCorner = Instance.new("UICorner")
        cardCorner.CornerRadius = UDim.new(0, 14)
        cardCorner.Parent = card

        local cardStroke = Instance.new("UIStroke")
        cardStroke.Color = Palette.PanelBorder
        cardStroke.Thickness = 1
        cardStroke.Transparency = 0.3
        cardStroke.Parent = card

        -- Item icon area
        local iconFrame = Instance.new("Frame")
        iconFrame.Name = "Icon"
        iconFrame.Size = UDim2.new(0, 64, 0, 64)
        iconFrame.Position = UDim2.new(0, 14, 0.5, -32)
        iconFrame.BackgroundColor3 = Palette.Background
        iconFrame.BackgroundTransparency = 0.3
        iconFrame.BorderSizePixel = 0
        iconFrame.ZIndex = 97
        iconFrame.Parent = card

        local iconCorner = Instance.new("UICorner")
        iconCorner.CornerRadius = UDim.new(0, 12)
        iconCorner.Parent = iconFrame

        local iconLabel = Instance.new("TextLabel")
        iconLabel.Size = UDim2.new(1, 0, 1, 0)
        iconLabel.BackgroundTransparency = 1
        iconLabel.Font = Enum.Font.Gotham
        iconLabel.TextSize = 28
        iconLabel.Text = isCoinItem and "🎣" or "✨"
        iconLabel.ZIndex = 97
        iconLabel.Parent = iconFrame

        -- Name
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "ItemName"
        nameLabel.Size = UDim2.new(0, 200, 0, 24)
        nameLabel.Position = UDim2.new(0, 90, 0, 12)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextSize = 16
        nameLabel.Text = item.Name
        nameLabel.TextColor3 = Palette.TextPrimary
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.ZIndex = 97
        nameLabel.Parent = card

        -- Effect description
        local effectText = self:_describeEffect(item)
        local effectLabel = Instance.new("TextLabel")
        effectLabel.Name = "Effect"
        effectLabel.Size = UDim2.new(0, 250, 0, 20)
        effectLabel.Position = UDim2.new(0, 90, 0, 38)
        effectLabel.BackgroundTransparency = 1
        effectLabel.Font = Enum.Font.Gotham
        effectLabel.TextSize = 12
        effectLabel.Text = effectText
        effectLabel.TextColor3 = Palette.TextSecondary
        effectLabel.TextXAlignment = Enum.TextXAlignment.Left
        effectLabel.ZIndex = 97
        effectLabel.Parent = card

        -- Quantity selector
        local qtyLabel = Instance.new("TextLabel")
        qtyLabel.Name = "QtyLabel"
        qtyLabel.Size = UDim2.new(0, 60, 0, 24)
        qtyLabel.Position = UDim2.new(0, 90, 0, 62)
        qtyLabel.BackgroundTransparency = 1
        qtyLabel.Font = Enum.Font.GothamBold
        qtyLabel.TextSize = 14
        qtyLabel.Text = "x1"
        qtyLabel.TextColor3 = Palette.TextPrimary
        qtyLabel.TextXAlignment = Enum.TextXAlignment.Left
        qtyLabel.ZIndex = 97
        qtyLabel.Parent = card

        local minusBtn = Instance.new("TextButton")
        minusBtn.Name = "MinusBtn"
        minusBtn.Size = UDim2.new(0, 28, 0, 28)
        minusBtn.Position = UDim2.new(0, 160, 0, 60)
        minusBtn.BackgroundColor3 = Palette.TabInactive
        minusBtn.Text = "−"
        minusBtn.Font = Enum.Font.GothamBold
        minusBtn.TextSize = 18
        minusBtn.TextColor3 = Palette.TextPrimary
        minusBtn.ZIndex = 97
        minusBtn.Parent = card

        local minusCorner = Instance.new("UICorner")
        minusCorner.CornerRadius = UDim.new(0, 6)
        minusCorner.Parent = minusBtn

        local plusBtn = Instance.new("TextButton")
        plusBtn.Name = "PlusBtn"
        plusBtn.Size = UDim2.new(0, 28, 0, 28)
        plusBtn.Position = UDim2.new(0, 192, 0, 60)
        plusBtn.BackgroundColor3 = Palette.TabInactive
        plusBtn.Text = "+"
        plusBtn.Font = Enum.Font.GothamBold
        plusBtn.TextSize = 18
        plusBtn.TextColor3 = Palette.TextPrimary
        plusBtn.ZIndex = 97
        plusBtn.Parent = card

        local plusCorner = Instance.new("UICorner")
        plusCorner.CornerRadius = UDim.new(0, 6)
        plusCorner.Parent = plusBtn

        local currentQty = 1

        minusBtn.MouseButton1Click:Connect(function()
            currentQty = math.max(1, currentQty - 1)
            qtyLabel.Text = "x" .. tostring(currentQty)
            buyBtn.Text = currencyIcon .. " " .. tostring(price * currentQty)
        end)

        plusBtn.MouseButton1Click:Connect(function()
            currentQty = math.min(99, currentQty + 1)
            qtyLabel.Text = "x" .. tostring(currentQty)
            buyBtn.Text = currencyIcon .. " " .. tostring(price * currentQty)
        end)

        -- Buy button
        local buyBtn = Instance.new("TextButton")
        buyBtn.Name = "BuyBtn"
        buyBtn.Size = UDim2.new(0, 120, 0, 38)
        buyBtn.Position = UDim2.new(1, -134, 1, -48)
        buyBtn.BackgroundColor3 = canAfford and Palette.ButtonPrimary or Palette.Red
        buyBtn.Text = currencyIcon .. " " .. tostring(price)
        buyBtn.Font = Enum.Font.GothamBold
        buyBtn.TextSize = 14
        buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        buyBtn.ZIndex = 97
        buyBtn.Parent = card

        local buyCorner = Instance.new("UICorner")
        buyCorner.CornerRadius = UDim.new(0, 8)
        buyCorner.Parent = buyBtn

        buyBtn.MouseButton1Click:Connect(function()
            local totalCost = price * currentQty
            self:_showConfirmDialog("consumable", item, totalCost, item.CurrencyType, currentQty)
        end)

        self._consumableCards[item.Key] = {
            frame = card,
            qtyLabel = qtyLabel,
            buyBtn = buyBtn,
            currentQty = function() return currentQty end,
        }
    end
end

-- ============================================================
-- GAMEPASSES TAB
-- ============================================================
function ShopScreen:_populateGamepasses()
    -- Gamepasses defined per task spec, aligned with monetization analysis
    local gamepasses = {
        {
            Name = "2× Luck Pass",
            Key = "DoubleLuck",
            Price = 399,
            Currency = "Robux",
            Icon = "🍀",
            Description = "Permanently doubles your luck bonus. Rare and legendary fish appear more often.",
            Color = Palette.Gold,
        },
        {
            Name = "VIP Diver Pass",
            Key = "VIPDiver",
            Price = 999,
            Currency = "Robux",
            Icon = "👑",
            Description = "Permanent +10% luck, exclusive VIP rod skin, +30s oxygen on all suits, and 100 monthly gems.",
            Color = Palette.Accent,
        },
        {
            Name = "Starter Bait Pack",
            Key = "StarterBait",
            Price = 49,
            Currency = "Robux",
            Icon = "🎁",
            Description = "Jump-start your adventure! Includes 5 bait bundles and 50 bonus coins.",
            Color = Palette.Green,
        },
    }

    for i, pass in ipairs(gamepasses) do
        local card = Instance.new("Frame")
        card.Name = "GamepassCard_" .. pass.Key
        card.Size = UDim2.new(1, -16, 0, 130)
        card.BackgroundColor3 = Palette.CardBg
        card.BackgroundTransparency = 0.2
        card.BorderSizePixel = 0
        card.ZIndex = 96
        card.Parent = self._contentScroll

        local cardCorner = Instance.new("UICorner")
        cardCorner.CornerRadius = UDim.new(0, 14)
        cardCorner.Parent = card

        local cardStroke = Instance.new("UIStroke")
        cardStroke.Color = pass.Color
        cardStroke.Thickness = 1.5
        cardStroke.Transparency = 0.3
        cardStroke.Parent = card

        -- Icon
        local iconFrame = Instance.new("Frame")
        iconFrame.Name = "Icon"
        iconFrame.Size = UDim2.new(0, 70, 0, 70)
        iconFrame.Position = UDim2.new(0, 16, 0.5, -35)
        iconFrame.BackgroundColor3 = pass.Color
        iconFrame.BackgroundTransparency = 0.7
        iconFrame.BorderSizePixel = 0
        iconFrame.ZIndex = 97
        iconFrame.Parent = card

        local iconCorner = Instance.new("UICorner")
        iconCorner.CornerRadius = UDim.new(0, 16)
        iconCorner.Parent = iconFrame

        local iconLabel = Instance.new("TextLabel")
        iconLabel.Size = UDim2.new(1, 0, 1, 0)
        iconLabel.BackgroundTransparency = 1
        iconLabel.Font = Enum.Font.Gotham
        iconLabel.TextSize = 36
        iconLabel.Text = pass.Icon
        iconLabel.ZIndex = 97
        iconLabel.Parent = iconFrame

        -- Name
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "PassName"
        nameLabel.Size = UDim2.new(0, 250, 0, 26)
        nameLabel.Position = UDim2.new(0, 100, 0, 14)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextSize = 18
        nameLabel.Text = pass.Name
        nameLabel.TextColor3 = pass.Color
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.ZIndex = 97
        nameLabel.Parent = card

        -- Description
        local descLabel = Instance.new("TextLabel")
        descLabel.Name = "Description"
        descLabel.Size = UDim2.new(1, -120, 0, 44)
        descLabel.Position = UDim2.new(0, 100, 0, 44)
        descLabel.BackgroundTransparency = 1
        descLabel.Font = Enum.Font.Gotham
        descLabel.TextSize = 12
        descLabel.Text = pass.Description
        descLabel.TextColor3 = Palette.TextSecondary
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.TextWrapped = true
        descLabel.ZIndex = 97
        descLabel.Parent = card

        -- Buy button (Robux)
        local buyBtn = Instance.new("TextButton")
        buyBtn.Name = "BuyBtn"
        buyBtn.Size = UDim2.new(0, 140, 0, 42)
        buyBtn.Position = UDim2.new(1, -156, 1, -56)
        buyBtn.BackgroundColor3 = Palette.RobuxGreen
        buyBtn.Text = "R$ " .. tostring(pass.Price)
        buyBtn.Font = Enum.Font.GothamBold
        buyBtn.TextSize = 16
        buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        buyBtn.ZIndex = 97
        buyBtn.Parent = card

        local buyCorner = Instance.new("UICorner")
        buyCorner.CornerRadius = UDim.new(0, 10)
        buyCorner.Parent = buyBtn

        -- Robux icon
        local robuxIcon = Instance.new("TextLabel")
        robuxIcon.Name = "RobuxIcon"
        robuxIcon.Size = UDim2.new(0, 24, 0, 24)
        robuxIcon.Position = UDim2.new(0, 14, 0.5, -12)
        robuxIcon.BackgroundTransparency = 1
        robuxIcon.Font = Enum.Font.Gotham
        robuxIcon.TextSize = 18
        robuxIcon.Text = "R$"
        robuxIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
        robuxIcon.ZIndex = 98
        robuxIcon.Parent = buyBtn

        buyBtn.MouseButton1Click:Connect(function()
            self:_showConfirmDialog("gamepass", pass, pass.Price, "Robux")
        end)

        self._gamepassCards[pass.Key] = { frame = card, buyBtn = buyBtn }
    end
end

-- ============================================================
-- Confirmation dialog
-- ============================================================
function ShopScreen:_showConfirmDialog(itemType, item, cost, currency, quantity)
    quantity = quantity or 1

    local name = item.Name or item.name or item
    local currencySymbol = ""
    if currency == "Coins" then
        currencySymbol = "🪙"
    elseif currency == "Gems" then
        currencySymbol = "💎"
    elseif currency == "Robux" then
        currencySymbol = "R$"
    end

    local totalCost = cost * quantity
    local qtyStr = quantity > 1 and (" × " .. tostring(quantity)) or ""
    local message = string.format("Buy %s%s for %s %d?", name, qtyStr, currencySymbol, totalCost)

    self._dialogTitleLabel.Text = "Confirm Purchase"
    self._dialogMsgLabel.Text = message

    -- Wire confirm button
    self._confirmBtn.MouseButton1Click:Once(function()
        self:_executePurchase(itemType, item, totalCost, currency, quantity)
        self:_hideConfirmDialog()
    end)

    -- Show with animation
    self._dimOverlay.Visible = true
    self._confirmDialog.Visible = true

    -- Fade in dim overlay
    TweenService:Create(self._dimOverlay,
        TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { BackgroundTransparency = 0.5 }
    ):Play()

    -- Pop-in dialog
    self._confirmDialog.Size = UDim2.new(0.7, 0, 0, 160)
    TweenService:Create(self._confirmDialog,
        TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Size = UDim2.new(0.7, 0, 0, 180) }
    ):Play()
end

function ShopScreen:_hideConfirmDialog()
    if not self._confirmDialog.Visible then return end

    TweenService:Create(self._dimOverlay,
        TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { BackgroundTransparency = 1 }
    ):Play()

    self._confirmDialog.Visible = false
    self._dimOverlay.Visible = false
end

-- ============================================================
-- Execute purchase
-- ============================================================
function ShopScreen:_executePurchase(itemType, item, cost, currency, quantity)
    -- This is called after confirmation. In MVP, we signal the
    -- EconomyService to process the purchase. The actual transaction
    -- happens server-side; we just fire the request here.
    print(string.format("[ShopScreen] Purchase: %s (%d %s)", tostring(item.Name or item.Key), cost, currency))

    -- TODO: Wire to EconomyService.Client.BuyItem
    -- For now, the UIController will handle this via OnBuyClicked
    if self._onPurchaseCallback then
        self._onPurchaseCallback(itemType, item, cost, currency, quantity)
    end
end

-- ============================================================
-- Helper: Check if rod is owned
-- ============================================================
function ShopScreen:_isRodOwned(rod)
    if rod.Tier == 1 then return true end -- starter rod always owned
    if not self._playerData or not self._playerData.Gear then return false end
    local ownedRods = self._playerData.Gear.OwnedRods or {}
    for _, key in ipairs(ownedRods) do
        if key == rod.Key then return true end
    end
    return false
end

-- ============================================================
-- Helper: Check if rod is level-locked
-- ============================================================
function ShopScreen:_isRodLocked(rod)
    if not rod.UnlockRequirement then return false end
    if not self._playerData then return true end

    local req = rod.UnlockRequirement
    if req.Type == "TotalCatches" then
        local totalCatches = self:_getTotalCatches()
        return totalCatches < req.Count
    elseif req.Type == "RareCatches" then
        local rareCatches = self:_getRareCatches()
        return rareCatches < req.Count
    elseif req.Type == "CollectionComplete" then
        return not self:_isCollectionComplete(req.Zone)
    elseif req.Type == "DepthReached" then
        return true -- future zone, always locked in MVP
    end

    return false
end

function ShopScreen:_getTotalCatches()
    local count = 0
    if self._playerData and self._playerData.CollectionLog and self._playerData.CollectionLog.Species then
        for _, log in pairs(self._playerData.CollectionLog.Species) do
            count = count + (log.Count or 0)
        end
    end
    return count
end

function ShopScreen:_getRareCatches()
    local count = 0
    if self._playerData and self._playerData.CollectionLog and self._playerData.CollectionLog.Species then
        for key, log in pairs(self._playerData.CollectionLog.Species) do
            if log.Caught then
                local species = Shared.Constants.FishSpecies.GetByKey(key)
                if species and species.Rarity == "Rare" then
                    count = count + (log.Count or 0)
                end
            end
        end
    end
    return count
end

function ShopScreen:_isCollectionComplete(zoneKey)
    -- MVP: all 5 species in Sunken Shallows
    if not self._playerData or not self._playerData.CollectionLog or not self._playerData.CollectionLog.Species then
        return false
    end
    local speciesList = Shared.Constants.FishSpecies
    for _, s in ipairs(speciesList) do
        local log = self._playerData.CollectionLog.Species[s.Key]
        if not log or not log.Caught then
            return false
        end
    end
    return true
end

-- ============================================================
-- Equip rod
-- ============================================================
function ShopScreen:_equipRod(rod)
    self._equippedRodKey = rod.Key
    print("[ShopScreen] Equipping rod:", rod.Name)
    -- Signal to EconomyService
    if self._onEquipCallback then
        self._onEquipCallback(rod.Key)
    end
    -- Refresh display
    self:_switchTab("Rods")
    self:_updateCurrencyDisplay()
end

-- ============================================================
-- Helper: Describe consumable effect
-- ============================================================
function ShopScreen:_describeEffect(item)
    if item.Effect.LuckBonus then
        return "+" .. tostring(math.floor(item.Effect.LuckBonus * 100)) .. "% luck for all nearby players"
    elseif item.Effect.OxygenRefill then
        return "Instantly refills oxygen to 100%"
    elseif item.Effect.BiteSpeedBonus then
        return "Fish bite " .. tostring(math.floor(item.Effect.BiteSpeedBonus * 100)) .. "% faster (" .. tostring(item.Uses or 5) .. " uses)"
    elseif item.Effect.RevealChest then
        return "Reveals a hidden treasure chest location"
    end
    return ""
end

-- ============================================================
-- Callbacks for UIController
-- ============================================================
function ShopScreen:SetPurchaseCallback(cb)
    self._onPurchaseCallback = cb
end

function ShopScreen:SetEquipCallback(cb)
    self._onEquipCallback = cb
end

-- ============================================================
-- Cleanup
-- ============================================================
function ShopScreen:IsOpen()
    return self._isOpen
end

function ShopScreen:Destroy()
    if self._backdrop then
        self._backdrop:Destroy()
        self._backdrop = nil
    end
end

return ShopScreen
