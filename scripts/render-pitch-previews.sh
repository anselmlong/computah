#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/pitch-previews
capture_sources=(Sources/Computah/*.swift)
capture_sources=(${capture_sources:#Sources/Computah/main.swift})
swiftc -parse-as-library "${capture_sources[@]}" scripts/PitchPreviews.swift -o .build/pitch-previews/Capture
.build/pitch-previews/Capture
