--!strict
-- goes in ReplicatedStorage. the prop shapes, built as real meshes from code. shared so Studio (in
-- edit mode) and every player's computer build exactly the same ones: same seed, same order, same
-- shapes. meshes built on the server never reach players, so each machine makes its own
local AssetService = game:GetService("AssetService")

local CaveMeshes = {}

-- how many variants of each shape. the server picks one by number, so this has to match everywhere
CaveMeshes.counts = { spike = 6, crystal = 4, lump = 8 }

-- every triangle gets its own corners so the faces come out flat, which suits the stylized rock.
-- flipped if it faces inwards, or it'd be invisible from outside
local function addTri(em: any, a: Vector3, b: Vector3, c: Vector3, inside: Vector3)
	local n = (b - a):Cross(c - a)
	if n.Magnitude < 1e-6 then
		return
	end
	if n:Dot((a + b + c) / 3 - inside) < 0 then
		b, c = c, b
	end
	em:AddTriangle(em:AddVertex(a), em:AddVertex(b), em:AddVertex(c))
end

-- a wobbly cone, root at y = 0, tip at y = -1
local function spikeShape(em: any, rng: Random)
	local sides, rings = rng:NextInteger(6, 8), 4
	local ring = {}
	for r = 0, rings - 1 do
		local t = r / rings
		local verts = {}
		for i = 0, sides - 1 do
			local a = i / sides * math.pi * 2 + r * 0.35 + rng:NextNumber(-0.15, 0.15)
			local rr = 0.22 * (1 - t * 0.85) * rng:NextNumber(0.8, 1.2)
			table.insert(verts, Vector3.new(math.cos(a) * rr, -t, math.sin(a) * rr))
		end
		table.insert(ring, verts)
	end
	local tip = Vector3.new(rng:NextNumber(-0.02, 0.02), -1, rng:NextNumber(-0.02, 0.02))
	for r = 1, rings - 1 do
		local a, b = ring[r], ring[r + 1]
		local inside = Vector3.new(0, -(r - 0.5) / rings, 0)
		for i = 1, sides do
			local j = i % sides + 1
			addTri(em, a[i], b[i], b[j], inside)
			addTri(em, a[i], b[j], a[j], inside)
		end
	end
	local last = ring[rings]
	for i = 1, sides do
		addTri(em, last[i], tip, last[i % sides + 1], Vector3.new(0, -0.85, 0))
	end
	local top = ring[1]
	for i = 2, sides - 1 do
		addTri(em, top[1], top[i], top[i + 1], Vector3.new(0, -0.5, 0))
	end
end

-- a six-sided shard, base at y = 0, point at y = 1
local function crystalShape(em: any, rng: Random)
	local sides = 6
	local r0 = 0.2 * rng:NextNumber(0.85, 1.15)
	local twist = rng:NextNumber(0, math.pi)
	local bottom, top = {}, {}
	for i = 0, sides - 1 do
		local a = i / sides * math.pi * 2 + twist
		table.insert(bottom, Vector3.new(math.cos(a) * r0, 0, math.sin(a) * r0))
		table.insert(top, Vector3.new(math.cos(a) * r0 * 0.9, 0.72, math.sin(a) * r0 * 0.9))
	end
	local tip = Vector3.new(rng:NextNumber(-0.03, 0.03), 1, rng:NextNumber(-0.03, 0.03))
	for i = 1, sides do
		local j = i % sides + 1
		addTri(em, bottom[i], top[i], top[j], Vector3.new(0, 0.36, 0))
		addTri(em, bottom[i], top[j], bottom[j], Vector3.new(0, 0.36, 0))
		addTri(em, top[i], tip, top[j], Vector3.new(0, 0.8, 0))
	end
	for i = 2, sides - 1 do
		addTri(em, bottom[1], bottom[i], bottom[i + 1], Vector3.new(0, 0.3, 0))
	end
end

-- a lumpy rock around the origin, about 1 stud across
local function lumpShape(em: any, rng: Random)
	local lat, lon = 5, 7
	local off = rng:NextNumber(0, 100)
	local pts = {}
	for u = 0, lat do
		pts[u] = {}
		for v = 0, lon do
			local theta = u / lat * math.pi
			local phi = (v % lon) / lon * math.pi * 2
			local dir = Vector3.new(math.sin(theta) * math.cos(phi), math.cos(theta), math.sin(theta) * math.sin(phi))
			pts[u][v] = dir * 0.5 * (1 + math.noise(dir.X * 1.7 + off, dir.Y * 1.7, dir.Z * 1.7) * 0.6)
		end
	end
	for u = 0, lat - 1 do
		for v = 0, lon - 1 do
			local a, b, c, d = pts[u][v], pts[u + 1][v], pts[u + 1][v + 1], pts[u][v + 1]
			addTri(em, a, b, c, Vector3.zero)
			addTri(em, a, c, d, Vector3.zero)
		end
	end
end

local SHAPES = { spike = spikeShape, crystal = crystalShape, lump = lumpShape }
local ORDER = { "spike", "crystal", "lump" }

local lib: { [string]: { MeshPart } }? = nil
local tried = false
local building = false
local keepAlive: { any } = {} -- the EditableMeshes stay referenced so their geometry isn't freed

local function meshPart(shape: (any, Random) -> (), rng: Random): MeshPart
	local em = AssetService:CreateEditableMesh()
	shape(em, rng)
	table.insert(keepAlive, em)
	local part = AssetService:CreateMeshPartAsync(Content.fromObject(em))
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	return part
end

-- builds the whole library once and hands back the same one after. nil if meshes aren't allowed
function CaveMeshes.build(): { [string]: { MeshPart } }?
	while building do
		task.wait()
	end
	if tried then
		return lib
	end
	tried = true
	building = true
	local ok, err = pcall(function()
		local rng = Random.new(4242)
		local made = {}
		for _, kind in ORDER do
			made[kind] = {}
			for _ = 1, CaveMeshes.counts[kind] do
				table.insert(made[kind], meshPart(SHAPES[kind], rng))
			end
		end
		lib = made
	end)
	building = false
	if not ok then
		warn("cave: couldn't build prop meshes, props stay as blocks:", err)
	end
	return lib
end

return CaveMeshes
