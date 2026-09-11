-- goes in StarterPlayerScripts. hold left click on rock to dig, the server does the actual digging
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local dig = ReplicatedStorage:WaitForChild("CaveDig") :: RemoteEvent
local mouse = Players.LocalPlayer:GetMouse()
local holding = false

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

UserInputService.InputBegan:Connect(function(input, typing)
	if not typing and isPress(input) then
		holding = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if isPress(input) then
		holding = false
	end
end)

while true do
	task.wait(0.15)
	-- only rock. clicking an ore mines it instead
	if holding and mouse.Target == Workspace.Terrain then
		dig:FireServer(mouse.Hit.Position)
	end
end
