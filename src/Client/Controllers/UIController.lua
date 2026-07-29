--[[
    UIController.lua
    Deep Tide Studios — Client Controller
    Manages all game UI: persistent HUD overlay, fishing UI (via FishingHUD),
    shop screen, collection book, and screen state transitions.

    HUD Overlay (always visible):
      - Top bar: coins, gems, settings button
      - Oxygen gauge (circular, red flash at <25%)
      - Depth meter (color-coded by zone)
      - Equipped rod name display
      - Collection book & shop quick-access buttons

    Keyboard shortcuts:
      - B = Toggle collection book
      - S = Toggle shop
      - ESC = Close all overlays

    Integrates with FishingHUD.lua (does NOT break it).
]]

local Knit = require(game:GetService("ReplicatedStorage"):WaitForChild("Knit"))
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))

local CollectionBook = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("CollectionBook"))
local ShopScreen = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("ShopScreen"))

local UIController = Knit.CreateController({
    Name = "UIController",
})

-- ============================================================
-- Color palette (matches CollectionBook & ShopScreen themes)
-- ============================================================
local Palette = {
    Background = Color3.fromRGB(8, 14, 28),
    PanelBg = Color3.fromRGB(10, 18, 36),
    PanelBorder = Color3.fromRGB(40, 100, 160),
    TextPrimary = Color3.fromRGB(220, 235, 255),
    TextSecondary = Color3.fromRGB(140, 175, 210),
    Accent = Color3.fromRGB(60, 200, 220),
    Gold = Color3.fromRGB(255, 200, 50),
    Red = Color3.fromRGB(255, 70, 70),
    Green = Color3.fromRGB(80, 220, 80),
    OxygenCyan = Color3.fromRGB(40, 220, 240),
    OxygenRed = Color3.fromRGB(255, 50, 50),
    DepthShallow = Color3.fromRGB(100, 200, 255),
    DepthMid = Color3.fromRGB(60, 140, 220),
    DepthDeep = Color3.fromRGB(30, 80, 180),
    ButtonBg = Color3.fromRGB(16, 30, 52),
    ButtonHover = Color3.fromRGB(30, 60, 100),
}

-- ============================================================
-- UI State
-- ============================================================
UIController._activeScreen = "HUD" -- HUD | Shop | CollectionLog | Settings
UIController._playerData = nil
UIController._equippedRodKey = "BambooRod"

-- ============================================================
-- Lifecycle: KnitStart
-- ============================================================
function UIController:KnitStart()
    print("[UIController] Started")

    -- Listen for player data updates
    local playerDataService = self.Services.PlayerDataService
    if playerDataService and playerDataService.Client then
        playerDataService.Client.DataUpdated:Connect(function(data)
            self._playerData = data
            self:_refreshHUD()
            self:_refreshActiveOverlay()
        end)

        playerDataService.Client.GetPlayerData:Connect(function(data)
            self._playerData = data
            self:_refreshHUD()
            self:_refreshActiveOverlay()
        end)
    end

    -- Request initial data
    task.spawn(function()
        local player = Players.LocalPlayer
        if self.Services.PlayerDataService and self.Services.PlayerDataService.Client then
            local data = self.Services.PlayerDataService.Client.GetPlayerData:Call(player)
            if data then
                self._playerData = data
                self:_refreshHUD()
            end
        end
    end)

    -- Start oxygen update loop
    self:_startOxygenLoop()
end

-- ============================================================
-- Lifecycle: KnitInit — create all UI
-- ============================================================
function UIController:KnitInit()
    -- Initialize persistent HUD
    self:_createPersistentHUD()

    -- Initialize overlay screens
    self._collectionBook = CollectionBook.new()
    self._shopScreen = ShopScreen.new()

    -- Wire purchase/equip callbacks from ShopScreen
    self._shopScreen:SetPurchaseCallback(function(itemType, item, cost, currency, quantity)
        self:OnBuyClicked(itemType, item, cost, currency, quantity)
    end)
    self._shopScreen:SetEquipCallback(function(rodKey)
        self:_onRodEquipped(rodKey)
    end)

    -- Wire keyboard input
    self:_wireKeyboardShortcuts()
end

-- ============================================================
-- PERSISTENT HUD OVERLAY
-- ============================================================

function UIController:_createPersistentHUD()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    local gui = playerGui:FindFirstChild("DeepTideUI")
    if not gui then
        gui = Instance.new("ScreenGui")
        gui.Name = "DeepTideUI"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.Parent = playerGui
    end
    self._hudGui = gui

    -- ---- TOP BAR ----
    self:_createTopBar(gui)

    -- ---- OXYGEN GAUGE (bottom-center) ----
    self:_createOxygenGauge(gui)

    -- ---- DEPTH METER (right side) ----
    self:_createDepthMeter(gui)

    -- ---- EQUIPPED ROD DISPLAY (top-left below currency) ----
    self:_createRodDisplay(gui)

    -- ---- QUICK-ACCESS BUTTONS (bottom-right area) ----
    self:_createQuickButtons(gui)

    print("[UIController] Persistent HUD created")
end

-- ============================================================
-- Top Bar: coin counter, gem counter, settings
-- ============================================================
function UIController:_createTopBar(parent)
    local topBar = Instance.new("Frame")
    topBar.Name = "HUDTopBar"
    topBar.Size = UDim2.new(0, 340, 0, 48)
    topBar.Position = UDim2.new(0, 12, 0, 12)
    topBar.BackgroundColor3 = Palette.PanelBg
    topBar.BackgroundTransparency = 0.25
    topBar.BorderSizePixel = 0
    topBar.ZIndex = 10
    topBar.Parent = parent

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 12)
    barCorner.Parent = topBar

    local barStroke = Instance.new("UIStroke")
    barStroke.Color = Palette.PanelBorder
    barStroke.Thickness = 1
    barStroke.Transparency = 0.5
    barStroke.Parent = topBar

    -- Coin display
    local coinFrame = Instance.new("Frame")
    coinFrame.Name = "CoinFrame"
    coinFrame.Size = UDim2.new(0, 100, 1, -8)
    coinFrame.Position = UDim2.new(0, 8, 0, 4)
    coinFrame.BackgroundTransparency = 1
    coinFrame.ZIndex = 11
    coinFrame.Parent = topBar

    local coinIcon = Instance.new("TextLabel")
    coinIcon.Name = "CoinIcon"
    coinIcon.Size = UDim2.new(0, 24, 0, 24)
    coinIcon.Position = UDim2.new(0, 0, 0.5, -12)
    coinIcon.BackgroundTransparency = 1
    coinIcon.Font = Enum.Font.Gotham
    coinIcon.TextSize = 18
    coinIcon.Text = "🪙"
    coinIcon.ZIndex = 11
    coinIcon.Parent = coinFrame

    local coinLabel = Instance.new("TextLabel")
    coinLabel.Name = "CoinLabel"
    coinLabel.Size = UDim2.new(1, -28, 0, 24)
    coinLabel.Position = UDim2.new(0, 26, 0.5, -12)
    coinLabel.BackgroundTransparency = 1
    coinLabel.Font = Enum.Font.GothamBold
    coinLabel.TextSize = 15
    coinLabel.Text = "0"
    coinLabel.TextColor3 = Palette.Gold
    coinLabel.TextXAlignment = Enum.TextXAlignment.Left
    coinLabel.ZIndex = 11
    coinLabel.Parent = coinFrame
    self._hudCoinLabel = coinLabel

    -- Separator
    local sep1 = Instance.new("Frame")
    sep1.Name = "Separator"
    sep1.Size = UDim2.new(0, 1, 0, 28)
    sep1.Position = UDim2.new(0, 112, 0.5, -14)
    sep1.BackgroundColor3 = Palette.PanelBorder
    sep1.BackgroundTransparency = 0.5
    sep1.BorderSizePixel = 0
    sep1.ZIndex = 11
    sep1.Parent = topBar

    -- Gem display
    local gemFrame = Instance.new("Frame")
    gemFrame.Name = "GemFrame"
    gemFrame.Size = UDim2.new(0, 100, 1, -8)
    gemFrame.Position = UDim2.new(0, 118, 0, 4)
    gemFrame.BackgroundTransparency = 1
    gemFrame.ZIndex = 11
    gemFrame.Parent = topBar

    local gemIcon = Instance.new("TextLabel")
    gemIcon.Name = "GemIcon"
    gemIcon.Size = UDim2.new(0, 24, 0, 24)
    gemIcon.Position = UDim2.new(0, 0, 0.5, -12)
    gemIcon.BackgroundTransparency = 1
    gemIcon.Font = Enum.Font.Gotham
    gemIcon.TextSize = 18
    gemIcon.Text = "💎"
    gemIcon.ZIndex = 11
    gemIcon.Parent = gemFrame

    local gemLabel = Instance.new("TextLabel")
    gemLabel.Name = "GemLabel"
    gemLabel.Size = UDim2.new(1, -28, 0, 24)
    gemLabel.Position = UDim2.new(0, 26, 0.5, -12)
    gemLabel.BackgroundTransparency = 1
    gemLabel.Font = Enum.Font.GothamBold
    gemLabel.TextSize = 15
    gemLabel.Text = "0"
    gemLabel.TextColor3 = Palette.Accent
    gemLabel.TextXAlignment = Enum.TextXAlignment.Left
    gemLabel.ZIndex = 11
    gemLabel.Parent = gemFrame
    self._hudGemLabel = gemLabel

    -- Settings gear button (right side of top bar)
    local settingsBtn = Instance.new("TextButton")
    settingsBtn.Name = "SettingsBtn"
    settingsBtn.Size = UDim2.new(0, 36, 0, 36)
    settingsBtn.Position = UDim2.new(1, -42, 0.5, -18)
    settingsBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    settingsBtn.BackgroundTransparency = 0.85
    settingsBtn.Text = "⚙️"
    settingsBtn.Font = Enum.Font.Gotham
    settingsBtn.TextSize = 20
    settingsBtn.ZIndex = 11
    settingsBtn.Parent = topBar

    settingsBtn.MouseButton1Click:Connect(function()
        self:_openSettings()
    end)

    self._hudTopBar = topBar
end

-- ============================================================
-- Oxygen Gauge: circular, depletes clockwise, red flash <25%
-- ============================================================
function UIController:_createOxygenGauge(parent)
    local gaugeSize = 80

    local gaugeFrame = Instance.new("Frame")
    gaugeFrame.Name = "OxygenGauge"
    gaugeFrame.Size = UDim2.new(0, gaugeSize + 16, 0, gaugeSize + 16)
    gaugeFrame.Position = UDim2.new(0.5, -(gaugeSize + 16) / 2, 1, -(gaugeSize + 40))
    gaugeFrame.BackgroundColor3 = Palette.PanelBg
    gaugeFrame.BackgroundTransparency = 0.25
    gaugeFrame.BorderSizePixel = 0
    gaugeFrame.ZIndex = 10
    gaugeFrame.Parent = parent

    local gaugeCorner = Instance.new("UICorner")
    gaugeCorner.CornerRadius = UDim.new(1, 0)
    gaugeCorner.Parent = gaugeFrame

    local gaugeStroke = Instance.new("UIStroke")
    gaugeStroke.Color = Palette.PanelBorder
    gaugeStroke.Thickness = 1
    gaugeStroke.Transparency = 0.5
    gaugeStroke.Parent = gaugeFrame

    -- Background ring
    local bgRing = Instance.new("Frame")
    bgRing.Name = "BgRing"
    bgRing.Size = UDim2.new(0, gaugeSize, 0, gaugeSize)
    bgRing.Position = UDim2.new(0, 8, 0, 8)
    bgRing.BackgroundTransparency = 1
    bgRing.ZIndex = 11
    bgRing.Parent = gaugeFrame

    local bgRingCorner = Instance.new("UICorner")
    bgRingCorner.CornerRadius = UDim.new(1, 0)
    bgRingCorner.Parent = bgRing

    local bgRingStroke = Instance.new("UIStroke")
    bgRingStroke.Name = "BgRingStroke"
    bgRingStroke.Color = Color3.fromRGB(30, 50, 70)
    bgRingStroke.Thickness = 4
    bgRingStroke.Transparency = 0.3
    bgRingStroke.Parent = bgRing

    -- Fill ring (uses a Frame with UICorner + UIStroke as the fill arc — we'll use simple % text + color for MVP)
    -- For a proper circular gauge, we'd use ImageLabels; for MVP, we use a text-based approach
    -- with the frame's background serving as the gauge fill indicator
    local fillIndicator = Instance.new("Frame")
    fillIndicator.Name = "FillIndicator"
    fillIndicator.Size = UDim2.new(0, gaugeSize - 8, 0, 20)
    fillIndicator.Position = UDim2.new(0, 4, 0, gaugeSize - 8)
    fillIndicator.BackgroundColor3 = Palette.OxygenCyan
    fillIndicator.BackgroundTransparency = 0
    fillIndicator.BorderSizePixel = 0
    fillIndicator.ZIndex = 12
    fillIndicator.Parent = gaugeFrame

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 6)
    fillCorner.Parent = fillIndicator
    self._oxygenFill = fillIndicator

    -- Oxygen percentage text
    local oxygenPercent = Instance.new("TextLabel")
    oxygenPercent.Name = "OxygenPercent"
    oxygenPercent.Size = UDim2.new(0, gaugeSize, 0, 22)
    oxygenPercent.Position = UDim2.new(0, 8, 0, 22)
    oxygenPercent.BackgroundTransparency = 1
    oxygenPercent.Font = Enum.Font.GothamBold
    oxygenPercent.TextSize = 18
    oxygenPercent.Text = "100%"
    oxygenPercent.TextColor3 = Palette.OxygenCyan
    oxygenPercent.ZIndex = 12
    oxygenPercent.Parent = gaugeFrame
    self._oxygenPercentLabel = oxygenPercent

    -- "O₂" label
    local o2Label = Instance.new("TextLabel")
    o2Label.Name = "O2Label"
    o2Label.Size = UDim2.new(0, gaugeSize, 0, 16)
    o2Label.Position = UDim2.new(0, 8, 0, 45)
    o2Label.BackgroundTransparency = 1
    o2Label.Font = Enum.Font.Gotham
    o2Label.TextSize = 11
    o2Label.Text = "OXYGEN"
    o2Label.TextColor3 = Palette.TextSecondary
    o2Label.ZIndex = 12
    o2Label.Parent = gaugeFrame

    self._oxygenGaugeFrame = gaugeFrame
    self._oxygenFlashConnection = nil
    self._currentOxygenPercent = 100
end

-- ============================================================
-- Depth Meter: right side, color-coded by zone
-- ============================================================
function UIController:_createDepthMeter(parent)
    local depthFrame = Instance.new("Frame")
    depthFrame.Name = "DepthMeter"
    depthFrame.Size = UDim2.new(0, 60, 0, 80)
    depthFrame.Position = UDim2.new(1, -72, 0.5, -40)
    depthFrame.BackgroundColor3 = Palette.PanelBg
    depthFrame.BackgroundTransparency = 0.25
    depthFrame.BorderSizePixel = 0
    depthFrame.ZIndex = 10
    depthFrame.Parent = parent

    local depthCorner = Instance.new("UICorner")
    depthCorner.CornerRadius = UDim.new(0, 12)
    depthCorner.Parent = depthFrame

    local depthStroke = Instance.new("UIStroke")
    depthStroke.Color = Palette.PanelBorder
    depthStroke.Thickness = 1
    depthStroke.Transparency = 0.5
    depthStroke.Parent = depthFrame

    -- Depth value
    local depthValue = Instance.new("TextLabel")
    depthValue.Name = "DepthValue"
    depthValue.Size = UDim2.new(1, 0, 0, 28)
    depthValue.Position = UDim2.new(0, 0, 0, 8)
    depthValue.BackgroundTransparency = 1
    depthValue.Font = Enum.Font.GothamBold
    depthValue.TextSize = 22
    depthValue.Text = "0"
    depthValue.TextColor3 = Palette.DepthShallow
    depthValue.ZIndex = 11
    depthValue.Parent = depthFrame
    self._depthValueLabel = depthValue

    -- "m" label
    local depthUnit = Instance.new("TextLabel")
    depthUnit.Name = "DepthUnit"
    depthUnit.Size = UDim2.new(1, 0, 0, 16)
    depthUnit.Position = UDim2.new(0, 0, 0, 36)
    depthUnit.BackgroundTransparency = 1
    depthUnit.Font = Enum.Font.Gotham
    depthUnit.TextSize = 12
    depthUnit.Text = "METERS"
    depthUnit.TextColor3 = Palette.TextSecondary
    depthUnit.ZIndex = 11
    depthUnit.Parent = depthFrame

    -- Zone name
    local zoneLabel = Instance.new("TextLabel")
    zoneLabel.Name = "ZoneLabel"
    zoneLabel.Size = UDim2.new(1, 0, 0, 16)
    zoneLabel.Position = UDim2.new(0, 0, 0, 54)
    zoneLabel.BackgroundTransparency = 1
    zoneLabel.Font = Enum.Font.Gotham
    zoneLabel.TextSize = 10
    zoneLabel.Text = "SUNKEN SHALLOWS"
    zoneLabel.TextColor3 = Palette.DepthShallow
    zoneLabel.TextTruncate = Enum.TextTruncate.AtEnd
    zoneLabel.ZIndex = 11
    zoneLabel.Parent = depthFrame
    self._depthZoneLabel = zoneLabel

    self._depthMeterFrame = depthFrame
end

-- ============================================================
-- Equipped Rod Display
-- ============================================================
function UIController:_createRodDisplay(parent)
    local rodFrame = Instance.new("Frame")
    rodFrame.Name = "EquippedRod"
    rodFrame.Size = UDim2.new(0, 180, 0, 30)
    rodFrame.Position = UDim2.new(0, 12, 0, 68)
    rodFrame.BackgroundColor3 = Palette.PanelBg
    rodFrame.BackgroundTransparency = 0.25
    rodFrame.BorderSizePixel = 0
    rodFrame.ZIndex = 10
    rodFrame.Parent = parent

    local rodCorner = Instance.new("UICorner")
    rodCorner.CornerRadius = UDim.new(0, 8)
    rodCorner.Parent = rodFrame

    local rodStroke = Instance.new("UIStroke")
    rodStroke.Color = Palette.PanelBorder
    rodStroke.Thickness = 1
    rodStroke.Transparency = 0.5
    rodStroke.Parent = rodFrame

    local rodIcon = Instance.new("TextLabel")
    rodIcon.Name = "RodIcon"
    rodIcon.Size = UDim2.new(0, 24, 0, 24)
    rodIcon.Position = UDim2.new(0, 4, 0.5, -12)
    rodIcon.BackgroundTransparency = 1
    rodIcon.Font = Enum.Font.Gotham
    rodIcon.TextSize = 16
    rodIcon.Text = "🎣"
    rodIcon.ZIndex = 11
    rodIcon.Parent = rodFrame

    local rodLabel = Instance.new("TextLabel")
    rodLabel.Name = "RodLabel"
    rodLabel.Size = UDim2.new(1, -32, 0, 24)
    rodLabel.Position = UDim2.new(0, 28, 0.5, -12)
    rodLabel.BackgroundTransparency = 1
    rodLabel.Font = Enum.Font.Gotham
    rodLabel.TextSize = 13
    rodLabel.Text = "Bamboo Rod"
    rodLabel.TextColor3 = Palette.TextPrimary
    rodLabel.TextXAlignment = Enum.TextXAlignment.Left
    rodLabel.ZIndex = 11
    rodLabel.Parent = rodFrame
    self._hudRodLabel = rodLabel

    self._hudRodFrame = rodFrame
end

-- ============================================================
-- Quick-Access Buttons (Collection Book & Shop)
-- ============================================================
function UIController:_createQuickButtons(parent)
    -- Collection book button (bottom-right)
    local collectionBtn = Instance.new("TextButton")
    collectionBtn.Name = "CollectionBookBtn"
    collectionBtn.Size = UDim2.new(0, 52, 0, 52)
    collectionBtn.Position = UDim2.new(1, -128, 1, -64)
    collectionBtn.BackgroundColor3 = Palette.ButtonBg
    collectionBtn.BackgroundTransparency = 0.15
    collectionBtn.Text = "📖"
    collectionBtn.Font = Enum.Font.Gotham
    collectionBtn.TextSize = 24
    collectionBtn.ZIndex = 10
    collectionBtn.Parent = parent

    local collCorner = Instance.new("UICorner")
    collCorner.CornerRadius = UDim.new(0, 14)
    collCorner.Parent = collectionBtn

    local collStroke = Instance.new("UIStroke")
    collStroke.Color = Palette.PanelBorder
    collStroke.Thickness = 1.5
    collStroke.Transparency = 0.4
    collStroke.Parent = collectionBtn

    -- Label below
    local collLabel = Instance.new("TextLabel")
    collLabel.Name = "CollectionLabel"
    collLabel.Size = UDim2.new(0, 52, 0, 14)
    collLabel.Position = UDim2.new(1, -128, 1, -10)
    collLabel.BackgroundTransparency = 1
    collLabel.Font = Enum.Font.Gotham
    collLabel.TextSize = 9
    collLabel.Text = "Collection"
    collLabel.TextColor3 = Palette.TextSecondary
    collLabel.ZIndex = 10
    collLabel.Parent = parent

    collectionBtn.MouseButton1Click:Connect(function()
        self:ToggleCollectionBook()
    end)

    -- Shop button
    local shopBtn = Instance.new("TextButton")
    shopBtn.Name = "ShopBtn"
    shopBtn.Size = UDim2.new(0, 52, 0, 52)
    shopBtn.Position = UDim2.new(1, -68, 1, -64)
    shopBtn.BackgroundColor3 = Palette.ButtonBg
    shopBtn.BackgroundTransparency = 0.15
    shopBtn.Text = "🛒"
    shopBtn.Font = Enum.Font.Gotham
    shopBtn.TextSize = 24
    shopBtn.ZIndex = 10
    shopBtn.Parent = parent

    local shopCorner = Instance.new("UICorner")
    shopCorner.CornerRadius = UDim.new(0, 14)
    shopCorner.Parent = shopBtn

    local shopStroke = Instance.new("UIStroke")
    shopStroke.Color = Palette.PanelBorder
    shopStroke.Thickness = 1.5
    shopStroke.Transparency = 0.4
    shopStroke.Parent = shopBtn

    local shopLabel = Instance.new("TextLabel")
    shopLabel.Name = "ShopLabel"
    shopLabel.Size = UDim2.new(0, 52, 0, 14)
    shopLabel.Position = UDim2.new(1, -68, 1, -10)
    shopLabel.BackgroundTransparency = 1
    shopLabel.Font = Enum.Font.Gotham
    shopLabel.TextSize = 9
    shopLabel.Text = "Shop"
    shopLabel.TextColor3 = Palette.TextSecondary
    shopLabel.ZIndex = 10
    shopLabel.Parent = parent

    shopBtn.MouseButton1Click:Connect(function()
        self:ToggleShop()
    end)

    self._collectionBtn = collectionBtn
    self._shopBtn = shopBtn
end

-- ============================================================
-- Keyboard Shortcuts
-- ============================================================
function UIController:_wireKeyboardShortcuts()
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end

        if input.KeyCode == Enum.KeyCode.B then
            self:ToggleCollectionBook()
        elseif input.KeyCode == Enum.KeyCode.S then
            self:ToggleShop()
        elseif input.KeyCode == Enum.KeyCode.Escape then
            self:CloseAllScreens()
        end
    end)
end

-- ============================================================
-- Screen Management
-- ============================================================

function UIController:ToggleCollectionBook()
    if self._activeScreen == "CollectionLog" then
        self:CloseCollectionLog()
    else
        -- Close other overlays first
        if self._activeScreen == "Shop" then
            self:CloseShop()
        end
        self:OpenCollectionLog()
    end
end

function UIController:ToggleShop()
    if self._activeScreen == "Shop" then
        self:CloseShop()
    else
        if self._activeScreen == "CollectionLog" then
            self:CloseCollectionLog()
        end
        self:OpenShop()
    end
end

function UIController:CloseAllScreens()
    if self._activeScreen == "CollectionLog" then
        self:CloseCollectionLog()
    end
    if self._activeScreen == "Shop" then
        self:CloseShop()
    end
end

-- ============================================================
-- Open/Close: Collection Book
-- ============================================================
function UIController:OpenCollectionLog()
    if not self._collectionBook then return end
    self._activeScreen = "CollectionLog"
    self._collectionBook:Open(self._playerData, function()
        self._activeScreen = "HUD"
    end)
end

function UIController:CloseCollectionLog()
    if not self._collectionBook then return end
    self._collectionBook:Close()
    self._activeScreen = "HUD"
end

-- ============================================================
-- Open/Close: Shop
-- ============================================================
function UIController:OpenShop()
    if not self._shopScreen then return end
    self._activeScreen = "Shop"
    self._shopScreen:Open(self._playerData, function()
        self._activeScreen = "HUD"
    end)
end

function UIController:CloseShop()
    if not self._shopScreen then return end
    self._shopScreen:Close()
    self._activeScreen = "HUD"
end

-- ============================================================
-- Settings (stub — to be expanded)
-- ============================================================
function UIController:_openSettings()
    -- TODO: Settings panel (volume, accessibility, etc.)
    print("[UIController] Settings opened (stub)")
end

-- ============================================================
-- Oxygen Update Loop
-- ============================================================
function UIController:_startOxygenLoop()
    -- The actual oxygen value comes from the swimming system.
    -- We poll/update at 10 Hz.
    RunService.Heartbeat:Connect(function()
        -- Oxygen value is set externally by UpdateOxygen()
        -- This heartbeat just handles the red flash
        if self._currentOxygenPercent <= 25 and self._currentOxygenPercent > 0 then
            local flash = math.sin(tick() * 8) * 0.5 + 0.5 -- 0-1 pulsing
            if self._oxygenFill then
                self._oxygenFill.BackgroundColor3 = Palette.OxygenRed:Lerp(
                    Color3.fromRGB(255, 120, 120), flash
                )
            end
        end
    end)
end

--- Update oxygen display (called by swimming controller)
function UIController:UpdateOxygen(currentPercent)
    self._currentOxygenPercent = math.clamp(currentPercent, 0, 100)

    if not self._oxygenFill or not self._oxygenPercentLabel then return end

    -- Update fill bar width
    self._oxygenFill.Size = UDim2.new((currentPercent / 100), -8, 0, 20)

    -- Update text
    self._oxygenPercentLabel.Text = string.format("%d%%", math.floor(currentPercent))

    -- Color based on threshold
    if currentPercent > 25 then
        self._oxygenFill.BackgroundColor3 = Palette.OxygenCyan
        self._oxygenPercentLabel.TextColor3 = Palette.OxygenCyan
    elseif currentPercent > 0 then
        self._oxygenFill.BackgroundColor3 = Palette.OxygenRed
        self._oxygenPercentLabel.TextColor3 = Palette.OxygenRed
    else
        self._oxygenFill.BackgroundColor3 = Color3.fromRGB(180, 20, 20)
        self._oxygenPercentLabel.TextColor3 = Color3.fromRGB(255, 20, 20)
    end
end

-- ============================================================
-- Depth Meter Update
-- ============================================================
function UIController:UpdateDepth(depthMeters)
    if not self._depthValueLabel or not self._depthZoneLabel then return end

    self._depthValueLabel.Text = string.format("%.0f", depthMeters)

    -- Color by zone
    local zoneColor, zoneName
    if depthMeters <= 15 then
        zoneColor = Palette.DepthShallow
        zoneName = "CORAL GARDENS"
    elseif depthMeters <= 30 then
        zoneColor = Palette.DepthMid
        zoneName = "SANDY PLAINS"
    elseif depthMeters <= 45 then
        zoneColor = Palette.DepthDeep
        zoneName = "THE SHIPWRECK"
    else
        zoneColor = Color3.fromRGB(20, 50, 130)
        zoneName = "DEEP REEF EDGE"
    end

    self._depthValueLabel.TextColor3 = zoneColor
    self._depthZoneLabel.Text = zoneName
    self._depthZoneLabel.TextColor3 = zoneColor
end

-- ============================================================
-- Refresh HUD from player data
-- ============================================================
function UIController:_refreshHUD()
    if not self._playerData then return end
    local data = self._playerData

    -- Update currency display
    if self._hudCoinLabel then
        local coins = (data.Currency and data.Currency.Coins) or 0
        self._hudCoinLabel.Text = self:_formatNumber(coins)
    end

    if self._hudGemLabel then
        local gems = (data.Currency and data.Currency.Gems) or 0
        self._hudGemLabel.Text = self:_formatNumber(gems)
    end

    -- Update equipped rod display
    if data.Gear and data.Gear.EquippedRod then
        self._equippedRodKey = data.Gear.EquippedRod
        local rod = Shared.Constants.RodTiers.GetByKey(self._equippedRodKey)
        if rod and self._hudRodLabel then
            self._hudRodLabel.Text = rod.Name
        end
    end
end

-- ============================================================
-- Refresh active overlay (collection book or shop)
-- ============================================================
function UIController:_refreshActiveOverlay()
    if self._activeScreen == "CollectionLog" and self._collectionBook then
        self._collectionBook:Refresh(self._playerData)
    elseif self._activeScreen == "Shop" and self._shopScreen then
        self._shopScreen:Refresh(self._playerData)
    end
end

-- ============================================================
-- Helper: Format large numbers
-- ============================================================
function UIController:_formatNumber(num)
    if num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 10000 then
        return string.format("%.1fK", num / 1000)
    else
        return tostring(num)
    end
end

-- ============================================================
-- Rod equipped callback (from shop)
-- ============================================================
function UIController:_onRodEquipped(rodKey)
    self._equippedRodKey = rodKey
    local rod = Shared.Constants.RodTiers.GetByKey(rodKey)
    if rod and self._hudRodLabel then
        self._hudRodLabel.Text = rod.Name

        -- Brief highlight animation
        TweenService:Create(self._hudRodLabel,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextColor3 = Palette.Gold }
        ):Play()
        task.delay(1.5, function()
            if self._hudRodLabel then
                TweenService:Create(self._hudRodLabel,
                    TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    { TextColor3 = Palette.TextPrimary }
                ):Play()
            end
        end)
    end

    -- Notify server
    task.spawn(function()
        if self.Services.EconomyService and self.Services.EconomyService.Client then
            self.Services.EconomyService.Client.EquipRod:Call(rodKey)
        end
    end)
end

-- ============================================================
-- Buy Click Handler (called by shop screen)
-- ============================================================
function UIController:OnBuyClicked(itemType, item, cost, currency, quantity)
    quantity = quantity or 1
    print(string.format("[UIController] Buying: %s (%s) x%d = %d %s",
        tostring(item.Name or item.Key), itemType, quantity, cost, currency))

    -- Route to EconomyService
    task.spawn(function()
        local economyService = self.Services.EconomyService
        if economyService and economyService.Client then
            local result = economyService.Client.BuyItem:Call(item.Key or item, itemType, quantity)
            if result and result.Success then
                -- Refresh will come via DataUpdated event
                print("[UIController] Purchase successful")
            else
                warn("[UIController] Purchase failed:", result and result.Message or "unknown error")
            end
        end
    end)
end

-- ============================================================
-- Fish Showcase Popup (delegates to FishingHUD or own popup)
-- ============================================================
function UIController:ShowFishShowcase(fishData)
    -- For now, FishingHUD handles the showcase (rarity reveal).
    -- If we want a separate collection notification:
    if self._collectionBook then
        self._collectionBook:NotifyDiscovery(fishData, fishData.Weight)
    end
end

-- ============================================================
-- New discovery notification from collection
-- ============================================================
function UIController:NotifyFishDiscovery(fishData)
    if self._collectionBook then
        self._collectionBook:NotifyDiscovery(fishData, fishData.Weight)
    end
end

-- ============================================================
-- Fishing UI (delegates to FishingHUD — do NOT break this)
-- Existing stubs are preserved for backward compatibility.
-- ============================================================

-- These are stubs that the FishingController may call.
-- In a full integration, FishingHUD handles the actual UI.

function UIController:ShowHookCircle(hookWindowSize)
    -- FishingHUD handles this
end

function UIController:HideHookCircle()
    -- FishingHUD handles this
end

function UIController:ShowHookResult(resultText, color)
    -- FishingHUD handles this
end

function UIController:UpdateReelUI(tension, progress, tensionZone)
    -- FishingHUD handles this
end

function UIController:ShowReelUI()
    -- FishingHUD handles this
end

function UIController:HideReelUI()
    -- FishingHUD handles this
end

-- ============================================================
-- Cleanup
-- ============================================================
function UIController:Destroy()
    if self._collectionBook then
        self._collectionBook:Destroy()
        self._collectionBook = nil
    end
    if self._shopScreen then
        self._shopScreen:Destroy()
        self._shopScreen = nil
    end
    if self._hudGui then
        self._hudGui:Destroy()
        self._hudGui = nil
    end
end

return UIController
