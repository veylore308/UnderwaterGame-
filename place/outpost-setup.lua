-- Deep Tide Studios | Phase 3 Outpost Hub
-- Server/Studio setup: all geometry is BasePart-native and idempotent.
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local root = Workspace:FindFirstChild("Outpost") or Instance.new("Model")
root.Name = "Outpost"; root.Parent = Workspace
local wood = Color3.fromRGB(118,73,38); local darkWood = Color3.fromRGB(67,42,27)
local rope = Color3.fromRGB(188,151,91); local stone = Color3.fromRGB(105,111,112)
local function part(name,size,pos,color,material,parent,shape)
    local p=Instance.new("Part"); p.Name=name; p.Size=size; p.Position=pos; p.Color=color; p.Material=material or Enum.Material.WoodPlanks; p.Anchored=true; p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
    if shape then p.Shape=shape end; p.Parent=parent or root; return p
end
local function beam(name,a,b,width,color)
    local mid=(a+b)/2; local p=part(name,Vector3.new(width,width,(a-b).Magnitude),mid,color,Enum.Material.Wood)
    p.CFrame=CFrame.lookAt(mid,b); return p
end
local function lantern(pos,parent)
    local p=part("Lantern",Vector3.new(1,1,1),pos,Color3.fromRGB(255,181,61),Enum.Material.Neon,parent,Enum.PartType.Ball)
    local l=Instance.new("PointLight"); l.Name="WarmLanternGlow"; l.Color=Color3.fromRGB(255,170,72); l.Brightness=1.8; l.Range=18; l.Shadows=true; l.Parent=p
end
-- Dock: broad pier, legs, cleats, mooring rings and floating barrels.
local dock=Instance.new("Model"); dock.Name="Dock"; dock.Parent=root
for x=-18,18,3 do part("WeatheredPlank",Vector3.new(2.8,0.7,46),Vector3.new(x,3,0),wood,Enum.Material.WoodPlanks,dock) end
for x=-18,18,9 do for z=-18,18,12 do part("SupportBeam",Vector3.new(1.1,9,1.1),Vector3.new(x, -1.5,z),darkWood,Enum.Material.Wood,dock) end end
for i,x in ipairs({-14,-7,0,7,14}) do
    local cleat=part("MooringCleat",Vector3.new(2.2,0.45,0.7),Vector3.new(x,3.7,19),darkWood,Enum.Material.Wood,dock)
    beam("MooringRope",Vector3.new(x,4,20),Vector3.new(x+(i%2==0 and 5 or -5),1.3,25),0.16,rope)
    local barrel=part("FloatingBarrel",Vector3.new(2.4,1.8,2.4),Vector3.new(x,0.2,23),wood,Enum.Material.Wood,dock,Enum.PartType.Cylinder); barrel.Orientation=Vector3.new(0,0,90)
end
-- Trading Post with counter, price board, and lanterns.
local shop=Instance.new("Model"); shop.Name="TradingPost"; shop.Parent=root
part("ShopFloor",Vector3.new(18,0.6,12),Vector3.new(0,4, -9),wood,Enum.Material.WoodPlanks,shop)
part("ShopBack",Vector3.new(18,9,0.6),Vector3.new(0,8,-14.5),darkWood,Enum.Material.Wood,shop)
part("ShopLeft",Vector3.new(.6,9,12),Vector3.new(-8.7,8,-9),darkWood,Enum.Material.Wood,shop); part("ShopRight",Vector3.new(.6,9,12),Vector3.new(8.7,8,-9),darkWood,Enum.Material.Wood,shop)
part("ShopRoof",Vector3.new(21,0.8,15),Vector3.new(0,13,-9),wood,Enum.Material.WoodPlanks,shop)
part("ShopCounter",Vector3.new(14,3,1),Vector3.new(0,6,-3.4),wood,Enum.Material.Wood,shop)
local board=part("PriceBoard",Vector3.new(7,4,.3),Vector3.new(0,10,-14),Color3.fromRGB(44,29,20),Enum.Material.Wood,shop); board:SetAttribute("DisplayText","SURFACE MARKET | FISH BUY PRICES")
lantern(Vector3.new(-7,10,-3),shop); lantern(Vector3.new(7,10,-3),shop)
-- Tall leaderboard visible from incoming boats.
local lb=Instance.new("Model"); lb.Name="LeaderboardStand"; lb.Parent=root
part("LeaderboardPost",Vector3.new(2,18,2),Vector3.new(28,10,0),darkWood,Enum.Material.Wood,lb); part("LeaderboardBoard",Vector3.new(14,10,1),Vector3.new(28,19,0),wood,Enum.Material.WoodPlanks,lb)
for i,y in ipairs({21,19,17}) do part("RankSlot"..i,Vector3.new(10,1,.2),Vector3.new(28,y,-.6),Color3.fromRGB(218,177,101),Enum.Material.Wood,lb) end
-- Daily quest campfire, seats, and board.
local quest=Instance.new("Model"); quest.Name="DailyQuestArea"; quest.Parent=root
part("QuestBoardPost",Vector3.new(.8,6,.8),Vector3.new(-28,6,-2),darkWood,Enum.Material.Wood,quest); part("QuestBoard",Vector3.new(6,4,.4),Vector3.new(-28,9,-2),wood,Enum.Material.WoodPlanks,quest)
for i=1,3 do part("QuestPaper"..i,Vector3.new(1.3,1.8,.1),Vector3.new(-30+i*1.3,9,-2.25),Color3.fromRGB(235,218,166),Enum.Material.SmoothPlastic,quest) end
local fire=part("Campfire",Vector3.new(2.5,1.2,2.5),Vector3.new(-22,4,0),Color3.fromRGB(255,104,25),Enum.Material.Neon,quest,Enum.PartType.Ball); local fl=Instance.new("Fire"); fl.Heat=6; fl.Size=5; fl.Color=Color3.fromRGB(255,150,45); fl.Parent=fire; local fLight=Instance.new("PointLight"); fLight.Color=Color3.fromRGB(255,125,45); fLight.Range=20; fLight.Brightness=2; fLight.Parent=fire
for _,z in ipairs({-5,5}) do part("CampSeat",Vector3.new(5,1,1.4),Vector3.new(-22,4,z),wood,Enum.Material.Wood,quest) end
-- Trophy plinth at entrance.
local trophy=Instance.new("Model"); trophy.Name="TrophyPlinth"; trophy.Parent=root; part("StonePedestal",Vector3.new(7,4,7),Vector3.new(-28,5,18),stone,Enum.Material.Slate,trophy); part("TrophyDisplay",Vector3.new(4,0.3,4),Vector3.new(-28,7.2,18),Color3.fromRGB(205,169,75),Enum.Material.Marble,trophy)
-- Elevated VIP deck and canopy.
local vip=Instance.new("Model"); vip.Name="VIPLounge"; vip.Parent=root; part("VIPDeck",Vector3.new(18,1,14),Vector3.new(20,7,-12),Color3.fromRGB(164,108,57),Enum.Material.WoodPlanks,vip)
for _,x in ipairs({13,27}) do for _,z in ipairs({-17,-7}) do part("CanopyPost",Vector3.new(.7,7,.7),Vector3.new(x,11,z),darkWood,Enum.Material.Wood,vip) end end
part("VIPCanopy",Vector3.new(16,.5,12),Vector3.new(20,15,-12),Color3.fromRGB(44,78,77),Enum.Material.Fabric,vip)
for _,x in ipairs({15,25}) do part("VIPSeat",Vector3.new(5,2,2),Vector3.new(x,9,-12),Color3.fromRGB(190,144,87),Enum.Material.Wood,vip) end
lantern(Vector3.new(20,13,-5),vip)
-- Shared zone metadata for ZoneService and client atmosphere hooks.
local zone=part("OutpostZone",Vector3.new(90,20,90),Vector3.new(0,10,0),Color3.new(1,1,1),Enum.Material.ForceField,root); zone.Transparency=1; zone.CanCollide=false; zone.CanTouch=true; zone:SetAttribute("ZoneKey","OUTPOST_ZONE")
Lighting:SetAttribute("OutpostConfigured",true)
print("[OutpostSetup] Outpost hub created: dock, trading post, leaderboard, quest area, trophy plinth, VIP lounge")
return root
