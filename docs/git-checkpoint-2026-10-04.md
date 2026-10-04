# Native PC development checkpoint — 2026-10-04

This is a development checkpoint, not a completed replica or a release. Windows and macOS remain the current priority; mobile work is deferred and iOS signing work is paused. Mini Tanks and the external animation reference projects remain read-only.

## Repository scope

The repository contains the Godot project, runtime assets, native Motion Matching libraries and reproducible source archive, development tools, contracts and assessment documents. Git LFS stores the binary assets. Godot import caches, `.tools`, `builds`, `shots`, dependency caches and local signing configuration are excluded. Existing `.import` files preserve importer settings; a clone regenerates `.godot` itself.

The game can run from this repository after LFS download and Godot import. Tools that re-extract or compare the original web implementation still require the INKWAVE reference checkout; see tool source and existing assessment documents for those paths. Engine and platform SDK paths are local configuration.

## Locomotion status

The original 87-bone character, gameplay movement and upper-body weapon actions are retained. Native lower-body Motion Matching and the presentation experiments are opt-in. The formal Motion Matching dataset has not been replaced with the evaluated Mixamo candidates.

The coherent pelvis presentation experiment remains disabled: measured upper-body connection distortion and muzzle displacement prevent acceptance despite improved leg continuity in some runs. See `coherent-pelvis-locomotion.md` for its evidence and limits.

The newer `--footplant-continuous-reach` experiment changes physics-stage hip correction under native Motion Matching for the local player only. `--footplant-reach-trace` observes the original policy. Both are disabled by default. The Windows contract passed 328,863 checks with zero failures and exact unaffected local translations and scales; the preceding rich-diagnostic version passed 326,343 checks on Windows and macOS. The latest minimal non-local diagnostic branch has only been validated on Windows.

Initial actual-input probes reduced maximum consecutive physics hip displacement from about 46 mm to 33 mm. Foot contact quality is still under investigation, so this experiment is not accepted for normal play. Rich telemetry caused substantial probe overhead; those runs cannot establish 144 FPS animation quality or production performance. The observer serialization cache passed static review and a Godot headless parse check (exit zero and both logs clean); it still requires an actual-input performance comparison.

Detailed JSON traces and both engine logs for each run remain in the excluded local `shots` directory. A green structural contract is not proof of visual quality, stable foot contact or complete replication.

## Latest Windows playtest feedback

The player reported foot sliding and stiff locomotion, movement jitter, weak hit and self-damage feedback, and occasional perceived stutter despite acceptable overall FPS. These are open PC polish issues. Reproduction must identify the executable and whether native Motion Matching was enabled; the latest existing development export predates the new footplant experiments. Follow-up verification must measure foot contact and animation/physics alignment, distinguish display interpolation from source-pose changes, and inspect frame-time spikes as well as average FPS.
