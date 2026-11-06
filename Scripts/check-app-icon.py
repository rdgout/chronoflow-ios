import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess


ROOT = Path(__file__).resolve().parents[1]
APPEARANCES = ("UIAppearanceAny", "UIAppearanceDark", "ISAppearanceTintable")
DEFAULT_CONTROLS = ROOT / "build/icon-probe"


def control_sources():
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for directory in ("App/ChronoFlow.icon", "App/Assets.xcassets/ChronoFlow.appiconset")
            for path in sorted((ROOT / directory).rglob("*")) if path.is_file()}


def pixel_reader():
    source = ROOT / "Scripts/icon-pixels.m"
    binary = ROOT / "build/icon-tools/icon-pixels"
    binary.parent.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(ROOT / "build/ModuleCache"))
    subprocess.run([
        "xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
        "-framework", "Foundation", "-framework", "CoreGraphics", "-framework", "ImageIO",
        str(source), "-o", str(binary),
    ], check=True, env=environment)
    return binary


def read_pixels(reader, path, export=None):
    return json.loads(subprocess.check_output([
        str(reader), str(path), *([str(export)] if export else []),
    ]))


def catalog_info(path):
    return json.loads(subprocess.check_output(["xcrun", "assetutil", "--info", str(path)]))


def fingerprint(record):
    if (record.get("width"), record.get("height"), record.get("opaque")) != (1024, 1024, True):
        raise ValueError("Expected opaque 1024-square decoded pixels")
    digest = record.get("rgbaSHA256", "")
    if len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
        raise ValueError("Missing decoded sRGB RGBA SHA-256")
    return digest


def check_pixels(actual, expected):
    for appearance in APPEARANCES:
        if appearance not in actual or appearance not in expected:
            raise ValueError(f"Missing pixel appearance: {appearance}")
        if fingerprint(actual[appearance]) != fingerprint(expected[appearance]):
            raise ValueError(f"Stored {appearance} pixels differ from the expected control")


def check_catalog(records, pixels, expected, layered=True):
    icons = [record for record in records if record.get("Name") == "ChronoFlow"]
    for appearance in APPEARANCES:
        matches = [record for record in icons
                   if record.get("AssetType") == "Icon Image"
                   and (record.get("Appearance") or "UIAppearanceAny") == appearance
                   and record.get("Idiom") == "phone"
                   and record.get("PixelWidth") == 1024
                   and record.get("PixelHeight") == 1024
                   and record.get("Opaque") is True]
        if len(matches) != 1:
            raise ValueError(f"Expected one opaque 1024-square phone icon for {appearance}, found {len(matches)}")
    check_pixels(pixels, expected)
    if layered:
        for appearance in ("UIAppearanceLight", "UIAppearanceDark", "ISAppearanceTintable"):
            if not any(record.get("AssetType") == "IconImageStack"
                       and record.get("Appearance") == appearance for record in icons):
                raise ValueError(f"Missing ChronoFlow Liquid Glass stack: {appearance}")


def check_bundle(bundle):
    with (bundle / "Info.plist").open("rb") as source:
        info = plistlib.load(source)
    primary = info["CFBundleIcons"]["CFBundlePrimaryIcon"]
    if primary.get("CFBundleIconName") != "ChronoFlow" or not primary.get("CFBundleIconFiles"):
        raise ValueError("Built app must declare the ChronoFlow primary icon and fallback files")
    if "UIDesignRequiresCompatibility" in info:
        raise ValueError("Liquid Glass compatibility opt-out is forbidden")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path, help="Built .app or Assets.car")
    parser.add_argument("--flat-only", action="store_true", help="Require designed flats without a glass stack")
    parser.add_argument("--controls", type=Path, default=DEFAULT_CONTROLS)
    arguments = parser.parse_args()
    catalog = arguments.path
    if catalog.is_dir():
        check_bundle(catalog)
        catalog /= "Assets.car"
    flat_reference = arguments.controls / "flat/Assets.car"
    composer_reference = arguments.controls / "composer/Assets.car"
    references = [flat_reference]
    if not arguments.flat_only:
        references.append(composer_reference)
    for reference in references:
        if not reference.is_file():
            parser.error(f"Missing control {reference}; run make icon-probe first")
    report_path = arguments.controls / "report.json"
    if not report_path.is_file():
        parser.error("Missing control provenance; run make icon-probe first")
    report = json.loads(report_path.read_text())
    xcode = subprocess.check_output(["xcodebuild", "-version"], text=True).strip()
    if report.get("sources") != control_sources() or report.get("xcode") != xcode:
        parser.error("Icon sources or Xcode changed; run make icon-probe again")
    reader = pixel_reader()
    designed = read_pixels(reader, ROOT / "App/Assets.xcassets/ChronoFlow.appiconset")
    flat = read_pixels(reader, flat_reference)
    check_catalog(catalog_info(flat_reference), flat, designed, layered=False)
    expected = flat
    if not arguments.flat_only:
        expected = read_pixels(reader, composer_reference)
        check_catalog(catalog_info(composer_reference), expected, expected)
    actual = read_pixels(reader, catalog)
    check_catalog(catalog_info(catalog), actual, expected, layered=not arguments.flat_only)
    for appearance in APPEARANCES:
        preserved = fingerprint(actual[appearance]) == fingerprint(designed[appearance])
        print(f"{appearance}: rgbaSHA256={fingerprint(actual[appearance])}; designed PNG preserved={preserved}")
    print("ChronoFlow: designed flat pixels verified" if arguments.flat_only else
          "ChronoFlow: Composer-generated legacy pixels and all three Liquid Glass stacks verified; "
          "designed legacy PNG preservation is not promised (Docs/app-icon.md)")


if __name__ == "__main__":
    main()
