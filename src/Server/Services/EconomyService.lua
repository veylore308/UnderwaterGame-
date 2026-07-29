--[[
    EconomyService.lua
    Deep Tide Studios — Server Service
    Handles all transactions: buying, selling, upgrades.
    Validates balance, processes purchases, prevents exploits.
]]

local Knit = require(game:GetService("ReplicatedStorage"):WaitForChild("Knit"))
local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))

local EconomyService = Knit.CreateService({
    Name = "EconomyService",
    Client = {
        BuyItem = Knit.CreateSignal(),       -- (itemKey, itemType, quantity?) -> { Success, Message }
        SellFish = Knit.CreateSignal(),      -- (inventoryIndex) -> { Success, CoinsEarned }
        EquipRod = Knit.CreateSignal(),      -- (rodKey) -> { Success }
        GetShopData = Knit.CreateSignal(),   -- () -> { Rods, Suits, Consumables }
        TransactionResult = Knit.CreateSignal(),
    },
})

-- ============================================================
-- Service Dependencies
-- ============================================================
-- PlayerDataService is injected by Knit at runtime
-- [economyService].Services.PlayerDataService

function EconomyService:KnitStart()
    print("[EconomyService] Started")
end

function EconomyService:KnitInit()
    -- Client buy requests
    self.Client.BuyItem:Connect(function(player, itemKey, itemType)
        return self:ProcessBuyRequest(player, itemKey, itemType)
    end)

    -- Client sell requests
    self.Client.SellFish:Connect(function(player, inventoryIndex)
        return self:SellFish(player, inventoryIndex)
    end)

    -- Client equip rod requests
    self.Client.EquipRod:Connect(function(player, rodKey)
        return self:ProcessEquipRod(player, rodKey)
    end)
end

-- ============================================================
-- Purchase Processing
-- ============================================================

function EconomyService:ProcessBuyRequest(player, itemKey, itemType)
    local playerData = self.Services.PlayerDataService:GetData(player)
    if not playerData then
        return { Success = false, Message = "Player data not loaded" }
    end

    if itemType == "Rod" then
        return self:BuyRod(player, itemKey, playerData)
    elseif itemType == "Suit" then
        return self:BuySuit(player, itemKey, playerData)
    elseif itemType == "Consumable" then
        return self:BuyConsumable(player, itemKey, playerData)
    else
        return { Success = false, Message = "Unknown item type: " .. tostring(itemType) }
    end
end

--- Purchase a fishing rod
function EconomyService:BuyRod(player, rodKey, playerData)
    local rod = Shared.Constants.RodTiers.GetByKey(rodKey)
    if not rod then
        return { Success = false, Message = "Rod not found" }
    end

    if rod.IsFuture then
        return { Success = false, Message = "This rod is not yet available" }
    end

    -- Check ownership
    if playerData.Gear.OwnedRods[rodKey] then
        return { Success = false, Message = "You already own this rod" }
    end

    -- Check unlock condition
    if rod.UnlockRequirement then
        local req = rod.UnlockRequirement
        if req.Type == "TotalCatches" and playerData.Progression.TotalCatches < req.Count then
            return { Success = false, Message = string.format("Catch %d fish to unlock", req.Count) }
        elseif req.Type == "RareCatches" then
            -- Count rare catches
            local rareCount = 0
            for key, log in pairs(playerData.CollectionLog.Species) do
                local species = Shared.Constants.FishSpecies.GetByKey(key)
                if species and species.Rarity == "Rare" then
                    rareCount = rareCount + log.Count
                end
            end
            if rareCount < req.Count then
                return { Success = false, Message = string.format("Catch %d Rare fish to unlock", req.Count) }
            end
        end
    end

    -- Check balance
    local cost = rod.Cost
    if playerData.Currency.Coins < cost then
        return { Success = false, Message = string.format("Need %d Coins (have %d)", cost, playerData.Currency.Coins) }
    end

    -- Deduct and grant
    playerData.Currency.Coins = playerData.Currency.Coins - cost
    self.Services.PlayerDataService:GrantRod(player, rodKey)
    self.Services.PlayerDataService:EquipRod(player, rodKey)
    self.Services.PlayerDataService:SaveData(player)

    return { Success = true, Message = string.format("Purchased %s!", rod.Name), ItemKey = rodKey }
end

--- Purchase a diving suit
function EconomyService:BuySuit(player, suitKey, playerData)
    local suit = Shared.Constants.SuitTiers.GetByKey(suitKey)
    if not suit then
        return { Success = false, Message = "Suit not found" }
    end

    if suit.IsFuture then
        return { Success = false, Message = "This suit is not yet available" }
    end

    if playerData.Gear.OwnedSuits[suitKey] then
        return { Success = false, Message = "You already own this suit" }
    end

    -- Check unlock condition
    if suit.UnlockRequirement then
        local req = suit.UnlockRequirement
        if req.Type == "TotalCatches" and playerData.Progression.TotalCatches < req.Count then
            return { Success = false, Message = string.format("Catch %d fish to unlock", req.Count) }
        end
        if req.RequiredRod and not playerData.Gear.OwnedRods[req.RequiredRod] then
            local rod = Shared.Constants.RodTiers.GetByKey(req.RequiredRod)
            local rodName = rod and rod.Name or req.RequiredRod
            return { Success = false, Message = string.format("Own the %s to unlock", rodName) }
        end
    end

    local cost = suit.Cost
    if playerData.Currency.Coins < cost then
        return { Success = false, Message = string.format("Need %d Coins (have %d)", cost, playerData.Currency.Coins) }
    end

    playerData.Currency.Coins = playerData.Currency.Coins - cost
    self.Services.PlayerDataService:GrantSuit(player, suitKey)
    self.Services.PlayerDataService:EquipSuit(player, suitKey)
    self.Services.PlayerDataService:SaveData(player)

    return { Success = true, Message = string.format("Purchased %s!", suit.Name), ItemKey = suitKey }
end

--- Purchase a consumable
function EconomyService:BuyConsumable(player, consumableKey, playerData)
    local consumable = nil
    for _, c in ipairs(Shared.Shop.Consumables) do
        if c.Key == consumableKey then
            consumable = c
            break
        end
    end

    if not consumable then
        return { Success = false, Message = "Consumable not found" }
    end

    local cost = consumable.Cost
    local currencyType = consumable.CurrencyType

    if currencyType == "Coins" then
        if playerData.Currency.Coins < cost then
            return { Success = false, Message = string.format("Need %d Coins", cost) }
        end
        playerData.Currency.Coins = playerData.Currency.Coins - cost
    elseif currencyType == "Gems" then
        if playerData.Currency.Gems < cost then
            return { Success = false, Message = string.format("Need %d Gems", cost) }
        end
        playerData.Currency.Gems = playerData.Currency.Gems - cost
    end

    self.Services.PlayerDataService:SaveData(player)

    -- Consumable effect is applied client-side when used
    return { Success = true, Message = string.format("Purchased %s!", consumable.Name), ItemKey = consumableKey }
end

-- ============================================================
-- Sell Fish
-- ============================================================

function EconomyService:SellFish(player, inventoryIndex)
    local success, fish = self.Services.PlayerDataService:RemoveFish(player, inventoryIndex)
    if not success then
        return { Success = false, CoinsEarned = 0, Message = "Fish not found in inventory" }
    end

    -- Calculate sell price with weight bonus
    local species = Shared.Constants.FishSpecies.GetByKey(fish.SpeciesKey)
    if not species then
        return { Success = false, CoinsEarned = 0, Message = "Unknown species" }
    end

    local basePrice = fish.SellPrice

    -- Weight bonus: top 5% of weight range = +50%
    local weightRange = species.WeightRange.Max - species.WeightRange.Min
    local weightPercentile = (fish.Weight - species.WeightRange.Min) / weightRange
    if weightPercentile >= Shared.Constants.RarityTiers.WeightBonus.PercentileThreshold then
        basePrice = math.floor(basePrice * Shared.Constants.RarityTiers.WeightBonus.PriceMultiplier)
    end

    self.Services.PlayerDataService:AddCoins(player, basePrice)

    return {
        Success = true,
        CoinsEarned = basePrice,
        Message = string.format("Sold %s for %d Coins!", species.Name, basePrice),
    }
end

---
--- Process an equip rod request (called from client)
---
function EconomyService:ProcessEquipRod(player, rodKey)
    local playerData = self.Services.PlayerDataService:GetData(player)
    if not playerData then
        return { Success = false, Message = "Player data not loaded" }
    end

    if not playerData.Gear.OwnedRods[rodKey] then
        return { Success = false, Message = "Rod not owned" }
    end

    local success, err = self.Services.PlayerDataService:EquipRod(player, rodKey)
    return { Success = success, Message = err }
end

return EconomyService
