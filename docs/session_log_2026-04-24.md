# Session Log - 2026-04-24

## Reference Context

- Primary context file: `PROJECT_CONTEXT.md`
- Supporting docs:
  - `docs/roadmap.md`
  - `docs/mechanics.md`
  - `docs/tasks.md`
  - `docs/balance.md`
  - `docs/decisions.md`

## Active Focus

- Continue the first-pass combat foundation with data-driven projectiles and eventual tower ranged attacks.

## Major Tasks Completed

- Added data-driven projectile definitions under `data/projectiles/`.
- Added `basic_arrow` as the first projectile definition for the existing `North Tower` `projectile_id`.
- Added a generic `RtsProjectile` runtime script that tracks one target, moves using projectile data, and applies shared combat damage on impact.
- Extended `GameData` with projectile loading and normalization, including template filtering.
- Added `BuildingCombatSystem` so placed ranged buildings acquire the nearest valid enemy in range and launch their configured projectile.
- Added first-pass enemy death cleanup when damage reduces health to zero.
- Fixed endpoint removal to use the grid footprint so enemies are removed from the same area they can path into.
- Refined enemy obstruction attacks so grunts recheck for a valid exit path before choosing or continuing a building attack.
- Reworked that obstruction recheck to avoid poll-time hitches: removed the pre-swing path probe, replaced per-cell exit A* checks with a single multi-target search, and staggered enemies' first AI poll.
- Fixed moving enemies failing to reroute after new towers blocked their current exit path by checking remaining path walkability before taking the cheap "already moving to exit" early return.
- Added a throttled reroute check before melee building attacks so cached attack targets do not keep priority when an exit route is available.
- Disabled enemy path smoothing for now so grunts follow grid waypoints and cannot cut between occupied building cells.
- Hardened the sealed-exit fallback so enemies keep or acquire an attackable blocker instead of silently idling when no route to the exit exists.
- Added first-pass data-driven movement types for units and enemies: `ground` uses grid pathing, while `flying` moves directly at `flight_height` and ignores blocker collision.
- Converted the prototype `Scout` builder to flying movement so it can move and build without trapping itself behind ground blockers.
- Re-enabled directional shadows and retuned the scene lighting with lower sun intensity plus stronger ambient fill so flying units read better without harsh black shadows.
- Added a simple circular ground shadow for flying units and enemies so flyers stay readable while still using normal scene lighting and shadows.
- Added a debug `Test Dummy` enemy with high health, health regeneration, and an overhead damage readout showing the last hit plus total damage taken in the past ten seconds.
- Added an `F2` debug hotkey that spawns a test dummy at the mouse position.
- Added direct melee attack support for placed buildings, so data-driven melee building stats work without requiring a projectile.
- Added an `Alt`-hold attack range overlay for selected units, enemies, and buildings with positive `attack_range`.

## Decisions And Notes

- Projectile-specific tuning lives in JSON, while movement, targeting, visual construction, lifetime cleanup, and damage application live in generic runtime code.
- First-pass projectile visuals are simple data-driven meshes, currently box or sphere.

## Open Follow-Ups

- Add ranged attack presentation polish such as launch sounds, impact sounds, projectile trails, and attack animation timing.

## End-Of-Session State

- First-pass combat now supports building ranged projectiles, building melee direct damage, enemy melee obstruction attacks, health regeneration, enemy death cleanup, and debug damage readouts.
- First-pass movement now supports data-driven `ground` and `flying` movement for units and enemies.
- Flying actors have readable circular ground shadows while normal scene shadows remain enabled.
- Selected combat-capable actors and buildings show a perimeter-only attack range overlay while `Alt` is held.
