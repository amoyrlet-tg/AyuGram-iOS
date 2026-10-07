import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile


def validate_entitlements(entitlements, bundle_id):
    forbidden = {'aps-environment', 'com.apple.developer.siri'}
    if any(key in forbidden or key.startswith('com.apple.developer.icloud') or key.startswith('com.apple.developer.ubiquity') for key in entitlements):
        raise ValueError('Unsupported CloudKit, push or Siri entitlement in sideload app')
    if entitlements.get('com.apple.security.application-groups') != ['group.' + bundle_id]:
        raise ValueError('Missing or incorrect app group: Telegram needs this container at startup')


def package(ipa, output, entitlements_path, configuration):
    config = json.loads(Path(configuration).read_text())
    entitlements = plistlib.loads(Path(entitlements_path).read_bytes())
    validate_entitlements(entitlements, config['bundle_id'])
    output = Path(output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='ayugram-package-') as directory:
        root = Path(directory)
        subprocess.run(['ditto', '-x', '-k', str(Path(ipa).resolve()), str(root)], check=True)
        apps = list((root / 'Payload').glob('*.app'))
        if len(apps) != 1:
            raise ValueError('Expected one application')
        app = apps[0]
        info_path = app / 'Info.plist'
        info = plistlib.loads(info_path.read_bytes())
        info['CFBundleDisplayName'] = 'AyuGram'
        info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
        nested = list(app.rglob('*.framework')) + list(app.rglob('*.dylib'))
        for path in sorted(nested, key=lambda item: len(item.parts), reverse=True):
            subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(path)], check=True)
        subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', '--generate-entitlement-der', '--entitlements', str(Path(entitlements_path).resolve()), str(app)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        actual = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)], check=True, capture_output=True).stdout
        validate_entitlements(plistlib.loads(actual), config['bundle_id'])
        subprocess.run(['ditto', '-c', '-k', '--keepParent', str(root / 'Payload'), str(output)], check=True)
    print('Packaged ad-hoc signed IPA with app-group entitlements for SideStore re-signing.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--ipa', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--entitlements', required=True)
    parser.add_argument('--configuration', required=True)
    args = parser.parse_args()
    package(args.ipa, args.output, args.entitlements, args.configuration)
