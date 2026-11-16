-- ProfileService: сохранение рода, поколения и древа игрока в DataStore.
-- В Studio нужно включить Game Settings > Security > Enable Studio Access to API Services, иначе данные не будут сохраняться (игра правильно работает без этого).
local DataStoreService = game:GetService("DataStoreService")

local Profile = {}

local store
local okStore = pcall(function()
	store = DataStoreService:GetDataStore("EvolutionProfile_v1")
end)

local function key(player)
	return "u_" .. player.UserId
end

function Profile.load(player)
	if okStore and store then
		local ok, data = pcall(function()
			return store:GetAsync(key(player))
		end)
		if ok and type(data) == "table" then
			return data
		end
		if not ok then
			warn("[Profile] не удалось загрузить:", data)
		end
	end
	return { Generation = 0, Records = {} }
end

function Profile.save(player, data)
	if not (okStore and store) then return end
	local ok, err = pcall(function()
		store:SetAsync(key(player), data)
	end)
	if not ok then
		warn("[Profile] не удалось сохранить:", err)
	end
end

return Profile
