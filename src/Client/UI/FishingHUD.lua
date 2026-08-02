--[[
    FishingHUD.lua
    Deep Tide Studios — Client UI Module
    Fishing-specific UI: hook circle, tension meter, progress bar,
    rarity reveal popup, and result text labels.
    All UI elements are created as ScreenGui under PlayerGui.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))

local FishingHUD = {}
FishingHUD.__index = FishingHUD

-- ============================================================
-- Constructor
-- ============================================================
function FishingHUD.new()
    local self = setmetatable({}, FishingHUD)

    self._gui = nil
    self._hookFrame = nil
    self._hookCircle = nil       -- shrinking inner circle
    self._hookOuterRing = nil   -- outer ring
    self._hookSweetZone = nil   -- sweet zone arc indicator
    self._hookResultLabel = nil -- "PERFECT!", "NICE!", "MISS!"
    self._hookTimer = 0
    self._hookActive = false
    self._hookWindowSize = 0.4
    self._hookCallback = nil

    self._tensionFrame = nil
    self._tensionBar = nil
    self._tensionFill = nil
    self._tensionGreenZone = nil
    self._tensionYellowZone = nil
    self._tensionRedZone = nil
    self._tensionLabel = nil

    self._progressFrame = nil
    self._progressBar = nil
    self._progressFill = nil

    self._showcaseFrame = nil
    self._showcaseLabel = nil
    self._showcaseRarity = nil
    self._showcaseWeight = nil
    self._showcaseParticles = nil

    self:_createGUI()

    return self
end

-- ============================================================
-- Create all UI elements
-- ============================================================

function FishingHUD:_createGUI()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    local gui = Instance.new("ScreenGui")
    gui.Name = "FishingHUD"
    gui.ResetOnSpawn = false
    gui.Parent = playerGui

    self._gui = gui

    self:_createHookCircle(gui)
    self:_createTensionMeter(gui)
    self:_createProgressBar(gui)
    self:_createShowcaseFrame(gui)
end

-- ============================================================
-- Hook Circle (bite timing minigame)
-- ============================================================

function FishingHUD:_createHookCircle(parent)
    -- Container
    local frame = Instance.new("Frame")
    frame.Name = "HookCircleFrame"
    frame.Size = UDim2.new(0, 200, 0, 200)
    frame.Position = UDim2.new(0.5, -100, 0.5, -100)
    frame.BackgroundTransparency = 1
    frame.Visible = false
    frame.Parent = parent
    self._hookFrame = frame

    -- Outer ring
    local outerRing = Instance.new("Frame")
    outerRing.Name = "OuterRing"
    outerRing.Size = UDim2.new(1, 0, 1, 0)
    outerRing.Position = UDim2.new(0, 0, 0, 0)
    outerRing.BackgroundTransparency = 1
    outerRing.Parent = frame

    local ringUI = Instance.new("UICorner")
    ringUI.CornerRadius = UDim.new(1, 0)
    ringUI.Parent = outerRing

    local ringStroke = Instance.new("UIStroke")
    ringStroke.Name = "RingStroke"
    ringStroke.Color = Color3.fromRGB(200, 200, 200)
    ringStroke.Thickness = 4
    ringStroke.Parent = outerRing
    self._hookOuterRing = outerRing

    -- Sweet zone indicator (colored arc)
    local sweetZone = Instance.new("Frame")
    sweetZone.Name = "SweetZone"
    sweetZone.Size = UDim2.new(0.85, 0, 0.85, 0)
    sweetZone.Position = UDim2.new(0.075, 0, 0.075, 0)
    sweetZone.BackgroundTransparency = 1
    sweetZone.Parent = frame

    local sweetCorner = Instance.new("UICorner")
    sweetCorner.CornerRadius = UDim.new(1, 0)
    sweetCorner.Parent = sweetZone

    local sweetStroke = Instance.new("UIStroke")
    sweetStroke.Name = "SweetStroke"
    sweetStroke.Color = Color3.fromRGB(255, 220, 50) -- Gold
    sweetStroke.Thickness = 3
    sweetStroke.Parent = sweetZone
    self._hookSweetZone = sweetZone
    self._hookSweetStroke = sweetStroke

    -- Inner shrinking circle
    local innerCircle = Instance.new("Frame")
    innerCircle.Name = "InnerCircle"
    innerCircle.Size = UDim2.new(0.3, 0, 0.3, 0)
    innerCircle.Position = UDim2.new(0.35, 0, 0.35, 0)
    innerCircle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    innerCircle.BackgroundTransparency = 0.6
    innerCircle.Parent = frame

    local innerCorner = Instance.new("UICorner")
    innerCorner.CornerRadius = UDim.new(1, 0)
    innerCorner.Parent = innerCircle
    self._hookCircle = innerCircle

    -- Result text label
    local resultLabel = Instance.new("TextLabel")
    resultLabel.Name = "HookResult"
    resultLabel.Size = UDim2.new(1, 0, 0, 40)
    resultLabel.Position = UDim2.new(0, 0, -0.3, 0)
    resultLabel.BackgroundTransparency = 1
    resultLabel.Font = Enum.Font.GothamBold
    resultLabel.TextSize = 32
    resultLabel.Text = ""
    resultLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    resultLabel.TextStrokeTransparency = 0
    resultLabel.Visible = false
    resultLabel.Parent = frame
    self._hookResultLabel = resultLabel
end

--- Start the hook minigame
--- @param hookWindowSize number (0-1) — sweet zone size as fraction of circle
--- @param callback function — called with timingQuality: "Perfect" | "Good" | "Early" | "Late"
function FishingHUD:StartHookMinigame(hookWindowSize, callback)
    if self._hookActive then return end

    self._hookActive = true
    self._hookWindowSize = hookWindowSize
    self._hookCallback = callback

    -- Show frame
    self._hookFrame.Visible = true

    -- Set sweet zone visual
    local zoneInner = 1 - hookWindowSize
    self._hookSweetZone.Size = UDim2.new(zoneInner, 0, zoneInner, 0)
    self._hookSweetZone.Position = UDim2.new((1 - zoneInner) / 2, 0, (1 - zoneInner) / 2, 0)

    -- Reset inner circle to full size
    self._hookCircle.Size = UDim2.new(0.9, 0, 0.9, 0)
    self._hookCircle.Position = UDim2.new(0.05, 0, 0.05, 0)
    self._hookCircle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)

    -- Start shrinking animation over 1.5-2.0 seconds
    local duration = Shared.Fishing.HookCircleDuration.Min
        + math.random() * (Shared.Fishing.HookCircleDuration.Max - Shared.Fishing.HookCircleDuration.Min)

    self._hookTimer = tick()
    self._hookDuration = duration

    -- Animate shrink
    self._hookShrinkTween = TweenService:Create(
        self._hookCircle,
        TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.In),
        {
            Size = UDim2.new(0.05, 0, 0.05, 0),
            Position = UDim2.new(0.475, 0, 0.475, 0),
        }
    )
    self._hookShrinkTween:Play()

    -- Auto-timeout: if player doesn't click, it's "Late"
    self._hookTimeoutConnection = task.delay(duration + 0.1, function()
        if self._hookActive then
            self:_resolveHook("Late")
        end
    end)
end

--- Player clicked during hook minigame — evaluate timing
function FishingHUD:OnHookClick()
    if not self._hookActive then return end

    local elapsed = tick() - self._hookTimer
    local progress = math.clamp(elapsed / self._hookDuration, 0, 1)

    -- Circle shrinks from outer toward center
    -- When progress=0, circle is at outer ring (size ~0.9)
    -- When progress=1, circle is at center (size ~0.05)
    -- Sweet zone is centered on the inner ring

    -- The sweet zone occupies hookWindowSize fraction of the radius
    -- We need to check if the current circle radius overlaps the sweet zone

    -- Circle current size (linear interpolation)
    local currentSize = 0.9 - progress * 0.85 -- from 0.9 to 0.05

    -- Sweet zone boundaries in size units
    -- If hookWindowSize=0.4, sweet zone is between (1-0.4)=0.6 and 0.6+0.4=1.0... 
    -- Wait, let me think about this differently.
    -- The sweet zone is positioned at a specific radial distance.
    -- Let's define: sweet zone occupies from (1 - hookWindowSize) to (1.0) of the outer ring radius.
    -- In terms of the circle's Size fraction:
    --   Outer ring size = 1.0 (frame size)
    --   Sweet zone outer = hookWindowSize fraction of radius inward from outer ring
    --   So the sweet zone in Size units: from (1 - hookWindowSize) to (1 - hookWindowSize*0.2)
    -- Actually, let me simplify: the circle Size goes from 0.9 to 0.05.
    -- The sweet zone is at the radial position where the circle's edge overlaps the sweet zone visual.
    --
    -- Let me use a simpler approach: based on the progress value.
    -- Sweet zone is centered at some progress value.
    -- For hookWindowSize=0.4, the sweet zone occupies 40% of the circle shrinking timeline.
    -- Center of sweet zone: at 0.5 progress. Sweet zone spans [0.3, 0.7].
    -- For hookWindowSize=0.25: center at 0.5, spans [0.375, 0.625].
    -- For hookWindowSize=0.08: center at 0.5, spans [0.46, 0.54].

    local zoneCenter = 0.5
    local zoneHalf = self._hookWindowSize / 2

    if progress >= (zoneCenter - zoneHalf) and progress <= (zoneCenter + zoneHalf) then
        -- Inside sweet zone
        local distanceFromCenter = math.abs(progress - zoneCenter)
        local perfectHalf = zoneHalf * Shared.Fishing.PerfectRatio -- 30% of sweet zone = perfect

        if distanceFromCenter <= perfectHalf then
            self:_resolveHook("Perfect")
        else
            self:_resolveHook("Good")
        end
    elseif progress < (zoneCenter - zoneHalf) then
        self:_resolveHook("Early")
    else
        self:_resolveHook("Late")
    end
end

function FishingHUD:_resolveHook(quality)
    if not self._hookActive then return end
    self._hookActive = false

    -- Cancel tween and timeout
    if self._hookShrinkTween then
        self._hookShrinkTween:Cancel()
        self._hookShrinkTween = nil
    end
    if self._hookTimeoutConnection then
        self._hookTimeoutConnection = nil
    end

    -- Show result text
    local resultText, textColor
    if quality == "Perfect" then
        resultText = "PERFECT!"
        textColor = Color3.fromRGB(255, 220, 50) -- gold
    elseif quality == "Good" then
        resultText = "NICE!"
        textColor = Color3.fromRGB(100, 255, 100) -- green
    elseif quality == "Early" then
        resultText = "TOO SOON!"
        textColor = Color3.fromRGB(255, 200, 100) -- orange
    else
        resultText = "MISS!"
        textColor = Color3.fromRGB(255, 80, 80) -- red
    end

    self._hookResultLabel.Text = resultText
    self._hookResultLabel.TextColor3 = textColor
    self._hookResultLabel.Visible = true

    -- Hide hook UI after a brief moment
    task.delay(0.8, function()
        self._hookFrame.Visible = false
        self._hookResultLabel.Visible = false
    end)

    -- Callback
    if self._hookCallback then
        self._hookCallback(quality)
        self._hookCallback = nil
    end
end

--- Cancel hook minigame (e.g., if fish leaves)
function FishingHUD:CancelHook()
    if not self._hookActive then return end
    self._hookActive = false

    if self._hookShrinkTween then
        self._hookShrinkTween:Cancel()
        self._hookShrinkTween = nil
    end

    self._hookFrame.Visible = false
    self._hookResultLabel.Visible = false
    self._hookCallback = nil
end

-- ============================================================
-- Tension Meter (reel minigame)
-- ============================================================

function FishingHUD:_createTensionMeter(parent)
    -- Container (vertical bar, right side)
    local frame = Instance.new("Frame")
    frame.Name = "TensionMeterFrame"
    frame.Size = UDim2.new(0, 40, 0, 250)
    frame.Position = UDim2.new(0.9, 0, 0.5, -125)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    frame.BackgroundTransparency = 0.3
    frame.Visible = false
    frame.Parent = parent

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 8)
    barCorner.Parent = frame

    -- Background label
    local bgLabel = Instance.new("TextLabel")
    bgLabel.Name = "BG"
    bgLabel.Size = UDim2.new(1, 0, 1, 0)
    bgLabel.BackgroundTransparency = 1
    bgLabel.Font = Enum.Font.GothamBold
    bgLabel.TextSize = 14
    bgLabel.Text = ""
    bgLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    bgLabel.Parent = frame

    -- Tension fill (grows from bottom)
    local fill = Instance.new("Frame")
    fill.Name = "TensionFill"
    fill.Size = UDim2.new(1, 0, 0, 0) -- starts empty
    fill.Position = UDim2.new(0, 0, 1, 0)
    fill.AnchorPoint = Vector2.new(0, 1)
    fill.BackgroundColor3 = Color3.fromRGB(100, 255, 100) -- green
    fill.Parent = frame

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 8)
    fillCorner.Parent = fill
    self._tensionFill = fill

    -- Zone markers
    local greenZone = Instance.new("Frame")
    greenZone.Name = "GreenZone"
    greenZone.Size = UDim2.new(0, 3, 0.5, 0) -- 0-50%
    greenZone.Position = UDim2.new(1, 2, 0.5, 0)
    greenZone.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    greenZone.BackgroundTransparency = 0.5
    greenZone.Parent = frame
    self._tensionGreenZone = greenZone

    local yellowZone = Instance.new("Frame")
    yellowZone.Name = "YellowZone"
    yellowZone.Size = UDim2.new(0, 3, 0.3, 0) -- 50-80%
    yellowZone.Position = UDim2.new(1, 2, 0.2, 0)
    yellowZone.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
    yellowZone.BackgroundTransparency = 0.5
    yellowZone.Parent = frame
    self._tensionYellowZone = yellowZone

    local redZone = Instance.new("Frame")
    redZone.Name = "RedZone"
    redZone.Size = UDim2.new(0, 3, 0.2, 0) -- 80-100%
    redZone.Position = UDim2.new(1, 2, 0, 0)
    redZone.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    redZone.BackgroundTransparency = 0.5
    redZone.Parent = frame
    self._tensionRedZone = redZone

    -- Tension label
    local tensionLabel = Instance.new("TextLabel")
    tensionLabel.Name = "TensionLabel"
    tensionLabel.Size = UDim2.new(1, 0, 0, 20)
    tensionLabel.Position = UDim2.new(0, 0, -0.1, -20)
    tensionLabel.BackgroundTransparency = 1
    tensionLabel.Font = Enum.Font.Gotham
    tensionLabel.TextSize = 12
    tensionLabel.Text = "TENSION"
    tensionLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    tensionLabel.Parent = frame
    self._tensionLabel = tensionLabel

    self._tensionFrame = frame
    self._tensionBar = frame
end

--- Update tension meter
function FishingHUD:UpdateTension(tension, tensionZone)
    local height = tension / 100

    self._tensionFill.Size = UDim2.new(1, 0, height, 0)
    self._tensionFill.Position = UDim2.new(0, 0, 1, 0)

    -- Color based on zone
    if tensionZone == "Green" then
        self._tensionFill.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
    elseif tensionZone == "Yellow" then
        self._tensionFill.BackgroundColor3 = Color3.fromRGB(255, 255, 80)
    else
        self._tensionFill.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    end

    -- Flash red zone when in danger
    if tensionZone == "Red" then
        self._tensionRedZone.BackgroundTransparency = 0.3 + math.sin(tick() * 10) * 0.3
    else
        self._tensionRedZone.BackgroundTransparency = 0.5
    end
end

function FishingHUD:ShowTensionMeter()
    self._tensionFrame.Visible = true
    self._tensionFill.Size = UDim2.new(1, 0, 0, 0)
end

function FishingHUD:HideTensionMeter()
    self._tensionFrame.Visible = false
end

-- ============================================================
-- Progress Bar (fish reeling progress)
-- ============================================================

function FishingHUD:_createProgressBar(parent)
    local frame = Instance.new("Frame")
    frame.Name = "ProgressBarFrame"
    frame.Size = UDim2.new(0.4, 0, 0, 16)
    frame.Position = UDim2.new(0.3, 0, 0.1, 0)
    frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    frame.BackgroundTransparency = 0.2
    frame.Visible = false
    frame.Parent = parent

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 8)
    barCorner.Parent = frame

    -- Fill
    local fill = Instance.new("Frame")
    fill.Name = "ProgressFill"
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
    fill.Parent = frame

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 8)
    fillCorner.Parent = fill
    self._progressFill = fill

    -- Label
    local label = Instance.new("TextLabel")
    label.Name = "ProgressLabel"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.Text = "REELING..."
    label.TextColor3 = Color3.fromRGB(200, 200, 200)
    label.Parent = frame

    self._progressFrame = frame
    self._progressBar = frame
end

function FishingHUD:UpdateProgress(progress)
    self._progressFill.Size = UDim2.new(progress / 100, 0, 1, 0)
end

function FishingHUD:ShowProgressBar()
    self._progressFrame.Visible = true
    self._progressFill.Size = UDim2.new(0, 0, 1, 0)
end

function FishingHUD:HideProgressBar()
    self._progressFrame.Visible = false
end

-- ============================================================
-- Rarity / Fish Showcase
-- ============================================================

function FishingHUD:_createShowcaseFrame(parent)
    local frame = Instance.new("Frame")
    frame.Name = "ShowcaseFrame"
    frame.Size = UDim2.new(0.5, 0, 0.3, 0)
    frame.Position = UDim2.new(0.25, 0, 0.35, 0)
    frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    frame.BackgroundTransparency = 0.7
    frame.Visible = false
    frame.Parent = parent

    local showcaseCorner = Instance.new("UICorner")
    showcaseCorner.CornerRadius = UDim.new(0, 16)
    showcaseCorner.Parent = frame

    -- Dramatic pause first (hidden), then reveal

    -- Fish name label
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "FishName"
    nameLabel.Size = UDim2.new(1, 0, 0, 40)
    nameLabel.Position = UDim2.new(0, 0, 0.3, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 28
    nameLabel.Text = ""
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextStrokeTransparency = 0
    nameLabel.Parent = frame
    self._showcaseLabel = nameLabel

    -- Rarity label
    local rarityLabel = Instance.new("TextLabel")
    rarityLabel.Name = "RarityLabel"
    rarityLabel.Size = UDim2.new(1, 0, 0, 30)
    rarityLabel.Position = UDim2.new(0, 0, 0.45, 0)
    rarityLabel.BackgroundTransparency = 1
    rarityLabel.Font = Enum.Font.GothamBold
    rarityLabel.TextSize = 22
    rarityLabel.Text = ""
    rarityLabel.TextStrokeTransparency = 0
    rarityLabel.Parent = frame
    self._showcaseRarity = rarityLabel

    -- Weight label
    local weightLabel = Instance.new("TextLabel")
    weightLabel.Name = "WeightLabel"
    weightLabel.Size = UDim2.new(1, 0, 0, 25)
    weightLabel.Position = UDim2.new(0, 0, 0.58, 0)
    weightLabel.BackgroundTransparency = 1
    weightLabel.Font = Enum.Font.Gotham
    weightLabel.TextSize = 18
    weightLabel.Text = ""
    weightLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    weightLabel.Parent = frame
    self._showcaseWeight = weightLabel

    -- Particle burst (simulated with UI elements)
    local particles = {}
    for i = 1, 20 do
        local dot = Instance.new("Frame")
        dot.Size = UDim2.new(0, 6, 0, 6)
        dot.Position = UDim2.new(0.5, 0, 0.5, 0)
        dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        dot.BackgroundTransparency = 1
        dot.Parent = frame

        local dotCorner = Instance.new("UICorner")
        dotCorner.CornerRadius = UDim.new(1, 0)
        dotCorner.Parent = dot

        particles[i] = dot
    end
    self._showcaseParticles = particles

    self._showcaseFrame = frame
end

--- Show rarity reveal (dramatic pause → reveal)
function FishingHUD:ShowRarityReveal(fishData)
    -- Dramatic pause: show dark frame
    self._showcaseFrame.Visible = true
    self._showcaseFrame.BackgroundTransparency = 0.9

    -- Get rarity color
    local rarity = Shared.Constants.RarityTiers[fishData.Rarity]
    local rarityColor = rarity and rarity.Color or Color3.fromRGB(255, 255, 255)

    -- Set up the text (hidden initially)
    self._showcaseLabel.Text = ""
    self._showcaseLabel.TextColor3 = rarityColor
    self._showcaseRarity.Text = ""
    self._showcaseWeight.Text = ""

    -- Dramatic pause then reveal
    task.delay(0.6, function()
        -- Reveal
        self._showcaseFrame.BackgroundTransparency = 0.5

        local tween = TweenService:Create(
            self._showcaseFrame,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0.5 }
        )
        tween:Play()

        self._showcaseLabel.Text = fishData.SpeciesName
        self._showcaseLabel.TextColor3 = rarityColor
        self._showcaseRarity.Text = fishData.Rarity:upper()
        self._showcaseRarity.TextColor3 = rarityColor

        local weightStr = string.format("%.1f kg", fishData.Weight)
        if fishData.SellPrice then
            weightStr = weightStr .. "  •  💰 " .. tostring(fishData.SellPrice)
        end
        self._showcaseWeight.Text = weightStr

        -- Particle burst
        self:_playParticleBurst(rarityColor)
    end)

    -- Auto-dismiss after 3 seconds
    task.delay(3.5, function()
        self:HideShowcase()
    end)
end

function FishingHUD:_playParticleBurst(color)
    if not self._showcaseParticles then return end

    for i, dot in ipairs(self._showcaseParticles) do
        dot.BackgroundColor3 = color
        dot.BackgroundTransparency = 0

        local angle = math.random() * math.pi * 2
        local distance = 0.15 + math.random() * 0.25
        local targetX = 0.5 + math.cos(angle) * distance
        local targetY = 0.5 + math.sin(angle) * distance

        local tween = TweenService:Create(dot,
            TweenInfo.new(0.6 + math.random() * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                Position = UDim2.new(targetX, 0, targetY, 0),
                BackgroundTransparency = 1,
            }
        )
        tween:Play()

        -- Reset after animation
        task.delay(1.0, function()
            dot.Position = UDim2.new(0.5, 0, 0.5, 0)
            dot.BackgroundTransparency = 1
        end)
    end
end

function FishingHUD:HideShowcase()
    if self._showcaseFrame then
        self._showcaseFrame.Visible = false
    end
end

-- ============================================================
-- Simple popup text
-- ============================================================

function FishingHUD:ShowPopupText(text, color, duration)
    duration = duration or 1.5
    color = color or Color3.fromRGB(255, 255, 255)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0, 300, 0, 40)
    label.Position = UDim2.new(0.5, -150, 0.4, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 28
    label.Text = text
    label.TextColor3 = color
    label.TextStrokeTransparency = 0
    label.Parent = self._showcaseFrame and self._showcaseFrame.Parent or self._gui

    local tween = TweenService:Create(label,
        TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            Position = UDim2.new(0.5, -150, 0.3, 0),
            TextTransparency = 1,
        }
    )
    tween:Play()
    tween.Completed:Connect(function()
        label:Destroy()
    end)
end

function FishingHUD:ShowKelpEntanglement(duration)
    self:ShowPopupText("KELP ENTANGLED!", Color3.fromRGB(80, 220, 120), duration or 1.5)
end

function FishingHUD:ClearKelpEntanglement() end

function FishingHUD:SetTensionMeterObscured(obscured, duration)
    if not self._tensionFrame then return end
    self._tensionFrame.BackgroundTransparency = obscured and 0 or 0.3
    if self._tensionLabel then self._tensionLabel.Text = obscured and "INK!" or "TENSION" end
    if obscured and duration then
        task.delay(duration, function() self:SetTensionMeterObscured(false) end)
    end
end

-- ============================================================
-- Show/hide everything
-- ============================================================

function FishingHUD:ShowReelUI()
    self:ShowTensionMeter()
    self:ShowProgressBar()
end

function FishingHUD:HideReelUI()
    self:HideTensionMeter()
    self:HideProgressBar()
end

function FishingHUD:HideAll()
    self:CancelHook()
    self:HideReelUI()
    self:HideShowcase()
end

function FishingHUD:Destroy()
    self:HideAll()
    if self._gui then
        self._gui:Destroy()
        self._gui = nil
    end
end

return FishingHUD
