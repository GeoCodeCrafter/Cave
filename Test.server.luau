local Players = game:GetService("Players")

-- nobody spawns until the mine exists, otherwise you land before the terrain does and fall forever
Players.CharacterAutoLoads = false

local Cave = require(game.ServerScriptService.Cave)
Cave.settings.seed = 1

-- wipe whatever preview() left in the place so there aren't two copies of every ore
Cave.clear()
local spawnAt = Cave.buildSpawnRoom()
Cave.start()

local function spawn(player: Player)
	-- make sure the terrain around the spawn has reached this player's computer first
	pcall(function()
		player:RequestStreamAroundAsync(spawnAt.Position)
	end)
	player:LoadCharacter()
end

local function setup(player: Player)
	player.CharacterAdded:Connect(function(char)
		local humanoid = char:WaitForChild("Humanoid") :: Humanoid
		humanoid.Died:Connect(function()
			task.wait(3)
			if player.Parent then
				spawn(player)
			end
		end)
	end)
	spawn(player)
end

Players.PlayerAdded:Connect(setup)
-- anyone who joined while the mine was being built
for _, player in Players:GetPlayers() do
	task.spawn(setup, player)
end
