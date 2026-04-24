# Tasks

## Future Command Grid Work

- Add paging or nested categories for build menus once a unit can build more than eight buildings. The current 3x3 command grid reserves the final slot for Back, so only eight building options are displayed in the first-pass build menu.

## Future Enemy Flow

- Decide whether enemies reaching an `Exit Point` should affect player lives, scoring, economy, or wave state before they are removed.

## Combat Foundation

- Add projectile definitions under `data/projectiles/`.
- Add a generic projectile runtime that tracks a target and applies damage on impact.
- Add first-pass ranged attack launching that spawns projectiles instead of applying immediate damage.
- Keep first-pass combat behavior driven by `attack_cooldown`; reserve `attack_speed` for future attack animation timing.

## Next Session

- Add attack functionality to towers so placed defensive buildings can acquire targets and make ranged attacks.
- Start the first-pass ranged combat system, including projectile definitions and generic projectile behavior.
- Replace Scout-built `Spawner` and `Exit Point` flow with dedicated map-level spawn and end points.
- Add separate movement types, starting with `ground` and `flying`, and define how each interacts with pathing and blockers.
