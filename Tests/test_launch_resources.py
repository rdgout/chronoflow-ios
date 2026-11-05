import json
from pathlib import Path
import plistlib
import re
import struct
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]


class LaunchResourcesTests(unittest.TestCase):
    def setUp(self):
        self.document = ET.parse(ROOT / "App/LaunchScreen.storyboard").getroot()
        self.view = self.document.find(".//viewController/view")

    def test_hosted_tests_reuse_the_apps_package_products(self):
        project = (ROOT / "project.yml").read_text()
        target = re.search(r"(?ms)^  AppTests:\n(.*?)(?=^  \S|\Z)", project)
        self.assertIsNotNone(target)
        configuration = target.group(1)
        self.assertIn('TEST_HOST: "$(BUILT_PRODUCTS_DIR)/ChronoFlow.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ChronoFlow"', configuration)
        self.assertIn('BUNDLE_LOADER: "$(TEST_HOST)"', configuration)
        dependencies = configuration.split("    dependencies:\n", 1)[1]
        self.assertEqual(dependencies.strip(), "- target: ChronoFlow")

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
