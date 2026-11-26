# Agent Notes

Project-specific guidance for AI agents lives here.

## Feature branches and chats

- Use one new chat and one new branch for each feature. Keep follow-up work for that feature in the same chat and branch; do not reuse the branch for an unrelated feature.
- Chats using the same project folder share one Git checkout, not separate branches. Do not switch it while another chat is working; use separate clones or worktrees for simultaneous feature work, or work on one feature at a time.
- Before editing in a new feature chat, check the current branch, working-tree and staged changes, and unsaved editor work. Preserve existing changes; never stash, discard, reset, or switch branches over them automatically.
- With a clean working tree, the correct `main` checked out, and its intended upstream configured, obtain the user's approval to sync, then fetch and check whether `main` is ahead or diverged. Run `git pull --rebase` only when `main` has no local commits to rewrite. Do not rebase shared history; ask how to proceed if the histories diverge or the pull fails.
- After `main` is up to date, create a uniquely named branch such as `feature/horse-saddle` for the chat, but only when the user explicitly requests or approves branch creation. Ask before switching branches. If existing work or another checkout prevents a safe start, stop and ask instead of moving or overwriting it.
- After an answer that includes project changes, offer to commit the relevant changes. Commit only when the user explicitly asks; review and stage the intended files without including unrelated work. Ask before pushing.
- Questions that require no project changes do not need a new branch.

## Git commit prefixes

Every commit subject starts with one lowercase prefix and a colon:

`<prefix>(<scope>): <imperative summary>`

- Lowercase, imperative mood ("add", not "added"), no trailing period, subject at most 72 characters.
- One prefix per commit: it names the single intent of the change, not the folder you happened to touch.
- The optional body explains why, wrapped at 72 characters. Skip it when the subject says everything.
- Breaking change gets `!` before the colon: `feat(world)!: build terrain at runtime`.
- Prefixes describe the change, not the author, so history still reads correctly when people swap lanes.

### Prefixes

| Prefix | Use for |
| --- | --- |
| `feat` | new gameplay or player-visible capability |
| `fix` | bug, crash or broken behavior |
| `art` | models, textures, materials, lighting, sky, VFX |
| `world` | terrain, river, props, level layout, scene assembly |
| `ui` | HUD, menus, world map, fonts |
| `audio` | sound effects, ambience, music |
| `perf` | measured speed or memory improvement |
| `refactor` | code change with no behavior change |
| `test` | verification probes, play-test checks |
| `docs` | README, AGENTS.md, written notes |
| `chore` | tooling, config, dependencies, LFS, git housekeeping |
| `build` | export presets, project settings, CI |
| `revert` | undo of an earlier commit: `revert: <original subject> (<short hash>)` |

### Scopes for this project

`player` (cossack controller, camera, input) · `horse` (rig, gaits, mounting) · `world` (terrain, river, stronghold layout) · `ui` (HUD, world map) · `input` · `save` · `audio` · `assets` (rigs, library props)

Use a scope only when it sharpens the line. Leave it out when the change spans areas.

### Good and bad examples

Good:

- `feat(horse): mount from either side`
- `fix(player): stop sliding down steep banks`
- `world(stronghold): move gatehouse off the road`
- `art: soften sunset fog color`
- `chore: track glb files with git lfs`
- `revert: soften sunset fog color (6769b1e)`

Bad:

- `Fixed river` - no prefix, past tense
- `world/ui: map and river` - two intents in one commit
- `update stuff` - nothing a teammate can grep
- `wip` on `main` - keep it on your own branch and squash before opening the PR

### Team rules

- One prefix, one intent, one commit. Need a second prefix? Make a second commit.
- `main` only receives changes through a reviewed PR, so its log stays a readable list of prefixed work.
- Do not prefix merge commits; the default merge subject is fine.
- Tag the build that passed a team play-test, for example `git tag v0.3-playtest`.
