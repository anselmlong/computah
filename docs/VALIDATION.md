# Validation record

## Demo-readiness pass — 2026-09-13

Working tree based on `31420dc`; these results apply to the local changes, not a published release.

| Check | Result |
| --- | --- |
| `swift build` | Passed |
| `swift build -c release` | Passed |
| `swift test` | Blocked: local toolchain cannot import XCTest; the new worker regression test still needs hosted CI |
| Python release tests | Five passed, including public-file staging and checksum checks |
| Node website tests | Three passed: fallback markup, deep links, and keyboard/click navigation |
| Installer compilation and build-script syntax | Passed |
| Local documentation links, HTML anchors, and website assets | Passed; generated download excluded from source-only checks |
| `git diff --check` | Passed |
| Live homepage | HTTP 200 from https://computah2.anselmlong.com |
| Browser visual review | Unavailable: no connected browser; desktop/mobile rendering still needs inspection |
| Design detector | Degraded regex-only mode because parser dependencies are absent; reported the existing selected-tab underline warning and design-token advisories |

The pass reviewed app orchestration, voice transport, capture, permissions, credential handling, worker/browser lifecycles, release tooling, and documentation. It fixed unknown worker completion states being reported as successful, made website workflow links respond to hash changes, and restricted release staging to public site files. The website now uses the native lime character and links to a public setup/architecture guide and the supplied demo recording.

No authenticated model or hardware smoke test was run in this pass. No release was published. The remaining production work is documented in [ARCHITECTURE.md](../ARCHITECTURE.md#remaining-production-work); use the [demo rehearsal](DEMO.md) before presenting.

## Website theme and animation follow-up — 2026-09-13

The homepage and public docs now use black-and-lime branding. The inline SVG companion blinks, looks around, and responds to a tap; controls pause decorative motion, and offscreen/background faces stop animating. Reduced-motion styles disable decorative movement.

Five Node interaction tests and five Python release tests passed. Main palette contrast pairs measured 7.84:1–13.45:1. `git diff --check` passed. The design detector ran in degraded regex-only mode and reported palette/type advisories, the intentional tab underline, and a false-positive layout warning for SVG `stroke-width`. No browser was available for desktop/mobile rendering or performance checks. This follow-up has not been deployed.

## Earlier evidence

Hosted CI verification (2026-09-13, `88e2577`): the Swift suite executed 53 tests with zero failures and one skip (Codex CLI is absent on the hosted Mac), and all five release-script tests passed. The fake-worker fixtures no longer require a real Codex installation. [CI run](https://github.com/anselmlong/computah2/actions/runs/34757008698).

Earlier local source verification (2026-09-13, working tree after `00032e9`): debug and release compilation passed and `git diff --check` passed. Standalone protocol probes using production code verified that live search events complete normally and native execution events still stop the worker. `swift test` could not compile the test target because the local toolchain could not find `XCTest`; this is a blocked test run, not a passing suite. Tests cover protocol handling, audio conversion, permissions, credentials, hotkeys, executable discovery, worker restrictions, and concurrent browser tasks. Run them with an Xcode toolchain that provides XCTest.

Authenticated text routing and browser research were exercised with the saved app credential and Codex 0.154.0: the NUS Master of Computing General Track request reached the official program and admissions pages and produced a sourced summary without submitting anything. Early runs still navigated search-engine pages; enabling the custom provider’s standalone search capability exposed actual web-search events and navigation directly to the official admissions URL. Full voice/vision execution and a real application portal remain unverified.

Earlier signed app packaging was blocked because that session had no valid Apple Development or Developer ID signing identity. The version-tag pipeline now supports explicit ad hoc development signing for the existing prototype; Developer ID signing still requires an Apple identity.

Earlier development notes report that, with the user's authorization, local hardware tests verified nonzero microphone input after multichannel conversion, echo cancellation, and output completion through the mixer and audio device. The tests did not save audio or send it to an API. These checks do not verify a complete model conversation.


## Local test commands

```sh
swift build
swift test
python3 -m unittest discover -s scripts/tests -v
node --test scripts/tests/site.test.cjs
zsh -n scripts/build.sh
git diff --check
```

The optional `zsh scripts/run-browser-research-smoke.sh` uses the saved API key and incurs API usage. It tests text routing and browser research, not voice. `zsh scripts/audio-smoke-test.sh` exercises microphone and speaker hardware. Neither is part of ordinary CI.
