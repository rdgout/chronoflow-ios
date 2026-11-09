from copy import deepcopy
from pathlib import Path
import runpy
import unittest


ROOT = Path(__file__).resolve().parents[1]
CHECK = runpy.run_path(str(ROOT / "Scripts/check-app-icon.py"))
CONFIGURE = runpy.run_path(str(ROOT / "Scripts/configure-icon-project.py"))["configure"]


def pixels():
    return {appearance: dict(width=1024, height=1024, opaque=True, rgbaSHA256=str(index) * 64)
            for index, appearance in enumerate(CHECK["APPEARANCES"])}


def renditions():
    return [dict(
        Name="ChronoFlow", AssetType="Icon Image", RenditionName=f"renamed-{index}-uuid.png",
        Idiom="phone", PixelWidth=1024, PixelHeight=1024, Opaque=True,
        **({"Appearance": value} if value else {})
    ) for index, value in enumerate([None, "UIAppearanceDark", "ISAppearanceTintable"])] + [
        dict(Name="ChronoFlow", AssetType="IconImageStack", Appearance=appearance)
        for appearance in ["UIAppearanceLight", "UIAppearanceDark", "ISAppearanceTintable"]
    ]


class AppIconToolingTests(unittest.TestCase):
    def test_content_matches_despite_renamed_renditions(self):
        CHECK["check_catalog"](renditions(), pixels(), pixels())
        records = renditions()
        for record in records:
            record["RenditionName"] = "arbitrary-name.png"
        CHECK["check_catalog"](records, pixels(), pixels())
        CHECK["check_catalog"](records[:3], pixels(), pixels(), layered=False)

    def test_every_flat_and_glass_appearance_is_required(self):
        for index in range(6):
            records = renditions()
            records.pop(index)
            with self.subTest(index=index), self.assertRaises(ValueError):
                CHECK["check_catalog"](records, pixels(), pixels())

    def test_source_filenames_do_not_disguise_substituted_pixels(self):
        records = renditions()
        for record, name in zip(records, ["default", "dark", "tinted"]):
            record["RenditionName"] = f"AppIcon-{name}.png"
        for appearance in CHECK["APPEARANCES"]:
            changed = pixels()
            changed[appearance]["rgbaSHA256"] = "f" * 64
            with self.subTest(appearance=appearance), self.assertRaises(ValueError):
                CHECK["check_catalog"](records, changed, pixels())

    def test_unrelated_or_ambiguous_icons_do_not_pass(self):
        for key, value in [
            ("Name", "LaunchMoon"), ("Idiom", "pad"), ("PixelWidth", 60),
            ("Appearance", None), ("Opaque", False),
        ]:
            records = deepcopy(renditions())
            records[1][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                CHECK["check_catalog"](records, pixels(), pixels())
        with self.assertRaises(ValueError):
            CHECK["check_catalog"](renditions() + [renditions()[0]], pixels(), pixels())

    def test_invalid_or_missing_pixel_evidence_does_not_pass(self):
        for key, value in [("rgbaSHA256", ""), ("width", 60), ("height", 60), ("opaque", False)]:
            invalid = pixels()
            invalid["UIAppearanceDark"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                CHECK["check_catalog"](renditions(), invalid, pixels())
        missing = pixels()
        del missing["UIAppearanceDark"]
        with self.assertRaises(ValueError):
            CHECK["check_catalog"](renditions(), missing, pixels())

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
