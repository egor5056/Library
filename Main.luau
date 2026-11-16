-- Main: точка входа. Создаёт ремоуты, подключает сервисы и ведёт игроков.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Modules.LifeConfig)
local Services = ServerScriptService:WaitForChild("Services")
local Life = require(Services.LifeService)
local Family = require(Services.FamilyService)
local Stats = require(Services.StatsService)

-- ремоуты (контракт как в оригинале)
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
for _, name in ipairs({ "GetFamilyTree", "GetFamilyPlayers", "GetWorldStats", "LifeAdminGetPlayers" }) do
	local r = Instance.new("RemoteFunction")
	r.Name = name
	r.Parent = remotes
end
for _, name in ipairs({ "FamilyInvite", "FamilyRespond", "FamilyNotice", "SleepRequest", "LifeAdminAction", "LifeAdminNotice" }) do
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
end
remotes.Parent = ReplicatedStorage

Players.RespawnTime = Config.RespawnTime

Family.init(remotes, Life)
Stats.init(remotes)
Life.init(remotes)

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		Life.birth(player, character)
	end)
	if player.Character then
		task.spawn(Life.birth, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	Life.release(player)
end)

-- сохранение при закрытии сервера
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		Life.release(player)
	end
end)
