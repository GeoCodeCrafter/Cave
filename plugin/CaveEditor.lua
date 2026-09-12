--[[
	Cave editor: a studio plugin for tweaking the generator live.

	install: copy this file into your local plugins folder and restart studio
		windows: %LOCALAPPDATA%\Roblox\Plugins
		mac:     ~/Documents/Roblox/Plugins
	then Plugins > Cave > Editor. edit mode only, it needs Cave (and optionally CaveDebug and
	CaveTimelapse) in ServerScriptService.

	every change rebuilds the cave round the camera. nothing gets saved into Cave.luau, "print
	settings" writes the changed ones to the output so you can paste them into Start.server.luau
]]
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

if RunService:IsRunning() then
	return
end

local SLIDERS = {
	{ label = "tunnel radius", path = "tunnelRadius", min = 4, max = 14, step = 0.5 },
	{ label = "chamber radius", path = "chamberRadius", min = 10, max = 40, step = 1 },
	{ label = "cavern chance", path = "cavernChance", min = 0, max = 0.4, step = 0.01 },
	{ label = "loops", path = "loopChance", min = 0, max = 0.6, step = 0.01 },
	{ label = "wall roughness", path = "roughness", min = 0, max = 5, step = 0.1 },
	{ label = "river chance", path = "riverChance", min = 0, max = 1, step = 0.05 },
	{ label = "sinkhole chance", path = "shaftChance", min = 0, max = 1, step = 0.05 },
	{ label = "lava tube chance", path = "tubeChance", min = 0, max = 1, step = 0.05 },
	{ label = "geode chance", path = "geodeChance", min = 0, max = 1, step = 0.05 },
	{ label = "hill height", path = "surface.hills", min = 0, max = 40, step = 1 },
	{ label = "build radius (chunks)", path = "buildRadius", min = 1, max = 4, step = 1, editorOnly = true },
}

local function getPath(t: any, path: string): any
	for _, key in string.split(path, ".") do
		t = t[key]
	end
	return t
end

local function setPath(t: any, path: string, v: any)
	local keys = string.split(path, ".")
	for i = 1, #keys - 1 do
		t = t[keys[i]]
	end
	t[keys[#keys]] = v
end

-- start from whatever Cave.luau has now
local values: { [string]: any } = { buildRadius = 2 }
local defaults: { [string]: any } = {}
do
	local source = ServerScriptService:FindFirstChild("Cave")
	local base = if source then require(source:Clone()) :: any else nil
	values.seed = if base then base.settings.seed else 1
	for _, s in SLIDERS do
		if not s.editorOnly then
			values[s.path] = if base then getPath(base.settings, s.path) else s.min
			defaults[s.path] = values[s.path]
		end
	end
end
local withGround = false

-- ============================================================ widget

local toolbar = plugin:CreateToolbar("Cave")
local button = toolbar:CreateButton("CaveEditor", "live cave generation editor", "", "Editor")
button.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGui(
	"CaveEditor",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 320, 700, 260, 300)
)
widget.Title = "Cave"
button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	button:SetActive(widget.Enabled)
end)

local theme = settings().Studio.Theme
local function themed(c: Enum.StudioStyleGuideColor): Color3
	return theme:GetColor(c)
end

local root = Instance.new("ScrollingFrame")
root.Size = UDim2.fromScale(1, 1)
root.CanvasSize = UDim2.new()
root.AutomaticCanvasSize = Enum.AutomaticSize.Y
root.ScrollBarThickness = 6
root.BorderSizePixel = 0
root.BackgroundColor3 = themed(Enum.StudioStyleGuideColor.MainBackground)
root.Parent = widget

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = root
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 8)
pad.PaddingLeft = UDim.new(0, 8)
pad.PaddingRight = UDim.new(0, 8)
pad.Parent = root

local order = 0
local function row(height: number): Frame
	order += 1
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, -6, 0, height)
	f.BackgroundTransparency = 1
	f.LayoutOrder = order
	f.Parent = root
	return f
end

local function text(parent: Instance, s: string, pos: UDim2, size: UDim2, right: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.Font = Enum.Font.SourceSans
	l.TextSize = 15
	l.TextColor3 = themed(Enum.StudioStyleGuideColor.MainText)
	l.TextXAlignment = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = s
	l.Parent = parent
	return l
end

local function btn(parent: Instance, s: string, pos: UDim2, size: UDim2, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Position = pos
	b.Size = size
	b.Font = Enum.Font.SourceSans
	b.TextSize = 15
	b.Text = s
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.BackgroundColor3 = themed(Enum.StudioStyleGuideColor.Button)
	b.TextColor3 = themed(Enum.StudioStyleGuideColor.ButtonText)
	b.Parent = parent
	b.Activated:Connect(onClick)
	return b
end

local status: TextLabel
local mapFrame: Frame
local lastCave: any = nil
local token = 0

local function freshCave(): any
	local source = ServerScriptService:FindFirstChild("Cave")
	if not source then
		error("there's no Cave module in ServerScriptService")
	end
	local Cave = require(source:Clone()) :: any
	Cave.settings.seed = values.seed
	for _, s in SLIDERS do
		if not s.editorOnly then
			setPath(Cave.settings, s.path, values[s.path])
		end
	end
	return Cave
end

local function tool(name: string): any
	local m = ServerScriptService:FindFirstChild(name)
	if not m then
		status.Text = name .. " isn't in ServerScriptService"
		return nil
	end
	return require(m:Clone())
end

local function camPoint(): Vector3
	return Workspace.CurrentCamera.CFrame.Position
end

-- rebuild round the camera. every change bumps the token, so a rebuild still going stops as soon
-- as a newer one wants to start
local function rebuild(now: boolean?)
	token += 1
	local mine = token
	status.Text = "waiting..."
	task.delay(if now then 0 else 0.4, function()
		if mine ~= token then
			return
		end
		local ok, err = pcall(function()
			local debugModule = ServerScriptService:FindFirstChild("CaveDebug")
			if debugModule then
				local debug: any = require(debugModule:Clone())
				debug.clear()
			end
			local Cave = freshCave()
			Cave.clear()
			Cave.prepare()
			local list = Cave.chunksAround(camPoint(), values.buildRadius, withGround)
			local t0 = os.clock()
			for i, c in list do
				if mine ~= token then
					return
				end
				Cave.generateChunk(c.X, c.Y, c.Z)
				if i % 3 == 0 then
					status.Text = ("building %d / %d"):format(i, #list)
					task.wait()
				end
			end
			lastCave = Cave
			status.Text = ("seed %d: %d chunks in %.1fs"):format(values.seed, #list, os.clock() - t0)
		end)
		if not ok then
			status.Text = "error: " .. tostring(err)
			warn("cave editor: " .. tostring(err))
		end
	end)
end

-- ============================================================ seed

do
	local r = row(26)
	text(r, "seed", UDim2.new(), UDim2.new(0, 40, 1, 0))
	local box = Instance.new("TextBox")
	box.Position = UDim2.fromOffset(44, 0)
	box.Size = UDim2.new(1, -150, 1, 0)
	box.Font = Enum.Font.Code
	box.TextSize = 15
	box.Text = tostring(values.seed)
	box.ClearTextOnFocus = false
	box.BorderSizePixel = 0
	box.BackgroundColor3 = themed(Enum.StudioStyleGuideColor.InputFieldBackground)
	box.TextColor3 = themed(Enum.StudioStyleGuideColor.MainText)
	box.Parent = r
	box.FocusLost:Connect(function()
		local n = tonumber(box.Text)
		if n then
			values.seed = math.floor(n)
			rebuild(true)
		end
		box.Text = tostring(values.seed)
	end)
	btn(r, "random", UDim2.new(1, -100, 0, 0), UDim2.new(0, 100, 1, 0), function()
		values.seed = math.random(1, 999999)
		box.Text = tostring(values.seed)
		rebuild(true)
	end)
end

-- ============================================================ sliders

local function fmt(s, v: number): string
	return if s.step >= 1 then tostring(math.floor(v + 0.5)) else ("%.2f"):format(v)
end

for _, s in SLIDERS do
	local r = row(34)
	text(r, s.label, UDim2.new(), UDim2.new(0.7, 0, 0, 16))
	local shown = text(r, "", UDim2.new(0.7, 0, 0, 0), UDim2.new(0.3, 0, 0, 16), true)

	-- a thin bar with a fill, and a taller invisible strip over it that takes the mouse
	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromOffset(0, 22)
	bar.Size = UDim2.new(1, 0, 0, 6)
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = themed(Enum.StudioStyleGuideColor.InputFieldBorder)
	bar.Parent = r
	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = themed(Enum.StudioStyleGuideColor.DialogMainButton)
	fill.Parent = bar
	local hit = Instance.new("TextButton")
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.Position = UDim2.fromOffset(0, 16)
	hit.Size = UDim2.new(1, 0, 0, 18)
	hit.Parent = r

	local function show()
		local v = values[s.path]
		fill.Size = UDim2.fromScale(math.clamp((v - s.min) / (s.max - s.min), 0, 1), 1)
		shown.Text = fmt(s, v)
	end
	local function setFromX(x: number)
		local a = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		local v = s.min + a * (s.max - s.min)
		v = math.floor(v / s.step + 0.5) * s.step
		if v ~= values[s.path] then
			values[s.path] = v
			show()
			rebuild()
		end
	end
	local dragging = false
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	hit.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
	hit.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			setFromX(input.Position.X)
		end
	end)
	hit.MouseLeave:Connect(function()
		dragging = false
	end)
	show()
end

-- ============================================================ buttons

local function buttonRow(a: string, fa: () -> (), b: string, fb: () -> ()): (TextButton, TextButton)
	local r = row(26)
	local left = btn(r, a, UDim2.new(), UDim2.new(0.5, -3, 1, 0), fa)
	local right = btn(r, b, UDim2.new(0.5, 3, 0, 0), UDim2.new(0.5, -3, 1, 0), fb)
	return left, right
end

local groundButton: TextButton
_, groundButton = buttonRow("rebuild", function()
	rebuild(true)
end, "surface: off", function()
	withGround = not withGround
	groundButton.Text = if withGround then "surface: on" else "surface: off"
	rebuild(true)
end)

buttonRow("print settings", function()
	local lines = { "-- cave settings from the editor", ("Cave.settings.seed = %d"):format(values.seed) }
	for _, s in SLIDERS do
		if not s.editorOnly and values[s.path] ~= defaults[s.path] then
			table.insert(lines, ("Cave.settings.%s = %s"):format(s.path, tostring(values[s.path])))
		end
	end
	print(table.concat(lines, "\n"))
	status.Text = "settings are in the output"
end, "stop", function()
	token += 1
	status.Text = "stopped"
end)

buttonRow("show network", function()
	local debug = tool("CaveDebug")
	if debug then
		local counts = debug.network(lastCave or freshCave(), camPoint(), 4, 2)
		status.Text = ("%d junctions, %d links, %d hubs, %d dead ends"):format(
			counts.nodes, counts.links, counts.hub or 0, (counts["end"] or 0) + (counts.pocket or 0))
	end
end, "cut away", function()
	local debug = tool("CaveDebug")
	if debug then
		debug.cutaway(lastCave or freshCave())
		status.Text = "cut. rebuild to put it back"
	end
end)

local function drawMap()
	local debug = tool("CaveDebug")
	if not debug then
		return
	end
	local data = debug.map(lastCave or freshCave(), camPoint(), 6)
	mapFrame:ClearAllChildren()
	local scale = mapFrame.AbsoluteSize.X / data.span
	local function px(x: number, z: number): (number, number)
		return (x - data.x0) * scale, (z - data.z0) * scale
	end
	for _, l in data.links do
		local ax, az = px(l.ax, l.az)
		local bx, bz = px(l.bx, l.bz)
		local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromOffset((ax + bx) / 2, (az + bz) / 2)
		f.Size = UDim2.fromOffset(len, 2)
		f.Rotation = math.deg(math.atan2(bz - az, bx - ax))
		f.BorderSizePixel = 0
		f.BackgroundColor3 = if l.ramp then debug.colors.ramp else debug.colors.link
		f.Parent = mapFrame
	end
	for _, n in data.nodes do
		local x, z = px(n.x, n.z)
		local big = if n.kind == "hub" or n.kind == "cavern" then 9 else 5
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromOffset(x, z)
		f.Size = UDim2.fromOffset(big, big)
		f.BorderSizePixel = 0
		f.BackgroundColor3 = debug.colors[n.kind] or debug.colors.tunnel
		f.Parent = mapFrame
	end
	local c = data.counts
	status.Text = ("level %d from above: %d hubs, %d caverns, %d dead ends"):format(
		data.level, c.hub or 0, c.cavern or 0, (c["end"] or 0) + (c.pocket or 0))
end

buttonRow("map", drawMap, "clear debug", function()
	local debug = tool("CaveDebug")
	if debug then
		debug.clear()
	end
	mapFrame:ClearAllChildren()
end)

buttonRow("timelapse", function()
	local lapse = tool("CaveTimelapse")
	if not lapse then
		return
	end
	token += 1
	local mine = token
	task.spawn(function()
		local ok, err = pcall(function()
			lapse.run(freshCave(), {
				center = camPoint(),
				radius = values.buildRadius + 1,
				onProgress = function(i, n)
					status.Text = ("timelapse %d / %d"):format(i, n)
				end,
				stop = function()
					return mine ~= token
				end,
			})
		end)
		status.Text = if ok then "timelapse done" else "error: " .. tostring(err)
	end)
end, "timelapse, no cut", function()
	local lapse = tool("CaveTimelapse")
	if not lapse then
		return
	end
	token += 1
	local mine = token
	task.spawn(function()
		local ok, err = pcall(function()
			lapse.run(freshCave(), {
				center = camPoint(),
				radius = values.buildRadius + 1,
				cutaway = false,
				onProgress = function(i, n)
					status.Text = ("timelapse %d / %d"):format(i, n)
				end,
				stop = function()
					return mine ~= token
				end,
			})
		end)
		status.Text = if ok then "timelapse done" else "error: " .. tostring(err)
	end)
end)

do
	local r = row(20)
	status = text(r, "ready. move the camera, then rebuild", UDim2.new(), UDim2.fromScale(1, 1))
end

do
	local r = row(270)
	mapFrame = Instance.new("Frame")
	mapFrame.Size = UDim2.fromOffset(270, 270)
	mapFrame.BorderSizePixel = 0
	mapFrame.ClipsDescendants = true
	mapFrame.BackgroundColor3 = themed(Enum.StudioStyleGuideColor.InputFieldBackground)
	mapFrame.Parent = r
end
