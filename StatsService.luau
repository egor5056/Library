-- StatsService: мировая статистика сервера (читает атрибуты игроков)
local Players = game:GetService("Players")

local Stats = {}

local function entry(player, extra)
	local e = {
		Username = player.Name,
		Name = player.DisplayName,
		Age = player:GetAttribute("CurrentAge") or 0,
		Height = player:GetAttribute("LifeHeight") or 0,
	}
	for k, v in pairs(extra or {}) do e[k] = v end
	return e
end

function Stats.get()
	local total, count, partnered = 0, 0, 0
	local tallest, shortest, oldest, fastest, slowest
	local skinCounts, skinRgb = {}, {}

	for _, p in ipairs(Players:GetPlayers()) do
		local h = p:GetAttribute("LifeHeight")
		if h then
			count += 1
			total += h
			local age = p:GetAttribute("CurrentAge") or 0
			local speed = p:GetAttribute("CurrentSpeed") or 0
			local adult = age >= (p:GetAttribute("PubertyEndAge") or 18)

			if p:GetAttribute("HasFamilyPartner") then partnered += 1 end

			if adult then
				if not tallest or h > tallest.Height then tallest = entry(p) end
				if not shortest or h < shortest.Height then shortest = entry(p) end
			end
			if not oldest or age > oldest.Age then oldest = entry(p) end
			if not fastest or speed > fastest.Speed then fastest = entry(p, { Speed = speed }) end
			if not slowest or speed < slowest.Speed then slowest = entry(p, { Speed = speed }) end

			local c = p:GetAttribute("SkinColor")
			if typeof(c) == "Color3" then
				local r, g, b = math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)
				local key = r .. "," .. g .. "," .. b
				skinCounts[key] = (skinCounts[key] or 0) + 1
				skinRgb[key] = { r, g, b }
			end
		end
	end

	local bestKey, bestCount
	for key, n in pairs(skinCounts) do
		if not bestCount or n > bestCount then bestKey, bestCount = key, n end
	end

	return {
		ServerCount = 1,
		PlayerCount = #Players:GetPlayers(),
		AverageHeight = count > 0 and (math.floor(total / count * 100 + 0.5) / 100) or 0,
		PartnerCount = math.floor(partnered / 2),
		TallestAdult = tallest,
		ShortestAdult = shortest,
		OldestPlayer = oldest,
		FastestPlayer = fastest,
		SlowestPlayer = slowest,
		MostCommonSkinColor = bestKey and skinRgb[bestKey] or nil,
		MostCommonSkinCount = bestCount or 0,
	}
end

function Stats.init(remotes)
	remotes.GetWorldStats.OnServerInvoke = function()
		return Stats.get()
	end
end

return Stats
