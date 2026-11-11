import os
from pathlib import Path
import plistlib
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AuthSigningTests(unittest.TestCase):
    def run_guard(self, **values):
        keys = ['CODE_SIGN_ENTITLEMENTS', 'PLATFORM_NAME', 'CONFIGURATION', 'DEVELOPMENT_TEAM',
                'CODE_SIGN_IDENTITY', 'CODE_SIGNING_ALLOWED', 'EXPANDED_CODE_SIGN_IDENTITY',
                'CHRONOFLOW_ASSOCIATED_DOMAINS']
        env = {k: v for k, v in os.environ.items() if k not in keys}
        env.update(values)
        return subprocess.run(['sh', str(ROOT / 'Scripts/check-device-entitlements.sh')],
                              env=env, capture_output=True).returncode

    def test_release_and_device_signed_require_team_and_associated_domains_opt_in(self):
        project = (ROOT / 'project.yml').read_text()
        app = project.split('\n  ChronoFlow:\n', 1)[1].split('\n  AppTests:\n', 1)[0]
        self.assertIn('DeviceSigned: Config/DeviceSigned.xcconfig', app)
        self.assertIn('Release: Config/DeviceSigning.xcconfig', app)
        self.assertNotIn('Perf: Config/DeviceSigning.xcconfig', project)
        configs = project.split('\nconfigFiles:\n', 1)[1].split('\nsettings:\n', 1)[0]
        for configuration in ['Debug', 'Release', 'Perf', 'DeviceSigned']:
            self.assertIn(configuration + ': Config/Base.xcconfig', configs)
        config = (ROOT / 'Config/DeviceSigning.xcconfig').read_text()
        self.assertNotIn('#include "Base.xcconfig"', config)
        self.assertIn('CHRONOFLOW_HAS_TEAM_ = NO\n', config)
        self.assertIn('CHRONOFLOW_HAS_TEAM = $(CHRONOFLOW_HAS_TEAM_$(DEVELOPMENT_TEAM):default=YES)', config)
        self.assertIn('CHRONOFLOW_DEVICE_ENTITLEMENTS_YES_YES = Config/Device.entitlements', config)
        self.assertIn('CODE_SIGN_ENTITLEMENTS =\n', config)
        self.assertIn('CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*] = $(CHRONOFLOW_DEVICE_ENTITLEMENTS_$(CHRONOFLOW_HAS_TEAM)_$(CHRONOFLOW_ASSOCIATED_DOMAINS))', config)
        development = (ROOT / 'Config/DeviceSigned.xcconfig').read_text()
        self.assertIn('#include "DeviceSigning.xcconfig"', development)
        self.assertIn('CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Development', development)
        self.assertNotIn('CODE_SIGN_IDENTITY', config)
        self.assertNotIn('CODE_SIGN_ENTITLEMENTS', (ROOT / 'Config/Base.xcconfig').read_text())
        data = plistlib.loads((ROOT / 'Config/Device.entitlements').read_bytes())
        self.assertEqual(data, {'com.apple.developer.associated-domains': ['webcredentials:app.chronoflow.net', 'applinks:app.chronoflow.net']})

    def test_normal_simulator_and_adhoc_builds_have_no_entitlements(self):
        for configuration in ['Debug', 'Release', 'Perf', 'DeviceSigned']:
            for platform in ['iphonesimulator', 'iphoneos']:
                with self.subTest(configuration=configuration, platform=platform):
                    self.assertEqual(self.run_guard(CONFIGURATION=configuration,
                                                    PLATFORM_NAME=platform, CODE_SIGN_IDENTITY='-'), 0)

    def test_signed_configurations_accept_development_and_distribution_certificates(self):
        for configuration in ['Release', 'DeviceSigned']:
            for identity in ['Apple Development', 'Apple Distribution']:
                with self.subTest(configuration=configuration, identity=identity):
                    self.assertEqual(self.run_guard(
                        CODE_SIGN_ENTITLEMENTS='Config/Device.entitlements', PLATFORM_NAME='iphoneos',
                        CONFIGURATION=configuration, DEVELOPMENT_TEAM='TESTTEAM', CODE_SIGN_IDENTITY=identity,
                        CHRONOFLOW_ASSOCIATED_DOMAINS='YES',
                        CODE_SIGNING_ALLOWED='YES', EXPANDED_CODE_SIGN_IDENTITY='test-certificate-hash'), 0)

    def test_personal_team_builds_without_entitlements_need_no_opt_in(self):
        for configuration in ['Release', 'DeviceSigned']:
            for opt_in in ['', 'NO']:
                with self.subTest(configuration=configuration, opt_in=opt_in):
                    self.assertEqual(self.run_guard(
                        PLATFORM_NAME='iphoneos', CONFIGURATION=configuration,
                        DEVELOPMENT_TEAM='2UMFLSCBZ6', CODE_SIGN_IDENTITY='Apple Development',
                        EXPANDED_CODE_SIGN_IDENTITY='test-certificate-hash',
                        CHRONOFLOW_ASSOCIATED_DOMAINS=opt_in), 0)

    def test_signed_configurations_reject_unsafe_or_non_opted_in_entitlement_overrides(self):
        for configuration in ['Release', 'DeviceSigned']:
            valid = dict(CODE_SIGN_ENTITLEMENTS='Config/Device.entitlements', PLATFORM_NAME='iphoneos',
                         CONFIGURATION=configuration, DEVELOPMENT_TEAM='TESTTEAM', CODE_SIGN_IDENTITY='Apple Development',
                         EXPANDED_CODE_SIGN_IDENTITY='test-certificate-hash', CHRONOFLOW_ASSOCIATED_DOMAINS='YES')
            for key, invalid in [
                ('PLATFORM_NAME', ['iphonesimulator', 'macosx', '']),
                ('CONFIGURATION', ['Debug', 'Perf', '']),
                ('DEVELOPMENT_TEAM', ['']), ('CODE_SIGN_IDENTITY', ['-', '']),
                ('EXPANDED_CODE_SIGN_IDENTITY', ['-', '']), ('CODE_SIGNING_ALLOWED', ['NO']),
                ('CHRONOFLOW_ASSOCIATED_DOMAINS', ['', 'NO', 'yes', '1']),
            ]:
                for value in invalid:
                    with self.subTest(configuration=configuration, key=key, value=value):
                        self.assertNotEqual(self.run_guard(**(valid | {key: value})), 0)
                if key != 'CODE_SIGNING_ALLOWED':
                    with self.subTest(configuration=configuration, missing=key):
                        self.assertNotEqual(self.run_guard(**{k: v for k, v in valid.items() if k != key}), 0)


if __name__ == '__main__':
    unittest.main()
