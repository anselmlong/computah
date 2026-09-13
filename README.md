# Computah

Computah is a personal macOS prototype for talking about your screen and delegating browser tasks while you keep using your Mac. Its animated lime character lives in a black notch panel, called the Dynamic Island in this project. Conversation, settings, and task previews expand from that panel. The app uses Codex's native Computer Use capability to work in your existing Mac applications. There is no Dock icon or separate menu bar item.

## Build and open

You need macOS 14 or later, an Xcode Swift toolchain, and internet access. Computer tasks also need the Codex CLI at `/opt/homebrew/bin/codex` or `/usr/local/bin/codex`, signed in to an account with the required native apps and plugins.

```sh
zsh scripts/build.sh
open dist/Computah.app
```

The script builds a release executable, stages and verifies the app, then replaces `dist/Computah.app`. By default it requires an existing Developer ID Application identity and signs with hardened runtime, a secure timestamp, and the microphone input entitlement. There is no automatic fallback to an Apple Development identity. Set `COMPUTAH_SIGNING_IDENTITY` to explicitly choose another existing identity for local use. Only an explicit value of `-` selects ad hoc signing, with a warning about permission stability.

For notarization, set `COMPUTAH_NOTARY_PROFILE` to an existing `notarytool` Keychain profile. The script submits the archive, waits for acceptance, staples and validates the ticket, and checks Gatekeeper before publishing the staged app. It does not write notarization credentials to files. Without this profile, the build is signed but not notarized, and Gatekeeper acceptance is not established. The validated local Keychain profile is `computah-notary`; use it for future releases:

```sh
COMPUTAH_NOTARY_PROFILE=computah-notary zsh scripts/build.sh
```

Quit a running Computah before opening a rebuilt version. Signing identity changes can require macOS permission approval again. Use the normal permission prompt for the current signed app rather than repeatedly toggling or resetting permissions.

Hover over the lime face or click it to open the notch panel. Click the face again or click outside the panel to close it, then open settings with the gear when needed. Paste your OpenAI API key. Starting a conversation automatically saves it to macOS Keychain; you can also save it directly in settings. Computah loads the saved key at startup. Settings provide save, replace, and remove controls. The key needs access to `gpt-live-1` and `gpt-5.6-luna`. Voice and screen-reading requests use your OpenAI API account and incur its applicable charges. Computer tasks use your signed-in Codex account instead.

Use each permission row's **Allow** or **Settings** control to grant Microphone, Screen Recording, and Input Monitoring access. Permission status refreshes automatically without triggering consent prompts. An explicit **Allow** action requests access once. Input Monitoring enables the conversation key, which defaults to Right Shift. The **Conversation key** picker also offers right Command, Option, and Control; this choice persists between launches. The **Start talking** button works without the shortcut.

If macOS requires a relaunch after permission changes, choose **Reopen Computah**. Reopening ends voice and computer tasks, then loads the saved API key from Keychain.

## Use it

- Tap right Shift to start or end a conversation.
- Hold right Shift and drag around something on the current display. Release to finish the selection, then ask about it. Press Escape to cancel.
- Ask about your screen or circled content. Computah reads the display under your pointer, including a separate crop when you circle a region. **Clear** removes that selection.
- Ask for research or preparation, including multiple independent jobs. Concurrent reasoning tasks share your Mac's app interface; they are not isolated browser or desktop sessions. Computer actions can affect the app you are using.
- Review prepared work before submission. Stop task stops the selected worker; Quit Computah stops voice and all workers.
- End conversation stops audio and screen analysis while existing tasks continue.

## Computer Use dependency

App control runs through a regular per-task `codex app-server` process. It uses the signed-in user's Codex account, configuration, plugins, and native Computer Use capability with existing Mac applications. There is no custom Chrome extension, manual Load unpacked setup, or private-browser fallback.

Computah checks that the Codex CLI is installed, then starts the worker when you delegate a task. It does not call the protected Computer Use helper directly or require a separate helper-authentication gate. The worker requests `gpt-6-astra` with high reasoning effort. It does not use a custom model provider or receive the OpenAI API key saved for voice and screen reading.

Earlier builds called the protected helper directly and received `Computer Use server error -10000: Sender process is not authenticated`. The regular Codex worker replaces that unsupported route.

Native app access can trigger a Codex MCP elicitation request, which is an in-task approval prompt. The task card shows **Allow once** and **Don't allow**. Either response is sent back over the same app-server connection so the turn can continue. Requests for missing information or review before a consequential action still stop the worker for manual review.

## Microphone troubleshooting

The initial build's microphone startup error `-10875` and silent multichannel microphone conversion have been fixed. Quit Computah and reopen the rebuilt app before retrying. The saved API key loads automatically.

Computah tries echo cancellation first. If your audio devices cannot start it, the app uses ordinary audio and shows a notice recommending headphones so it does not hear its own speech. If both modes fail, check the input and output devices in macOS Sound settings, close other apps using the microphone, and retry.

## What runs where

| Job | Implementation |
| --- | --- |
| Spoken conversation | `gpt-live-1` with streamed audio and text |
| Question routing and screenshot interpretation | Responses API with `gpt-5.6-luna` |
| Computer task reasoning | Per-task `codex app-server`, requesting `gpt-6-astra` with high reasoning effort |
| App control | Native Codex Computer Use, sharing the existing Mac app interface |
| UI and capture | SwiftUI, AppKit, AVFoundation, and ScreenCaptureKit |

The voice model receives text findings from vision rather than screenshot images. The worker delegates app observation and interaction to the Computer Use dependency. It does not provide an isolated desktop for each concurrent task.

## Data and limits

Computah stores the voice and screen-reading API key in macOS Keychain, not UserDefaults or a plain settings file. Remove the saved key in settings when you no longer want startup access. Codex workers do not receive this key. Each worker inherits the user's normal `HOME`, `CODEX_HOME`, account, configuration, and plugins, while Computah removes parent-task identity variables. The worker uses the user's home directory as its working directory and starts an ephemeral Codex thread, so Computah does not delete or replace the user's files when the worker exits.

Screenshots and captions remain in app memory rather than a Computah transcript archive. Screen analysis sends the whole selected display and any circled crop to OpenAI; circling does not mean only the crop leaves your Mac. Requests set `store: false`, which does not promise that OpenAI retains no request data under its service policies. App interactions use existing application state and signed-in accounts. They are not private browsing sessions.

Computer Use operates the shared app interface. Fresh observation and action are serialized across tasks, but you and workers still share existing applications. Review stops the selected task and waits for already-dispatched action handling before manual interaction. Review is a worker instruction and task lock, not browser network blocking or a guarantee that every consequential control is prevented. Review prepared work and destinations before acting.

Each computer task is a separate Codex process, but it uses the user's installed Codex capabilities and the same Mac application interface as other tasks. The voice and screenshot APIs remain separate and continue to use the key saved in Keychain.

## Verification

```sh
swift test
zsh scripts/build.sh
```

All 66 Swift tests pass. A focused set of 15 worker tests also passes, including a handshake with the installed Codex CLI, approval continuation and concurrent task handling against a fake app server, and preservation of the worker's current directory. A live Astra probe started through the user's normal Codex account, loaded Computer Use, and emitted a native MCP elicitation request. Declining that request produced the expected not-approved result. A separate acceptance probe stalled before the tool request, so these diagnostics do not establish successful Calculator observation or a complete Computer Use task.

With the user's authorization, local hardware tests verified nonzero microphone input after multichannel conversion, echo cancellation, and output completion through the mixer and audio device. The tests did not save audio or send it to an API. These checks do not verify a complete model conversation.

Build 18 is signed, notarized, stapled, accepted by Gatekeeper, installed at `/Applications/Computah.app`, and running. The distribution archive is `dist/Computah-build-18.zip`. Installed-app checks on the same final geometry confirmed the 273 by 32 point idle notch, the lime face as its only visible control, face-click opening and closing, normal Codex installed status, and all four permissions allowed. The face toggle passed twice on build 17 and did not change in build 18. Hover opening and physical outside-click collapse are implemented but remain unverified in the installed app. The final in-app **Allow once** continuation and a successful read from Calculator are also not yet claimed. The physical Right Shift tap-and-circle flow remains untested by automation. Settings show the build number and UTC build date; each build increments the bundle version.

See [PRODUCT.md](PRODUCT.md) for product scope and [DESIGN.md](DESIGN.md) for the current interface. Protocol references: [OpenAI API documentation](https://platform.openai.com/docs) and [Codex app-server documentation](https://developers.openai.com/codex/app-server).
