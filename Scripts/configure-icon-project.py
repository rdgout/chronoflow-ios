from pathlib import Path
import re


def configure(source):
    # XcodeGen 2.46's wrapper.icon type bypasses Xcode's actool input grouping.
    pattern = r'(isa = PBXFileReference; lastKnownFileType = )(?:wrapper\.icon|folder\.iconcomposer\.icon)(; path = ChronoFlow\.icon;)'
    result, count = re.subn(pattern, r'\g<1>folder.iconcomposer.icon\2', source)
    if count != 1:
        raise ValueError(f"Expected one ChronoFlow.icon file reference, found {count}")
    return result


if __name__ == "__main__":
    project = Path(__file__).resolve().parents[1] / "ChronoFlow.xcodeproj/project.pbxproj"
    source = project.read_text()
    result = configure(source)
    if result != source:
        project.write_text(result)
