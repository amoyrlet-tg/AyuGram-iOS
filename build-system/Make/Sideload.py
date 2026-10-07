import json
import os
from pathlib import Path
import re


def configuration_for_sideload(template, api_id, api_hash):
    api_id = api_id.strip()
    api_hash = api_hash.strip()
    if not api_id.isascii() or not api_id.isdecimal() or not 0 < int(api_id) <= 2147483647:
        raise ValueError('TELEGRAM_API_ID must contain a positive Telegram application ID')
    if not re.fullmatch(r'[0-9a-fA-F]{32}', api_hash) or int(api_hash, 16) == 0:
        raise ValueError('TELEGRAM_API_HASH must contain the 32-character Telegram application hash')
    result = dict(template)
    result.update(api_id=str(int(api_id)), api_hash=api_hash, enable_icloud=False,
                  enable_siri=False, is_appstore_build='false', premium_iap_product_id='')
    return result


def prepare_rules_apple(base_path):
    path = Path(base_path) / 'build-system/bazel-rules/rules_apple/apple/internal/ios_rules.bzl'
    source = path.read_text()
    original = '''    if platform_prerequisites.platform.is_device:
        processor_partials.append(
            partials.provisioning_profile_partial('''
    patched = '''    if platform_prerequisites.platform.is_device and "apple.sideload" not in features:
        processor_partials.append(
            partials.provisioning_profile_partial('''
    if patched in source:
        return
    if original not in source:
        raise RuntimeError('rules_apple changed: review the sideload provisioning integration')
    path.write_text(source.replace(original, patched, 1))


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--template', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    try:
        config = configuration_for_sideload(json.loads(Path(args.template).read_text()),
            os.environ.get('TELEGRAM_API_ID', ''), os.environ.get('TELEGRAM_API_HASH', ''))
    except ValueError as error:
        parser.error(str(error))
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(config, indent=2) + '\n')
    output.chmod(0o600)
    print('Validated Telegram API credentials; iCloud and Siri disabled for SideStore.')
