import argparse
import json
from pathlib import Path
import runpy
import shlex
import subprocess


ROOT = Path(__file__).resolve().parents[1]
CHECK = runpy.run_path(str(ROOT / "Scripts/check-app-icon.py"))


def compile_catalog(output, inputs, flags):
    output.mkdir(parents=True, exist_ok=True)
    command = [
        "xcrun", "actool", *map(str, inputs), "--compile", str(output),
        "--platform", "iphonesimulator", "--minimum-deployment-target", "17.0",
        "--target-device", "iphone", "--app-icon", "ChronoFlow", "--include-all-app-icons",
        *flags, "--output-partial-info-plist", str(output / "partial.plist"),
        "--output-format", "human-readable-text", "--warnings", "--errors", "--notices",
    ]
    print(shlex.join(command), flush=True)
    subprocess.run(command, check=True, cwd=ROOT)
    return output / "Assets.car"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--existing", type=Path, help="Also classify an existing Assets.car")
    arguments = parser.parse_args()
    output = ROOT / "build/icon-probe"
    output.mkdir(parents=True, exist_ok=True)
    reader = CHECK["pixel_reader"]()
    designed = CHECK["read_pixels"](reader, ROOT / "App/Assets.xcassets/ChronoFlow.appiconset")
    report = {"xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
              "sources": CHECK["control_sources"](), "designed": designed, "catalogs": {}}
    catalog = ROOT / "App/Assets.xcassets"
    icon = ROOT / "App/ChronoFlow.icon"
    cases = [
        ("flat", [catalog], []),
        ("composer", [icon], []),
        ("combined", [catalog, icon], []),
        ("combined-disabled", [catalog, icon], ["--enable-icon-stack-fallback-generation=disabled"]),
    ]
    paths = [(name, compile_catalog(output / name, inputs, flags)) for name, inputs, flags in cases]
    if arguments.existing:
        paths.append(("existing", arguments.existing.resolve()))
    for name, path in paths:
        records = CHECK["catalog_info"](path)
        pixels = CHECK["read_pixels"](reader, path, output / name / "pixels")
        (output / name).mkdir(parents=True, exist_ok=True)
        (output / name / "info.json").write_text(json.dumps(records, indent=2) + "\n")
        report["catalogs"][name] = {"path": str(path), "pixels": pixels}
    controls = report["catalogs"]
    for name, entry in controls.items():
        entry["matches"] = {}
        for appearance in CHECK["APPEARANCES"]:
            digest = CHECK["fingerprint"](entry["pixels"][appearance])
            matches = [label for label, expected in [
                ("designed PNG", designed), ("flat-only", controls["flat"]["pixels"]),
                ("Composer-only", controls["composer"]["pixels"]),
            ] if digest == CHECK["fingerprint"](expected[appearance])]
            entry["matches"][appearance] = matches
            print(f"{name} / {appearance}: {digest} -> {', '.join(matches) or 'NEITHER CONTROL'}", flush=True)
    report_path = output / "report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Evidence: {report_path}", flush=True)
    CHECK["check_catalog"](CHECK["catalog_info"](paths[0][1]), controls["flat"]["pixels"], designed, layered=False)
    CHECK["check_catalog"](CHECK["catalog_info"](paths[2][1]), controls["combined"]["pixels"],
                           controls["composer"]["pixels"])


if __name__ == "__main__":
    main()
