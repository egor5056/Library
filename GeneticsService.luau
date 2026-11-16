-- GeneticsService: гены основателя, наследование 50/50, мутации, трейты, конечности, админ-переопределения
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.LifeConfig)

local G = {}

local function rf(r) return r[1] + math.random() * (r[2] - r[1]) end
local function ri(r) return math.random(r[1], r[2]) end
local function pick(a, b) return (math.random() < 0.5) and a or b end
local function round1(x) return math.floor(x * 10 + 0.5) / 10 end

local function vec(v) return { X = v.X, Y = v.Y, Z = v.Z } end

-- одна дополнительная конечность: position в стадах относительно торса (без масштаба)
local function randomLimb(small)
	local side = (math.random() < 0.5) and -1 or 1
	local pos = Vector3.new(side * 1.0, math.random() * 1.2 - 0.6, (math.random() * 2 - 1) * 0.4)
	local dir = Vector3.new(side, math.random() * 0.8 - 0.4, math.random() * 0.8 - 0.4).Unit
	return {
		position = vec(pos),
		direction = vec(dir),
		lengthMultiplier = small and (0.35 + math.random() * 0.25) or (0.8 + math.random() * 0.5),
		depthMultiplier = small and (0.5 + math.random() * 0.3) or (0.9 + math.random() * 0.3),
	}
end

local function jitterLimb(l)
	return {
		position = l.position,
		direction = l.direction,
		lengthMultiplier = math.clamp(l.lengthMultiplier * (0.93 + math.random() * 0.14), 0.2, 2),
		depthMultiplier = math.clamp(l.depthMultiplier * (0.93 + math.random() * 0.14), 0.3, 2),
	}
end

local function has(list, name)
	return table.find(list, name) ~= nil
end

-- у трейта ExtraLimb/SmallExtraLimb должны быть гены конечностей
local function ensureLimbs(g)
	if (has(g.Traits, "ExtraLimb") or has(g.Traits, "SmallExtraLimb")) and #g.ExtraLimbGenes == 0 then
		local small = has(g.Traits, "SmallExtraLimb") and not has(g.Traits, "ExtraLimb")
		for _ = 1, math.random(1, 2) do
			table.insert(g.ExtraLimbGenes, randomLimb(small))
		end
	end
	if not (has(g.Traits, "ExtraLimb") or has(g.Traits, "SmallExtraLimb")) then
		g.ExtraLimbGenes = {}
	end
end

function G.bodyTrait(traits)
	for _, t in ipairs(Config.BodyTraits) do
		if has(traits, t) then return t end
	end
	return "Normal"
end

-- основатель рода (нет родителей)
function G.founder()
	local g = {
		BirthHeight = math.floor(rf(Config.BirthHeight) + 0.5),
		StartingSpeed = round1(rf(Config.StartingSpeed)),
		ChildGrowth = round1(rf(Config.ChildGrowth) * 10) / 10,
		PubertyStart = ri(Config.PubertyStart),
		PubertyDuration = ri(Config.PubertyDuration),
		PubertyGrowthPerYear = Config.PubertyGrowthPerYear,
		SleepBonusTotal = round1(rf(Config.SleepBonusTotal)),
		SkinColor = Config.SkinPalette[math.random(#Config.SkinPalette)],
		GrowthTrait = "Normal",
		Traits = {},
		ExtraLimbGenes = {},
		SpikyLimbGenes = {},
		PubertyMutation = "Inherited",
	}

	local r = math.random()
	if r < Config.FounderGiantChance then
		g.GrowthTrait = "Gigantism"
	elseif r < Config.FounderGiantChance + Config.FounderDwarfChance then
		g.GrowthTrait = "Dwarfism"
	end

	-- 1–4 случайных трейта (без противоречий: не берём одновременно Speed и Slow и т.п.)
	local pool = table.clone(Config.TraitNames)
	for _ = 1, math.random(1, 4) do
		local i = math.random(#pool)
		table.insert(g.Traits, pool[i])
		table.remove(pool, i)
	end
	G.fixConflicts(g.Traits)
	ensureLimbs(g)
	return g
end

local CONFLICTS = {
	{ "BigHead", "SmallHead" }, { "FastGrowth", "SlowGrowth" }, { "HighEnergy", "LowEnergy" },
	{ "Speed", "Slow" }, { "LongArms", "SmallArm" }, { "LongLegs", "SmallLeg" },
	{ "StrongBones", "WeakBones" }, { "DeepSleeper", "HeavySleeper" }, { "DeepSleeper", "LightSleeper" },
	{ "HeavySleeper", "LightSleeper" }, { "ExtraLimb", "SmallExtraLimb" },
}

function G.fixConflicts(traits)
	for _, pair in ipairs(CONFLICTS) do
		local a, b = table.find(traits, pair[1]), table.find(traits, pair[2])
		if a and b then
			table.remove(traits, math.max(a, b))
		end
	end
end

-- ребёнок: 50% от каждого родителя + редкая мутация
-- opts.forceMutation = true для тестов
function G.child(a, b, opts)
	local g = {
		BirthHeight = math.clamp(math.floor(pick(a.BirthHeight, b.BirthHeight) + math.random(-2, 2) + 0.5), Config.BirthHeight[1], Config.BirthHeight[2]),
		StartingSpeed = pick(a.StartingSpeed, b.StartingSpeed),
		ChildGrowth = pick(a.ChildGrowth, b.ChildGrowth),
		PubertyStart = pick(a.PubertyStart, b.PubertyStart),
		PubertyDuration = pick(a.PubertyDuration, b.PubertyDuration),
		PubertyGrowthPerYear = pick(a.PubertyGrowthPerYear, b.PubertyGrowthPerYear),
		SleepBonusTotal = pick(a.SleepBonusTotal, b.SleepBonusTotal),
		SkinColor = a.SkinColor:Lerp(b.SkinColor, math.random()),
		GrowthTrait = pick(a.GrowthTrait, b.GrowthTrait),
		Traits = {},
		ExtraLimbGenes = {},
		SpikyLimbGenes = {},
		PubertyMutation = "Inherited",
	}

	-- трейты: общие достаются всегда, одиночные — с шансом 50%
	local seen = {}
	for _, parent in ipairs({ a, b }) do
		for _, t in ipairs(parent.Traits) do
			if not seen[t] then
				seen[t] = true
				local both = has(a.Traits, t) and has(b.Traits, t)
				if both or math.random() < 0.5 then
					table.insert(g.Traits, t)
				end
			end
		end
	end

	-- конечности наследуются от родителя с такими же генами
	local limbSource = (#a.ExtraLimbGenes > 0 and (#b.ExtraLimbGenes == 0 or math.random() < 0.5)) and a.ExtraLimbGenes or b.ExtraLimbGenes
	for _, l in ipairs(limbSource) do
		table.insert(g.ExtraLimbGenes, jitterLimb(l))
	end
	local spikySource = pick(a.SpikyLimbGenes, b.SpikyLimbGenes)
	for _, l in ipairs(spikySource) do
		table.insert(g.SpikyLimbGenes, jitterLimb(l))
	end

	-- мутация
	local chance = (opts and opts.forceMutation) and 100 or Config.NaturalGeneticTraitChancePercent
	if math.random() * 100 < chance then
		local pool = {}
		for _, t in ipairs(Config.TraitNames) do
			if not has(g.Traits, t) then table.insert(pool, t) end
		end
		if #pool > 0 then
			local t = pool[math.random(#pool)]
			table.insert(g.Traits, t)
			g.MutatedTrait = t
		end
		g.PubertyMutation = "Random"
		g.PubertyStart = math.clamp(g.PubertyStart + math.random(-1, 1), Config.PubertyStart[1], Config.PubertyStart[2])
		g.PubertyDuration = math.clamp(g.PubertyDuration + math.random(-1, 1), Config.PubertyDuration[1], Config.PubertyDuration[2])
		if math.random() < 0.25 then
			table.insert(g.SpikyLimbGenes, randomLimb(false))
		end
	end

	G.fixConflicts(g.Traits)
	ensureLimbs(g)
	return g
end

-- админ-переопределения следующего рождения (уже валидированы и ограничены в FamilyService)
function G.applyOverrides(g, ov)
	if not ov then return g end
	if ov.Height then g.BirthHeight = ov.Height end
	if ov.PubertyStart then g.PubertyStart = ov.PubertyStart end
	if ov.PubertyDuration then g.PubertyDuration = ov.PubertyDuration end
	if ov.PubertyGrowth then g.PubertyGrowthPerYear = ov.PubertyGrowth end
	if ov.GrowthTrait then g.GrowthTrait = ov.GrowthTrait end
	if ov.Traits then
		g.Traits = table.clone(ov.Traits)
		g.ExtraLimbGenes = {}
		G.fixConflicts(g.Traits)
		ensureLimbs(g)
	end
	return g
end

return G
