from copy import deepcopy
from pathlib import Path
import runpy
import unittest


ROOT = Path(__file__).resolve().parents[1]
CHECK = runpy.run_path(str(ROOT / "Scripts/check-app-icon.py"))
CONFIGURE = runpy.run_path(str(ROOT / "Scripts/configure-icon-project.py"))["configure"]


def renditions():
    return [dict(
        Name="ChronoFlow", AssetType="Icon Image", RenditionName=f"AppIcon-{appearance}.png",
        PixelWidth=1024, PixelHeight=1024, Opaque=True, **({"Appearance": value} if value else {})
    ) for appearance, value in [
        ("default", None), ("dark", "UIAppearanceDark"), ("tinted", "ISAppearanceTintable"),
    ]] + [{"Name": "ChronoFlow", "AssetType": "IconImageStack"}]


class AppIconToolingTests(unittest.TestCase):
    def test_catalog_requires_designed_renditions_and_the_glass_stack(self):
        CHECK["check_catalog"](renditions())
        for index in range(4):
            records = renditions()
            records.pop(index)
            with self.subTest(index=index), self.assertRaises(ValueError):
                CHECK["check_catalog"](records)
        CHECK["check_catalog"](renditions()[:3], layered=False)

    def test_generated_fallbacks_and_unrelated_dark_assets_do_not_pass(self):
        for key, value in [
            ("RenditionName", "generated-from-glass.png"), ("Name", "LaunchMoon"),
            ("PixelWidth", 60), ("Appearance", None), ("Opaque", False),
        ]:
            records = deepcopy(renditions())
            records[1][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                CHECK["check_catalog"](records)

    def test_xcodegen_adapter_sets_the_actool_type_and_is_idempotent(self):
        source = 'id = {isa = PBXFileReference; lastKnownFileType = wrapper.icon; path = ChronoFlow.icon; sourceTree = "<group>"; };'
        configured = CONFIGURE(source)
        self.assertIn("lastKnownFileType = folder.iconcomposer.icon;", configured)
        self.assertEqual(CONFIGURE(configured), configured)
        for invalid in ["", source + source, source.replace("wrapper.icon", "folder")]:
            with self.assertRaises(ValueError):
                CONFIGURE(invalid)


if __name__ == "__main__":
    unittest.main()
