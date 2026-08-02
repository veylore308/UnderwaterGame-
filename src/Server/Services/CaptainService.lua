local Knit=require(game:GetService("ReplicatedStorage"):WaitForChild("Knit")); local R=require(game:GetService("ReplicatedStorage").Shared.Constants.CaptainRanks)
local S=Knit.CreateService({Name="CaptainService",Client={RankUpdated=Knit.CreateSignal(),GetRank=Knit.CreateSignal()}})
function S:AwardXP(p,amount,reason) local d=self.Services.PlayerDataService:GetData(p); if not d then return false end; d.captainData.CaptainXP=math.max(0,d.captainData.CaptainXP+math.max(0,tonumber(amount) or 0)); self:CheckRank(p,d); self.Services.PlayerDataService:SaveData(p); return true end
function S:CheckRank(p,d) local rank=R[1]; for _,v in ipairs(R) do if d.captainData.CaptainXP>=v.XpRequired then rank=v end end; if rank.Name~=d.captainData.CaptainRank then d.captainData.CaptainRank=rank.Name; d.captainData.RankUnlocks=rank.Unlocks; d.tradeData.ListingSlots=rank.TradeSlots; self.Client.RankUpdated:Fire(p,rank) end end
function S:GetRank(p) local d=self.Services.PlayerDataService:GetData(p); return d and d.captainData end
function S:KnitInit() self.Client.GetRank:Connect(function(p)return self:GetRank(p)end) end
return S
