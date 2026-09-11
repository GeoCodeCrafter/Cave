local Cave = require(game.ServerScriptService.Cave)

Cave.settings.seed = 1
Cave.start()

-- drop players into the mine
game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		task.wait()
		char:PivotTo(CFrame.new(0, -40, 0))
	end)
end)
