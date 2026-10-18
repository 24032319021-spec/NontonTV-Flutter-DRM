#!/usr/bin/env python3
"""Verify the protected player files against the uploaded 0.3.0 snapshot."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
baseline = json.loads((root / 'test/fixtures/player_baseline_sha256.json').read_text())
changed = []
cast_cleanup = []
for relative, expected in baseline.items():
    file = root / relative
    if not file.is_file():
        changed.append(relative)
        continue
    data = file.read_bytes()
    if hashlib.sha256(data).hexdigest() == expected:
        continue
    # Retain the ORIGINAL baseline and permit only this explicitly documented
    # no-op cast removal in the Dart bridge. Native Kotlin must match exactly.
    if relative == 'lib/features/player/native/native_exoplayer_controller.dart':
        cleaned = b'final map = Map<Object?, Object?>.from(event);'
        original = b'final map = Map<Object?, Object?>.from(event as Map);'
        if data.count(cleaned) == 1 and hashlib.sha256(
            data.replace(cleaned, original, 1)
        ).hexdigest() == expected:
            cast_cleanup.append(relative)
            continue
    changed.append(relative)
if changed:
    raise SystemExit('Protected player files changed: ' + ', '.join(changed))
print(f'PASS: {len(baseline) - len(cast_cleanup)} protected files unchanged; '
      f'{len(cast_cleanup)} bridge file has only the documented redundant-cast cleanup.')
