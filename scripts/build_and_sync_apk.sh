#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "=== 1. Building Flutter Release APK ==="
cd frontend
flutter build apk --release
cd "$REPO_ROOT"

echo "=== 2. Synchronizing APK to apks/ and landing page ==="
node tools/sync_apk.js
