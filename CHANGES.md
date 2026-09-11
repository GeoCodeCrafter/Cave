# changes

- first version: chambers + spaghetti tunnels with terrain, generates around players, ore on walls
- can generate in edit mode now with Cave.preview() so you can actually look at it, Cave.clear() wipes it
- rock layers by depth (sandstone > limestone > slate > basalt) with wavy edges, rock patches, dirt floors, lava at the bottom, custom colours
- ores were buried inside the walls, now they're clumps of chunks stuck on the wall surface poking into the tunnel. gold is foil, diamond is glass
- kept spawning inside solid rock so you never actually saw a tunnel. findSpawn() looks for air with a floor, preview() puts the camera there and play mode spawns you there
- tried raycasting ores onto the walls, raycasts miss fresh terrain in edit mode so 0 ores. added Cave.check() which showed the terrain matches the code 300/300, so ores go straight on the voxel face again
- new cave shape that's always connected: one node per chunk, tunnels to the next node east and south, some ramps down a level, some chambers, all bent with noise. noise blobs could never guarantee that
- first go at the network still left 84 sealed pockets: tunnels got thinner than a voxel and the bending tore them. gentler bend + 4 stud minimum radius = one connected cave, 0 pockets
- caves were too narrow and too grid-like. wider tunnels (8), bigger chambers, nodes spread across more of the chunk, south links only 60% of the time plus some diagonals. still one connected cave in the sim, 0 sealed pockets
- added Cave.measure() to find out where roblox actually draws the wall, run it in play mode
- ores were still a couple of studs inside the rock, roblox draws the wall further into the tunnel than the maths. added oreOffset to push them out
- lighting: a lantern on a chain at every tunnel junction, gold and diamond glow, dark warm ambient, haze, bloom, slight colour grade
- mining: click ore to hit it (coal 3 hits up to diamond 12), it shakes and throws chips, breaks into bits on the last hit, goes on the leaderboard, grows back later. server checks reach and a cooldown
- kept falling forever on play: the server teleported you before the terrain reached your computer. added a spawn room (plank floor, beams, lamp, real SpawnLocation) dug out at a junction, and players only spawn once the mine is built and streamed in. respawns you there when you die
- spawn room was cramped, terrain smoothing crept over the floor. now 40x40 with a dome, dug out under the floor too
- walls: thin stripes running through each rock layer, less saturated colours, lanterns and fog more neutral so it's not all one orange
- big caverns: 1 junction in 14 gets a huge flattened dome (75-110 studs across) with 2-4 rock pillars instead of a chamber. pillars left a few 1-voxel sealed pockets in the sim so lone air voxels get filled back in
- ores sit where the wall really is (blending the air/rock values) instead of the voxel edge, which was 1-3 studs behind the visible wall
