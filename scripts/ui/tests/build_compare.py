"""Read capture PNGs and build source/native contact sheets; never modifies capture inputs."""
from pathlib import Path
import json
import argparse
from PIL import Image, ImageDraw

project = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--native", type=Path, default=project / "shots/ui-native-matrix")
arguments = parser.parse_args()
source = project / "shots/reference/ui"
native = arguments.native.resolve()
target = native / "compare"
target.mkdir(exist_ok=True, parents=True)
report = json.loads((native / "matrix.json").read_text(encoding="utf-8"))
pages = [row["variant"] for row in report["pages"]]
if len(pages) != 26:
    # A partial recapture replaces matrix.json; keep the existing full PNG corpus visible.
    order = ["loading", "title", "main", "mode", "setup", "loadout", "locker", "settings", "howto", "credits", "pause", "results", "online", "lobby", "hud", "settings-video", "settings-audio", "settings-gameplay", "locker-hair", "locker-face", "locker-outfit", "setup-boss", "hud-charger", "hud-map", "news-1", "news-2"]
    pages = [name for name in order if (native / f"{name}.png").exists()]
for group in range(0, len(pages), 6):
    names = pages[group:group + 6]
    sheet = Image.new("RGB", (1280, 390 * len(names)), "#15121c")
    draw = ImageDraw.Draw(sheet)
    for row, name in enumerate(names):
        draw.text((8, row * 390 + 8), f"SOURCE: {name}", fill="white")
        draw.text((648, row * 390 + 8), f"NATIVE: {name}", fill="white")
        for column, directory in enumerate((source, native)):
            path = directory / f"{name}.png"
            if path.exists():
                image = Image.open(path).convert("RGB").resize((640, 360), Image.Resampling.LANCZOS)
                sheet.paste(image, (640 * column, 30 + row * 390))
    path = target / f"{group // 6 + 1:02d}.png"
    sheet.save(path)
    print(path)
