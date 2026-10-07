import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'build-system/Make'))
from Sideload import configuration_for_sideload, prepare_rules_apple
from VerifySideload import verify
from PackageSideload import validate_entitlements
import Make


class SideloadTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.config = configuration_for_sideload(json.loads((ROOT / 'build-system/appstore-configuration.json').read_text()), '12345', '1234567890abcdef1234567890abcdef')
        self.config_path = self.root / 'config.json'
        self.config_path.write_text(json.dumps(self.config))

    def test_invalid_credentials_fail_before_build(self):
        for api_id, api_hash in [('', ''), ('0', '0'), ('-1', 'f' * 32), ('2147483648', 'f' * 32), ('12345', '0' * 32), ('12345', 'bad"hash')]:
            with self.subTest(api_id=api_id), self.assertRaises(ValueError):
                configuration_for_sideload({}, api_id, api_hash)

    def test_cloudkit_cannot_be_enabled_in_sideload_configuration(self):
        result = configuration_for_sideload({'enable_icloud': True, 'enable_siri': True}, ' 12345 ', 'f' * 32)
        self.assertFalse(result['enable_icloud'])
        self.assertFalse(result['enable_siri'])
        self.assertEqual(result['api_id'], '12345')

    def test_sideload_skips_profile_resolution(self):
        with patch.object(Make, 'resolve_codesigning') as resolver:
            Make.resolve_configuration(str(self.root), None, SimpleNamespace(configurationPath=str(self.config_path), sideload=True), None)
            resolver.assert_not_called()
        self.config['enable_icloud'] = True
        self.config_path.write_text(json.dumps(self.config))
        with self.assertRaises(ValueError):
            Make.resolve_configuration(str(self.root), None, SimpleNamespace(configurationPath=str(self.config_path), sideload=True), None)

    def test_release_still_requires_real_signing_configuration(self):
        with patch.object(Make, 'resolve_codesigning', return_value=Make.ResolvedCodesigningData(None, False)), self.assertRaises(ValueError):
            Make.resolve_configuration(str(self.root), None, SimpleNamespace(configurationPath=str(self.config_path), sideload=False), None)

    def test_sideload_flags_do_not_affect_normal_builds(self):
        with patch.object(Make, 'BuildEnvironment'), patch.object(Make, 'call_executable') as call:
            command = Make.BazelCommandLine('bazel', False, False, None)
            command.build_environment.bazel_path = 'bazel'
            command.set_configuration('release_arm64')
            command.invoke_build()
            self.assertNotIn('--//Telegram:disableExtensions', call.call_args.args[0])
            self.assertNotIn('//Telegram:TelegramEntitlements', call.call_args.args[0])
            command.sideload = True
            command.set_disable_provisioning_profiles()
            command.invoke_build()
            self.assertIn('//Telegram:TelegramEntitlements', call.call_args.args[0])
            for flag in ['--//Telegram:disableProvisioningProfiles', '--//Telegram:disableExtensions', '--features=apple.sideload', '--features=disable_legacy_signing']:
                self.assertIn(flag, call.call_args.args[0])

    def test_rules_patch_is_idempotent_and_feature_scoped(self):
        path = self.root / 'build-system/bazel-rules/rules_apple/apple/internal/ios_rules.bzl'
        path.parent.mkdir(parents=True)
        original = '    if platform_prerequisites.platform.is_device:\n        processor_partials.append(\n            partials.provisioning_profile_partial('
        path.write_text(original)
        prepare_rules_apple(self.root)
        first = path.read_text()
        prepare_rules_apple(self.root)
        self.assertEqual(path.read_text(), first)
        self.assertIn('"apple.sideload" not in features', first)

    def test_packaging_keeps_app_group_and_rejects_cloud_entitlements(self):
        entitlements = {'com.apple.security.application-groups': ['group.' + self.config['bundle_id']]}
        validate_entitlements(entitlements, self.config['bundle_id'])
        with self.assertRaises(ValueError):
            validate_entitlements({}, self.config['bundle_id'])
        for key in ['com.apple.developer.icloud-services', 'aps-environment', 'com.apple.developer.siri']:
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_entitlements(dict(entitlements, **{key: True}), self.config['bundle_id'])

    def test_ipa_rejects_stale_api_hash_and_cloudkit(self):
        variables = self.root / 'variables.bzl'
        config = Make.build_configuration_from_json(str(self.config_path))
        config.write_to_variables_file('bazel', False, '', str(variables))
        ipa = self.root / 'app.ipa'
        def write_ipa(binary):
            with zipfile.ZipFile(ipa, 'w') as archive:
                archive.writestr('Payload/AyuGram.app/Info.plist', plistlib.dumps({'CFBundleIdentifier': self.config['bundle_id'], 'CFBundleExecutable': 'AyuGram', 'CFBundleSupportedPlatforms': ['iPhoneOS']}))
                archive.writestr('Payload/AyuGram.app/AyuGram', binary)
        write_ipa(b'stale-config')
        with self.assertRaisesRegex(ValueError, 'compiled binaries'):
            verify(ipa, self.config_path, variables)
        write_ipa(self.config['api_hash'].encode())
        verify(ipa, self.config_path, variables)
        variables.write_text(variables.read_text().replace('telegram_enable_icloud = False', 'telegram_enable_icloud = True'))
        with self.assertRaisesRegex(ValueError, 'telegram_enable_icloud'):
            verify(ipa, self.config_path, variables)


if __name__ == '__main__':
    unittest.main()
