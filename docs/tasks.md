# Tasks

## Future Command Grid Work

- Add paging or nested categories for build menus once a unit can build more than eight buildings. The current 3x3 command grid reserves the final slot for Back, so only eight building options are displayed in the first-pass build menu.

## Future Enemy Flow

- Decide whether enemies reaching an `Exit Point` should affect player lives, scoring, economy, or wave state before they are removed.

## Combat Foundation

- Completed: first-pass combat behavior is driven by `attack_cooldown`; `attack_speed` remains reserved for future attack animation timing.
- Add presentation polish for ranged attacks, such as launch sounds, impact sounds, projectile trails, and tower attack animation timing.

## Next Session

- Build a general in-game map-building system for simple authored geometry.
- Allow map geometry to carry gameplay tags, with first-pass tags such as `spawner` and `end_point`.
- Replace the Scout-built prototype `Spawner` and `Exit Point` flow with tagged map geometry once the map-building system exists.
- Add a first flying enemy definition to exercise flying path-to-exit behavior under pressure.
- Add future polish for flying movement visuals, such as bobbing and altitude-aware selection rings.
- Add ranged attack presentation polish, such as launch sounds, impact sounds, projectile trails, and tower attack animation timing.

## Completed

- Added simple circular ground shadows for flying units and enemies so flyers remain readable while normal scene shadows are enabled.
- Added selected-actor attack range feedback: hold `Alt` while a unit, enemy, or building with `attack_range` is selected.
