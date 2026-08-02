--[[
    BoatService.lua
    Deep Tide Studios — Server Service (Phase 3)
    Server-authoritative boat system: ownership, 2D-plane physics with
    momentum, tier speed/accel/turn caps, anchor, dock auto-parking at the
    Outpost, recall, storage (Trawler 40 / RV 100), co-op rod stations
    (RV 2 stations), RV sonar pings, and wind push from WeatherService.

    Authority model: server runs the physics tick at 10Hz and fires
    BoatUpdated to all clients; clients predict locally and reconcile.
    All parameters come from Shared.Constants.BoatTiers.
]]

local Knit = require(game:GetService("ReplicatedStorage"):WaitForChild("Knit"))
local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))
local BoatTiers = Shared.Constants.BoatTiers
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local S = Knit.CreateService({
    Name = "BoatService",
    Client = {
        Control = Knit.CreateSignal(),        -- (player, {Throttle, Turn})
        Anchor = Knit.CreateSignal(),         -- () -> bool anchored
        Recall = Knit.CreateSignal(),         -- () -> bool
        Dock = Knit.CreateSignal(),           -- () -> bool (request park)
        Board = Knit.CreateSignal(),          -- (ownerUserId) -> result
        LeaveBoat = Knit.CreateSignal(),      -- () -> nil
        EquipBoat = Knit.CreateSignal(),      -- (key) -> spawn active boat
        GetBoatState = Knit.CreateSignal(),   -- () -> boat state table
        BoatUpdated = Knit.CreateSignal(),    -- (state) fired to owner
        BoatSpawned = Knit.CreateSignal(),    -- (state) fired to all (model exists)
        BoatDespawned = Knit.CreateSignal(),  -- (playerName) fired to all
        SonarPing = Knit.CreateSignal(),      -- (player, pingData) RV sonar
    },
})

S.Boats = {}                 -- [player] = boat state
S.WATER_Y = 0.5              -- waterline for boat hulls
S.PHYSICS_DT = 0.1           -- 10 Hz server tick
S.LINE_BREAK_SPEED = 8       -- studs/s (surface fishing, FishingService reads this)

-- Outpost dock geometry: 6 slips around the atoll at (0,0,0)
S.DOCK_CENTER = Vector3.new(0, 0, 0)
S.DOCK_SNAP_RADIUS = 40      -- studs: auto-park when slow & near
S.DOCK_SLOT_RADIUS = 22      -- studs from center per slip
S.DOCK_SLOTS = {}

function S:_buildDockSlots()
    S.DOCK_SLOTS = {}
    for i = 1, 6 do
        local angle = (i - 1) / 6 * math.pi * 2
        local pos = S.DOCK_CENTER + Vector3.new(math.cos(angle), 0, math.sin(angle)) * S.DOCK_SLOT_RADIUS
        table.insert(S.DOCK_SLOTS, { Position = pos, Heading = math.atan2(-math.sin(angle), -math.cos(angle)), Taken = false })
    end
end

-- ============================================================
-- Lifecycle
-- ============================================================
function S:KnitInit()
    self.Client.Control:Connect(function(p, input) return self:ControlBoat(p, input) end)
    self.Client.Anchor:Connect(function(p) return self:SetAnchor(p) end)
    self.Client.Recall:Connect(function(p) return self:RecallBoat(p) end)
    self.Client.Dock:Connect(function(p) return self:ParkAtDock(p) end)
    self.Client.Board:Connect(function(p, ownerUserId) return self:BoardBoat(p, ownerUserId) end)
    self.Client.LeaveBoat:Connect(function(p) return self:LeaveBoat(p) end)
    self.Client.GetBoatState:Connect(function(p) return self:GetBoatState(p) end)
    self.Client.EquipBoat:Connect(function(p, key) return self:SpawnBoat(p, key) end)

    Players.PlayerRemoving:Connect(function(p)
        self:DespawnBoat(p)
    end)

    self:_buildDockSlots()

    -- Ensure Boats folder exists
    if not Workspace:FindFirstChild("Boats") then
        local folder = Instance.new("Folder")
        folder.Name = "Boats"
        folder.Parent = Workspace
    end
end

function S:KnitStart()
    task.spawn(function()
        local last = tick()
        while true do
            task.wait(S.PHYSICS_DT)
            local now = tick()
            local dt = math.min(now - last, 0.25)
            last = now
            self:UpdateBoats(dt)
        end
    end)
    self:_startSonarLoop()
    print("[BoatService] Started — boat physics active")
end

-- ============================================================
-- Ownership / spawn / despawn
-- ============================================================
function S:SpawnBoat(p, key)
    local d = self.Services.PlayerDataService:GetData(p)
    if not d or not d.boatData or not d.boatData.OwnedBoats[key] then
        return false, "Not owned"
    end

    -- Despawn any existing boat first
    if self.Boats[p] then self:DespawnBoat(p) end

    local tier = BoatTiers.GetByKey(key)
    local model = self:_createBoatModel(p, tier)

    self.Boats[p] = {
        Key = key,
        Tier = tier,
        Anchored = true,
        Position = self:_findFreeDockPosition(),
        Heading = 0,
        Speed = 0,
        Throttle = 0,
        Turn = 0,
        Storage = {},
        StorageCapacity = tier.FishStorage or 0,
        Occupants = { [p.UserId] = true },
        RodStations = { [p.UserId] = 1 },
        Model = model,
        ModelName = model.Name,
        Docked = false,
        LastNearbyTime = tick(),
        LastControl = tick(),
        SonarLastPing = 0,
    }

    d.boatData.EquippedBoat = key
    self.Services.PlayerDataService:SaveData(p)

    -- Place model
    self:_applyBoatModel(p, self.Boats[p])

    local state = self:GetBoatState(p)
    self.Client.BoatSpawned:FireAll(state)
    self.Client.BoatUpdated:Fire(p, state)
    return true
end

function S:DespawnBoat(p)
    local b = self.Boats[p]
    if not b then return end
    if b.Model then
        b.Model:Destroy()
    end
    -- Free dock slot
    for _, slot in ipairs(self.DOCK_SLOTS) do
        slot.Taken = false
    end
    self.Boats[p] = nil
    self.Client.BoatDespawned:FireAll(p.Name)
end

-- ============================================================
-- Model assembly (simple parts: hull, deck, wheel) — replicated via workspace
-- ============================================================
function S:_createBoatModel(p, tier)
    local model = Instance.new("Model")
    model.Name = "Boat_" .. p.Name
    model.Parent = Workspace:FindFirstChild("Boats")

    local colors = {
        Raft = Color3.fromRGB(120, 82, 45),
        Trawler = Color3.fromRGB(40, 90, 160),
        ResearchVessel = Color3.fromRGB(220, 225, 230),
    }
    local color = colors[tier.Key] or Color3.fromRGB(150, 150, 150)
    local sizeScale = tier.Tier == 1 and 1 or (tier.Tier == 2 and 1.4 or 1.8)

    local function part(name, size, offset, c)
        local pt = Instance.new("Part")
        pt.Name = name
        pt.Size = size
        pt.Position = Vector3.new(0, S.WATER_Y, 0) + offset
        pt.Anchored = true
        pt.CanCollide = false
        pt.Material = Enum.Material.SmoothPlastic
        pt.Color = c
        pt.Parent = model
        return pt
    end

    -- Hull
    local hull = part("Hull", Vector3.new(5 * sizeScale, 1.2 * sizeScale, 2.4 * sizeScale), Vector3.new(0, -0.6 * sizeScale, 0), color)
    -- Deck
    local deck = part("Deck", Vector3.new(4.4 * sizeScale, 0.3 * sizeScale, 2.0 * sizeScale), Vector3.new(0, 0.3 * sizeScale, 0), color:Lerp(Color3.new(1, 1, 1), 0.2))
    -- Wheel / helm
    local wheel = part("Wheel", Vector3.new(0.5, 0.8, 0.5), Vector3.new(0, 1.1 * sizeScale, 0.6 * sizeScale), Color3.fromRGB(60, 50, 40))
    wheel.Shape = Enum.PartType.Cylinder
    -- Mast (RV)
    if tier.Key == "ResearchVessel" then
        part("Mast", Vector3.new(0.3, 3 * sizeScale, 0.3), Vector3.new(-1.5 * sizeScale, 1.5 * sizeScale, 0), Color3.fromRGB(90, 80, 60))
    end
    -- Second rod station marker (RV)
    if tier.RodStations >= 2 then
        local station2 = part("RodStation2", Vector3.new(0.8, 0.15, 0.8), Vector3.new(-1.8 * sizeScale, 0.8 * sizeScale, 0.8 * sizeScale), Color3.fromRGB(80, 200, 120))
        station2.Material = Enum.Material.Neon
    end

    model.PrimaryPart = hull
    return model
end

function S:_applyBoatModel(p, b)
    if not b.Model then return end
    local y = S.WATER_Y
    local cframe = CFrame.new(b.Position.X, y, b.Position.Z) * CFrame.Angles(0, b.Heading, 0)
    b.Model:SetPivot(cframe)
end

-- ============================================================
-- Physics tick (server-authoritative, 2D plane, momentum)
-- ============================================================
function S:UpdateBoats(dt)
    local wind = self.Services.WeatherService and self.Services.WeatherService:GetWindVector() or Vector3.zero
    local now = tick()

    for p, b in pairs(self.Boats) do
        local t = b.Tier or BoatTiers.GetByKey(b.Key)
        if not t then continue end

        -- Momentum: accelerate toward throttle target, keep drifting when released
        local target = b.Throttle * t.Speed
        local accel = t.Speed / t.Acceleration
        local speed = b.Speed
        if target > speed then
            speed = math.min(target, speed + accel * dt)
        elseif target < speed then
            speed = math.max(target, speed - accel * dt)
        end

        -- Turning (slight speed loss at full throttle = drift feel)
        local turn = 0
        if math.abs(speed) > 0.5 then
            turn = b.Turn * t.TurnRate * dt * (1 - math.abs(b.Throttle) * 0.25)
        end
        b.Heading = b.Heading + turn
        b.Speed = speed

        local dir = Vector3.new(math.cos(b.Heading), 0, math.sin(b.Heading))
        local position = b.Position

        if b.Anchored then
            -- Hold position (anchored boats resist wind; gentle bob handled client-side)
            b.Speed = 0
            speed = 0
        else
            position = position + dir * (speed * dt) + wind * dt
        end

        -- World bounds (3,000 x 3,000 square, GDD 2.4)
        local half = 1450
        position = Vector3.new(math.clamp(position.X, -half, half), S.WATER_Y, math.clamp(position.Z, -half, half))
        b.Position = position

        -- Dock auto-parking (owner approaching at < 5 studs/s within snap radius)
        self:_checkDockParking(p, b, now)

        -- Despawn tracking: owner online or anyone within 200 studs keeps the boat
        local nearby = false
        if p.Parent then nearby = true end
        if not nearby then
            for userId in pairs(b.Occupants) do
                local occ = Players:GetPlayerByUserId(userId)
                if occ and occ.Parent then nearby = true break end
            end
        end
        if nearby then b.LastNearbyTime = now end

        self:_applyBoatModel(p, b)
        local state = self:GetBoatState(p)
        -- Replicate to the owner and all occupants (co-op riders)
        self.Client.BoatUpdated:Fire(p, state)
        for userId in pairs(b.Occupants) do
            local occ = Players:GetPlayerByUserId(userId)
            if occ and occ ~= p then
                self.Client.BoatUpdated:Fire(occ, state)
            end
        end
    end

    -- Area despawn: boats abandoned > 5 minutes
    for p, b in pairs(self.Boats) do
        if now - b.LastNearbyTime > 300 then
            self:DespawnBoat(p)
        end
    end
end

-- ============================================================
-- Dock parking (GDD 5.2): auto-park at < 5 studs/s, snap to free slip
-- ============================================================
function S:_checkDockParking(p, b, now)
    local dx, dz = b.Position.X - self.DOCK_CENTER.X, b.Position.Z - self.DOCK_CENTER.Z
    local distToDock = math.sqrt(dx * dx + dz * dz)

    if b.Docked then
        -- Undock when the owner throttles
        if math.abs(b.Throttle or 0) > 0.15 then
            b.Docked = false
            b.Anchored = false
            for _, slot in ipairs(self.DOCK_SLOTS) do slot.Taken = false end
        end
        return
    end

    if distToDock <= self.DOCK_SNAP_RADIUS and b.Speed < 5 and not b.Anchored then
        -- Snag nearest free slot
        for _, slot in ipairs(self.DOCK_SLOTS) do
            if not slot.Taken then
                slot.Taken = true
                b.Position = Vector3.new(slot.Position.X, S.WATER_Y, slot.Position.Z)
                b.Heading = slot.Heading
                b.Speed = 0
                b.Anchored = true
                b.Docked = true
                break
            end
        end
    end
end

function S:ParkAtDock(p)
    local b = self.Boats[p]
    if not b then return false end
    local dist = (b.Position - self.DOCK_CENTER).Magnitude
    if dist > 60 then return false, "Too far from dock" end
    for _, slot in ipairs(self.DOCK_SLOTS) do
        if not slot.Taken then
            slot.Taken = true
            b.Position = Vector3.new(slot.Position.X, S.WATER_Y, slot.Position.Z)
            b.Heading = slot.Heading
            b.Speed = 0
            b.Anchored = true
            b.Docked = true
            self:_applyBoatModel(p, b)
            self.Client.BoatUpdated:Fire(p, self:GetBoatState(p))
            return true
        end
    end
    return false, "No free slip"
end

-- ============================================================
-- Controls
-- ============================================================
function S:ControlBoat(p, input)
    local b = self.Boats[p]
    if not b then return false end
    if type(input) ~= "table" then return false end
    b.Throttle = math.clamp(tonumber(input.Throttle) or 0, -1, 1)
    b.Turn = math.clamp(tonumber(input.Turn) or 0, -1, 1)
    b.LastControl = tick()
    return true
end

function S:SetAnchor(p)
    local b = self.Boats[p]
    if not b then return false end
    if b.Docked then
        b.Docked = false
        for _, slot in ipairs(self.DOCK_SLOTS) do slot.Taken = false end
        b.Anchored = true -- still anchored until throttle
        return b.Anchored
    end
    b.Anchored = not b.Anchored
    if b.Anchored then b.Speed = 0 end
    return b.Anchored
end

function S:RecallBoat(p)
    local d = self.Services.PlayerDataService:GetData(p)
    if not d or not d.boatData then return false end
    if not self.Boats[p] then
        return self:SpawnBoat(p, d.boatData.EquippedBoat or "Raft")
    end
    -- Teleport to nearest free dock slip
    local b = self.Boats[p]
    for _, slot in ipairs(self.DOCK_SLOTS) do
        if not slot.Taken then
            slot.Taken = true
            b.Position = Vector3.new(slot.Position.X, S.WATER_Y, slot.Position.Z)
            b.Heading = slot.Heading
            b.Speed = 0
            b.Anchored = true
            b.Docked = true
            b.Throttle = 0
            b.Turn = 0
            self:_applyBoatModel(p, b)
            self.Client.BoatUpdated:Fire(p, self:GetBoatState(p))
            return true
        end
    end
    return false, "No free slip"
end

-- ============================================================
-- Boarding / co-op rod stations
-- ============================================================
function S:BoardBoat(p, ownerUserId)
    local owner = Players:GetPlayerByUserId(ownerUserId)
    if not owner then return false, "Owner offline" end
    local b = self.Boats[owner]
    if not b then return false, "No boat" end

    -- Capacity check
    local occupantCount = 0
    for _ in pairs(b.Occupants) do occupantCount = occupantCount + 1 end
    if occupantCount >= (b.Tier.PassengerCapacity or 2) then
        return false, "Boat full"
    end

    if b.Occupants[p.UserId] then
        return true, "Already aboard"
    end

    b.Occupants[p.UserId] = true

    -- Assign a rod station (RV has 2)
    local tier = b.Tier
    local stations = tier.RodStations or 1
    local assigned = nil
    for userId, station in pairs(b.RodStations) do
        if station == 2 then
            -- someone already has station 2
        end
    end
    local station2Taken = false
    for _, station in pairs(b.RodStations) do
        if station == 2 then station2Taken = true break end
    end
    if stations >= 2 and not station2Taken then
        assigned = 2
    else
        assigned = 1
    end
    b.RodStations[p.UserId] = assigned

    self.Client.BoatUpdated:Fire(owner, self:GetBoatState(owner))
    self.Client.BoatUpdated:Fire(p, self:GetBoatState(p))
    return true, assigned
end

function S:LeaveBoat(p)
    for _, b in pairs(self.Boats) do
        if b.Occupants[p.UserId] then
            b.Occupants[p.UserId] = nil
            b.RodStations[p.UserId] = nil
            local owner = nil
            for pl in pairs(self.Boats) do
                if self.Boats[pl] == b then owner = pl break end
            end
            if owner then
                self.Client.BoatUpdated:Fire(owner, self:GetBoatState(owner))
            end
            self.Client.BoatUpdated:Fire(p, self:GetBoatState(p))
            return true
        end
    end
    return false
end

-- ============================================================
-- Queries used by FishingService / others
-- ============================================================
function S:GetBoat(p) return self.Boats[p] end

function S:GetBoatState(p)
    local b = self.Boats[p]
    if not b then return nil end
    return {
        OwnerName = p.Name,
        Key = b.Key,
        Tier = b.Tier.Tier,
        Position = b.Position,
        Heading = b.Heading,
        Speed = b.Speed,
        Throttle = b.Throttle,
        Turn = b.Turn,
        Anchored = b.Anchored,
        Docked = b.Docked,
        ModelName = b.ModelName,
        StorageCount = #b.Storage,
        StorageCapacity = b.StorageCapacity,
        RodStations = b.Tier.RodStations or 1,
        Occupants = {},
        PassengerCapacity = b.Tier.PassengerCapacity or 2,
        WindPush = self.Services.WeatherService and self.Services.WeatherService:GetWindPush() or 0,
    }
end

--- Actual scalar speed (studs/s) — used for the 8 studs/s line-break rule
function S:GetBoatSpeed(p)
    local b = self.Boats[p]
    if not b then return 0 end
    if b.Anchored then return 0 end
    return b.Speed or 0
end

--- Is the player aboard a boat (driver or passenger)?
function S:IsOnBoat(player)
    for _, b in pairs(self.Boats) do
        if b.Occupants and b.Occupants[player.UserId] then
            return true, b
        end
    end
    return false, nil
end

function S:GetBoatPosition(player)
    for _, b in pairs(self.Boats) do
        if b.Occupants and b.Occupants[player.UserId] then
            return b.Position
        end
    end
    return nil
end

-- ============================================================
-- Storage (Trawler 40 / RV 100; Raft 0 → personal inventory)
-- ============================================================
function S:AddFishToStorage(player, fishData)
    local b = self.Boats[player]
    if not b then return false end
    if b.StorageCapacity <= 0 then return false end
    if #b.Storage >= b.StorageCapacity then return false, "Hold full" end
    table.insert(b.Storage, {
        SpeciesKey = fishData.SpeciesKey,
        SpeciesName = fishData.SpeciesName,
        Rarity = fishData.Rarity,
        Weight = fishData.Weight,
        SellPrice = fishData.SellPrice,
        Timestamp = os.time(),
    })
    self.Client.BoatUpdated:Fire(player, self:GetBoatState(player))
    return true
end

function S:GetStorageCount(player)
    local b = self.Boats[player]
    return b and #b.Storage or 0
end

-- ============================================================
-- RV sonar (GDD 3.5): ping every 4s while anchored or < 5 studs/s
-- ============================================================
function S:_startSonarLoop()
    task.spawn(function()
        while true do
            task.wait(1)
            local activePings = 0
            local now = tick()
            for p, b in pairs(self.Boats) do
                if b.Tier and b.Tier.SonarRange and b.Tier.SonarRange > 0 and activePings < 2 then
                    local moving = not b.Anchored and b.Speed >= 5
                    if not moving and now - b.SonarLastPing >= (b.Tier.SonarPingInterval or 4) then
                        b.SonarLastPing = now
                        activePings = activePings + 1
                        self:_performSonarPing(p, b)
                    end
                end
            end
        end
    end)
end

function S:_performSonarPing(player, b)
    local spawner = self.Services.ZoneService and self.Services.ZoneService:GetSpawner("Surface")
    if not spawner then return end

    local range = b.Tier.SonarRange or 60
    local detected = {}
    for fishId, fish in pairs(spawner:GetAllFish()) do
        if fish.Species and not fish:IsHooked() then
            local fpos = fish:GetPosition()
            local dx, dz = fpos.X - b.Position.X, fpos.Z - b.Position.Z
            if math.sqrt(dx * dx + dz * dz) <= range then
                table.insert(detected, {
                    FishId = fishId,
                    SpeciesKey = fish.Species.Key,
                    SpeciesName = fish.Species.Name,
                    Rarity = fish.Species.Rarity,
                    Position = fpos,
                    Distance = math.sqrt(dx * dx + dz * dz),
                })
            end
        end
    end

    self.Client.SonarPing:Fire(player, {
        Origin = b.Position,
        Range = range,
        DetectedFish = detected,
        Timestamp = tick(),
    })
end

-- ============================================================
-- Helpers
-- ============================================================
function S:_findFreeDockPosition()
    for _, slot in ipairs(self.DOCK_SLOTS) do
        if not slot.Taken then
            slot.Taken = true
            return slot.Position
        end
    end
    return self.DOCK_CENTER + Vector3.new(30, 0, 0)
end

function S:GetDockCenter()
    return self.DOCK_CENTER
end

return S
