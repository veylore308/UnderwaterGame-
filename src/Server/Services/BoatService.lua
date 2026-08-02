local Knit=require(game:GetService("ReplicatedStorage"):WaitForChild("Knit")); local Shared=require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))
local S=Knit.CreateService({Name="BoatService",Client={Control=Knit.CreateSignal(),Anchor=Knit.CreateSignal(),Recall=Knit.CreateSignal(),Dock=Knit.CreateSignal(),BoatUpdated=Knit.CreateSignal()}}); S.Boats={}
function S:KnitInit() self.Client.Control:Connect(function(p,input) return self:ControlBoat(p,input) end); self.Client.Anchor:Connect(function(p) return self:SetAnchor(p) end); self.Client.Recall:Connect(function(p) return self:RecallBoat(p) end) end
function S:SpawnBoat(p,key) local d=self.Services.PlayerDataService:GetData(p); if not d or not d.boatData.OwnedBoats[key] then return false,"Not owned" end; self.Boats[p]={Key=key,Anchored=true,Storage={}}; d.boatData.EquippedBoat=key; self.Services.PlayerDataService:SaveData(p); self.Client.BoatUpdated:Fire(p,self.Boats[p]); return true end
function S:DespawnBoat(p) self.Boats[p]=nil end
function S:ControlBoat(p,input) local b=self.Boats[p]; local t=b and Shared.Constants.BoatTiers.GetByKey(b.Key); if not t then return false end; if type(input)~="table" then return false end; b.Throttle=math.clamp(tonumber(input.Throttle) or 0,-1,1); b.Turn=math.clamp(tonumber(input.Turn) or 0,-1,1); b.Speed=t.Speed; b.LastControl=os.clock(); return true end
function S:SetAnchor(p) local b=self.Boats[p]; if not b then return false end; b.Anchored=not b.Anchored; return b.Anchored end
function S:RecallBoat(p) if not self.Boats[p] then return self:SpawnBoat(p,self.Services.PlayerDataService:GetData(p).boatData.EquippedBoat) end; self.Boats[p].RecalledAt=os.time(); return true end
function S:GetBoat(p) return self.Boats[p] end
function S:GetBoatSpeed(p) local b=self.Boats[p]; return b and (b.Anchored and 0 or b.Speed*(b.Throttle or 0)) or 0 end
return S
