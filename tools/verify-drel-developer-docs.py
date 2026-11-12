#!/usr/bin/env python3
"""Fail closed on stale Drel developer contracts, malformed schema, or leaked keys."""
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / 'docs/site'
ERRORS = []
class Validator(HTMLParser):
    def error(self, message):
        ERRORS.append(message)

files = [SITE/'docs/zh/index.html', SITE/'docs/bridge/index.html', SITE/'docs/push/index.html']
for path in files:
    text = path.read_text(encoding='utf-8')
    Validator(convert_charrefs=True).feed(text)
    if re.search(r'https://api\.drel\.app/[A-Za-z0-9_-]{16,}(?:[/?"\s<]|$)', text):
        ERRORS.append(f'{path}: possible device key in public docs')
    if text.count('<pre') != text.count('</pre>'):
        ERRORS.append(f'{path}: unbalanced pre blocks')
for src in sorted((ROOT/'docs/api/schemas').glob('*.schema.json')):
    dest = SITE/'schemas'/src.name
    try:
        schema = json.loads(src.read_text(encoding='utf-8'))
        if schema.get('$schema') != 'https://json-schema.org/draft/2020-12/schema' or not schema.get('$id'):
            ERRORS.append(f'{src}: missing versioned schema metadata')
        if src.read_bytes() != dest.read_bytes():
            ERRORS.append(f'{dest}: differs from canonical schema')
    except (OSError, ValueError) as exc:
        ERRORS.append(f'{src}: {exc}')
host = (ROOT/'SuperApp/Sources/AppDelegate.swift').read_text()
allowlist = host.split('WebBridgeHostCapabilityPolicy.nativeActionAllowlist = [', 1)[1].split(']', 1)[0]
for required_action in ['haptic','vibrate','share','fullscreen','clipboard','getLocation','addToHomeScreen','sensors']:
    if f'"{required_action}"' not in allowlist:
        ERRORS.append(f'host allowlist is missing {required_action}')
if 'nativeActionAllowlist?.insert("audioLevel")' not in host:
    ERRORS.append('host audioLevel gate is missing')
bridge = (SITE/'docs/bridge/index.html').read_text()
zh = (SITE/'docs/zh/index.html').read_text()
guide = (ROOT/'docs/guides/bridge-api.md').read_text()
for action in ['haptic','vibrate','share','fullscreen','clipboard','getLocation','addToHomeScreen','sensors','audioLevel']:
    if f'<code>{action}</code>' not in bridge or f'<code>{action}</code>' not in zh:
        ERRORS.append(f'public docs missing action {action}')
for text in [bridge, zh, guide]:
    if not all(v in text for v in ['1.5.0','1.5.2','130','131','132','138']):
        ERRORS.append('missing app version/build boundaries')
    if re.search(r'audioLevel[^\n.]{0,100}1\.5\.1', text, re.I):
        ERRORS.append('audioLevel incorrectly attributed to 1.5.1')
    if re.search(r'(seven|7) actions are exposed', text, re.I):
        ERRORS.append('obsolete seven-actions claim')
if ERRORS:
    print('\n'.join('ERROR: '+error for error in ERRORS), file=sys.stderr)
    sys.exit(1)
print('PASS: developer docs versions, action names, schemas, and secret scan')
