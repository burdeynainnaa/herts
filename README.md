# Herts

Herts is planned as a third-person open-world action-adventure set in the
Ukrainian Great Meadow (Великий Луг) in 1675. The player is a Cossack exploring
the steppe and fighting the Ottoman-Tatar army. The intended presentation is
atmospheric low-poly scenery with warm southern Ukrainian light and a Ukrainian
game UI. The Summer board contains the current design and visual references.

## Current state

The main scene has an animated Cossack and a third-person movement controller.
The first area starts on a rocky ridge above a poppy field, a winding river and
a palisaded timber village at sunset, with a crimson cavalry standard flying at
the outpost gate. A first sabre-combat prototype puts two Tatar sabre fighters
on the slope below the spawn. The original
Summer starter scene remains at `main.tscn` as a reference.

## Open and run

Open this folder as a Summer Engine project and run the project with Play.
The configured entry point is `scenes/main.tscn`. Use WASD to walk, hold Shift
to run, Space to jump, and the mouse to look around. Press F near the horse to
mount or dismount; use WASD to ride and hold Shift to gallop. Escape releases the mouse;
click the game to capture it again. Press M to open or close the world map; Escape
also closes the map. Left mouse swings the sabre (press again during the
follow-through to chain an overhead chop, a spinning sweep that cuts all around,
and a lunging thrust); hold right mouse to guard.
Guarding just before a blow lands parries it and staggers the attacker, and a
staggered, wounded enemy is executed by the next blow, which refills stamina. The project uses the Forward+ renderer and
Jolt 3D physics.

## Project layout

- `scenes/main.tscn` assembles the characters, lighting, region and map. Character spawn positions live here.
- `scenes/characters/` contains the reusable player and horse scenes; their scripts are in `scripts/characters/`.
- `scenes/world/sun.tscn` and `scenes/world/world_environment.tscn` contain shared lighting and sky settings.
- `scenes/world/great_meadow/region.tscn` assembles the existing area. Its terrain, river pieces, stronghold, forest, road, grass, poppies and atmosphere are separate scenes in the same folder. Rocks and their collision remain in the region scene.
- `scenes/ui/world_map.tscn` and `scripts/ui/` contain the world map.
- `scenes/world/cavalry_standard.tscn` is the gate banner (pole, cloth, collision);
  `scripts/world/flag_wave.gdshader` waves the cloth from the hoist out.
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

## Combat prototype

- `scenes/characters/player.tscn` has a `Combat` node (`scripts/combat/player_combat.gd`)
  with its `Health`. The controller asks it whether it owns the animation and how fast
  the body may move; all tuning is exported on that node.
- `scenes/characters/enemy_sabre_fighter.tscn` is the basic enemy
  (`scripts/combat/enemy_sabre_fighter.gd`): approach, circle in front of the camera,
  telegraphed blow (one of the three, drawn at random) with a blade glint, random guard, stagger on parry. One fighter
  attacks at a time.
- `scenes/combat/training_encounter.tscn` places the fighters; `main.tscn` instances
  it together with `scenes/ui/combat_hud.tscn` (Ukrainian HUD).
- `scripts/combat/combat_kit.gd` holds the shared pieces. The Herts Cossack rig only
  ships locomotion, so the guard clip is borrowed at runtime from
  `assets/models/cossack_warrior/rig.glb`, which has the same skeleton. The sabre is
  built in code (`scripts/combat/sabre.gd`), attached to the right hand, and draws a
  fading trail while it cuts.
- `scripts/combat/sabre_attacks.gd` keys the three blows by hand as readable poses
  (bone aims, spine bend and turn, foot offsets) plus their timing, reach, arc and
  damage, and bakes them into clips for each rig when combat starts.
- Hits are resolved by reach and arc, not physics hitboxes; limb damage from the
  design board will need per-bone hurtboxes later. The enemy uses the rigged Crimean Tatar model (`assets/models/crimean_tatar`),
  which shares the Cossack skeleton.

## On-foot movement

`scripts/characters/player.gd` uses weighted, heading-driven locomotion. Input only
says where the Cossack wants to face and how fast; the body turns toward it with angular
momentum: the turn builds up, cruises (up to 260°/s standing, 150°/s at a run) and brakes
into the new heading, so a standing about-face takes about a second and always travels along its own heading, so
he arcs through turns instead of strafing. Speed builds and bleeds off over time; pulling
back against a run plants the feet, brakes, then pivots. Uphill slows him, downhill helps
a little, hard landings cost speed and briefly block jumping, and running into walls kills
momentum. The whole body leans into turns and against acceleration. All tuning is exported
under Momentum, Landing and Body Lean on the Player. Combat still owns facing and speed
while a swing, guard or stagger plays.

## Procedural animation layer

Three skeleton modifiers on the player's `Skeleton3D` (created in `player.gd`, in this order)
sit on top of the clips:

- `scripts/characters/locomotion_blend.gd` blends a stand pose, WalkStoic and RunSprint by speed,
  so there is no hard walk/run switch. The shipped Idle is a wide, staggered stance with the hips
  back and the arms raised, so the stand is built from the walk instead: the walk's average
  posture, with only the idle's breathing and sway on the upper body. Stopping finishes the step:
  the stride runs on to the moment the feet pass each other and settles over `settle_time`.
  Standing, the ground IK plants both feet flat at a natural width (`stand_spread`) and the body
  layer turns the sword hand so the sabre points forward and down (`carry_blade_direction`). Walk and run share one stride
  phase (the run's contacts lag the walk's by 0.27 of a cycle), and the phase advances by the
  distance the body really travels divided by the stride length (1.45 m walk, 3.6 m run, both
  measured from the planted foot), so cadence follows speed and turning on the spot steps.
  It also reports how firmly each foot is planted for the IK below.
- `scripts/characters/body_layer.gd` turns toward where the camera looks, head first: the head
  and neck take the turn up to about 32°, past that the upper body adds half of the rest (up to
  38°), on its own heavier spring so the head leads (with a slight overshoot) and the torso trails; each
  chain bone turns about the vertical (up to 105° in all, looks
  ahead again when the camera swings behind), leans the torso into
  slopes and against speed changes on an underdamped spring, breathes faster and deeper
  after a long run, and relaxes the shoulders: the clips hold the shoulder joints level with
  the neck (a shrug), so each clavicle is lowered until the joint sits 7 cm below the neck base
  while the upper arm keeps the clip's swing (`shoulder_depth_below_neck`, `shoulder_relax`).
  Idle fidgets (`idle_fidgets`, `fidget_interval` on the Player) play every 4-9 s while standing
  calm: the free hand rises to adjust the hat (two-bone IK to the brim), the weight rocks from foot
  to foot (hips slide and tilt, the freed foot lifts and sets down), or the head glances aside.
  Every fidget channel runs through its own spring (`FIDGET_SPRINGS` in player.gd) for a soft start and stop;
  the hand at the hat is critically damped. The hat reach follows the head's own frame and lets go when
  the head turns well away. They fade out at once when walking starts or combat begins.
- `scripts/characters/ground_ik.gd` raycasts under each foot, keeps the clip's foot height
  relative to the real ground, drops the pelvis so the lower foot reaches, re-solves both legs
  with analytic two-bone IK (knee direction from the clip), tilts planted feet to the slope, and
  pins each foot to where it landed for its contact window. Landing compresses the pelvis on a
  spring while the feet stay planted.

The AnimationPlayer still plays Idle (or Jump in the air) underneath; the locomotion layer fades
out while combat owns the animation or the Cossack is airborne, and the IK and body layers are
off while mounted. Set `procedural_body` off on the Player to fall back to the old clip
switching. Measured in play: planted-foot slip is about 0.1 m/s at a 1.4 m/s walk and about
0.2 m/s at a 6 m/s sprint.

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
