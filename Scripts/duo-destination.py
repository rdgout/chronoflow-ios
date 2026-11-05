import json
import subprocess
import sys

RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo"


def main():
    try:
        result = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "-j"],
            check=True,
            capture_output=True,
            text=True,
        )
        devices = json.loads(result.stdout)["devices"].get(RUNTIME, [])
    except subprocess.CalledProcessError as error:
        sys.exit(f"Could not list simulators: {error.stderr.strip()}")
    except (OSError, ValueError, KeyError) as error:
        sys.exit(f"Could not read simulator devices: {error}")

    for device in devices:
        if device.get("isAvailable") and device.get("deviceTypeIdentifier") == DEVICE_TYPE:
            print(f"platform=iOS Simulator,id={device['udid']}")
            return

    sys.exit(
        f"No available iPhone Duo on {RUNTIME}. "
        "Install the iPhone19-4 iOS 27.2 runtime and create an iPhone Duo simulator."
    )


if __name__ == "__main__":
    main()
