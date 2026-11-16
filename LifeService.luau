-- LifeService: жизнь персонажа Ч рождение, возраст, рост, скорость, энерги€, сон, смерть.
-- ¬—® считаетс€ только здесь (на сервере); клиент только читает атрибуты игрока.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage.Modules.LifeConfig)
local Genetics = require(script.Parent.GeneticsService)
local R6Scaler = require(script.Parent.R6Scaler)
local Overhead = require(script.Parent.OverheadService)
local Family = require(script.Parent.FamilyService)

local Life = {}
local lives = {}       -- [player] = life
local birthTokens = {} -- [player] = token (защита от двойного рождени€)

local APPEARANCE_TIMEOUT = 5
local SCALE_EPSILON = 0.002
local MAX_DT = 1
local OVERHEAD_INTERVAL = 0.25
local SLEEP_TOGGLE_COOLDOWN = 0.5

local function r2(x) return math.floor(x * 100 + 0.5) / 100 end
local function r1(x) return math.floor(x * 10 + 0.5) / 10 end
local function serverNow() return workspace:GetServerTimeNow() end

-- ставит атрибут только если значение изменилось
local function setAttr(life, name, value)
	local cache = life.attrCache
	if cache[name] == value then return end
	cache[name] = value
	life.player:SetAttribute(name, value)
end

----------------------------------------------------------------
-- ¬—ѕќћќ√ј“≈Ћ№Ќќ≈
----------------------------------------------------------------
local function computeMods(genes)
	local m = { Growth = 1, Speed = 1, Energy = 1, Jump = 1, Sleep = 1, WakeAt = 1 }
	for _, t in ipairs(genes.Traits) do
		local def = Config.Traits[t]
		if def then
			m.Growth *= def.Growth or 1
			m.Speed *= def.Speed or 1
			m.Energy *= def.Energy or 1
			m.Jump *= def.Jump or 1
			m.Sleep *= def.Sleep or 1
			if def.WakeAt then m.WakeAt = math.min(m.WakeAt, def.WakeAt) end
		end
	end
	m.GrowthTraitMult = Config.GrowthTraitMult[genes.GrowthTrait] or 1
	m.Growth *= m.GrowthTraitMult
	return m
end

function Life.isAdult(life)
	return life.age >= life.pubertyEnd
end

function Life.getLife(player)
	return lives[player]
end

local function buildScales(life)
	local S = life.height / Config.HeightPerScale
	local head, torso, arms, legs = Vector3.one, Vector3.one, Vector3.one, Vector3.one
	for _, t in ipairs(life.genes.Traits) do
		local d = Config.Traits[t]
		if d then
			if d.Head then head *= d.Head end
			if d.Torso then torso *= d.Torso end
			if d.Arms then arms *= d.Arms end
			if d.Legs then legs *= d.Legs end
		end
	end
	return {
		HumanoidRootPart = Vector3.one * S,
		Torso = torso * S,
		Head = head * S,
		["Left Arm"] = arms * S,
		["Right Arm"] = arms * S,
		["Left Leg"] = legs * S,
		["Right Leg"] = legs * S,
	}, S
end

-- высота центра HumanoidRootPart над землЄй дл€ R6
local function rootHeight(scales)
	return 2 * scales["Left Leg"].Y + scales.Torso.Y
end

local function applySkin(character, color)
	local bc = character:FindFirstChildOfClass("BodyColors")
	if not bc then
		bc = Instance.new("BodyColors")
		bc.Parent = character
	end
	bc.HeadColor3, bc.TorsoColor3 = color, color
	bc.LeftArmColor3, bc.RightArmColor3 = color, color
	bc.LeftLegColor3, bc.RightLegColor3 = color, color
end

local function waitAppearance(player, character, timeout)
	if player:HasAppearanceLoaded() then return end
	local done = false
	local conn = player.CharacterAppearanceLoaded:Connect(function(c)
		if c == character then done = true end
	end)
	local deadline = os.clock() + timeout
	while not done and character.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	conn:Disconnect()
end

local function computeSpeed(life)
	local ratio = life.height / Config.HeightPerScale
	return life.genes.StartingSpeed * (ratio ^ Config.SpeedExponent) * life.mods.Speed
end

-- прогноз: обычный взрослый рост и рост при хорошем сне
local function predict(life)
	local g = life.genes
	local a = life.age
	local adult = life.height
	local sleepLeft = 0
	if not life.stopped then
		local childRemain = math.max(0, g.PubertyStart - a)
		local pubRemain = math.max(0, life.pubertyEnd - math.max(a, g.PubertyStart))
		adult += childRemain * life.childGrowth + pubRemain * life.pubGrowth
		if a < life.pubertyEnd then
			sleepLeft = math.max(0, g.SleepBonusTotal - life.sleepEarned)
		end
	end
	adult = math.min(adult, Config.MaxHeight)
	return adult, math.min(adult + sleepLeft, Config.MaxHeight)
end

----------------------------------------------------------------
-- ј“–»Ѕ”“џ (всЄ, что видит клиент)
----------------------------------------------------------------
local function publishStatic(life)
	local g = life.genes
	local function set(n, v) setAttr(life, n, v) end

	set("BirthHeight", g.BirthHeight)
	set("StartingSpeed", g.StartingSpeed)
	set("StopGrowingAge", Config.StopGrowingAge)
	set("PubertyStart", g.PubertyStart)
	set("PubertyDuration", g.PubertyDuration)
	set("PubertyEndAge", life.pubertyEnd)
	set("PubertyGrowthPerYear", r2(life.pubGrowth))
	set("NaturalGeneticTraitChancePercent", Config.NaturalGeneticTraitChancePercent)
	set("MaxEnergy", life.maxEnergy)
	set("Generation", life.generation)
	set("Lineage", life.lineage)
	set("LineageColor", life.lineageColor)
	set("SkinColor", g.SkinColor)
	set("GrowthTrait", g.GrowthTrait)
	set("BodyTrait", Genetics.bodyTrait(g.Traits))
	set("PubertyMutation", g.PubertyMutation)
	set("TraitList", table.concat(g.Traits, ","))
	for _, name in ipairs(Config.TraitNames) do
		set("Trait_" .. name, table.find(g.Traits, name) ~= nil)
	end

	local extra = g.ExtraLimbGenes or {}
	set("ExtraLimbGenes", HttpService:JSONEncode(extra))
	set("ExtraLimbCount", #extra)

	local pu, pr = life.parentUserIds, life.parentRecordIds
	set("ParentAUserId", pu[1] or 0)
	set("ParentBUserId", pu[2] or 0)
	set("ParentARecordId", pr[1] or "")
	set("ParentBRecordId", pr[2] or "")
	set("ParentUserIds", table.concat(pu, ","))
	set("ParentRecordIds", table.concat(pr, ","))
	set("HasShortParent", life.hasShortParent)

	local fast = (Config.Traits.FastGrowth and table.find(g.Traits, "FastGrowth")) and 0.25 or 0
	local slow = (Config.Traits.SlowGrowth and table.find(g.Traits, "SlowGrowth")) and 0.25 or 0
	set("FastGrowthBonus", r2(fast - slow))
	set("EvolutionGrowthBonus", r2(life.mods.GrowthTraitMult - 1))
	set("InheritedGrowthBonus", 0)
	set("SpeedTraitBonus", r2(life.mods.Speed - 1))
	set("HasFamilyPartner", Family.partnerOf(life.player) ~= nil)

	-- дл€ плавного возраста на клиенте
	set("AgeTickSeconds", Config.AgeTickSeconds)
end

local function publishDynamic(life)
	local adult, good = predict(life)
	local h, sp = r2(life.height), r2(life.speed)
	local function set(n, v) setAttr(life, n, v) end

	set("CurrentAge", r1(life.age))
	set("LifeAge", r1(life.age))
	set("AgeYears", math.floor(life.age))
	set("LifeHeight", h)
	set("CurrentHeight", h)
	set("CurrentSpeed", sp)
	set("LifeSpeed", sp)
	set("SpeedGrowthBonus", r2(life.speed / math.max(life.genes.StartingSpeed, 1)))
	set("Energy", r1(life.energy))
	set("IsSleeping", life.sleeping)
	set("GrowthStopped", life.stopped)
	set("SpeedStopped", life.stopped)
	set("PubertyActive", life.age >= life.genes.PubertyStart and life.age < life.pubertyEnd)
	set("PredictedAdultHeight", r2(adult))
	set("PredictedGoodSleepHeight", r2(good))
end

local function updateOverhead(life)
	if not life.overhead then return end
	Overhead.update(life.overhead, {
		Lineage = life.lineage,
		LineageColor = life.lineageColor,
		Generation = life.generation,
		Nick = life.player.DisplayName,
		Age = r1(life.age),
		Height = life.height,
		Speed = life.speed,
	})
end

local function applyHumanoid(life)
	local h = life.humanoid
	if not h.Parent then return end
	local ws = life.sleeping and 0 or life.speed
	local jp = life.sleeping and 0 or (50 * math.sqrt(math.max(life.lastScale or 1, 0.3)) * life.mods.Jump)
	if not h.UseJumpPower then h.UseJumpPower = true end
	if math.abs(h.WalkSpeed - ws) > 0.01 then h.WalkSpeed = ws end
	if math.abs(h.JumpPower - jp) > 0.01 then h.JumpPower = jp end
	if h.DisplayDistanceType ~= Enum.HumanoidDisplayDistanceType.None then
		h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

----------------------------------------------------------------
-- —ќЌ
----------------------------------------------------------------
local function setSleeping(life, value)
	if life.sleeping == value then return end
	life.sleeping = value
	applyHumanoid(life)
	setAttr(life, "IsSleeping", value)
end

function Life.requestSleep(player)
	local life = lives[player]
	if not life or life.dead or not life.ready then return end
	local now = os.clock()
	if now - (life.lastSleepToggle or 0) < SLEEP_TOGGLE_COOLDOWN then return end
	life.lastSleepToggle = now

	if life.sleeping then
		setSleeping(life, false)
	elseif life.energy < Config.SleepThreshold then
		setSleeping(life, true)
	end
end

----------------------------------------------------------------
-- —ћ≈–“№
----------------------------------------------------------------
local function finish(life, leaving)
	if life.dead then return end
	life.dead = true
	life.ready = false
	life.sleeping = false
	for _, c in ipairs(life.conns) do c:Disconnect() end
	table.clear(life.conns)
	R6Scaler.release(life.character)

	if life.player.Parent == Players then
		setAttr(life, "IsSleeping", false)
		setAttr(life, "IsAlive", false)
		setAttr(life, "CurrentAge", r1(life.age))
	end
	local ok, err = pcall(Family.onDeath, life.player, life, leaving)
	if not ok then warn("[Life] ошибка Family.onDeath:", err) end
end

function Life.release(player)
	birthTokens[player] = nil
	local life = lives[player]
	if life then
		finish(life, true)
		lives[player] = nil
	end
end

----------------------------------------------------------------
-- –ќ∆ƒ≈Ќ»≈
----------------------------------------------------------------
local function setupBody(life)
	local character, root, genes = life.character, life.root, life.genes

	R6Scaler.capture(character)
	applySkin(character, genes.SkinColor)
	R6Scaler.addLimbs(character, genes.ExtraLimbGenes, genes.SkinColor)

	local scales, S = buildScales(life)
	R6Scaler.apply(character, scales, S)
	life.lastScale = S

	-- поднимаем только один раз, пока персонаж за€корен
	local dy = rootHeight(scales) - 3
	if dy > 0 then
		character:PivotTo(root.CFrame + Vector3.new(0, dy + 0.5, 0))
	end

	life.overhead = Overhead.attach(character)
	applyHumanoid(life)
	updateOverhead(life)
end

function Life.birth(player, character)
	local token = {}
	birthTokens[player] = token
	local function alive()
		return birthTokens[player] == token and player.Parent == Players and character.Parent ~= nil
	end

	local prev = lives[player]
	if prev and not prev.dead then
		finish(prev, false)
	end

	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root or not alive() then return end
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		warn("[Life] персонаж не R6! ¬ключи Game Settings > Avatar > R6.")
		return
	end

	root.Anchored = true
	local function unanchor()
		if root.Parent then root.Anchored = false end
	end

	local profile = Family.ensureProfile(player)
	if not profile or not alive() then unanchor() return end

	-- родители и гены
	local fam = Family.pickParents(player)
	local override = Family.consumeOverride(player.UserId)
	local genes, lineage, lineageColor, generation, parentUserIds, parentRecordIds
	local hasShortParent = false

	if fam then
		local force = player:GetAttribute("DebugForceMutation") == true
		genes = Genetics.child(fam.genesA, fam.genesB, { forceMutation = force })
		lineage, lineageColor = fam.lineage, fam.lineageColor
		generation = math.max(fam.generation, profile.Generation) + 1
		parentUserIds, parentRecordIds = fam.parentUserIds, fam.parentRecordIds
		hasShortParent = fam.genesA.GrowthTrait == "Dwarfism" or fam.genesB.GrowthTrait == "Dwarfism"
			or fam.genesA.BirthHeight <= 28 or fam.genesB.BirthHeight <= 28
	else
		genes = Genetics.founder()
		lineage, lineageColor = profile.Lineage, Family.lineageColorOf(profile)
		generation = profile.Generation + 1
		parentUserIds, parentRecordIds = {}, {}
	end
	Genetics.applyOverrides(genes, override)

	local mods = computeMods(genes)
	local life = {
		player = player, character = character, humanoid = humanoid, root = root,
		genes = genes, mods = mods,
		lineage = lineage, lineageColor = lineageColor, generation = generation,
		parentUserIds = parentUserIds, parentRecordIds = parentRecordIds, hasShortParent = hasShortParent,
		age = 1, birthTime = nil,
		height = genes.BirthHeight,
		childGrowth = genes.ChildGrowth * mods.Growth,
		pubGrowth = genes.PubertyGrowthPerYear * mods.Growth,
		pubertyEnd = math.min(genes.PubertyStart + genes.PubertyDuration, Config.StopGrowingAge),
		maxEnergy = Config.MaxEnergy * mods.Energy,
		sleeping = false, stopped = false, sleepEarned = 0,
		dead = false, ready = false, lastScale = 1, overheadClock = 0,
		conns = {}, attrCache = {},
	}
	life.energy = life.maxEnergy
	life.speed = computeSpeed(life)
	lives[player] = life

	life.recordId = Family.createRecord(player, life)
	setAttr(life, "IsAlive", true)
	publishStatic(life)
	publishDynamic(life)

	table.insert(life.conns, humanoid.Died:Connect(function()
		finish(life, false)
	end))

	-- ждЄм аватар (одежда, аксессуары), потом масштабируем
	waitAppearance(player, character, APPEARANCE_TIMEOUT)
	if life.dead or not alive() then unanchor() return end

	local ok, err = pcall(setupBody, life)
	if not ok then warn("[Life] ошибка настройки тела:", err) end

	if not life.dead and alive() then
		-- возраст отсчитываетс€ от этого момента по серверным часам
		life.birthTime = serverNow() - (life.age - 1) * Config.AgeTickSeconds
		setAttr(life, "BirthServerTime", life.birthTime)
		life.ready = true
	end
	unanchor()
end

----------------------------------------------------------------
-- “»  ∆»«Ќ»
----------------------------------------------------------------
local function update(life, dt)
	local humanoid = life.humanoid
	if not humanoid.Parent or humanoid.Health <= 0 then return end
	local g, m = life.genes, life.mods

	-- возраст: от времени рождени€, без накоплени€ ошибки
	local newAge = 1 + (serverNow() - life.birthTime) / Config.AgeTickSeconds
	local years = math.max(0, newAge - life.age)
	life.age = newAge

	-- рост
	if not life.stopped then
		if life.age >= Config.StopGrowingAge then
			life.stopped = true
		else
			local rate = 0
			if life.age < g.PubertyStart then
				rate = life.childGrowth
			elseif life.age < life.pubertyEnd then
				rate = life.pubGrowth
			end
			life.height += rate * years

			-- бонус от хорошего сна в пубертате
			if life.sleeping and life.age >= g.PubertyStart and life.age < life.pubertyEnd
				and life.sleepEarned < g.SleepBonusTotal then
				local perYear = g.SleepBonusTotal / (g.PubertyDuration * Config.SleepBonusSleepShare)
				local bonus = math.min(g.SleepBonusTotal - life.sleepEarned, perYear * years * m.Sleep)
				life.height += bonus
				life.sleepEarned += bonus
			end
			life.height = math.min(life.height, Config.MaxHeight)
		end
	end

	-- скорость
	life.speed = computeSpeed(life)

	-- энерги€ и сон
	if life.sleeping then
		life.energy = math.min(life.maxEnergy, life.energy + Config.EnergyRegenPerSec * m.Sleep * dt)
		if life.energy >= life.maxEnergy * m.WakeAt then
			setSleeping(life, false)
		end
	elseif humanoid.MoveDirection.Magnitude > 0.1 then
		life.energy = math.max(0, life.energy - Config.EnergyDrainPerSec * dt)
	end

	-- масштаб (без телепортов Ч R6 сам встаЄт на удлинившиес€ ноги)
	local S = life.height / Config.HeightPerScale
	if math.abs(S - life.lastScale) / life.lastScale > SCALE_EPSILON then
		local scales
		scales, S = buildScales(life)
		R6Scaler.apply(life.character, scales, S)
		life.lastScale = S
	end

	applyHumanoid(life)
	publishDynamic(life)

	life.overheadClock += dt
	if life.overheadClock >= OVERHEAD_INTERVAL then
		life.overheadClock = 0
		updateOverhead(life)
	end
end

function Life.init(remotes)
	remotes.SleepRequest.OnServerEvent:Connect(function(player)
		Life.requestSleep(player)
	end)

	task.spawn(function()
		while true do
			local dt = math.min(task.wait(Config.UpdateInterval), MAX_DT)
			for _, life in pairs(lives) do
				if life.ready and not life.dead then
					local ok, err = pcall(update, life, dt)
					if not ok then warn("[Life] ошибка тика:", err) end
				end
			end
		end
	end)
end

return Life