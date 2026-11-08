import os
from pathlib import Path
import plistlib
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AuthSigningTests(unittest.TestCase):
    def run_guard(self, **values):
        keys = ['CODE_SIGN_ENTITLEMENTS', 'PLATFORM_NAME', 'CONFIGURATION', 'DEVELOPMENT_TEAM',
                'CODE_SIGN_IDENTITY', 'CODE_SIGNING_ALLOWED', 'EXPANDED_CODE_SIGN_IDENTITY']
        env = {k: v for k, v in os.environ.items() if k not in keys}
        env.update(values)
        return subprocess.run(['sh', str(ROOT / 'Scripts/check-device-entitlements.sh')],
                              env=env, capture_output=True).returncode

    def test_only_device_signed_configuration_declares_entitlements(self):
        config = (ROOT / 'Config/DeviceSigned.xcconfig').read_text()
        self.assertIn('CODE_SIGN_ENTITLEMENTS =\n', config)
        self.assertIn('CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*] = Config/Device.entitlements', config)
        self.assertNotIn('CODE_SIGN_ENTITLEMENTS', (ROOT / 'Config/Base.xcconfig').read_text())
        data = plistlib.loads((ROOT / 'Config/Device.entitlements').read_bytes())
        self.assertEqual(data, {'com.apple.developer.associated-domains': ['webcredentials:app.chronoflow.net', 'applinks:app.chronoflow.net']})

    def test_normal_simulator_and_adhoc_builds_have_no_entitlements(self):
        self.assertEqual(self.run_guard(PLATFORM_NAME='iphonesimulator', CODE_SIGN_IDENTITY='-'), 0)
        self.assertEqual(self.run_guard(PLATFORM_NAME='iphoneos', CODE_SIGN_IDENTITY='-'), 0)

    def test_signed_configuration_rejects_adhoc_simulator_and_unsigned_overrides(self):
        valid = dict(CODE_SIGN_ENTITLEMENTS='Config/Device.entitlements', PLATFORM_NAME='iphoneos',
                     CONFIGURATION='DeviceSigned', DEVELOPMENT_TEAM='TESTTEAM', CODE_SIGN_IDENTITY='Apple Development',
                     EXPANDED_CODE_SIGN_IDENTITY='test-certificate-hash')
        self.assertEqual(self.run_guard(**valid), 0)
        for change in [dict(PLATFORM_NAME='iphonesimulator'), dict(CODE_SIGN_IDENTITY='-'),
                       dict(EXPANDED_CODE_SIGN_IDENTITY='-'), dict(DEVELOPMENT_TEAM=''),
                       dict(CONFIGURATION='Debug'), dict(CODE_SIGNING_ALLOWED='NO')]:
            self.assertNotEqual(self.run_guard(**(valid | change)), 0)


if __name__ == '__main__':
    unittest.main()
