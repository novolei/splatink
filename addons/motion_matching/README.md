# Splatink lower-body native motion matching pilot

Runtime is deliberately opt-in with `--native-locomotion-mm`. This is the recovered MIT MM source at 0208dd54902cca8a3bb016ed6591bfc933e2243a, with all 19 Rooftop frozen-patch blobs verified, plus a narrow normalized-query API. The actual MMAnimationLibrary native exact search and continuation costs are used. The MMCharacter physics controller is never instantiated.

Only hips and leg/foot/toe animation tracks may be selected by this provider; source weapons, upper body, face, hair, kid/squid switching and authoritative world movement remain with Splatink. Existing 42 in-place locomotion cycles contain no authored start/stop/pivot clips.

Windows debug/release DLL hashes and full source provenance are in provenance.json. macOS universal debug/release were compiled by Root from the same fixed source archive; actual macOS runtime validation is still pending. Runtime addon intentionally excludes build caches and C++ source.
