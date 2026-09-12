--[[
	debug views. they all work in edit mode, from the command bar or the editor plugin:

		local Cave = require(game.ServerScriptService.Cave)
		local CaveDebug = require(game.ServerScriptService.CaveDebug)
		CaveDebug.network(Cave)   -- the tunnel network as lines through the rock, junctions coloured by type
		CaveDebug.cutaway(Cave)   -- slices the built terrain in half on the camera's side, so you see the layers
		CaveDebug.map(Cave)       -- the network from above as data, the plugin draws it
		CaveDebug.clear()

	build something first (Cave.preview()), they show whatever's round the camera
]]
local Workspace = game:GetService("Workspace")

local CaveDebug = {}

CaveDebug.colors = {
	hub = Color3.fromRGB(255, 80, 60),
	cavern = Color3.fromRGB(190, 90, 255),
	chamber = Color3.fromRGB(255, 200, 60),
	pocket = Color3.fromRGB(90, 170, 255),
	["end"] = Color3.fromRGB(90, 170, 255),
	tunnel = Color3.fromRGB(230, 230, 230),
	link = Color3.fromRGB(200, 200, 210),
	ramp = Color3.fromRGB(120, 255, 140),
}

local function root(): Folder
	local f = Workspace:FindFirstChild("CaveDebug")
	if not f then
		f = Instance.new("Folder")
		f.Name = "CaveDebug"
		f.Parent = Workspace
	end
	return f :: Folder
end

-- one model per colour, each with a highlight drawn over everything, so the lines show through the rock
local function group(name: string, color: Color3): Model
	local f = root()
	local m = f:FindFirstChild(name) :: Model?
	if not m then
		local made = Instance.new("Model")
		made.Name = name
		local h = Instance.new("Highlight")
		h.FillColor = color
		h.FillTransparency = 0.15
		h.OutlineTransparency = 1
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Parent = made
		made.Parent = f
		m = made
	end
	return m :: Model
end

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, ball: boolean?)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.CFrame = cf
	if ball then
		p.Shape = Enum.PartType.Ball
	end
	p.Parent = parent
end

function CaveDebug.clear()
	local f = Workspace:FindFirstChild("CaveDebug")
	if f then
		f:Destroy()
	end
end

-- every junction in a box of chunks round the centre, from its level down
local function eachNode(Cave, center: Vector3, radius: number, levels: number, fn: (Vector3, { Vector3 }, string) -> ())
	local net = Cave.network
	local SIZE = Cave.SIZE
	local top = math.floor(Cave.settings.top / SIZE) - 1
	local cx, cz = math.floor(center.X / SIZE), math.floor(center.Z / SIZE)
	local cy = math.min(math.floor(center.Y / SIZE), top)
	for y = cy, cy - levels + 1, -1 do
		if net.hasNode(y) then
			for x = cx - radius, cx + radius do
				for z = cz - radius, cz + radius do
					fn(Vector3.new(x, y, z), net.linkedTo(x, y, z), net.nodeKind(x, y, z))
				end
			end
		end
	end
end

local function linkKey(a: Vector3, b: Vector3): string
	local ka, kb = a.X .. "," .. a.Y .. "," .. a.Z, b.X .. "," .. b.Y .. "," .. b.Z
	return if ka < kb then ka .. "|" .. kb else kb .. "|" .. ka
end

-- the network as balls and lines. the real tunnels bend round these lines, the lines are the plan.
-- red = hub (4+ tunnels), purple = cavern, yellow = chamber, blue = dead end, green lines = ramps down
function CaveDebug.network(Cave, center: Vector3?, radius: number?, levels: number?): { [string]: number }
	CaveDebug.clear()
	local net = Cave.network
	local c = center or Workspace.CurrentCamera.CFrame.Position
	local counts: { [string]: number } = { nodes = 0, links = 0 }
	local drawn: { [string]: boolean } = {}
	eachNode(Cave, c, radius or 4, levels or 2, function(g, links, kind)
		local a = net.unwarp(net.nodeAt(g.X, g.Y, g.Z))
		local big = if kind == "hub" or kind == "cavern" then 6 else 3.5
		local color = CaveDebug.colors[kind] or CaveDebug.colors.tunnel
		part(group(kind, color), Vector3.one * big, CFrame.new(a), color, true)
		counts.nodes += 1
		counts[kind] = (counts[kind] or 0) + 1
		for _, l in links do
			local key = linkKey(g, l)
			if not drawn[key] then
				drawn[key] = true
				local b = net.unwarp(net.nodeAt(l.X, l.Y, l.Z))
				local ramp = l.Y ~= g.Y
				local name = if ramp then "ramp" else "link"
				part(group(name, CaveDebug.colors[name]), Vector3.new(0.8, 0.8, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), CaveDebug.colors[name])
				counts.links += 1
			end
		end
	end)
	return counts
end

-- slices away everything on the camera's side of a flat cut through the centre, terrain and props,
-- so you look straight at a cross-section: the rock layers, and tunnels cut open. rebuild to undo
function CaveDebug.cutaway(Cave, center: Vector3?): Vector3
	local camera = Workspace.CurrentCamera
	local c = center or camera.CFrame.Position + camera.CFrame.LookVector * 60
	local toCam = camera.CFrame.Position - c
	-- cut along whichever flat axis faces the camera most
	local normal = if math.abs(toCam.X) > math.abs(toCam.Z)
		then Vector3.new(math.sign(toCam.X), 0, 0)
		else Vector3.new(0, 0, math.sign(toCam.Z))
	local depth, width, height = 900, 1800, 900
	local size = if normal.X ~= 0 then Vector3.new(depth, height, width) else Vector3.new(width, height, depth)
	Workspace.Terrain:FillBlock(CFrame.new(Vector3.new(c.X, Cave.settings.top - 300, c.Z) + normal * (depth / 2)), size, Enum.Material.Air)
	for _, name in { "Ores", "Lanterns", "Decor", "Bridges", "Rivers", "SpawnRoom" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			for _, m in f:GetChildren() do
				local ok, pos = pcall(function()
					return (m :: any):GetPivot().Position
				end)
				if ok and (pos - c):Dot(normal) > 0 then
					m:Destroy()
				end
			end
		end
	end
	return normal
end

-- the network on one level seen from above, in chunk units, for the plugin to draw
function CaveDebug.map(Cave, center: Vector3?, radius: number?)
	local net = Cave.network
	local SIZE = Cave.SIZE
	local c = center or Workspace.CurrentCamera.CFrame.Position
	local r = radius or 6
	local nodes, links = {}, {}
	local drawn: { [string]: boolean } = {}
	local counts: { [string]: number } = {}
	eachNode(Cave, c, r, 1, function(g, linked, kind)
		local a = net.nodeAt(g.X, g.Y, g.Z) / SIZE
		table.insert(nodes, { x = a.X, z = a.Z, kind = kind, links = #linked })
		counts[kind] = (counts[kind] or 0) + 1
		for _, l in linked do
			local key = linkKey(g, l)
			if not drawn[key] then
				drawn[key] = true
				local b = net.nodeAt(l.X, l.Y, l.Z) / SIZE
				table.insert(links, { ax = a.X, az = a.Z, bx = b.X, bz = b.Z, ramp = l.Y ~= g.Y })
			end
		end
	end)
	local cy = math.min(math.floor(c.Y / SIZE), math.floor(Cave.settings.top / SIZE) - 1)
	return {
		x0 = math.floor(c.X / SIZE) - r,
		z0 = math.floor(c.Z / SIZE) - r,
		span = r * 2 + 1,
		level = cy,
		nodes = nodes,
		links = links,
		counts = counts,
	}
end

return CaveDebug
