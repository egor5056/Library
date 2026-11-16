-- R6Scaler: масштабирование R6-персонажа от исходных размеров (apply можно вызывать сколько угодно раз)
-- capture(character)                 Ч запомнить исходные размеры (после загрузки внешности)
-- apply(character, scales, S)        Ч scales = { [им€ детали] = Vector3 }, S = общий масштаб
-- addLimbs(character, genes, color)  Ч дополнительные конечности
-- release(character)                 Ч перестать отслеживать персонажа
local R6Scaler = {}

local PART_NAMES = { "HumanoidRootPart", "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
local ONE = Vector3.one
local EPS = 1e-4

local cache = setmetatable({}, { __mode = "k" })

local function mulCF(cf, s)
	return CFrame.new(cf.Position * s) * cf.Rotation
end

-- масштаб s (в ос€х части тела) > в ос€х повЄрнутой детали
local function toLocalScale(rot, s)
	return Vector3.new(
		(rot.XVector * s).Magnitude,
		(rot.YVector * s).Magnitude,
		(rot.ZVector * s).Magnitude
	)
end

local function captureMeshes(part)
	local list = {}
	for _, c in ipairs(part:GetChildren()) do
		if c:IsA("SpecialMesh") then
			table.insert(list, {
				mesh = c, scale = c.Scale, offset = c.Offset,
				-- у FileMesh размер задаЄт Scale; у остальных (Head, BrickЕ) Ч размер детали
				file = c.MeshType == Enum.MeshType.FileMesh,
			})
		end
	end
	return list
end

local function captureAtts(part)
	local map = {}
	for _, c in ipairs(part:GetChildren()) do
		if c:IsA("Attachment") then map[c] = c.CFrame end
	end
	return map
end

local function applyMeshes(list, s)
	for _, m in ipairs(list) do
		if m.mesh.Parent then
			if m.file then m.mesh.Scale = m.scale * s end
			m.mesh.Offset = m.offset * s
		end
	end
end

local function applyAtts(map, s)
	for att, cf in pairs(map) do
		if att.Parent then
			att.CFrame = mulCF(cf, s)
		else
			map[att] = nil
		end
	end
end

----------------------------------------------------------------
-- ј —≈——”ј–џ
----------------------------------------------------------------
local function scaleOf(d, entry)
	return d.current[entry.name] or ONE
end

local function findBodyAttachment(d, attName)
	for name, e in pairs(d.parts) do
		if name ~= "HumanoidRootPart" then
			local a = e.part:FindFirstChild(attName)
			if a and a:IsA("Attachment") then
				if not e.atts[a] then
					-- аттачмент по€вилс€ позже Ч восстанавливаем исходное значение
					e.atts[a] = mulCF(a.CFrame, ONE / scaleOf(d, e))
				end
				return a, e
			end
		end
	end
end

local function captureAccessory(d, acc)
	if d.accs[acc] then return d.accs[acc] end
	local handle = acc:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then return nil end

	local weld = handle:FindFirstChild("AccessoryWeld")
	if weld and not weld:IsA("JointInstance") then weld = nil end
	local handleIsPart0 = weld ~= nil and weld.Part0 == handle

	local hAtt = handle:FindFirstChildOfClass("Attachment")
	local bAtt, entry
	if hAtt then bAtt, entry = findBodyAttachment(d, hAtt.Name) end

	if not entry and weld then
		local body = handleIsPart0 and weld.Part1 or weld.Part0
		entry = body and d.parts[body.Name]
	end
	entry = entry or d.parts.Head
	if not entry then return nil end

	local a = {
		handle = handle, entry = entry, weld = weld, handleIsPart0 = handleIsPart0,
		hAtt = bAtt and hAtt or nil, bAtt = bAtt,
		size = handle.Size,
		meshes = captureMeshes(handle),
		atts = captureAtts(handle),
		rot = CFrame.identity,
	}

	if a.hAtt then
		a.rot = entry.atts[bAtt].Rotation * a.atts[hAtt].Rotation:Inverse()
	elseif weld then
		-- старые шл€пы без аттачментов
		local s = scaleOf(d, entry)
		local hc = handleIsPart0 and weld.C0 or weld.C1
		local bc = handleIsPart0 and weld.C1 or weld.C0
		a.hc = hc
		a.bc = mulCF(bc, ONE / s)
		a.rot = (bc * hc:Inverse()).Rotation
	end

	-- аксессуары не вли€ют на физику тела
	handle.Massless = true
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false

	d.accs[acc] = a
	return a
end

local function applyAccessory(d, a)
	if not a.handle.Parent then return end
	local s = scaleOf(d, a.entry)
	local ls = toLocalScale(a.rot, s)

	a.handle.Size = a.size * ls
	applyMeshes(a.meshes, ls)
	applyAtts(a.atts, ls)

	local w = a.weld
	if w and w.Parent then
		local hc, bc
		if a.hAtt and a.bAtt then
			hc, bc = a.hAtt.CFrame, a.bAtt.CFrame
		elseif a.hc then
			hc, bc = mulCF(a.hc, ls), mulCF(a.bc, s)
		end
		if hc then
			if a.handleIsPart0 then
				w.C0, w.C1 = hc, bc
			else
				w.C0, w.C1 = bc, hc
			end
		end
	end
	-- RigidConstraint сам следует за аттачментами
end

----------------------------------------------------------------
-- ƒќѕќЋЌ»“≈Ћ№Ќџ≈  ќЌ≈„Ќќ—“»
-- genes = массив { position, direction, lengthMultiplier, depthMultiplier }
----------------------------------------------------------------
local function applyLimbs(d)
	local ts = d.current.Torso or ONE
	local S = d.S
	for _, l in ipairs(d.limbs) do
		if l.part.Parent then
			local g = l.gene
			local pos = Vector3.new(g.position.X, g.position.Y, g.position.Z)
			local dir = Vector3.new(g.direction.X, g.direction.Y, g.direction.Z)
			if dir.Magnitude < EPS then dir = Vector3.xAxis end
			dir = dir.Unit
			local up = math.abs(dir.Y) > 0.99 and Vector3.zAxis or Vector3.yAxis

			local len = 2 * (g.lengthMultiplier or 1) * S
			local thick = 0.8 * (g.depthMultiplier or 1) * S
			l.part.Size = Vector3.new(thick, thick, len)

			local start = pos * ts
			l.weld.C0 = CFrame.lookAt(start, start + dir, up) * CFrame.new(0, 0, -len / 2)
		end
	end
end

function R6Scaler.addLimbs(character, genes, color)
	local d = cache[character]
	local torso = d and d.parts.Torso
	if not torso or not genes then return end

	for i, gene in ipairs(genes) do
		local part = Instance.new("Part")
		part.Name = "ExtraLimb" .. i
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = Vector3.one

		local weld = Instance.new("Weld")
		weld.Part0 = torso.part
		weld.Part1 = part
		weld.Parent = part
		part.Parent = character

		table.insert(d.limbs, { part = part, weld = weld, gene = gene })
	end
	applyLimbs(d)
end

----------------------------------------------------------------
-- ќ—Ќќ¬Ќќ≈
----------------------------------------------------------------
function R6Scaler.release(character)
	local d = cache[character]
	if not d then return end
	for _, c in ipairs(d.conns) do c:Disconnect() end
	cache[character] = nil
end

function R6Scaler.capture(character)
	R6Scaler.release(character)

	local d = { parts = {}, motors = {}, accs = {}, limbs = {}, current = {}, S = 1, conns = {} }

	for _, name in ipairs(PART_NAMES) do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			d.parts[name] = {
				name = name, part = p, size = p.Size,
				meshes = captureMeshes(p), atts = captureAtts(p),
			}
		end
	end

	-- только суставы между част€ми тела
	for _, e in pairs(d.parts) do
		for _, m in ipairs(e.part:GetChildren()) do
			if m:IsA("Motor6D") and m.Part0 and m.Part1
				and d.parts[m.Part0.Name] and d.parts[m.Part1.Name] then
				table.insert(d.motors, {
					m = m, c0 = m.C0, c1 = m.C1, p0 = m.Part0.Name, p1 = m.Part1.Name,
				})
			end
		end
	end

	for _, acc in ipairs(character:GetChildren()) do
		if acc:IsA("Accessory") then captureAccessory(d, acc) end
	end

	cache[character] = d

	-- аксессуары, надетые позже
	table.insert(d.conns, character.ChildAdded:Connect(function(child)
		if not child:IsA("Accessory") then return end
		task.defer(function()
			local handle = child:WaitForChild("Handle", 3)
			if handle then handle:WaitForChild("AccessoryWeld", 1) end
			if cache[character] ~= d or child.Parent ~= character then return end
			local a = captureAccessory(d, child)
			if a then applyAccessory(d, a) end
		end)
	end))
	table.insert(d.conns, character.ChildRemoved:Connect(function(child)
		d.accs[child] = nil
	end))
	table.insert(d.conns, character.Destroying:Connect(function()
		R6Scaler.release(character)
	end))
end

-- возвращает true, если что-то реально помен€лось
function R6Scaler.apply(character, scales, S)
	local d = cache[character]
	if not d then return false end
	S = S or 1

	local changed = math.abs(S - d.S) > EPS
	for name in pairs(d.parts) do
		local s = scales[name] or ONE
		local cur = d.current[name]
		if not cur or (s - cur).Magnitude > EPS then
			d.current[name] = s
			changed = true
		end
	end
	if not changed then return false end
	d.S = S

	-- 1) части тела + их аттачменты
	for name, e in pairs(d.parts) do
		if e.part.Parent then
			local s = d.current[name]
			e.part.Size = e.size * s
			applyMeshes(e.meshes, s)
			applyAtts(e.atts, s)
		end
	end

	-- 2) суставы
	for _, mo in ipairs(d.motors) do
		if mo.m.Parent then
			mo.m.C0 = mulCF(mo.c0, d.current[mo.p0] or ONE)
			mo.m.C1 = mulCF(mo.c1, d.current[mo.p1] or ONE)
		end
	end

	-- 3) аксессуары (после аттачментов тела)
	for acc, a in pairs(d.accs) do
		if acc.Parent == character then
			applyAccessory(d, a)
		else
			d.accs[acc] = nil
		end
	end

	-- 4) доп. конечности
	applyLimbs(d)
	return true
end

return R6Scaler