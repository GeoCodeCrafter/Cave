# Cave

procedural mines for roblox. every server gets a new one. tunnels generate around you as you explore, every cave connects to every other one, and ore grows on the walls.

![gold glowing next to a side tunnel](progress/08-gold.png)

## what's in it

- a new mine every server, seed shown in the corner so you can share a good one
- terrain tunnels, chambers and the odd huge cavern with rock pillars, all one connected network so there's never a sealed-off pocket
- deep chasms through several layers with rope bridges wherever a tunnel comes out
- rock changes with depth: sandstone, limestone, slate, basalt, then lava at the bottom
- biomes: plain rock with lanterns, crystal caves, mushroom caves and caves full of little tide pools
- stalactites, stalagmites, rubble and puddles in the plain rock bits
- coal, iron, gold and diamond on the walls. they grow back after you mine them and your counts save
- a spawn room with a minecart, crates and a lit first tunnel with easy ore in it
- chunks load nearest first around players and unload when nobody's near. anything you dig stays dug

## controls

equip the pickaxe (1) and hold click. hit ore to mine it, hit rock to dig through it.

## setup

with [rojo](https://rojo.space): `rokit install`, then `rojo serve` and hit connect in the studio plugin. everything goes in the right place and lighting gets set to Future.

or by hand:

1. `src/Cave.luau` goes in ServerScriptService as a ModuleScript called `Cave`
2. `src/Start.server.luau` goes next to it as a Script
3. `src/Pickaxe.client.luau` goes in StarterPlayerScripts as a LocalScript
4. set `Lighting.Technology` to Future

to keep ore counts between sessions, publish the place and turn on Studio Access to API Services (File → Experience Settings → Security).

## changing it

- same mine every time: set `LOCK_SEED` at the top of `Start.server.luau`
- everything else is in `Cave.settings` at the top of `Cave.luau`. the ones worth trying first are `tunnelRadius`, `cavernChance`, `chasmChance`, `biomes` and the `ores` table (`hits` and `respawn`)
- in edit mode, `Cave.preview()`, `Cave.findCavern()`, `Cave.findChasm()` and `Cave.findBiome("crystal")` build it without pressing play so you can fly around

every step with screenshots is in [PROGRESS.md](PROGRESS.md), changes are in [CHANGES.md](CHANGES.md). MIT licensed.
