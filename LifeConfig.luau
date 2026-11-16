-- LifeConfig: все константы и таблицы игры в одном месте (читают и сервер, и клиент)
local C = {}

----------------------------------------------------------------
-- ВРЕМЯ И ВОЗРАСТ
----------------------------------------------------------------
C.AgeTickSeconds = 3          -- сколько реальных секунд = 1 игровой год (в оригинале 2–6)
C.UpdateInterval = 0.2         -- частота серверного тика
C.StopGrowingAge = 20
C.RespawnTime = 3

----------------------------------------------------------------
-- РОСТ
----------------------------------------------------------------
C.BirthHeight = { 26, 39 }
C.ChildGrowth = { 2.2, 4.2 }          -- рост за год до пубертата
C.PubertyStart = { 10, 12 }
C.PubertyDuration = { 7, 9 }
C.PubertyGrowthPerYear = 2
C.SleepBonusTotal = { 18, 20 }        -- максимум доп. роста от хорошего сна в пубертате
C.SleepBonusSleepShare = 0.5          -- доля пубертата, которую нужно проспать для полного бонуса
C.MaxHeight = 135
C.HeightPerScale = 66                 -- масштаб = LifeHeight / 66  =>  HRP.Size.Y = LifeHeight / 33
C.GrowthTraitMult = { Normal = 1, Gigantism = 1.35, Dwarfism = 0.6 }

----------------------------------------------------------------
-- СКОРОСТЬ
----------------------------------------------------------------
C.StartingSpeed = { 23, 25 }
C.SpeedExponent = 1.6   -- скорость ~ StartingSpeed * (рост/66)^1.6

----------------------------------------------------------------
-- ЭНЕРГИЯ И СОН
----------------------------------------------------------------
C.MaxEnergy = 100
C.EnergyDrainPerSec = 1.5
C.EnergyRegenPerSec = 2
C.SleepThreshold = 45   -- ниже этого значения можно лечь спать

----------------------------------------------------------------
-- ГЕНЕТИКА
----------------------------------------------------------------
C.NaturalGeneticTraitChancePercent = 0.8
C.FounderGiantChance = 0.04
C.FounderDwarfChance = 0.04
C.MaxTreeRecordsPerPlayer = 30

----------------------------------------------------------------
-- СЕМЬЯ
----------------------------------------------------------------
C.InviteLifetime = 30   -- секунд жизни приглашения
C.MaxFamilies = 30
C.AdminUserIds = {}      -- сюда можно добавить UserId админов; владелец игры админ автоматически

C.Lineages = {
	"KAELVARION", "KORROR", "RAVMAROS", "ZENTHORIA", "VALKYRIX",
	"MORDEVAN", "SYLTHARA", "DRAKONIS", "ORVELIAN", "THANOSKA",
}

C.SkinPalette = {
	Color3.fromRGB(255, 224, 189), Color3.fromRGB(241, 194, 125), Color3.fromRGB(224, 172, 105),
	Color3.fromRGB(198, 134, 66), Color3.fromRGB(141, 85, 36), Color3.fromRGB(92, 58, 30),
	Color3.fromRGB(150, 90, 120), Color3.fromRGB(120, 160, 140),
}

----------------------------------------------------------------
-- ТРЕЙТЫ
-- Head/Torso/Arms/Legs = вектор масштаба части тела (перемножается)
-- Growth/Speed/Energy/Jump/Sleep = множители, WakeAt = доля энергии, при которой просыпаешься
----------------------------------------------------------------
local V = Vector3.new
C.Traits = {
	BigHead     = { Head = V(1.4, 1.4, 1.4) },
	SmallHead   = { Head = V(0.7, 0.7, 0.7) },
	BlockyHead  = { Head = V(1.15, 1, 1.15) },
	RoundyHead  = { Head = V(1.1, 1.1, 1.1) },
	SkinnyHead  = { Head = V(0.7, 1, 1) },
	ThinHead    = { Head = V(1, 1, 0.7) },
	BigTorso    = { Torso = V(1.25, 1, 1.25) },
	Bulky       = { Torso = V(1.3, 1, 1.3) },
	Muscles     = { Arms = V(1.3, 1, 1.3), Legs = V(1.3, 1, 1.3) },
	LongArms    = { Arms = V(1, 1.35, 1) },
	SmallArm    = { Arms = V(0.75, 0.75, 0.75) },
	LongLegs    = { Legs = V(1, 1.35, 1), Speed = 1.1 },
	SmallLeg    = { Legs = V(0.75, 0.75, 0.75) },
	WideLegs    = { Legs = V(1.4, 1, 1.4) },
	StrongBones = {},
	WeakBones   = {},
	FastGrowth  = { Growth = 1.25 },
	SlowGrowth  = { Growth = 0.75 },
	HighEnergy  = { Energy = 1.4 },
	LowEnergy   = { Energy = 0.7 },
	HighJump    = { Jump = 1.5 },
	Speed       = { Speed = 1.2 },
	Slow        = { Speed = 0.75 },
	ExtraLimb   = {},
	SmallExtraLimb = {},
	DeepSleeper  = { Sleep = 1.5 },
	HeavySleeper = { Sleep = 0.7 },
	LightSleeper = { Sleep = 1.2 },
	EarlyRiser   = { WakeAt = 0.85 },
}

C.TraitNames = {}
for name in pairs(C.Traits) do
	table.insert(C.TraitNames, name)
end
table.sort(C.TraitNames)

-- что считать «телосложением» для атрибута BodyTrait
C.BodyTraits = { "Bulky", "Muscles", "BigTorso" }

C.GrowthTraits = { "Normal", "Gigantism", "Dwarfism" }

return C
