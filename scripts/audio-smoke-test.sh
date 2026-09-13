#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/diagnostics
swiftc -parse-as-library Sources/Computah/Protocol.swift Sources/Computah/AudioEngine.swift scripts/AudioSmokeTest.swift -o .build/diagnostics/AudioSmokeTest
.build/diagnostics/AudioSmokeTest
