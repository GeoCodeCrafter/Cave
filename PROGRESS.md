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

**19 · pickaxe.** you spawn with one now. hold click and it swings, hits ore to mine it and rock to dig. first version was held backwards with the head behind you. also in this stretch: ore counts save between sessions, and ore waits for you to move before growing back into you

![holding the pickaxe in a mushroom cave](progress/19-pickaxe.png)

**20 · chasms.** long ravines cutting down through a few layers of the mine, with sagging rope bridges wherever a tunnel comes out. the bridge ends get found by walking out from the middle until there's floor. before this i tried flooding whole tunnels with water, it looked awful, so that became little tide pools instead

![rope bridges at two levels of a chasm](progress/20-chasm-bridges.png)

**21 · furnished spawn room.** rails and a minecart of coal pointing at the first tunnel, crates, barrels, a tool rack, and a sign with the controls. the first tunnel gets lanterns and some easy ore. the coal floating by the tunnel mouth here is a bug, the dug-out room reached further than the ore spots so it lost its wall. moved them further down the tunnel

![the furnished spawn room](progress/21-furnished-spawn.png)

**22 · glowworms and the dark.** it's properly dark away from lights now, you've got a helmet lamp, and F throws a flare. caverns get glowworms on the ceiling, little blue dots with a few hanging threads. a bit sparse from far away, might bump them up

![glowworms on a cavern ceiling](progress/22-glowworms.png)

**23 · rough walls.** the tunnels were perfect round tubes, which is most of why it looked basic. now the rock is bumpy, there's faint shelves along the walls in places, floors are flatter with arched ceilings, and there's boulders half sunk into the floor

![rough walls and an arched ceiling by a rope bridge](progress/23-rough-walls.png)

**24 · rock texture.** swapped roblox's stock rock for a proper pbr texture (Stylized Rock PBR Material by Nezhull, public domain). put it on rock and slate first and couldn't see it anywhere, turns out the top layers where you actually walk are sandstone and limestone. on those too now and it's a different game

![a lantern-lit tunnel with the new rock texture](progress/24-rock-texture.png)

**25 · checker boxes.** made the stalactites, crystals and ore into real meshes built from code, and they looked great in studio. in an actual game they were this: red and green checker boxes. meshes made on the server never reach players, i'd only checked the part arrived and not its shape. now the server puts down plain stand-ins and each player's computer builds the meshes itself. also found about 1 ore clump in 10 floating, the push off the wall was set for the old smooth tunnels, measured it and dropped it from 2 studs to 0.5

![ore showing up as checker boxes in game](progress/25-checker-boxes.png)

**26 · underground rivers, first go.** rivers wind downhill between junctions with real water in the bottom. this is what it looked like: a flat navy slab. reflective water in a dark cave just mirrors the dark

![the first river, a flat navy slab](progress/26-river-first.png)

**27 · rivers, fixed.** lighter clearer water that barely reflects, small waves, soft lights under the surface, a sand bed and narrower channels. you can see down it now

![a river running off down a tunnel](progress/27-river.png)

**28 · sinkholes.** round shafts from the surface down through a few layers, with a spiral ledge round the wall and a torch every quarter turn. first version bent like the tunnels do and you couldn't see down it, they're dead straight now

![looking down a sinkhole](progress/28-sinkhole.png)

**29 · looking up one.** it was still night up top at this point

![the moon through the top of a sinkhole](progress/29-sinkhole-up.png)

**30 · lava tubes.** long round tunnels deep down, cracked glowing lava floor, basalt walls, barely any bumps so they look melted instead of dug

![inside a lava tube](progress/30-lava-tube.png)

**31 · geodes.** hollow balls sealed inside solid rock, the only thing in the mine that doesn't connect. lined with glowing crystals pointing in. the only clue is a faint sparkle on the nearest tunnel wall, so you have to dig in

![inside a geode](progress/31-geode-inside.png)

**32 · a geode dug out.** what it looks like with the rock round it cleared away

![a geode from outside](progress/32-geode.png)

**33 · the surface.** the mine used to just stop at y 0. now there's hills over it, and in between the layout became random trees with loops instead of a grid, and water settles in the dips in the floor. first versions of this had it at night (too dark), stopping in a cliff 2 chunks out, and caverns punching huge holes in the grass. it loads 10 chunks out now and the caves keep a proper roof

![hills over the mine](progress/33-surface.png)

**34 · a sinkhole from up top.** the orange blobs in the last one are these

![a sinkhole in the grass](progress/34-sinkhole-from-above.png)

**35 · caves, not tunnels.** people on reddit said it was mostly tunnels and the terrain looked like an early 2000s game. both fair. passages open out into wide galleries now, there are rooms along the way, and the wall bumps that were smaller than the terrain grid (they came out as jagged facets) are gone. big spaces get glowworms and glowing fungus so they're not just black past your lamp

![a big cave with pillars and glowworms](progress/35-bigger-caves.png)

**36 · down a chasm.** rope bridges across one of the ravines, looking down between them

![rope bridges across a chasm](progress/36-chasm-bridges.png)

**37 · cut open.** a block of the new caves sliced in half with the debug cut-away. same block of rock had 16% air before, 33% now

![the new caves in cross section](progress/37-caves-cut-open.png)

**38 · where the biomes meet.** one of the new big caves with glowing mushrooms on one side, plain rock in the middle and crystals on the other, and a pool in front

![mushroom, rock and crystal caves meeting in one big cave](progress/38-biomes-meet.png)
