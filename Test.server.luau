local Cave = require(game.ServerScriptService.Cave)

Cave.settings.seed = 1

-- build around a real tunnel first so nobody spawns inside rock
local spot = Cave.preview(nil, 2)
Cave.start()

game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		task.wait()
		char:PivotTo(CFrame.new(spot + Vector3.new(0, 3, 0)))
	end)
end)
