import argparse
import ast
import json
from pathlib import Path
import plistlib
import zipfile


def verify(ipa_path, configuration_path, variables_path):
    config = json.loads(Path(configuration_path).read_text())
    variables = {}
    for statement in ast.parse(Path(variables_path).read_text()).body:
        if isinstance(statement, ast.Assign) and len(statement.targets) == 1 and isinstance(statement.targets[0], ast.Name):
            variables[statement.targets[0].id] = ast.literal_eval(statement.value)
    expected = {
        'telegram_api_id': config['api_id'],
        'telegram_api_hash': config['api_hash'],
        'telegram_bundle_id': config['bundle_id'],
        'telegram_enable_icloud': False,
        'telegram_enable_siri': False,
        'telegram_aps_environment': '',
        'telegram_use_xcode_managed_codesigning': False,
    }
    for key, value in expected.items():
        if variables.get(key) != value:
            raise ValueError('Build configuration mismatch: ' + key)
    with zipfile.ZipFile(ipa_path) as archive:
        roots = [name for name in archive.namelist() if name.startswith('Payload/') and name.count('/') == 2 and name.endswith('.app/Info.plist')]
        if len(roots) != 1:
            raise ValueError('Expected exactly one application in the IPA')
        info = plistlib.loads(archive.read(roots[0]))
        if info['CFBundleIdentifier'] != config['bundle_id']:
            raise ValueError('IPA bundle identifier does not match the configured application')
        if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
            raise ValueError('IPA is not an iPhone device build')
        if any('/PlugIns/' in name or '/Watch/' in name or name.endswith('embedded.mobileprovision') for name in archive.namelist()):
            raise ValueError('Unexpected extension, watch app or embedded provisioning profile')
        app_root = roots[0].rsplit('/', 1)[0]
        candidates = [app_root + '/' + info['CFBundleExecutable']]
        candidates += [name for name in archive.namelist() if '.framework/' in name and name.rsplit('/', 1)[-1] == name.split('.framework/')[0].rsplit('/', 1)[-1]]
        needle = config['api_hash'].encode()
        found = False
        for name in candidates:
            with archive.open(name) as binary:
                tail = b''
                while chunk := binary.read(1024 * 1024):
                    data = tail + chunk
                    if needle in data:
                        found = True
                        break
                    tail = data[-len(needle):]
            if found:
                break
        if not found:
            raise ValueError('Configured Telegram API hash is missing from the compiled binaries')
    print('Verified device IPA, compiled API configuration and SideStore feature settings.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--ipa', required=True)
    parser.add_argument('--configuration', required=True)
    parser.add_argument('--variables', required=True)
    args = parser.parse_args()
    verify(args.ipa, args.configuration, args.variables)
