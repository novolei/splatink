"""Run the embedded development probe on one explicitly selected Android device."""
import argparse
import hashlib
import json
import re
import struct
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--adb", required=True)
parser.add_argument("--serial", required=True)
parser.add_argument("--build", type=Path, required=True)
parser.add_argument("--reuse-install", action="store_true")
args = parser.parse_args()
package = "com.inkwave.splatink.dev"
output = args.build.resolve() / "output"
apk = output / "Splatink.apk"
record = json.loads((output / "export_record.json").read_text(encoding="utf-8-sig"))
if not record["stamp"].get("probe"):
    raise SystemExit("This build has no embedded device probe.")
evidence = output / "device"
evidence.mkdir(exist_ok=True)

def adb(*arguments, binary=False, check=True, timeout=60):
    result = subprocess.run([args.adb, "-s", args.serial, *arguments],
                            capture_output=True, timeout=timeout)
    if check and result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace") + result.stdout.decode(errors="replace"))
    return result.stdout if binary else result.stdout.decode(errors="replace")

def memory(name):
    raw = adb("shell", "dumpsys", "meminfo", package)
    (evidence / (name + ".txt")).write_text(raw, encoding="utf-8")
    native = re.search(r"^\s*Native Heap\s+(\d+)", raw, re.MULTILINE)
    total = re.search(r"TOTAL PSS:\s*(\d+)", raw)
    measured = {"elapsed_s": round(time.monotonic() - started, 3),
                "native_heap_pss_kb": int(native.group(1)) if native else None,
                "total_pss_kb": int(total.group(1)) if total else None}
    print(name + " " + json.dumps(measured), flush=True)
    return measured

if not args.reuse_install:
    print("Installing " + str(apk), flush=True)
    installed = adb("install", "-r", str(apk), timeout=180)
    (evidence / "install.txt").write_text(installed, encoding="utf-8")
    if "Success" not in installed:
        raise RuntimeError("Install did not report success: " + installed)
adb("shell", "am", "force-stop", package)
adb("shell", "run-as", package, "rm", "-f", "files/phone-probe.png", "files/phone-probe.json")
launch = adb("shell", "am", "start", "-n", package + "/com.godot.game.GodotAppLauncher")
(evidence / "launch.txt").write_text(launch, encoding="utf-8")
started = time.monotonic()
pid = ""
while time.monotonic() - started < 8:
    pid = adb("shell", "pidof", package, check=False).strip().split(" ")[0]
    if pid:
        break
    time.sleep(.5)
if not pid:
    raise RuntimeError("The game did not start.")
print("Game process " + pid, flush=True)
time.sleep(max(0, 8 - (time.monotonic() - started)))
first = memory("memory-start")
time.sleep(30)
last = memory("memory-end")
capture_bytes = b""
while time.monotonic() - started < 90:
    capture_bytes = adb("exec-out", "run-as", package, "cat", "files/phone-probe.json", binary=True, check=False)
    try:
        capture = json.loads(capture_bytes)
        break
    except (ValueError, UnicodeDecodeError):
        time.sleep(2)
else:
    capture = None
logs = adb("logcat", "-d", "--pid=" + pid, "-v", "brief", timeout=30)
(evidence / "own-process.log").write_text(logs, encoding="utf-8")
failures = [line for line in logs.splitlines() if re.search(
    r"SCRIPT ERROR|Parse Error|ERROR:|PSEUDOIMUL32|compile failed|compilation failed", line, re.I)]
if capture:
    (evidence / "phone-probe.json").write_bytes(capture_bytes)
    png = adb("exec-out", "run-as", package, "cat", "files/phone-probe.png", binary=True)
    if not png.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError("Capture did not contain a PNG.")
    (evidence / "phone-probe.png").write_bytes(png)
    dimensions = struct.unpack(">II", png[16:24])
else:
    dimensions = None
device = {"serial": args.serial, "pid": int(pid), "build": record["stamp"],
          "apk_sha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
          "memory_start": first, "memory_end": last,
          "native_heap_pss_delta_kb": last["native_heap_pss_kb"] - first["native_heap_pss_kb"]
              if first["native_heap_pss_kb"] is not None and last["native_heap_pss_kb"] is not None else None,
          "capture": capture, "dimensions": dimensions, "runtime_errors": failures,
          "rendering_review": "pending", "touch_review": "pending"}
(evidence / "device_probe_record.json").write_text(json.dumps(device, indent=2), encoding="utf-8")
print("ANDROID_DEVICE_PROBE " + json.dumps(device), flush=True)
if failures or not capture or capture.get("state") != "playing" or capture.get("actors") != 8:
    raise SystemExit(1)
