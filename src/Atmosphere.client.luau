-- goes in StarterPlayerScripts. fades the fog, colour and floating particles to match the biome
-- you're standing in. the server works out the biome and puts it on you as the CaveBiome attribute
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

type Look = {
	fog: Color3,
	decay: Color3,
	density: number,
	tint: Color3,
	saturation: number,
	mote: { color: Color3, size: number, rate: number, speed: number, rise: number, glow: number },
	light: { ambient: Color3, outdoor: Color3, brightness: number }?,
}

-- the dark underground light the server sets. only the surface changes it
local CAVE_LIGHT = { ambient = Color3.fromRGB(6, 6, 7), outdoor = Color3.fromRGB(4, 4, 5), brightness = 0 }

local LOOKS: { [string]: Look } = {
	rock = {
		fog = Color3.fromRGB(52, 48, 46), decay = Color3.fromRGB(26, 24, 23), density = 0.38,
		tint = Color3.fromRGB(255, 244, 232), saturation = -0.05,
		mote = { color = Color3.fromRGB(255, 226, 190), size = 0.08, rate = 14, speed = 0.4, rise = 0.05, glow = 0.3 },
	},
	crystal = {
		fog = Color3.fromRGB(70, 40, 110), decay = Color3.fromRGB(30, 10, 60), density = 0.42,
		tint = Color3.fromRGB(240, 225, 255), saturation = 0.15,
		mote = { color = Color3.fromRGB(210, 150, 255), size = 0.1, rate = 22, speed = 0.5, rise = 0.2, glow = 1 },
	},
	mushroom = {
		fog = Color3.fromRGB(30, 70, 50), decay = Color3.fromRGB(10, 40, 25), density = 0.45,
		tint = Color3.fromRGB(225, 255, 235), saturation = 0.1,
		mote = { color = Color3.fromRGB(150, 255, 170), size = 0.14, rate = 18, speed = 0.3, rise = 0.6, glow = 1 },
	},
	pools = {
		fog = Color3.fromRGB(40, 80, 95), decay = Color3.fromRGB(15, 40, 50), density = 0.35,
		tint = Color3.fromRGB(225, 245, 255), saturation = 0.05,
		mote = { color = Color3.fromRGB(200, 240, 255), size = 0.07, rate = 16, speed = 0.3, rise = 0.4, glow = 0.6 },
	},
	deep = {
		fog = Color3.fromRGB(90, 40, 20), decay = Color3.fromRGB(50, 15, 5), density = 0.42,
		tint = Color3.fromRGB(255, 225, 200), saturation = 0.1,
		mote = { color = Color3.fromRGB(255, 140, 60), size = 0.1, rate = 30, speed = 1, rise = 3, glow = 1 },
	},
	-- outside at night: moonlight, thin blue haze, a few fireflies
	surface = {
		fog = Color3.fromRGB(38, 46, 70), decay = Color3.fromRGB(18, 22, 36), density = 0.3,
		tint = Color3.fromRGB(220, 230, 255), saturation = -0.1,
		mote = { color = Color3.fromRGB(220, 255, 120), size = 0.12, rate = 5, speed = 0.3, rise = 0.1, glow = 1 },
		light = { ambient = Color3.fromRGB(46, 50, 66), outdoor = Color3.fromRGB(80, 90, 120), brightness = 1.2 },
	},
}

local atmosphere = Lighting:WaitForChild("CaveAtmosphere") :: Atmosphere
local grade = Lighting:WaitForChild("CaveColor") :: ColorCorrectionEffect

-- a big invisible box that follows the camera and fills the air around you with motes
local box = Instance.new("Part")
box.Name = "AtmosphereMotes"
box.Anchored = true
box.CanCollide = false
box.CanQuery = false
box.CanTouch = false
box.CastShadow = false
box.Transparency = 1
box.Size = Vector3.new(60, 30, 60)
box.Parent = workspace

local motes = Instance.new("ParticleEmitter")
motes.Shape = Enum.ParticleEmitterShape.Box
motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
motes.Lifetime = NumberRange.new(6, 10)
motes.SpreadAngle = Vector2.new(180, 180)
motes.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.2, 0.3),
	NumberSequenceKeypoint.new(0.8, 0.3),
	NumberSequenceKeypoint.new(1, 1),
})
motes.Parent = box

RunService.RenderStepped:Connect(function()
	box.CFrame = CFrame.new(camera.CFrame.Position)
end)

local fade = TweenInfo.new(2.5, Enum.EasingStyle.Sine)

local function apply(name: string?)
	local look = LOOKS[name or "rock"] or LOOKS.rock
	TweenService:Create(atmosphere, fade, { Color = look.fog, Decay = look.decay, Density = look.density }):Play()
	TweenService:Create(grade, fade, { TintColor = look.tint, Saturation = look.saturation }):Play()
	local light = look.light or CAVE_LIGHT
	TweenService:Create(Lighting, fade, { Ambient = light.ambient, OutdoorAmbient = light.outdoor, Brightness = light.brightness }):Play()
	local m = look.mote
	motes.Color = ColorSequence.new(m.color)
	motes.Size = NumberSequence.new(m.size)
	motes.Rate = m.rate
	motes.Speed = NumberRange.new(m.speed * 0.5, m.speed)
	motes.Acceleration = Vector3.new(0, m.rise, 0)
	motes.LightEmission = m.glow
end

apply(player:GetAttribute("CaveBiome"))
player:GetAttributeChangedSignal("CaveBiome"):Connect(function()
	apply(player:GetAttribute("CaveBiome"))
end)
