"""Collect licenses from the locked Cargo graph, without recording local paths.

Run cargo metadata --locked --format-version 1 in the host's rust directory,
redirect its output into .tools/mornye-cargo-metadata.json, then run this script.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVISION = '45df9860661e9c4e731ef26a60c44b2b5d8cf125'


def generate():
    metadata = json.loads((ROOT / '.tools/mornye-cargo-metadata.json').read_text(encoding='utf-8-sig'))
    parts = [
        'Hyperstream native music extension runtime\n'
        'Includes Mornye core, network, providers and extensions (LGPL-3.0-only).\n'
        f'Corresponding source: https://github.com/mornyeapp/Mornye/tree/{REVISION}\n'
        'Hyperstream adapter and reproducible build instructions: '
        'https://github.com/victoralvelais/navidrome-hyperstream/tree/main/apps/client/packages/mornye_host\n'
        'The native runtime is dynamically linked. You may replace/rebuild it; '
        'the Hyperstream source is available for relinking and sideloading.\n'
        'The remainder of this file contains notices for the pinned native dependencies.\n'
    ]
    upstream = next(Path(p['manifest_path']).parents[3] for p in metadata['packages'] if p['name'] == 'mornye-extensions')
    if not (upstream / 'COPYING').is_file():
        raise RuntimeError('Mornye source license files are missing.')
    for relative in ['LICENSE', 'COPYING', 'NOTICE', 'rust_backend/NOTICE',
                     'assets/licenses/native_palette.txt', 'assets/licenses/native_data_jobs.txt']:
        file = upstream / relative
        if file.is_file():
            parts.append(f'Mornye: {relative}\n\n{file.read_text(encoding="utf-8", errors="replace")}')
    seen = set()
    count = 0
    for package in sorted(metadata['packages'], key=lambda p: (p['name'], p['version'])):
        if not package.get('source') or package['name'].startswith('mornye-'):
            continue
        directory = Path(package['manifest_path']).parent
        files = [p for p in directory.rglob('*') if p.is_file()
                 and re.match(r'^(LICENSE|LICENCE|COPYING|NOTICE)([-_.].*)?$', p.name, re.I)
                 and p.stat().st_size < 2_000_000]
        if package.get('license_file'):
            files.append(directory / package['license_file'])
        parts.append(f"{package['name']} {package['version']}\nLicense: {package.get('license') or 'See license file'}\n"
                     f"Source: {package.get('repository') or 'https://crates.io/crates/' + package['name']}")
        for file in sorted(set(files)):
            text = file.read_text(encoding='utf-8', errors='replace').strip()
            if text not in seen:
                parts.append(text)
                seen.add(text)
        count += 1
    output = '\n\n'.join(parts)
    output = '\n'.join(line.expandtabs(4).rstrip() for line in output.splitlines()) + '\n'
    (ROOT / 'apps/client/assets/licenses/MORNYE-NOTICES.txt').write_bytes(output.encode('utf-8'))
    print(f'Collected notices for {count} native dependencies.')


if __name__ == '__main__':
    generate()
