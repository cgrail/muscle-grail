#!/bin/bash
# Downloads RepDB's exercise list into Core's resources, at the commit `CatalogExercise.repdbCommit` pins.
# RepDB's license allows in-app use but forbids republishing the dataset, so it is never committed (.gitignore):
# the Xcode schemes run this before every build, CI runs it as a step, and `swift test` needs it run once.
set -euo pipefail
core=$(cd "$(dirname "$0")" && pwd)
commit=$(grep -o 'repdbCommit = "[0-9a-f]\{40\}"' "$core/Sources/Core/Catalog.swift" | grep -o '[0-9a-f]\{40\}')
out="$core/Sources/Core/RepDB/exercises.json"
stamp="$core/Sources/Core/RepDB/.commit"
if [ -s "$out" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$commit" ]; then exit 0; fi
curl -fsSL --retry 3 "https://raw.githubusercontent.com/RepDB/exercise-dataset/$commit/exercises.json" -o "$out.download"
mv "$out.download" "$out"
echo "$commit" > "$stamp"
