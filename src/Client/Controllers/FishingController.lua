--[[
    FishingController.lua
    Deep Tide Studios — Client Controller
    Full fishing gameplay loop: equip rod, aim, cast, hook minigame,
    reel minigame, catch/lose. Coordinates FishingRodHandler (visuals),
    FishingHUD (UI), and server-authoritative FishingService.
]]

local Knit = require(game:GetService("ReplicatedStorage"):WaitForChild("Knit"))
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))

-- Import our client-side modules
local FishingRodHandler = require(script.Parent.Parent:WaitForChild("Handlers"):WaitForChild("FishingRodHandler"))
local FishingHUD = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("FishingHUD"))

local FishingController = Knit.CreateController({
    Name = "FishingController",
})

-- ============================================================
-- State
-- ============================================================
FishingController._isFishing = false
FishingController._phase = "Idle" -- Idle | Aiming | Casting | Waiting | Biting | Reeling | Showcase
FishingController._castId = nil
FishingController._tension = 0
FishingController._progress = 0

-- Cached player data (synced from PlayerDataService)
FishingController._cachedEquippedRod = "BambooRod"

-- Aiming state
FishingController._aimStartTime = 0
FishingController._aimPower = 0

-- Reel loop
FishingController._reelLoop = nil
FishingController._isReeling = false -- instance var, not closure
FishingController._reelTickAccumulator = 0
FishingController._lastReelTickTime = 0
FishingController._resultHandled = false -- guard against double-fire from tick + event

-- Bite timer
FishingController._biteTimer = nil
FishingController._biteStartTime = 0
FishingController._currentBiteDelay = 0
FishingController._pendingSpecies = nil

-- Handlers
FishingController._rodHandler = nil
FishingController._fishingHUD = nil

-- ============================================================
-- Init / Start
-- ============================================================

function FishingController:KnitStart()
    print("[FishingController] Started")

    self._rodHandler = FishingRodHandler.new()
    self._fishingHUD = FishingHUD.new()

    -- Wire up PlayerDataService to cache equipped rod stats
    self:_wirePlayerDataService()

    -- Equip rod by default (reads from cached data or falls back to BambooRod)
    self:_equipDefaultRod()

    -- Bind inputs
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        self:_handleInput(input, true)
    end)

    UserInputService.InputEnded:Connect(function(input)
        self:_handleInput(input, false)
    end)
end

function FishingController:KnitInit()
    -- Listen for server events
    local fishingService = self.Services.FishingService
    if not fishingService then
        warn("[FishingController] FishingService not available")
        return
    end

    fishingService.Client.FishHooked:Connect(function(fishData)
        self:_onFishHooked(fishData)
    end)

    fishingService.Client.FishCaught:Connect(function(fishData, rewards)
        self:_onFishCaught(fishData, rewards)
    end)

    fishingService.Client.LineSnapped:Connect(function()
        self:_onLineSnapped()
    end)

    fishingService.Client.FishEscaped:Connect(function(reason)
        self:_onFishEscaped(reason)
    end)
end

-- ============================================================
-- PlayerDataService Wiring — keeps _cachedEquippedRod in sync
-- ============================================================

function FishingController:_wirePlayerDataService()
    local playerDataService = self.Services.PlayerDataService
    if not playerDataService or not playerDataService.Client then
        return
    end

    local function onPlayerDataReceived(data)
        if data and data.Gear and data.Gear.EquippedRod then
            self._cachedEquippedRod = data.Gear.EquippedRod
            -- Re-equip the rod visuals if they changed
            if self._rodHandler then
                self._rodHandler:Equip(self._cachedEquippedRod)
            end
        end
    end

    -- Listen for initial data push on join
    playerDataService.Client.GetPlayerData:Connect(onPlayerDataReceived)

    -- Listen for data updates (e.g., after rod purchase/equip)
    playerDataService.Client.DataUpdated:Connect(onPlayerDataReceived)

    -- Request initial data asynchronously (covers the race where
    -- KnitStart runs before the server pushes data)
    task.spawn(function()
        local player = Players.LocalPlayer
        local data = playerDataService.Client.GetPlayerData:Call(player)
        if data then
            onPlayerDataReceived(data)
        end
    end)
end

-- ============================================================
-- Rod Equip
-- ============================================================

function FishingController:_equipDefaultRod()
    -- Use cached rod key (populated by _wirePlayerDataService).
    -- Falls back to BambooRod until the first PlayerDataService push.
    self:_doEquipRod(self._cachedEquippedRod)
end

function FishingController:_doEquipRod(rodKey)
    if self._rodHandler then
        self._rodHandler:Equip(rodKey)
        print("[FishingController] Rod equipped:", rodKey)
    end
end

-- ============================================================
-- Input handling
-- ============================================================

function FishingController:_handleInput(input, isBegin)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if isBegin then
            self:_onClickPress()
        else
            self:_onClickRelease()
        end
    end
end

function FishingController:_onClickPress()
    if self._phase == "Idle" then
        -- Check if rod is equipped
        if not self._rodHandler or not self._rodHandler._isEquipped then
            return
        end
        self._phase = "Aiming"
        self:_startAiming()

    elseif self._phase == "Biting" then
        -- Hook attempt — pass to HUD for timing evaluation
        if self._fishingHUD then
            self._fishingHUD:OnHookClick()
        end

    elseif self._phase == "Reeling" then
        -- Start reeling
        self._isReeling = true
    end
end

function FishingController:_onClickRelease()
    if self._phase == "Aiming" then
        self:_performCast()

    elseif self._phase == "Reeling" then
        -- Stop reeling
        self._isReeling = false
    end
end

-- ============================================================
-- Aiming Phase
-- ============================================================

function FishingController:_startAiming()
    print("[FishingController] Aiming...")
    self._aimStartTime = tick()
    self._aimPower = 0

    -- Get player's rod stats for max cast range
    local rodStats = self:_getRodStats()
    local maxRange = rodStats and rodStats.CastRange or 15

    -- Transition camera
    if self.Controllers and self.Controllers.CameraController then
        self.Controllers.CameraController:TransitionToFishingCam()
    end

    -- RenderStepped loop for updating aim arc
    self._aimLoop = RunService.RenderStepped:Connect(function(dt)
        if self._phase ~= "Aiming" then
            self._aimLoop:Disconnect()
            self._aimLoop = nil
            return
        end

        -- Calculate power based on hold duration
        local holdDuration = tick() - self._aimStartTime
        self._aimPower = math.clamp(holdDuration / 1.5, 0.2, 1.0) -- 0.2-1.0 range over 1.5s

        local origin, direction = self:_getCastOriginAndDirection()
        if origin and direction then
            if self._rodHandler then
                self._rodHandler:UpdateAimArc(origin, direction, self._aimPower, maxRange)
            end
        end
    end)

    -- Show initial aim arc
    local origin, direction = self:_getCastOriginAndDirection()
    if origin and direction and self._rodHandler then
        self._rodHandler:ShowAimArc(origin, direction, self._aimPower, maxRange)
    end
end

function FishingController:_getCastOriginAndDirection()
    local camera = workspace.CurrentCamera
    if not camera then return nil, nil end

    local origin = camera.CFrame.Position
    local direction = camera.CFrame.LookVector

    return origin, direction
end

-- ============================================================
-- Cast Phase
-- ============================================================

function FishingController:_performCast()
    -- Calculate target position
    local targetPosition = self:_getAimTarget()

    -- Clean up aim UI
    if self._aimLoop then
        self._aimLoop:Disconnect()
        self._aimLoop = nil
    end

    if not targetPosition then
        print("[FishingController] No valid cast target")
        self._phase = "Idle"
        return
    end

    self._phase = "Casting"

    -- Get origin for animation
    local origin, _ = self:_getCastOriginAndDirection()

    -- Play cast animation
    if self._rodHandler then
        self._rodHandler:PlayCastAnimation(origin, targetPosition, self._aimPower, function()
            -- Animation complete, now send cast to server
            self:_sendCastToServer(targetPosition)
        end)
    else
        self:_sendCastToServer(targetPosition)
    end
end

function FishingController:_sendCastToServer(targetPosition)
    local fishingService = self.Services.FishingService
    if not fishingService then
        self._phase = "Idle"
        return
    end

    local result = fishingService.Client.CastLine:Call(targetPosition)

    if result and result.Success then
        self._castId = result.CastId
        self._phase = "Waiting"

        -- Create bobber visual
        if self._rodHandler then
            self._rodHandler:CreateBobber(targetPosition)
        end

        -- Play cast splash sound
        self:_playSound("Cast")

        -- Start waiting for fish bite
        self:_startWaitingForBite()

        print("[FishingController] Cast successful, waiting for bite...")
    else
        self._phase = "Idle"
        warn("[FishingController] Cast failed:", result and result.Message or "unknown")
    end
end

function FishingController:_getAimTarget()
    -- Raycast from camera to find water surface / target point
    local camera = workspace.CurrentCamera
    if not camera then return nil end

    local mousePos = UserInputService:GetMouseLocation()
    local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

    -- First try raycasting against terrain/water
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Include
    raycastParams.FilterDescendantsInstances = { workspace }

    local raycastResult = workspace:Raycast(ray.Origin, ray.Direction * 500, raycastParams)
    if raycastResult then
        return raycastResult.Position
    end

    -- Fallback: project to a reasonable distance
    return ray.Origin + ray.Direction * 50
end

-- ============================================================
-- Waiting Phase (for fish to approach bobber)
-- ============================================================

function FishingController:_startWaitingForBite()
    -- Determine which species might bite (client predictive — server has final say)
    -- We'll use a reasonable delay range based on the likely species
    -- Server's _resolveBitingSpecies uses spawn table weighting

    -- Random delay simulating fish approach (1.0-4.0 seconds typical for common fish)
    local minDelay = 1.5
    local maxDelay = 3.5

    self._currentBiteDelay = minDelay + math.random() * (maxDelay - minDelay)
    self._biteStartTime = tick()

    -- Start polling for bite
    self:_pollBiteReady()
end

function FishingController:_pollBiteReady()
    if self._phase ~= "Waiting" then return end

    local elapsed = tick() - self._biteStartTime

    if elapsed >= self._currentBiteDelay then
        -- Fish is biting!
        self:_onFishBiting()
    else
        -- Check again next frame
        task.wait(0.1)
        self:_pollBiteReady()
    end
end

-- ============================================================
-- Biting / Hook Phase
-- ============================================================

function FishingController:_onFishBiting()
    if self._phase ~= "Waiting" then return end
    self._phase = "Biting"

    -- Bobber bite animation (rapid bobbing)
    if self._rodHandler then
        self._rodHandler:PlayBobberBite()

        -- Enable bobber glow for bite anticipation
        self._rodHandler:SetBobberGlow(true, Color3.fromRGB(100, 200, 255))
    end

    -- Play bite splash
    self:_playSound("Bite")

    -- Slight delay before UI appears (fish is circling bobber)
    task.delay(0.3, function()
        if self._phase ~= "Biting" then return end
        self:_startHookMinigame()
    end)
end

function FishingController:_startHookMinigame()
    if self._phase ~= "Biting" then return end

    -- Get hook window size from rod stats (server-authoritative, but client shows it)
    local rodStats = self:_getRodStats()
    local hookWindowSize = rodStats and rodStats.HookWindow or 0.40

    if self._fishingHUD then
        self._fishingHUD:StartHookMinigame(hookWindowSize, function(timingQuality)
            self:_onHookResolved(timingQuality)
        end)
    end
end

function FishingController:_onHookResolved(timingQuality)
    local fishingService = self.Services.FishingService
    if not fishingService or not self._castId then
        self:_endFishing()
        return
    end

    local result = fishingService.Client.HookAttempt:Call(self._castId, timingQuality)

    if not result then
        self:_endFishing()
        return
    end

    if result.Result == "Hooked" then
        -- Hook successful — transition to reeling
        self._phase = "Reeling"
        self._tension = result.Tension or 0
        self._progress = 0

        -- Hide hook UI, show reel UI
        if self._fishingHUD then
            self._fishingHUD:CancelHook()
            self._fishingHUD:ShowReelUI()
        end

        -- Disable bobber glow
        if self._rodHandler then
            self._rodHandler:SetBobberGlow(false)
        end

        -- Start reeling
        self:_startReelLoop()

        -- Play hook success sound
        if timingQuality == "Perfect" then
            self:_playSound("Perfect")
        else
            self:_playSound("HookSuccess")
        end

    elseif result.Result == "TooSoon" then
        -- Retry — back to waiting
        self._phase = "Waiting"
        self._biteStartTime = tick()
        self._currentBiteDelay = 1.0 + math.random() * 2.0

        if self._fishingHUD then
            self._fishingHUD:CancelHook()
        end

        self:_pollBiteReady()

    else
        -- Fish fled (Late or Early with flee)
        self:_playSound("FishFlee")
        self:_endFishing()
    end
end

-- ============================================================
-- Reeling Phase
-- ============================================================

function FishingController:_startReelLoop()
    -- Setup: throttled to ~10Hz (matching server's TensionTickRate)
    self._isReeling = false
    self._reelTickAccumulator = 0
    self._lastReelTickTime = tick()
    self._lastTugTime = tick()
    self._tugCooldown = 0
    self._resultHandled = false

    self._reelLoop = RunService.Heartbeat:Connect(function(dt)
        if self._phase ~= "Reeling" then return end

        self._reelTickAccumulator = self._reelTickAccumulator + dt
        local tickRate = Shared.Fishing.TensionTickRate -- 0.1 (10 Hz)

        -- Send reel updates at ~10Hz
        while self._reelTickAccumulator >= tickRate do
            self._reelTickAccumulator = self._reelTickAccumulator - tickRate
            self:_sendReelTick()
        end

        -- Update HUD every frame for smooth visuals
        if self._fishingHUD then
            self._fishingHUD:UpdateTension(self._tension, self:_getTensionZone())
            self._fishingHUD:UpdateProgress(self._progress)
        end

        -- Update line tension visual
        if self._rodHandler then
            self._rodHandler:UpdateLineTension(self._tension)
        end

        -- Apply screen shake periodically during fish tugs
        self:_checkTugShake(dt)
    end)
end

function FishingController:_sendReelTick()
    local fishingService = self.Services.FishingService
    if not fishingService or not self._castId then return end

    local result = fishingService.Client.ReelUpdate:Call(self._castId, self._isReeling)

    if not result then
        self:_endFishing()
        return
    end

    self._tension = result.Tension or 0
    self._progress = result.Progress or 0

    -- Detect fish tug (tension spiked)
    if self._tension > 60 and (tick() - (self._lastTugDetectTime or 0)) > 0.5 then
        self:_onFishTug()
        self._lastTugDetectTime = tick()
    end

    if result.State == "Caught" then
        self._endReelLoop()
        self._resultHandled = true
        -- _onFishCaught event handles the showcase
    elseif result.State == "LineSnapped" then
        self._endReelLoop()
        self._resultHandled = true
        self:_onLineSnapped()
    elseif result.State == "FishEscaped" then
        self._endReelLoop()
        self._resultHandled = true
        self:_onFishEscaped(result.Reason)
    elseif result.State == "InventoryFull" then
        self._endReelLoop()
        self._resultHandled = true
        self:_playSound("InventoryFull")
        self:_endFishing()
    elseif result.State == "InvalidSession" then
        self:_endReelLoop()
        self:_endFishing()
    end
end

function FishingController:_onFishTug()
    -- Screen shake on fish tug
    self:_applyScreenShake(0.3, 2.0)

    -- Sound
    self:_playSound("Tug")

    -- HUD flash
    if self._fishingHUD and self._tension > 80 then
        -- Already handled by the tension meter's red flash
    end
end

function FishingController:_checkTugShake(dt)
    -- We apply shake through _onFishTug triggered by tension spikes
    -- This is a backup: if tension stays high for too long, apply subtle shake
    if self._tension > 85 then
        self:_applyScreenShake(0.1, 1.0)
    end
end

-- ============================================================
-- Screen Shake
-- ============================================================

function FishingController:_applyScreenShake(intensity, duration)
    local camera = workspace.CurrentCamera
    if not camera then return end

    local originalCFrame = camera.CFrame
    local startTime = tick()

    local shakeConnection
    shakeConnection = RunService.RenderStepped:Connect(function()
        local elapsed = tick() - startTime
        if elapsed > duration then
            shakeConnection:Disconnect()
            return
        end

        local decay = 1 - (elapsed / duration)
        local offset = Vector3.new(
            (math.random() - 0.5) * intensity * decay * 2,
            (math.random() - 0.5) * intensity * decay * 2,
            (math.random() - 0.5) * intensity * decay * 0.5
        )
        camera.CFrame = originalCFrame * CFrame.new(offset)
    end)
end

-- ============================================================
-- Server Event Handlers
-- ============================================================

function FishingController:_onFishHooked(fishData)
    print("[FishingController] Fish hooked:", fishData.SpeciesName)

    self._phase = "Reeling"
    self._tension = 0
    self._progress = 0

    -- Clean up hook UI if it was still showing
    if self._fishingHUD then
        self._fishingHUD:CancelHook()
        self._fishingHUD:ShowReelUI()
    end

    -- Disable bobber glow
    if self._rodHandler then
        self._rodHandler:SetBobberGlow(false)
    end

    -- Start reeling
    self:_startReelLoop()
end

function FishingController:_onFishCaught(fishData, rewards)
    if self._resultHandled then return end
    self._resultHandled = true

    print("[FishingController] Fish caught:", fishData.SpeciesName, fishData.Rarity)

    self:_endReelLoop()
    self._phase = "Showcase"

    -- Play catch fanfare
    self:_playSound("CatchFanfare")

    -- Rarity reveal
    if self._fishingHUD then
        self._fishingHUD:HideReelUI()
        self._fishingHUD:ShowRarityReveal(fishData)
    end

    -- Cleanup bobber
    if self._rodHandler then
        self._rodHandler:SetBobberGlow(false)
    end

    -- Return to idle after showcase
    task.delay(4.0, function()
        self:_endFishing()
    end)
end

function FishingController:_onLineSnapped()
    if self._resultHandled then return end
    self._resultHandled = true

    print("[FishingController] Line snapped!")

    self:_endReelLoop()

    -- Play line snap sound
    self:_playSound("LineSnap")

    -- Show popup
    if self._fishingHUD then
        self._fishingHUD:HideReelUI()
        self._fishingHUD:ShowPopupText("LINE SNAPPED!", Color3.fromRGB(255, 60, 60), 2.0)
    end

    -- Cleanup bobber immediately
    if self._rodHandler then
        self._rodHandler:SetBobberGlow(false)
    end

    -- Brief delay then end
    task.delay(1.5, function()
        self:_endFishing()
    end)
end

function FishingController:_onFishEscaped(reason)
    if self._resultHandled then return end
    self._resultHandled = true

    print("[FishingController] Fish escaped:", reason or "unknown")

    self:_endReelLoop()

    if self._fishingHUD then
        self._fishingHUD:HideReelUI()
        if reason == "LowTension" then
            self._fishingHUD:ShowPopupText("NOT ENOUGH TENSION!", Color3.fromRGB(255, 170, 50), 2.0)
        else
            self._fishingHUD:ShowPopupText("FISH ESCAPED!", Color3.fromRGB(255, 170, 50), 2.0)
        end
    end

    self:_playSound("FishFlee")

    if self._rodHandler then
        self._rodHandler:SetBobberGlow(false)
    end

    task.delay(1.5, function()
        self:_endFishing()
    end)
end

-- ============================================================
-- Sound Events (placeholders — integration with SoundHandler)
-- ============================================================

function FishingController:_playSound(event)
    -- Sound events are triggered here. In production, these would play
    -- actual Roblox Sound objects or call a SoundService.
    -- For now, we log them — the audio assets can be wired in by the
    -- Technical Artist or in a future iteration.

    -- Key sound events:
    -- "Cast"       — splash on cast
    -- "Bite"       — splash + bobber dunk
    -- "HookSuccess" — click + line tension
    -- "Perfect"    — special chime
    -- "FishFlee"   — splash exit
    -- "Tug"        — line strain creak
    -- "LineSnap"   — snap + splash
    -- "CatchFanfare" — triumphant jingle
    -- "InventoryFull" — error buzz

    -- To wire real sounds, create Sound instances in appropriate
    -- locations and call :Play() here. We use a lookup table.

    if not self._soundCache then
        self._soundCache = {}
    end

    -- Log for debugging
    -- print("[FishingController] Sound:", event)
end

-- ============================================================
-- Cleanup & Utilities
-- ============================================================

function FishingController:_endReelLoop()
    if self._reelLoop then
        self._reelLoop:Disconnect()
        self._reelLoop = nil
    end
    self._isReeling = false
end

function FishingController:_endFishing()
    local fishingService = self.Services.FishingService
    if self._castId and fishingService then
        pcall(function()
            fishingService.Client.CancelFishing:Call(self._castId)
        end)
    end

    -- Cleanup reel
    self:_endReelLoop()

    -- Cleanup aim
    if self._aimLoop then
        self._aimLoop:Disconnect()
        self._aimLoop = nil
    end

    -- Cleanup bite timer
    self._biteTimer = nil

    -- Cleanup UI
    if self._fishingHUD then
        self._fishingHUD:HideAll()
    end

    -- Cleanup rod visuals
    if self._rodHandler then
        self._rodHandler:SetBobberGlow(false)
        -- Bobber cleanup is handled internally by next cast or manual
    end

    -- Restore camera
    if self.Controllers and self.Controllers.CameraController then
        self.Controllers.CameraController:TransitionToNormalCam()
    end

    -- Reset state
    self._phase = "Idle"
    self._castId = nil
    self._tension = 0
    self._progress = 0
    self._isFishing = false
    self._aimPower = 0
    self._pendingSpecies = nil
end

function FishingController:_getRodStats()
    -- Returns the rod stats for the player's currently equipped rod.
    -- Reads from the cached rod key, which is kept in sync by
    -- _wirePlayerDataService via PlayerDataService events.
    local rodKey = self._cachedEquippedRod or "BambooRod"
    return Shared.Constants.RodTiers.GetByKey(rodKey)
end

function FishingController:_getTensionZone()
    if self._tension < Shared.Fishing.TensionGreenZone then
        return "Green"
    elseif self._tension < Shared.Fishing.TensionYellowZone then
        return "Yellow"
    else
        return "Red"
    end
end

-- ============================================================
-- Public API (for other controllers)
-- ============================================================

--- Force-cancel fishing (e.g., player moved too far)
function FishingController:CancelFishing()
    self:_endFishing()
end

--- Check if player is currently fishing
function FishingController:IsFishing()
    return self._phase ~= "Idle"
end

--- Get current fishing phase
function FishingController:GetPhase()
    return self._phase
end

return FishingController
