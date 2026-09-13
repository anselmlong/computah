# Setup and usage

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

## Hands-free activation

In Computah settings, leave **Listen for “Hey, computah”** enabled and choose **Allow wake listening** to grant Microphone and Speech Recognition access. Say “Hey, computah” while Computah is running to open the notch and start a conversation using your saved API key. Computah gives a brief spoken acknowledgment as soon as the voice connection is ready, then listens for your request. On-device English speech recognition must be available on the Mac; settings reports availability. The switch is saved across launches, and disabling it releases the microphone while idle.

Click outside the expanded notch to collapse it. This leaves voice and independent tasks running; use **End conversation** to stop voice.

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

Quit Computah and reopen the rebuilt app before retrying; the saved API key loads automatically.

Computah tries echo cancellation first. If your audio devices cannot start it, the app uses ordinary audio and shows a notice recommending headphones so it does not hear its own speech. If both modes fail, check the input and output devices in macOS Sound settings, close other apps using the microphone, and retry.


## Building without an Apple signing certificate

For a local hackathon build, explicitly choose ad hoc signing:

```sh
COMPUTAH_SIGNING_IDENTITY=- zsh scripts/build.sh
open dist/Computah.app
```

This does not notarize the app, and macOS permission approvals can change after rebuilding. For repeat demos, keep the same tested app bundle.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| No Dock icon | Computah lives at the top of the display. Click the lime character or chevron. |
| Shortcut does nothing | Grant Input Monitoring, or use Start talking. Confirm the configured right-side modifier. |
| Screen unavailable | Grant Screen Recording in settings; reopen if macOS requests it. Voice can still work. |
| Worker unavailable | Check Codex discovery, the API key, model access, and network. |
| Scripted portal will not load | Take over, then reload manually. Reloading can clear prepared fields. |
| `no such module XCTest` | Select an installed full Xcode toolchain. Command-line tools alone may build the app but cannot run this suite. |

[Project overview](../README.md) · [Demo walkthrough](DEMO.md) · [Live site](https://computah.anselmlong.com)
