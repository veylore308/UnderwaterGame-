local Rods={
 {Name="Casting Rod",Key="CastingRod",Tier=1,Cost=300,CastRange=25,ReelSpeed=1,LuckBonus=0,LineStrength=0,LureSlots=1,UnlockCondition="License"},
 {Name="Spinning Rod",Key="SpinningRod",Tier=2,Cost=2000,CastRange=40,ReelSpeed=1.4,LuckBonus=.08,LineStrength=.25,LureSlots=2,UnlockCondition="5 surface catches"},
 {Name="Deep-Sea Rod",Key="DeepSeaRod",Tier=3,Cost=8500,CastRange=60,ReelSpeed=1.9,LuckBonus=.15,LineStrength=.60,LureSlots=3,UnlockCondition="Sailor + 1 Rare surface"},
}
function Rods.GetByKey(k) for _,v in ipairs(Rods) do if v.Key==k then return v end end end
return Rods
