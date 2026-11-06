import argparse
import json
from pathlib import Path
import plistlib
import subprocess


def check_catalog(records, layered=True):
    icons = [record for record in records if record.get("Name") == "ChronoFlow"]
    for appearance, filename in [
        (None, "AppIcon-default.png"),
        ("UIAppearanceDark", "AppIcon-dark.png"),
        ("ISAppearanceTintable", "AppIcon-tinted.png"),
    ]:
        matches = [record for record in icons
                   if record.get("AssetType") == "Icon Image"
                   and record.get("RenditionName") == filename
                   and record.get("Appearance") == appearance
                   and record.get("PixelWidth") == 1024
                   and record.get("PixelHeight") == 1024
                   and record.get("Opaque") is True]
        if not matches:
            raise ValueError(f"Missing designed flat icon rendition: {filename} ({appearance})")
    if layered and not any(
        record.get("AssetType") == "IconImageStack"
        for record in icons
    ):
        raise ValueError("Missing ChronoFlow Liquid Glass icon stack")


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
    parser.add_argument("--flat-only", action="store_true", help="Audit a catalog compiled without the .icon")
    arguments = parser.parse_args()
    catalog = arguments.path
    if catalog.is_dir():
        check_bundle(catalog)
        catalog /= "Assets.car"
    records = json.loads(subprocess.check_output([
        "xcrun", "--sdk", "iphoneos", "assetutil", "--info", str(catalog),
    ]))
    check_catalog(records, layered=not arguments.flat_only)
    print("ChronoFlow: designed any/dark/tinted icons verified" + (
        "; Liquid Glass stack verified" if not arguments.flat_only else ""))


if __name__ == "__main__":
    main()
