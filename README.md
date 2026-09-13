# Computah

Computah is a personal macOS prototype for talking about your screen and delegating browser tasks while you keep using your Mac. Its animated lime character lives in a black notch panel, called the Dynamic Island in this project. Conversation, settings, and task previews expand from that panel. The task browser can also open in a larger window for watching or manual review. There is no Dock icon or separate menu bar item.

## Build and open

You need macOS 14 or later, an Xcode Swift toolchain, and internet access. Browser tasks also need the Codex CLI at `/opt/homebrew/bin/codex` or `/usr/local/bin/codex`, with support for the app-server protocol and dynamic tools.

```sh
zsh scripts/build.sh
open dist/Computah.app
```

The script builds a release executable, stages and verifies the app, then replaces `dist/Computah.app`. It signs with an existing Apple Development certificate, falling back to Developer ID Application. The same bundle identifier and certificate keep the app's signing identity stable across rebuilds. This is a local prototype build, not a notarized distribution. Quit a running Computah before opening a rebuilt version.

Set `COMPUTAH_SIGNING_IDENTITY` to choose an existing signing identity. Only an explicit value of `-` selects ad hoc signing, with a warning about permission stability. The script fails clearly if it cannot find a signing identity. The earlier ad hoc Screen Recording grant was cleared for this app only after its stored signature no longer matched the certificate-signed build. Approve the current signed Computah once through the normal macOS permission prompt. Do not repeatedly toggle or reset permissions.

Expand the notch panel with its chevron, then open settings with the gear. Paste your OpenAI API key. Starting a conversation automatically saves it to macOS Keychain; you can also save it directly in settings. Computah loads the saved key at startup. Settings provide save, replace, and remove controls. The key needs access to `gpt-live-1`, `gpt-5.6-luna`, and `gpt-5.6-sol`. Requests use your OpenAI API account and incur its applicable charges.

Use each permission row's **Allow** or **Settings** control to grant Microphone, Screen Recording, and Input Monitoring access. Permission status refreshes automatically without triggering consent prompts. An explicit **Allow** action requests access once. Input Monitoring enables the conversation key, which defaults to Right Shift. The **Conversation key** picker also offers right Command, Option, and Control; this choice persists between launches. The **Start talking** button works without the shortcut.

If macOS requires a relaunch after permission changes, choose **Reopen Computah**. Reopening ends voice and computer tasks, then loads the saved API key from Keychain.

## Use it

- Tap right Shift to start or end a conversation.
- Hold right Shift and drag around something on the current display. Release to finish the selection, then ask about it. Press Escape to cancel.
- Ask about your screen or circled content. Computah reads the display under your pointer, including a separate crop when you circle a region. **Clear** removes that selection.
- Ask for research or preparation, including multiple independent jobs. Each concurrent task gets its own worker and browser session. There is no fixed task cap, though account limits and Mac resources still apply. Workers do not move your Mac's pointer or type into other applications.
- Click the task browser thumbnail or ask to show the browser to open a larger view of the same session. Watching keeps the task running; closing the window also keeps it running.
- Choose **Take over** for manual interaction. This stops the worker and gives you control of the browser. You decide whether to submit.
- Each task has its own title, open, review, and stop controls. **End conversation** stops audio and screen analysis while tasks continue. **Stop task** stops the selected worker; **Quit Computah** stops voice and all workers.

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

## Data and limits

Computah stores the API key in macOS Keychain, not UserDefaults or a plain settings file. Remove the saved key in settings when you no longer want startup access. Each Codex child process receives the key through its environment, along with an isolated temporary `HOME`, `CODEX_HOME`, and working directory instead of your existing Codex account, plugins, or project configuration. History persistence is disabled and the directory is removed when the worker exits normally. An abrupt process or system failure can leave temporary files behind.

Screenshots and captions remain in app memory rather than a Computah transcript archive. Screen analysis sends the whole selected display and any circled crop to OpenAI; circling does not mean only the crop leaves your Mac. Requests set `store: false`, which does not promise that OpenAI retains no request data under its service policies. Each task has a separate nonpersistent browser session. Its cookies remain within that session while it exists, without joining your usual browser profile.

The worker requests a read-only Codex sandbox, disables built-in execution tools, and accepts only its supplied browser tools. These are prototype boundaries, not a claim of complete operating-system isolation. Submission checks also cannot prove that every website's GET link is harmless. Review prepared work and destinations before acting.

## Verification

```sh
swift test
zsh scripts/build.sh
```

All 49 local tests passed, covering protocol handling, worker restrictions, browser behavior, and hotkeys. The app has been built and opened locally. An authenticated end-to-end voice, vision, and browser task has not been verified in the build environment because OpenAI API credentials were unavailable. Model access and installed Codex CLI compatibility must be checked on the user's account.

With the user's authorization, local hardware tests verified nonzero microphone input after multichannel conversion, echo cancellation, and output completion through the mixer and audio device. The tests did not save audio or send it to an API. These checks do not verify a complete model conversation.

The upcoming release is build 5. Settings show the build number and UTC build date; each build increments the bundle version.

See [PRODUCT.md](PRODUCT.md) for product scope and [DESIGN.md](DESIGN.md) for the current interface. Protocol references: [OpenAI API documentation](https://platform.openai.com/docs) and [Codex app-server documentation](https://developers.openai.com/codex/app-server).
