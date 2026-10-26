#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null; then
  echo 'Для сборки нужен macOS с установленным Xcode.' >&2
  exit 1
fi
xcodebuild -project RuPocket.xcodeproj -scheme RuPocket -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
python3 - <<'PY'
from pathlib import Path
import zipfile
app = Path('build/DerivedData/Build/Products/Release-iphoneos/RuPocket.app')
if not (app / 'RuPocket').is_file():
    raise SystemExit('Скомпилированное приложение не найдено')
output = Path('build/RuPocket-0.1.1-unsigned.ipa')
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for file in sorted(app.rglob('*')):
        if file.is_file():
            archive.write(file, 'Payload/RuPocket.app/' + file.relative_to(app).as_posix())
print(output.resolve())
PY
