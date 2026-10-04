# Reproducible native lower-body query source

The 4.3 MB source archive preserves the complete recovered native source and matching godot-cpp snapshot. It includes all 19 verified Rooftop increment files, the original frozen patch, MIT license, provenance, and the added `configure_external_database` / `query_normalized_vector` API. It excludes compiled code, Git, build caches and the documentation GIF. This directory is excluded from game exports.

`restore_native_mm_source.mjs` verifies the archive SHA and extracts only into Splatink's `.tools/mm-native`. Full source builds from `.tools/mm-native/source` use its upstream `SConstruct`:

```powershell
node tools/restore_native_mm_source.mjs
cd .tools/mm-native/source
py -m SCons platform=windows arch=x86_64 target=template_debug precision=single -j6
py -m SCons platform=windows arch=x86_64 target=template_release precision=single -j6
```

For the current checkpoint `native_mm_sconstruct.py` compiles extension code using the hash-verified frozen Windows godot-cpp static libraries copied by `prepare_native_mm.mjs`. The full-source commands above rebuild those bindings too and do not require either read-only reference project. Binary SHA and toolchain metadata must be updated only after the new artifacts have been tested.

macOS uses `tools/build_native_motion_matching_macos.sh` with an isolated `/Users/*/splatink-build/*` directory, this archive, and its recorded SHA. It creates a dedicated SCons virtualenv, builds universal debug/release, records clang/SDK/dependency inspection and binary SHA, and never invokes Godot. Runtime macOS mappings must be added only after the actual binaries exist and have passed the same engine contracts.
