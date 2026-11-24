# Herts

Herts is planned as a third-person open-world action-adventure set in the
Ukrainian Great Meadow (Великий Луг) in 1675. The player is a Cossack exploring
the steppe and fighting the Ottoman-Tatar army. The intended presentation is
atmospheric low-poly scenery with warm southern Ukrainian light and a Ukrainian
game UI. The Summer board contains the current design and visual references.

## Current state

The main scene has an animated Cossack, a third-person movement controller,
and a simple temporary ground plane for testing. World building, combat, and UI
come later. The original Summer starter scene remains at `main.tscn` as a reference.

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

Godot's `.godot/` import cache and Summer's `.summer/local/` state are local and
are not versioned. Commit source assets and their Godot import settings when
they are added, not the generated cache.
