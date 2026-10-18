#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"
command -v flutter >/dev/null 2>&1 || {
  echo "Flutter SDK tidak tersedia. Pasang Flutter dengan Dart >=3.10, lalu ulangi." >&2
  exit 1
}
flutter pub get
flutter analyze
flutter test
