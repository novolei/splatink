# Native ENet tick budget

`native_tick_contract.gd` exercises the native codec and inbox without contacting any network service. Run it through the owning host's serialized Godot wrapper:

```text
--headless --path <Splatink-project>
--script res://scripts/net/tests/native_tick_contract.gd --
--output=<absolute-writable-report.json>
```

An ordinary `k:'t'` dictionary that fits the budget retains its original fields. For larger ticks, `native_tick_codec.gd` partitions the complete 21-number actor rows and byte-encodes only the remaining metadata. Every RPC argument payload reserves the authenticated ten-character peer identity plus 64 bytes of RPC/header space, keeping the budget at 1200 bytes. `_nt` is an ENet-only transport header, not a source relay protocol change; the receiver removes it and reconstructs one original dictionary before replication and host forwarding. The existing reliable message/event channel and WebSocket branch are unchanged.

The tick channel is now unreliable without ordering because unequal chunks can arrive out of order. The inbox restores ordering by the source timestamp for both small and fragmented completed ticks. Old HP, clock and stats cannot overwrite a newer complete frame. Loss of any fragment drops that frame after one second; the next complete tick still proceeds. No partial frame changes actors, Boss state, events or stats.

Bounds are 128 parts, 64 KiB metadata per frame, two incomplete frames per sender and sixteen globally. Actor rows are never split or duplicated. Disconnect and room cleanup clear per-sender timestamp/history. The fixture checks reverse order, duplicate/conflicting parts, missing parts, expiration, older small/fragmented transitions, reconnect reset, 25 KiB Boss metadata, corruption rejection and budget/actor identity preservation. Its report is a codec test, **not** evidence of actual ENet delivery or clean two-device Game integration; those require both endpoint reports and logs from `lan_actual_game_contract.gd`.

Root's `shots/pc-native-tick-contract.json/.stdout` passed 112 checks with zero failures, with a largest serialized-argument-plus-reserve size of exactly 1200 bytes. Its report explicitly records `actual_enet=false`. The fresh project import was clean. Two-device actual Game delivery remains a separate acceptance step.
