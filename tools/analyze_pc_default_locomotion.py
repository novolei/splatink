"""Reuse frozen motion diagnostics for actual default (portable) game runs."""
import argparse
import json
from pathlib import Path
import analyze_locomotion_real_chain as frozen


class ObservedReport:
    def __init__(self, path, report):
        self.path = path
        self.report = report

    def read_text(self, encoding="utf-8"):
        return json.dumps(self.report)

    def __str__(self):
        return str(self.path)


def analyze(path):
    original = json.loads(path.read_text(encoding="utf-8"))
    if original.get("native_requested") is not False:
        raise ValueError(f"Expected explicit default portable run: {path}")
    report = dict(original)
    report["provider"] = dict(original["provider"])
    report["provider"]["provider"] = "portable-gdscript"
    result = frozen.analyze(ObservedReport(path, report))
    result["provider_label_basis"] = (
        "native_requested=false; portable provider selected by committed Avatar source. "
        "The older trace omitted its class label. The raw trace is unchanged."
    )
    result["portable_queries"] = original["provider"].get("queries")
    result["checks"] = original["checks"]
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("files", type=Path, nargs="+")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    reports = [analyze(path) for path in args.files]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(reports, indent=2), encoding="utf-8")
    for report in reports:
        print(json.dumps({key: report[key] for key in (
            "source_file", "checks", "presentation_mode", "sample_count",
            "maximum_grounded_render_leg_step_rad", "contact_coverage",
            "render_metrics", "physics_authority",
        )}))


if __name__ == "__main__":
    main()
