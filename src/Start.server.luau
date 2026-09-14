local Players = game:GetService("Players")

-- a new mine every server. put a number here to always get the same one
local LOCK_SEED: number? = nil

-- nobody spawns until the mine exists, otherwise you land before the terrain does and fall forever
Players.CharacterAutoLoads = false

local Cave = require(game.ServerScriptService.Cave)
Cave.settings.seed = LOCK_SEED or Random.new():NextInteger(1, 999999)
print("cave: seed", Cave.settings.seed)

-- wipe whatever preview() left in the place so there aren't two copies of every ore
Cave.clear()
-- you start outside on the hills next to a cave mouth. Cave.buildSpawnRoom() is the old underground room
local spawnAt = Cave.buildSurfaceSpawn()
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
