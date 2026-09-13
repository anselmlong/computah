#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/browser-research-smoke
smoke_sources=(Sources/Computah/*.swift)
smoke_sources=(${smoke_sources:#Sources/Computah/main.swift})
swiftc -parse-as-library "${smoke_sources[@]}" scripts/BrowserResearchSmoke.swift -o .build/browser-research-smoke/Run
.build/browser-research-smoke/Run "$@"
