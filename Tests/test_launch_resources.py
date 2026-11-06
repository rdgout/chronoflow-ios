import json
from pathlib import Path
import plistlib
import re
import runpy
import struct
import subprocess
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]


class LaunchResourcesTests(unittest.TestCase):
    def setUp(self):
        self.document = ET.parse(ROOT / "App/LaunchScreen.storyboard").getroot()
        self.view = self.document.find(".//viewController/view")

    def test_app_icon_reuses_the_opaque_1024_rn_source_without_variants(self):
        directory = ROOT / "App/Assets.xcassets/AppIcon.appiconset"
        catalog = json.loads((directory / "Contents.json").read_text())
        self.assertEqual(catalog["images"], [{
            "filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024",
        }])
        image = (directory / "icon.png").read_bytes()
        source = ROOT.parent / "chronoflow-mobile/assets/images/icon.png"
        self.assertEqual(image, source.read_bytes())
        self.assertEqual(image[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(struct.unpack(">II", image[16:24]), (1024, 1024))
        self.assertEqual(image[25], 2, "RGB PNG must have no alpha channel")
        offset = 8
        while offset < len(image):
            length = struct.unpack(">I", image[offset:offset + 4])[0]
            self.assertNotEqual(image[offset + 4:offset + 8], b"tRNS", "Icon must be opaque")
            offset += length + 12
        project = (ROOT / "project.yml").read_text().split("\n  AppTests:", 1)[0]
        self.assertIn("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon", project)
        self.assertIn('TARGETED_DEVICE_FAMILY: "1"', project)

    def test_welcome_capture_is_hosted_without_duplicate_package_linkage(self):
        source = ROOT / "AppTests/WelcomeSnapshotTests.swift"
        self.assertIn("drawHierarchy", source.read_text())
        self.assertFalse((ROOT / "Packages/ChronoFlowKit/Tests/WelcomeTests/WelcomeSnapshotTests.swift").exists())
        self.assertTrue((source.parent / "__Snapshots__/README.md").exists())
        self.assertNotIn("SnapshotTesting", (source.parent / "WelcomeSnapshotReference.swift").read_text())
        runner = runpy.run_path(str(ROOT / "Scripts/launch-simulators.py"))
        command = runner["selection"]("snapshots", "17e")
        for suite in ["AppTests/WelcomeSnapshotTests", "AppTests/WelcomeSnapshotGuardTests"]:
            self.assertIn(suite, command)
        project = (ROOT / "project.yml").read_text()
        self.assertIn("excludes: [__Snapshots__]", project)

    def test_make_test_and_snapshots_pin_the_snapshot_language(self):
        for target in ["test", "snapshots"]:
            with self.subTest(target=target):
                command = subprocess.check_output(["make", "-n", target], cwd=ROOT, text=True)
                self.assertIn("--devices 17e --mode " + target, command)

    def test_splash_baselines_cover_all_frames_at_each_devices_own_scale(self):
        directory = ROOT / "Packages/ChronoFlowKit/Tests/LaunchTests/__Snapshots__/LaunchSnapshotTests"
        frames = {
            "ready-0", "ready-700", "ready-1400", "ready-1700", "ready-1900",
            "slow-2600", "slow-4900", "welcome-1500", "welcome-1950", "welcome-2400", "reduceMotion-0",
        }
        devices = {}
        for image in directory.glob("*.png"):
            match = re.fullmatch(r"sampledSplashFrames\.(iPhone\d+-\d+)-(\d+)x(\d+)-([23])x-(light|dark)-(.+)\.png", image.name)
            self.assertIsNotNone(match, image.name)
            model, width, height, scale, style, frame = match.groups()
            dimensions = (int(width), int(height), int(scale))
            previous, coverage = devices.setdefault(model, (dimensions, set()))
            self.assertEqual(previous, dimensions, model)
            coverage.add((style, frame))
            data = image.read_bytes()
            self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
            self.assertEqual(struct.unpack(">II", data[16:24]), (int(width) * int(scale), int(height) * int(scale)))
        self.assertEqual(set(devices), {"iPhone14-6", "iPhone18-5", "iPhone18-3", "iPhone18-4", "iPhone19-2", "iPhone19-3", "iPhone19-4"})
        for model, (_, coverage) in devices.items():
            self.assertEqual(coverage, {(style, frame) for style in ["light", "dark"] for frame in frames}, model)

    def test_hosted_tests_reuse_the_apps_package_products(self):
        project = (ROOT / "project.yml").read_text()
        target = re.search(r"(?ms)^  AppTests:\n(.*?)(?=^  \S|\Z)", project)
        self.assertIsNotNone(target)
        configuration = target.group(1)
        self.assertIn('TEST_HOST: "$(BUILT_PRODUCTS_DIR)/ChronoFlow.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ChronoFlow"', configuration)
        self.assertIn('BUNDLE_LOADER: "$(TEST_HOST)"', configuration)
        dependencies = configuration.split("    dependencies:\n", 1)[1]
        self.assertEqual(dependencies.strip(), "- target: ChronoFlow")

    def test_simulator_keychain_host_uses_adhoc_signing_without_a_team(self):
        project = (ROOT / "project.yml").read_text()
        base = project.split("\nsettings:\n  base:\n", 1)[1].split("\npackages:\n", 1)[0]
        self.assertIn('CODE_SIGN_STYLE: Automatic', base)
        self.assertIn('"CODE_SIGNING_ALLOWED[sdk=iphonesimulator*]": YES', base)
        self.assertIn('"CODE_SIGN_IDENTITY[sdk=iphonesimulator*]": "-"', base)
        self.assertIn('"DEVELOPMENT_TEAM[sdk=iphonesimulator*]": ""', base)
        app = project.split("\n  ChronoFlow:\n", 1)[1].split("\n  AppTests:\n", 1)[0]
        self.assertIn('"CODE_SIGN_IDENTITY[sdk=iphonesimulator*]": "-"', app)
        self.assertNotRegex(project, r'(?m)^\s+CODE_SIGNING_ALLOWED:')
        self.assertNotRegex(project, r'(?m)^\s+CODE_SIGN_IDENTITY:')
        self.assertNotRegex(project, r'(?m)^\s+DEVELOPMENT_TEAM:')
        self.assertEqual((ROOT / "Config/Base.xcconfig").read_text().strip(), '#include? "Local.xcconfig"')

    def test_launch_is_an_unlocalised_storyboard_without_text_or_custom_code(self):
        with (ROOT / "App/Info.plist").open("rb") as source:
            info = plistlib.load(source)
        self.assertEqual(info["UILaunchStoryboardName"], "LaunchScreen")
        self.assertNotIn("UILaunchScreen", info)
        self.assertNotIn("UIDesignRequiresCompatibility", info)
        self.assertEqual(self.document.get("launchScreen"), "YES")
        self.assertEqual(list((ROOT / "App").rglob("LaunchScreen.storyboard")), [ROOT / "App/LaunchScreen.storyboard"])
        for element in self.document.iter():
            self.assertNotIn(element.tag, ["label", "textView", "textField", "button"])
            self.assertNotIn("customClass", element.attrib)
            self.assertNotIn("customModule", element.attrib)

    def test_moon_uses_intrinsic_size_and_superview_centres(self):
        children = list(self.view.find("subviews"))
        self.assertEqual(len(children), 1)
        moon = children[0]
        self.assertEqual(moon.tag, "imageView")
        self.assertEqual(moon.get("image"), "LaunchMoon")
        self.assertEqual(moon.get("contentMode"), "center")
        self.assertEqual(moon.get("translatesAutoresizingMaskIntoConstraints"), "NO")
        constraints = self.document.findall(".//constraint")
        self.assertEqual(len(constraints), 2)
        self.assertEqual({c.get("firstAttribute") for c in constraints}, {"centerX", "centerY"})
        for constraint in constraints:
            self.assertEqual(constraint.get("firstItem"), moon.get("id"))
            self.assertEqual(constraint.get("secondItem"), self.view.get("id"))
            self.assertEqual(constraint.get("secondAttribute"), constraint.get("firstAttribute"))
            self.assertEqual(float(constraint.get("constant", "0")), 0)
            self.assertEqual(float(constraint.get("multiplier", "1")), 1)
            self.assertEqual(constraint.get("relation", "equal"), "equal")

    def test_named_sky_and_image_metadata_match_generated_assets(self):
        self.assertEqual(self.view.find("color[@key='backgroundColor']").get("name"), "LaunchSky")
        catalog = ROOT / "App/Assets.xcassets"
        sky = json.loads((catalog / "LaunchSky.colorset/Contents.json").read_text())
        fallback = self.document.find("resources/namedColor[@name='LaunchSky']/color")
        self.assertEqual(fallback.get("customColorSpace"), "displayP3")
        for channel, value in sky["colors"][0]["color"]["components"].items():
            self.assertEqual(float(fallback.get(channel)), float(value))
        moon = json.loads((catalog / "LaunchMoon.imageset/Contents.json").read_text())
        resource = self.document.find("resources/image[@name='LaunchMoon']")
        self.assertEqual(len(moon["images"]), 4)
        for image in moon["images"]:
            with self.subTest(image=image["filename"]):
                data = (catalog / "LaunchMoon.imageset" / image["filename"]).read_bytes()
                self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
                width, height = struct.unpack(">II", data[16:24])
                scale = int(image["scale"].removesuffix("x"))
                self.assertEqual(width / scale, float(resource.get("width")))
                self.assertEqual(height / scale, float(resource.get("height")))


if __name__ == "__main__":
    unittest.main()
