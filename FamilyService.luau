-- FamilyService: роды, партнёры, приглашения, семейное древо, админ-права
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.LifeConfig)
local Profile = require(script.Parent.ProfileService)
local Genetics = require(script.Parent.GeneticsService)

local F = {}

local remotes, Life
local invites = {}     -- [toUserId] = { from = userId, t = os.clock() }
local partners = {}    -- [player] = player
local families = {}    -- снимки пар (родители могут умереть, дети всё равно рождаются)
local tree = {}        -- [lineage] = { record, ... }
local overrides = {}   -- [userId] = таблица переопределений следующего рождения
local profiles = {}    -- [player] = profile
local loading = {}
local lastInvite = {}
local recordCounter = 0

local function notice(player, text)
	if player and player.Parent == Players then
		remotes.FamilyNotice:FireClient(player, text)
	end
end

local function addToTree(rec)
	local list = tree[rec.Lineage]
	if not list then
		list = {}
		tree[rec.Lineage] = list
	end
	for _, r in ipairs(list) do
		if r.RecordId == rec.RecordId then return end
	end
	table.insert(list, rec)
end

----------------------------------------------------------------
-- ПРОФИЛЬ
----------------------------------------------------------------
function F.ensureProfile(player)
	if profiles[player] then return profiles[player] end
	if loading[player] then
		while loading[player] and player.Parent == Players do
			task.wait(0.1)
		end
		return profiles[player]
	end
	loading[player] = true
	local p = Profile.load(player)
	p.Generation = p.Generation or 0
	p.Records = p.Records or {}
	if not p.Lineage then
		p.Lineage = Config.Lineages[math.random(#Config.Lineages)]
		p.LineageColor = { math.random(90, 255), math.random(90, 255), math.random(90, 255) }
	end
	profiles[player] = p
	for _, rec in ipairs(p.Records) do
		addToTree(rec)
	end
	loading[player] = nil
	return p
end

function F.lineageColorOf(profile)
	local c = profile.LineageColor
	return Color3.fromRGB(c[1], c[2], c[3])
end

----------------------------------------------------------------
-- РОДИТЕЛИ ДЛЯ НОВОЙ ЖИЗНИ
----------------------------------------------------------------
-- возвращает случайную семью (не ту, где игрок сам родитель) или nil, если пар нет
function F.pickParents(player)
	local options = {}
	for _, fam in ipairs(families) do
		if fam.a ~= player and fam.b ~= player then
			table.insert(options, fam)
		end
	end
	if #options == 0 then return nil end
	return options[math.random(#options)]
end

function F.consumeOverride(userId)
	local ov = overrides[userId]
	overrides[userId] = nil
	return ov
end

----------------------------------------------------------------
-- ДРЕВО
----------------------------------------------------------------
function F.createRecord(player, life)
	recordCounter += 1
	local rec = {
		RecordId = string.format("%d-%d-%d", player.UserId, os.time(), recordCounter),
		UserId = player.UserId,
		Name = player.DisplayName,
		Lineage = life.lineage,
		Generation = life.generation,
		ParentUserIds = life.parentUserIds or {},
		ParentRecordIds = life.parentRecordIds or {},
		BirthHeight = life.genes.BirthHeight,
		FinalHeight = life.height,
		Age = math.floor(life.age),
		GrowthTrait = life.genes.GrowthTrait,
		Traits = table.clone(life.genes.Traits),
		Alive = true,
	}
	addToTree(rec)

	local p = profiles[player]
	if p then
		table.insert(p.Records, rec)
		while #p.Records > Config.MaxTreeRecordsPerPlayer do
			table.remove(p.Records, 1)
		end
	end
	life.record = rec
	return rec.RecordId
end

----------------------------------------------------------------
-- ПАРТНРСТВО
----------------------------------------------------------------
local function setPartnerAttr(player, value)
	if player and player.Parent == Players then
		player:SetAttribute("HasFamilyPartner", value)
	end
end

local function canInvite(from, to)
	if from == to then return false end
	local lf, lt = Life.getLife(from), Life.getLife(to)
	if not lf or not lt or lf.dead or lt.dead or not lf.ready or not lt.ready then return false end
	if partners[from] or partners[to] then return false end
	return Life.isAdult(lf) and Life.isAdult(lt)
end

local function pair(a, b)
	local la, lb = Life.getLife(a), Life.getLife(b)
	if not la or not lb then return end
	partners[a], partners[b] = b, a
	setPartnerAttr(a, true)
	setPartnerAttr(b, true)

	table.insert(families, {
		a = a, b = b,
		genesA = la.genes, genesB = lb.genes,
		lineage = la.lineage, lineageColor = la.lineageColor,
		generation = math.max(la.generation, lb.generation),
		parentUserIds = { a.UserId, b.UserId },
		parentRecordIds = { la.recordId, lb.recordId },
	})
	while #families > Config.MaxFamilies do
		table.remove(families, 1)
	end

	notice(a, "You are now partners with " .. b.DisplayName .. "!")
	notice(b, "You are now partners with " .. a.DisplayName .. "!")
end

local function dissolve(player)
	local other = partners[player]
	partners[player] = nil
	if other then
		partners[other] = nil
		setPartnerAttr(other, false)
		notice(other, "Your partner " .. player.DisplayName .. " is gone.")
	end
	setPartnerAttr(player, false)
end

function F.partnerOf(player)
	return partners[player]
end

-- вызывается LifeService при смерти / выходе из игры
function F.onDeath(player, life, leaving)
	if life.record then
		life.record.FinalHeight = life.height
		life.record.Age = math.floor(life.age)
		life.record.Alive = false
	end
	local p = profiles[player]
	if p then
		p.Generation = life.generation
		local snapshot = p
		task.spawn(function() Profile.save(player, snapshot) end)
	end
	dissolve(player)
	invites[player.UserId] = nil
	if leaving then
		profiles[player] = nil
		lastInvite[player] = nil
	end
end

----------------------------------------------------------------
-- АДМИНЫ
----------------------------------------------------------------
function F.isAdmin(player)
	if table.find(Config.AdminUserIds, player.UserId) then return true end
	return game.CreatorType == Enum.CreatorType.User and game.CreatorId ~= 0 and game.CreatorId == player.UserId
end

local function validTraits(list)
	local out = {}
	if type(list) ~= "table" then return out end
	for _, t in ipairs(list) do
		if type(t) == "string" and Config.Traits[t] and not table.find(out, t) and #out < 12 then
			table.insert(out, t)
		end
	end
	return out
end

local function numberIn(v, lo, hi)
	if type(v) ~= "number" or v ~= v then return nil end
	return math.clamp(v, lo, hi)
end

----------------------------------------------------------------
-- INIT: ремоуты
----------------------------------------------------------------
function F.init(r, lifeService)
	remotes = r
	Life = lifeService

	remotes.GetFamilyPlayers.OnServerInvoke = function(player)
		local list = {}
		local myInvite = invites[player.UserId]
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				local lo = Life.getLife(other)
				local inv = invites[other.UserId]
				local valid = function(i) return i and os.clock() - i.t <= Config.InviteLifetime end
				table.insert(list, {
					UserId = other.UserId,
					Name = other.DisplayName,
					Age = lo and math.floor(lo.age) or 0,
					CanInvite = canInvite(player, other),
					InvitedYou = valid(myInvite) and myInvite.from == other.UserId or false,
					Sent = valid(inv) and inv.from == player.UserId or false,
					IsPartner = partners[player] == other,
				})
			end
		end
		return list
	end

	remotes.FamilyInvite.OnServerEvent:Connect(function(player, userId)
		if type(userId) ~= "number" then return end
		local now = os.clock()
		if lastInvite[player] and now - lastInvite[player] < 1 then return end
		lastInvite[player] = now

		local target = Players:GetPlayerByUserId(userId)
		if not target or not canInvite(player, target) then
			notice(player, "You can't invite this player right now.")
			return
		end
		invites[target.UserId] = { from = player.UserId, t = now }
		notice(player, "Invitation sent to " .. target.DisplayName .. ".")
		notice(target, player.DisplayName .. " invited you to be partners.")
	end)

	remotes.FamilyRespond.OnServerEvent:Connect(function(player, userId, accept)
		if type(userId) ~= "number" or type(accept) ~= "boolean" then return end
		local inv = invites[player.UserId]
		local expired = inv and (os.clock() - inv.t > Config.InviteLifetime)
		if not inv or inv.from ~= userId or expired then
			if expired then invites[player.UserId] = nil end
			notice(player, "Invitation is no longer valid.")
			return
		end
		invites[player.UserId] = nil

		local inviter = Players:GetPlayerByUserId(userId)
		if not inviter or not canInvite(inviter, player) then
			notice(player, "Invitation is no longer valid.")
			return
		end

		if accept then
			pair(inviter, player)
		else
			notice(inviter, player.DisplayName .. " declined your invitation.")
		end
	end)

	remotes.GetFamilyTree.OnServerInvoke = function(player)
		local lineage = player:GetAttribute("Lineage")
		local out = {}
		for _, rec in ipairs(tree[lineage] or {}) do
			table.insert(out, table.clone(rec))
		end
		table.sort(out, function(x, y)
			if x.Generation ~= y.Generation then return x.Generation < y.Generation end
			return x.RecordId < y.RecordId
		end)
		return out
	end

	remotes.LifeAdminGetPlayers.OnServerInvoke = function(player)
		if not F.isAdmin(player) then return nil end
		local list = {}
		for _, other in ipairs(Players:GetPlayers()) do
			local lo = Life.getLife(other)
			table.insert(list, {
				UserId = other.UserId,
				Name = other.DisplayName,
				Age = lo and math.floor(lo.age) or 0,
				Height = lo and lo.height or 0,
			})
		end
		return list
	end

	remotes.LifeAdminAction.OnServerEvent:Connect(function(player, data)
		if not F.isAdmin(player) then return end
		if type(data) ~= "table" or type(data.UserId) ~= "number" then return end
		local target = Players:GetPlayerByUserId(data.UserId)
		if not target then
			remotes.LifeAdminNotice:FireClient(player, "Player not found.")
			return
		end

		local ov = {}
		ov.Height = numberIn(data.Height, 10, 120)
		ov.PubertyStart = numberIn(data.PubertyStart, 5, 15)
		ov.PubertyDuration = numberIn(data.PubertyDuration, 3, 12)
		ov.PubertyGrowth = numberIn(data.PubertyGrowth, 0, 10)
		if type(data.GrowthTrait) == "string" and table.find(Config.GrowthTraits, data.GrowthTrait) then
			ov.GrowthTrait = data.GrowthTrait
		end
		if data.Traits ~= nil or data.BodyTrait ~= nil then
			local traits = validTraits(data.Traits)
			if type(data.BodyTrait) == "string" and table.find(Config.BodyTraits, data.BodyTrait) and not table.find(traits, data.BodyTrait) then
				table.insert(traits, data.BodyTrait)
			end
			ov.Traits = traits
		end

		overrides[data.UserId] = ov
		remotes.LifeAdminNotice:FireClient(player, "Genes set for the next birth of " .. target.DisplayName .. ".")
	end)
end

return F
