# progress

**01 · first go.** camera's inside the rock here, so the tunnels show up as blobs. all the little cubes are ore, buried in the walls where you can't mine them

![first version](progress/01-first-go.png)

**02 · rock layers.** top of the mine from above, sandstone on top with the tunnels breaking through

![rock layers](progress/02-rock-layers.png)

**03 · ore clumps.** ores are clumps now instead of single cubes, but i kept spawning inside solid rock so everything looked inside out. turns out the spawn point was just a fixed spot and it's rock most of the time

![ore clumps, inside the rock](progress/03-ore-clumps.png)

**04 · tried raycasting the ores onto the walls.** 0 placed, 2080 skipped. raycasts don't see terrain you just wrote in edit mode. did at least prove the terrain matches the code 300/300, so the cave maths was fine all along

![raycast attempt, no ores](progress/04-raycast-fail.png)

**05 · tunnel network.** threw out the noise blobs, they could never guarantee every cave connects. now every chunk has a node and tunnels link the nodes, so it's one connected web. way too thin and way too grid-like though

![tunnel network, first version](progress/05-tunnel-network.png)

**06 · ores actually in the tunnels.** wider tunnels, and the ores get pushed 2 studs out of the wall because roblox draws the wall further in than the maths says. first time you can walk up to one. still way too dark though

![ores on the tunnel walls](progress/06-ores-on-walls.png)

**07 · lighting.** lantern on a chain at every junction, gold and diamond glow, warm haze, bloom. switched lighting to Future for the shadows. finally looks like a mine

![lanterns and iron on the wall](progress/07-lanterns.png)

![gold glowing by a side tunnel](progress/08-gold.png)

**09 · spawn room.** pressing play just dropped you forever, the server moved you before the terrain reached your computer. now there's a dug-out room with a real spawn pad and you only spawn once the mine's loaded. works, but it's cramped and everything's the same orange

![first spawn room](progress/09-spawn-room.png)

**10 · bigger spawn room, striped rock.** 40x40 with a dome, dug out under the floor so the terrain stops creeping over the planks. rock has thin stripes through each layer now and the light's warm white instead of orange

![bigger spawn room](progress/10-bigger-spawn.png)

**11 · the deep end.** below about -280 the walls turn to cracked lava. diamond only shows up down here

![lava walls and diamond](progress/11-deep-lava.png)

**12 · caverns.** 1 junction in 14 is a huge flattened dome with rock pillars instead of a normal chamber. seen from outside here so you can see how many there are. the pillars left a few single-voxel air bubbles in the sim, so lone air voxels get filled back in

![caverns from outside](progress/12-caverns.png)

**13 · crystal caves.** big regions of the mine turn into basalt and violet ice with neon crystals growing out of every surface. they light themselves so there's no lanterns down here

![inside a crystal tunnel](progress/13-crystal-tunnel.png)

**14 · where the biomes meet.** crystal on the left running into plain striped rock on the right. there's mushroom caves too, mossy floors and glowing mushrooms

![crystal biome next to plain rock](progress/14-crystal-meets-rock.png)

**15 · digging.** hold click on rock and you carve through it, dust comes off in the rock's colour. first version wouldn't let you dig the spawn room walls, which is exactly where you try it first, so that rule's gone

![digging into the spawn room wall](progress/15-digging.gif)

**16 · mushroom caves.** the other biome. mud walls, mossy floor, and glowing mushrooms that light the tunnel instead of lanterns

![a glowing mushroom in a mossy tunnel](progress/16-mushroom-cave.png)

**17 · decoration.** stalactites, stalagmites, rubble and little puddles (bottom left) in the plain rock bits, coloured to match the rock. the spikes look a bit like stacked boxes, roblox has no cone shape. going back to them

![stalactites and a puddle](progress/17-decoration.png)

**18 · digging through crystals.** digging used to leave ore and crystals floating in the air. now anything you dig the rock out from under breaks, ore counts as mined, the rest shatters. also chunks unload when you're far away now and your digging comes back when they reload

![digging through a crystal cave](progress/18-crystal-dig.gif)
