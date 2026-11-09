import plistlib
import sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:])
info = plistlib.loads(source.read_bytes())
info["CFBundleURLTypes"] = [{"CFBundleURLName": "UITestReseed", "CFBundleURLSchemes": ["chronoflow-uitest"]}]
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_bytes(plistlib.dumps(info))
