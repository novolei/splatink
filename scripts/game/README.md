# Native source gameplay

`InkActor` owns authoritative movement, ink, HP, form changes, wall climbing,
weapon charge/state and respawn. `InkWeapons` owns the seven original weapon
behaviors, projectile collision/paint, bombs, storms, slam and super-jumps.
Visual network replay never applies paint or damage.

`InkBossNav` reads the original half-metre Boss clearance bake.
`InkActorNav` reads the original one-metre multi-floor actor graph, including
directed jump/drop edges and spawn-zone filtering. The actor solver retains
the source Float32 path costs, Float64 edge costs and binary-heap ordering.
`InkLevelQueries` implements the original four-metre level broadphase and
CPU ink-region statistics; it reads the live stage ownership array.
The shared bot movement tail retains source velocity-based water probes and
the hop, waypoint-skip and replan sequence. Source probes for this policy are
exported from `BotBrain` into `data/bot_navigation.json`.

`InkBoss` uses source attack records, paced phase times, ten animated hit
spheres, terrain-clipped rings, barrels, sweep, charge, minions and frenzy.
`InkBossEvents` plays source animation hooks exported alongside the 72 phase
clips. `InkBossHazardVisuals` shares original GPU hazard geometry, shaders and
uniform/recipe descriptions with LAN proxies. Boss model ink/steam lives in
two bounded MultiMesh pools and does not modify authoritative turf.

Source-value contracts are in `tests/gameplay_contract.gd`,
`tests/actor_nav_contract.gd`, `tests/boss_nav_contract.gd`,
`tests/level_queries_contract.gd`, `tests/bot_navigation_contract.gd`, `tests/camera_contract.gd`,
`tests/actor_feel_contract.gd`,
`tests/fx_contract.gd`, `tests/minimap_contract.gd` and
`tests/audio_contract.gd`. Navigation and region query probes are produced by
the original JavaScript implementations, not a second native implementation.

Remaining behavior differences requiring further source comparison include
the complete Turf bot job and acquisition policy, continuous Boss
procedural aim/gait/acceleration overlays between sampled animation frames,
and renderer-dependent PBR/particle appearance. These contracts establish
specific mechanics and data fidelity; they do not establish 100% visual or
player-experience parity.
