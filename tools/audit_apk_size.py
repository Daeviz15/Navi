"""Measure APK ZIP contents without extracting or changing the APK.

Sizes describe this file, not Play Store downloads or Android installed storage.
"""

import argparse
from collections import defaultdict
import json
from pathlib import Path
import zipfile


def category(name):
    asset_prefix = 'assets/flutter_assets/assets/'
    if name.startswith('lib/'):
        return 'native/' + name.split('/')[1]
    if name.startswith(asset_prefix):
        relative = name[len(asset_prefix):]
        parts = relative.split('/')
        if parts[0] == 'voice' and len(parts) > 2:
            return '/'.join(parts[:2])
        return parts[0]
    if name == 'assets/flutter_assets/kernel_blob.bin':
        return 'debug Dart kernel'
    return 'other entries'


def audit(path):
    totals = defaultdict(lambda: {'compressed_bytes': 0, 'raw_bytes': 0, 'files': 0})
    with zipfile.ZipFile(path) as archive:
        for item in archive.infolist():
            if item.is_dir():
                continue
            group = totals[category(item.filename)]
            group['compressed_bytes'] += item.compress_size
            group['raw_bytes'] += item.file_size
            group['files'] += 1
    size = path.stat().st_size
    compressed = sum(group['compressed_bytes'] for group in totals.values())
    return {
        'apk': str(path),
        'apk_bytes': size,
        'zip_entry_compressed_bytes': compressed,
        # Includes ZIP headers, signing blocks, alignment and any unused space.
        'container_overhead_bytes': size - compressed,
        'categories': dict(sorted(totals.items())),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apks', nargs='+', type=Path)
    parser.add_argument('--json', type=Path, help='Save exact byte counts as JSON')
    args = parser.parse_args()
    reports = [audit(path) for path in args.apks]
    for report in reports:
        print(f"\n{report['apk']}: {report['apk_bytes'] / 1_000_000:.2f} MB")
        print(f"{'Category':30} {'ZIP MB':>10} {'Raw MB':>10} {'Files':>7}")
        for name, group in sorted(report['categories'].items(),
                                  key=lambda pair: -pair[1]['compressed_bytes']):
            print(f"{name:30} {group['compressed_bytes'] / 1_000_000:10.2f} "
                  f"{group['raw_bytes'] / 1_000_000:10.2f} {group['files']:7}")
        print(f"Container overhead: {report['container_overhead_bytes'] / 1_000_000:.2f} MB")
    if args.json:
        args.json.write_text(json.dumps(reports, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
