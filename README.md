# Herts

Herts is planned as a third-person open-world action-adventure set in the
Ukrainian Great Meadow (Великий Луг) in 1675. The player is a Cossack exploring
the steppe and fighting the Ottoman-Tatar army. The intended presentation is
atmospheric low-poly scenery with warm southern Ukrainian light and a Ukrainian
game UI. The Summer board contains the current design and visual references.

## Current state

The main scene has an animated Cossack and a third-person movement controller.
The first area starts on a rocky ridge above a poppy field, a winding river and
a palisaded timber village at sunset. Combat and UI come later. The original
Summer starter scene remains at `main.tscn` as a reference.

## Open and run

Open this folder as a Summer Engine project and run the project with Play.
The configured entry point is `scenes/main.tscn`. Use WASD to walk, hold Shift
to run, Space to jump, and the mouse to look around. Press F near the horse to
mount or dismount; use WASD to ride and hold Shift to gallop. Escape releases the mouse;
click the game to capture it again. Press M to open or close the world map; Escape
also closes the map. The project uses the Forward+ renderer and
Jolt 3D physics.

## Project layout

- `scenes/main.tscn` assembles the characters, lighting, region and map. Character spawn positions live here.
- `scenes/characters/` contains the reusable player and horse scenes; their scripts are in `scripts/characters/`.
- `scenes/world/sun.tscn` and `scenes/world/world_environment.tscn` contain shared lighting and sky settings.
- `scenes/world/great_meadow/region.tscn` assembles the existing area. Its terrain, river pieces, stronghold, forest, road, grass, poppies and atmosphere are separate scenes in the same folder. Rocks and their collision remain in the region scene.
- `scenes/ui/world_map.tscn` and `scripts/ui/` contain the world map.
- `assets/` holds models, textures and other source assets; `project.godot` contains project settings.

## Working on the world together

Open a component's own scene to edit it, rather than making local overrides in
`main.tscn` or `region.tscn`. Teammates can work in different component scenes
at the same time; agree on one owner for any shared scene while it is being
edited. Coordinate changes to the region assembly, character spawns, lighting,
and `project.godot` separately. The river's surface, highlights, shoreline and
water collision are separate files, so coordinate changes across them. When
changing rocks, keep the visuals and collision together.

The current meadow is one bounded region, not a streamed world. To expand it,
add neighboring region scenes in their own folders and instance them into the
world assembly. Agree on world coordinates and matching terrain heights at
shared edges; also connect roads, rivers, vegetation and collision across those
edges. The current terrain was sampled on a 2.5-unit grid and covers X -100 to
100 and Z -155 to 35. The world map has fixed bounds in
`scripts/ui/world_map.gd`; update its framing when the playable world grows.

For much larger worlds, plan region loading and unloading, terrain chunking,
level of detail, and testing of collision and transitions before expanding
indefinitely. None of those streaming features is implemented yet. The existing
terrain, road and grass scenes still contain large baked data and should each
have one editor at a time.

`scripts/world/level_builder.gd` is the legacy generator used for the original
monolithic scene. Its rebuild entry points reject the assembled instanced region
to avoid replacing the split scenes. Use a separate scratch scene for legacy
generation; adapting it to build individual regions is future work.

## The walk clip

The character package ships a walk with a strong pelvis sway. `scripts/characters/stoic_walk.gd`
rebuilds it into `assets/models/herts_cossack_reference/walk_stoic.tres`: the pelvis barely
turns, the arms swing about half as far, and the shoulder girdle counter-rotates against the
stride. The thighs are counter-posed against that quiet pelvis (rotation plus a small socket
offset), so the legs keep the source stride exactly and the feet stop sliding sideways.
`scripts/characters/player.gd` plays that clip as `WalkStoic` (see
`walk_animation_override`). Edit the keep and gain constants in the baker and save the clip
again to retune the gait.

## The sprint clip

`scripts/characters/sprint_run.gd` rebuilds the shipped Run into
`assets/models/herts_cossack_reference/run_sprint.tres`: the same stride played in 0.67 s
instead of 0.83 s (about 180 steps a minute), plus a forward lean from the pelvis and spine
while the head stays up. `player.gd` plays it as `RunSprint` (see `run_animation_override`),
and `run_speed` and `run_clip_ground_speed` are both 6.0 so the feet keep their grip on the
ground at full sprint. Retune `TIME_SCALE`, `HIPS_PITCH_DEGREES` and `SPINE_LEAN_DEGREES`
in the baker, save the clip again, and keep the two speeds equal to the clip's contact speed.

Godot's `.godot/` import cache and Summer's `.summer/local/` state are local and
are not versioned. Commit source assets and their Godot import settings when
they are added, not the generated cache.

## Asset credit

The Draft Horse model is a community asset from the Summer asset store
(asset ID `2427ace4-0cfd-419b-8817-18d93a5ef9fc`, attribution license).
