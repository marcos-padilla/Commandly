#!/usr/bin/env python3
"""Reproduce the bundled catalog using pinned Unicode data; Python standard library only.
Sources and Unicode-3.0 notices accompany the input and generated output.
No network access is needed. Run from any directory; --check verifies reproducibility.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
INPUT = ROOT / 'scripts' / 'emoji-data'
OUTPUT = ROOT / 'Commandly' / 'Resources' / 'Emoji' / 'emoji-catalog-v17.json'
SOURCES = {
    'emoji-test-17.0.txt': 'https://www.unicode.org/Public/17.0.0/emoji/emoji-test.txt',
    'cldr-48-annotations-en.xml': 'https://raw.githubusercontent.com/unicode-org/cldr/release-48/common/annotations/en.xml',
    'cldr-48-annotations-derived-en.xml': 'https://raw.githubusercontent.com/unicode-org/cldr/release-48/common/annotationsDerived/en.xml',
}
PINNED_SHA256 = {'emoji-test-17.0.txt': '1d8a944f88d7952f7ef7c5167fef3c67995bcae24543949710231b03a201acda', 'cldr-48-annotations-en.xml': '8511aadd046fdba2f0ffe590266ced8bbf48175ad139b2675d85d7141057b235', 'cldr-48-annotations-derived-en.xml': 'd76bd041c8c9e7b00b716aff8b7d9dbf509877010e191d5efd068be2553e066e'}
TONE = re.compile(r'(?:medium-light|medium-dark|light|medium|dark) skin tone')
def key(symbol):
    return symbol.replace('\ufe0f', '')

def generate():
    for name, expected in PINNED_SHA256.items():
        assert hashlib.sha256((INPUT / name).read_bytes()).hexdigest() == expected, f'Unexpected source data: {name}'
    annotations = {}
    for name in list(SOURCES)[1:]:
        for node in ET.parse(INPUT / name).findall('.//annotation'):
            if node.attrib.get('type') == 'tts':
                continue  # The official emoji-test short name identifies exact sequences.
            annotations[key(node.attrib['cp'])] = (node.text or '').split(' | ')
    entries, alternatives, counts = [], [], {}
    group = subgroup = ''
    for line in (INPUT / 'emoji-test-17.0.txt').read_text().splitlines():
        if line.startswith('# group: '): group = line.removeprefix('# group: ')
        if line.startswith('# subgroup: '): subgroup = line.removeprefix('# subgroup: ')
        match = re.match(r'^([A-F0-9 ]+)\s*;\s*([a-z-]+)\s*#\s*\S+\s+E[\d.]+\s+(.+)$', line)
        if not match: continue
        codes, status, name = match.groups()
        symbol = ''.join(chr(int(code, 16)) for code in codes.split())
        counts[status] = counts.get(status, 0) + 1
        if status not in ('fully-qualified', 'component'):
            alternatives.append(symbol)
            continue
        entries.append(dict(symbol=symbol, name=name, category=group, subgroup=subgroup,
                            keywords=sorted(set(annotations.get(key(symbol), []))),
                            isComponent=status == 'component', family=symbol))
    assert counts['fully-qualified'] == 3944 and counts['component'] == 9, counts
    assert len({x['symbol'] for x in entries}) == 3953
    symbols = {key(x['symbol']): x['symbol'] for x in entries}
    names = {x['name']: x['symbol'] for x in entries if not any(0x1F3FB <= ord(c) <= 0x1F3FF for c in x['symbol'])}
    unmatched = []
    for entry in entries:
        if entry['isComponent']: continue
        no_tone = ''.join(c for c in entry['symbol'] if not 0x1F3FB <= ord(c) <= 0x1F3FF)
        if no_tone == entry['symbol']: continue
        name = TONE.sub('', entry['name'])
        name = re.sub(r',\s*(?=,|$)', '', name).strip(' ,:')
        family = symbols.get(key(no_tone)) or names.get(name)
        # Gender-neutral kissing/heart couples use legacy single-codepoint defaults.
        if not family:
            family = names.get({'couple with heart: person, person': 'couple with heart',
                                'kiss: person, person': 'kiss'}.get(name, ''))
        if family: entry['family'] = family
        else: unmatched.append((entry['name'], name))
    assert not unmatched, unmatched
    payload = dict(schema=1, unicodeVersion='17.0', cldrVersion='48', fullyQualifiedCount=3944, componentCount=9,
                   license='Unicode-3.0', sources=[dict(file=n, url=u, sha256=hashlib.sha256((INPUT/n).read_bytes()).hexdigest()) for n,u in SOURCES.items()],
                   entries=entries, aliases={a:symbols[key(a)] for a in alternatives})
    assert all(x['family'] in {e['symbol'] for e in entries} for x in entries)
    return json.dumps(payload, ensure_ascii=False, separators=(',', ':')) + '\n'

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    result = generate()
    if args.check:
        assert OUTPUT.read_text() == result, 'Catalog differs. Regenerate and review the source/count changes.'
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(result)
    print('Unicode 17.0: 3,944 fully-qualified emoji + 9 components; CLDR 48 English keywords verified.')
