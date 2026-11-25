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
to run, Space to jump, and the mouse to look around. Escape releases the mouse;
click the game to capture it again. The project uses the Forward+ renderer and
Jolt 3D physics.

## Project layout

- `scenes/` contains the main scene and future character, world, and UI scenes.
- `scripts/` holds future character, world, and UI GDScript code.
- `assets/` holds future models, textures, and audio used by the game.
- `project.godot` contains the project and engine settings.

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
