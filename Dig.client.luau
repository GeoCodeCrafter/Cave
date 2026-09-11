-- goes in StarterPlayerScripts. equip the pickaxe and hold click: hits ore to mine it, hits rock to dig.
-- the server does the actual mining and digging, this just swings and says what you hit
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local swing = ReplicatedStorage:WaitForChild("CaveSwing") :: RemoteEvent
local player = Players.LocalPlayer
local mouse = player:GetMouse()

local SWING_EVERY = 0.3
local holding = false
local tool: Tool? = nil
local restGrip: CFrame? = nil

local function watch(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == "Pickaxe" then
			tool = child
			restGrip = child.Grip
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child == tool then
			tool = nil
			holding = false
		end
	end)
end
if player.Character then
	watch(player.Character)
end
player.CharacterAdded:Connect(watch)

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

-- tilt the pickaxe down and back. no animation asset needed
local function swingAnimation(t: Tool)
	local rest = restGrip or t.Grip
	TweenService:Create(t, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Grip = rest * CFrame.Angles(math.rad(-75), 0, 0),
	}):Play()
	task.delay(0.1, function()
		TweenService:Create(t, TweenInfo.new(0.16, Enum.EasingStyle.Quad), { Grip = rest }):Play()
	end)
end

while true do
	task.wait(SWING_EVERY)
	local t = tool
	if holding and t then
		swingAnimation(t)
		local target = mouse.Target
		if target then
			swing:FireServer(target, mouse.Hit.Position)
		end
	end
end
