# Computah

Computah is a personal macOS prototype for talking about your screen and delegating browser tasks while you keep using your Mac. Its animated lime character lives in a black notch panel, called the Dynamic Island in this project. Conversation, settings, and task previews expand from that panel. The task browser can also open in a larger window for watching or manual review. There is no Dock icon or separate menu bar item.

## Build and open

You need macOS 14 or later, an Xcode Swift toolchain, and internet access. Browser tasks also need the Codex CLI with support for the app-server protocol and dynamic tools. Computah checks its inherited `PATH`, then `~/.local/bin/codex`, `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, and `~/.cargo/bin/codex`. These explicit locations also work when opening the app from Finder, which does not inherit your shell's `PATH`.

```sh
zsh scripts/build.sh
open dist/Computah.app
```

The script builds a release executable, stages and verifies the app, then replaces `dist/Computah.app`. It signs with an existing Apple Development certificate, falling back to Developer ID Application. The same bundle identifier and certificate keep the app's signing identity stable across rebuilds. This is a local prototype build, not a notarized distribution. Quit a running Computah before opening a rebuilt version.

Set `COMPUTAH_SIGNING_IDENTITY` to choose an existing signing identity. Only an explicit value of `-` selects ad hoc signing, with a warning about permission stability. The script fails clearly if it cannot find a signing identity. Approve the signed Computah through the normal macOS permission prompt. Do not repeatedly toggle or reset permissions.

Expand the notch panel with its chevron, then open settings with the gear. Paste your OpenAI API key. Starting a conversation automatically saves it to macOS Keychain; you can also save it directly in settings. Computah loads the saved key at startup. Settings provide save, replace, and remove controls. The key needs access to `gpt-live-1`, `gpt-5.6-luna`, and `gpt-5.6-sol`. Requests use your OpenAI API account and incur its applicable charges.

Use each permission row's **Allow** or **Settings** control to grant Microphone, Screen Recording, and Input Monitoring access. Permission status refreshes automatically without triggering consent prompts. An explicit **Allow** action requests access once. Input Monitoring enables the conversation key, which defaults to Right Shift. The **Conversation key** picker also offers right Command, Option, and Control; this choice persists between launches. The **Start talking** button works without the shortcut.

If macOS requires a relaunch after permission changes, choose **Reopen Computah**. Reopening ends voice and computer tasks, then loads the saved API key from Keychain.

## Use it

- Tap your configured conversation key (Right Shift by default) to start or end a conversation.
- Hold that key and drag around something on the current display. Release to finish the selection, then ask about it. Press Escape to cancel.
- Ask about your screen or circled content. Computah reads the display under your pointer, including a separate crop when you circle a region. **Clear** removes that selection.
- Ask for research or preparation, including multiple independent jobs. Each concurrent task gets its own worker and browser session. There is no fixed task cap, though account limits and Mac resources still apply. Workers do not move your Mac's pointer or type into other applications.
- Click the task browser thumbnail or ask to show the browser to open a larger view of the same session. Watching keeps the task running; closing the window also keeps it running.
- Choose **Take over** for manual interaction. This stops the worker and gives you control of the browser. You decide whether to submit.
- Each task has its own title, open, review, and stop controls. **End conversation** stops audio and screen analysis while tasks continue. **Stop task** stops the selected worker; **Quit Computah** stops voice and all workers.

Workers use live web search to discover official websites, then open the discovered pages in their browser. Visible link destinations are included in page observations.

Browser preparation disables website JavaScript and blocks form submissions, non-GET navigation, and recognized action controls. Scripted websites, sign-in, and modern application forms may require manual review before useful preparation is possible. Review enables website JavaScript for subsequent navigation; reload manually when a page needs it. Opening review does not submit or reload the page automatically.

## Microphone troubleshooting

The initial build's microphone startup error `-10875` and silent multichannel microphone conversion have been fixed. Quit Computah and reopen the rebuilt app before retrying, the saved API key loads automatically.

Computah tries echo cancellation first. If your audio devices cannot start it, the app uses ordinary audio and shows a notice recommending headphones so it does not hear its own speech. If both modes fail, check the input and output devices in macOS Sound settings, close other apps using the microphone, and retry.

## What runs where

| Job | Implementation |
| --- | --- |
| Spoken conversation | `gpt-live-1` with streamed audio and text |
| Question routing and screenshot interpretation | Responses API with `gpt-5.6-luna` |
| Independent browser task | Local `codex app-server`, requesting `gpt-5.6-sol` |
| Browser | Separate nonpersistent `WKWebView` session |
| UI and capture | SwiftUI, AppKit, AVFoundation, and ScreenCaptureKit |

The voice model receives text findings from vision rather than screenshot images. Browser tools can navigate, observe, click, type, scroll, and request review. The worker does not automate native desktop applications.

## Pitch screenshots

The pitch site at [computah2.anselmlong.com](https://computah2.anselmlong.com) was originally maintained in the `computah` repository under `static/computah2`. The site source is now tracked in `website/`, and version-tag releases publish the matching ZIP through the pipeline described in [RELEASES.md](RELEASES.md).

To reproduce the native interface captures used for the master’s application example:

```sh
zsh scripts/render-pitch-previews.sh
```

The harness compiles the production views with `scripts/PitchPreviews.swift`, renders four PNGs into `.build/pitch-previews/`, and uses the fictional local form in `scripts/fixtures/masters-application.html`. It exercises browser click/type operations, checks that three fields contain text, and verifies that the submit control requests manual review. It captures the browser before and after takeover.

Transcripts, task results, and application data are illustrative. The harness does not load credentials, start the microphone, invoke a model, or submit an application. These captures demonstrate native UI and local browser behavior, not authenticated end-to-end AI execution. The site labels the examples and keeps screenshot provenance in `assets/screenshots.json` and PNG metadata.

## Data and limits

Computah stores the API key in macOS Keychain, not UserDefaults or a plain settings file. Remove the saved key in settings when you no longer want startup access. Each Codex child process receives the key through its environment, along with an isolated temporary `HOME`, `CODEX_HOME`, and working directory instead of your existing Codex account, plugins, or project configuration. History persistence is disabled and the directory is removed when the worker exits normally. An abrupt process or system failure can leave temporary files behind.

Screenshots and captions remain in app memory rather than a Computah transcript archive. During conversation, new utterances trigger display capture, and routing sends the available display image and selected crop to OpenAI even when it ultimately chooses a direct answer. Screen interpretation also sends those images; circling does not mean only the crop leaves your Mac. Requests set `store: false`, which does not promise that OpenAI retains no request data under its service policies. Each task has a separate nonpersistent browser session. Its cookies remain within that session while it exists, without joining your usual browser profile.

The worker requests a read-only Codex sandbox, disables built-in execution tools, and accepts live web search and its supplied browser tools. These are prototype boundaries, not a claim of complete operating-system isolation. Submission checks also cannot prove that every website's GET link is harmless. Review prepared work and destinations before acting.

## Live website-discovery test

Run `zsh scripts/run-browser-research-smoke.sh` to send a real public NUS program research request through the text router and browser worker. An optional quoted argument replaces the request. This explicitly uses the saved Computah API key and incurs API usage. It prints the routed task, visited URLs, and result without printing the key. It does not test voice input or application submission. The worker has a four-minute timeout; credential loading and routing happen before that timer.

## CI and tagged releases

Source pushes and pull requests run build/tests on a hosted Mac. Push a version tag such as `v0.1.1` to build, update the website download, and reopen the app on the configured personal Mac after checks pass. Dry-run and preview modes are available. See [RELEASES.md](RELEASES.md) for setup, testing, and signing limitations.

## Verification

```sh
swift test
zsh scripts/build.sh
```

Hosted CI verification (2026-09-13, `88e2577`): the Swift suite executed 53 tests with zero failures and one skip (Codex CLI is absent on the hosted Mac), and all five release-script tests passed. The fake-worker fixtures no longer require a real Codex installation. [CI run](https://github.com/anselmlong/computah2/actions/runs/34757008698).

Earlier local source verification (2026-09-13, working tree after `00032e9`): debug and release compilation passed and `git diff --check` passed. Standalone protocol probes using production code verified that live search events complete normally and native execution events still stop the worker. `swift test` could not compile the test target because the local toolchain could not find `XCTest`; this is a blocked test run, not a passing suite. Tests cover protocol handling, audio conversion, permissions, credentials, hotkeys, executable discovery, worker restrictions, and concurrent browser tasks. Run them with an Xcode toolchain that provides XCTest.

Authenticated text routing and browser research were exercised with the saved app credential and Codex 0.154.0: the NUS Master of Computing General Track request reached the official program and admissions pages and produced a sourced summary without submitting anything. Early runs still navigated search-engine pages; enabling the custom provider’s standalone search capability exposed actual web-search events and navigation directly to the official admissions URL. Full voice/vision execution and a real application portal remain unverified.

Signed app packaging was blocked because this session had no valid Apple Development or Developer ID signing identity. The version-tag pipeline now supports explicit ad hoc development signing for the existing prototype; Developer ID signing still requires an Apple identity.

Earlier development notes report that, with the user's authorization, local hardware tests verified nonzero microphone input after multichannel conversion, echo cancellation, and output completion through the mixer and audio device. The tests did not save audio or send it to an API. These checks do not verify a complete model conversation.

Settings show the local bundle build number and UTC build date. The build script increments the version from the existing `dist/Computah.app`; without that bundle it starts at 1. This number is local to the build directory, not a shared release counter. The checked-in app version is `0.1.0`.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the code map, request flow, and documentation maintenance workflow, [PRODUCT.md](PRODUCT.md) for product scope and [DESIGN.md](DESIGN.md) for the current interface. Protocol references: [OpenAI API documentation](https://platform.openai.com/docs) and [Codex app-server documentation](https://developers.openai.com/codex/app-server).
