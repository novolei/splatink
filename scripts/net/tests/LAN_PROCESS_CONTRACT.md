# Two-process ENet contract

This opt-in harness starts only the requested role. It does not launch a second Godot process, discover services, contact a relay, or change production modules. Its two `ProbeGame` instances run the real `InkNetwork` room, ownership, snapshot, paint and hit protocol; `actual_game=false` is included in each report. The rendered `InkGame` disconnect/HUD/progression boundary is covered separately by `abort_game_fixture.gd`.

Use the existing serialized engine wrapper on each machine. Start the host first, then the guest. Pass the same unique run identifier and UDP port to both. The host uses ENet's default wildcard listener (`0.0.0.0`); `--lan-probe-host` is the guest's destination address.

```text
--script res://scripts/net/tests/lan_process_contract.gd --
--lan-probe-role=host
--lan-probe-host=<host-LAN-address>
--lan-probe-port=27897
--lan-probe-run=pc-lan-unique-id
--lan-probe-output=<absolute-writable-host-report.json>
```

Run the same command on the other machine with `--lan-probe-role=guest` and its own report path. The default report is `user://lan-probe/<run>-<role>.json`. No user profile/settings are created or read. The expected duration after connection is about 20 seconds; the default 90-second watchdog writes an explicit failure report. `--lan-probe-timeout` accepts 30–180 seconds.

Round one checks an eight-slot Tidewater 4v4 roster, two humans and six host-owned bots, each owner's fixed movement, bidirectional damage (host HP73 / guest HP65 after one hit each), matching remote HP snapshots, and remote paint with kind/stretch/stretchAmt/instant/cosmetic metadata. A test-only reliable `qa` message coordinates checkpoints without adding handlers to production `InkNetwork`. The host publishes eight result rows and both peers wait the source 12-second deadline before returning to the same room. The guest readies for a second start; after both receive GO, the host intentionally closes its transport. The guest must emit exactly one interrupted-match abort, clear transport/peers/roster/replication and survive a reentrant `leave` and stale close callback. Intentional host close must emit no abort.

Collect **both** JSON reports and inspect both logs for engine errors. One successful report cannot prove the other endpoint completed. This harness does not prove WAN relay interoperability, rendered multiplayer FX fidelity, service capacity or all late-join/host-migration behavior.

The 2026-10-04 Windows ↔ macOS LAN run passed on both physical endpoints: `shots/pc-lan-macos-host.json/.log` has 20 checks and zero failures; `shots/pc-lan-windows-guest.json/.log` has 18 checks and zero failures. Both logs are clean. Both received two GO starts and one normal room return, the guest received results and exactly one second-round abort, and the host's intentional close emitted no abort. These are transport/lifecycle results with `actual_game=false`; the actual-game harness is separate.
