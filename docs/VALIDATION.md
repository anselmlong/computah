# Validation record

## Build 22 pass — 2026-09-13

These results apply to the merged working tree and the normal Codex worker architecture. The 80-test Swift run covers the YOLO configuration, worker-to-voice question flow, wake phrase, and notch dismissal. Build 22 packages that code.

| Check | Result |
| --- | --- |
| `swift test` | 80 passed |
| Focused worker tests before the merge | 15 passed, including installed Codex handshake, fake app-approval continuation, concurrency, and current-directory preservation |
| Python release tests | Eight passed |
| Node website tests | Six passed |
| Installer compilation | Passed |
| Installed release | Build 22 signed, notarized, stapled, accepted by Gatekeeper, installed, and running |
| Historical installed notch UI | Build 20 verified the 273 by 32 point idle geometry and face-only idle control; face-click open/close passed twice on build 17, whose interaction code remained unchanged in build 20 |
| Historical native Computer Use probe | Astra loaded native Computer Use and emitted MCP app approval; decline returned the expected not-approved result. The current GPT-5.6 Sol worker has not had this live check. |
| Approval acceptance probe | Stalled before the tool request; no successful Calculator observation or complete task is claimed |

Hover opening, physical outside-click collapse, the in-app **Allow once** continuation, the physical Right Shift tap-and-circle flow, and a full voice, vision, and native Computer Use sequence remain unverified in the installed app.

Worker-question tests verify that structured requests keep the same app-server turn alive, concurrent request IDs stay isolated by task, only grounded user speech becomes an answer, unrelated or ambiguous speech does not advance the worker, task-card forms submit complete answers, and secret fields stay out of voice transport. A live spoken worker-question exchange remains unverified.

Earlier validation below describes the retired private WebKit task runtime where stated. Keep it as historical evidence for the website, release tooling, voice, capture, and fixture code rather than evidence for current Computer Use behavior.

## Local Xcode verification — 2026-09-13

With Xcode 26.6 (17F113) installed, the incoming wake-word working tree passed all 58 XCTest tests with zero failures or skips, including four wake-phrase and notch-dismissal tests. Release compilation also passed. Both commands used `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; the system-wide selection remains Command Line Tools because changing it requires administrator authentication. This supersedes the earlier local XCTest toolchain blocker for that working tree.

`Resources/Info.plist` validation and `git diff --check` passed. The app was then packaged with explicit ad hoc signing and launched for user testing. After changing the phrase to "Hey, computah" and adding a spoken acknowledgment on connection, all 58 tests passed again and local build 2 was launched. No Apple Development or Developer ID signing identity was present. These tests do not verify spoken wake detection through a real microphone or an authenticated voice conversation.

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

The optional `zsh scripts/run-browser-research-smoke.sh` uses the saved API key and exercises the retired WebKit fixture path. It does not validate the current native Computer Use worker. `zsh scripts/audio-smoke-test.sh` exercises microphone and speaker hardware. Neither is part of ordinary CI.
