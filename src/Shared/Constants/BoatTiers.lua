local Boats = {
 {Name="Raft",Key="Raft",Tier=1,Cost={Coins=0,Gems=0},Speed=12,Acceleration=3,TurnRate=40,FishStorage=0,RodStations=1,PassengerCapacity=2,SonarRange=0,SonarPingInterval=0,CosmeticSlots={Skin=1,Flag=0,Trail=0,HullGlow=0},RankRequirement=1,UnlockCondition="Captain's License",Description="A humble wooden raft."},
 {Name="Trawler",Key="Trawler",Tier=2,Cost={Coins=4500,Gems=0},Speed=18,Acceleration=2.5,TurnRate=55,FishStorage=40,RodStations=1,PassengerCapacity=4,SonarRange=0,SonarPingInterval=0,CosmeticSlots={Skin=1,Flag=1,Trail=0,HullGlow=0},RankRequirement=1,UnlockCondition="LifetimeSailed:2000",Description="A sturdy working boat."},
 {Name="Research Vessel",Key="ResearchVessel",Tier=3,Cost={Coins=25000,Gems=300},Speed=24,Acceleration=2,TurnRate=70,FishStorage=100,RodStations=2,PassengerCapacity=6,SonarRange=60,SonarPingInterval=4,CosmeticSlots={Skin=1,Flag=1,Trail=1,HullGlow=1},RankRequirement=3,UnlockCondition="First Mate + Rare surface catch",Description="A premium vessel with sonar."},
}
function Boats.GetByKey(k) for _,v in ipairs(Boats) do if v.Key==k then return v end end end
function Boats.GetByTier(t) for _,v in ipairs(Boats) do if v.Tier==t then return v end end end
return Boats
