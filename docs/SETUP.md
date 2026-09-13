# Setup and usage

You need macOS 14 or later, an Xcode Swift toolchain, and internet access. Computer tasks also need a signed-in Codex CLI with native Computer Use and any required apps or plugins. Computah checks `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, and locations in its inherited `PATH`.

```sh
zsh scripts/build.sh
open dist/Computah.app
```

The build script creates a release executable, stages and verifies the app, then replaces `dist/Computah.app`. By default it requires an existing Developer ID Application identity and signs with hardened runtime, a secure timestamp, and the microphone input entitlement. Set `COMPUTAH_SIGNING_IDENTITY` to choose another existing identity. Only an explicit value of `-` selects ad hoc signing.

To notarize a Developer ID build, set `COMPUTAH_NOTARY_PROFILE` to an existing `notarytool` Keychain profile:

```sh
COMPUTAH_NOTARY_PROFILE=computah-notary zsh scripts/build.sh
```

The script submits the archive, waits for acceptance, staples and validates the ticket, and checks Gatekeeper before publishing the staged app. Quit a running Computah before opening a rebuilt version. Signing identity changes can require macOS permission approval again.

Hover over the lime face for 240 milliseconds or click it to open the notch panel. Click the face again or click outside the panel to close it. Open settings with the gear, then paste your OpenAI API key. Starting a conversation automatically saves it to macOS Keychain; settings also provide save, replace, and remove controls. The key needs access to `gpt-live-1` and `gpt-5.6-luna`. It is used for voice and screen reading only.

Computer tasks use the account already signed in through the Codex CLI. Computah does not pass the OpenAI API key from Keychain to workers.

Use each permission row's **Allow** or **Settings** control to grant Microphone, Screen Recording, and Input Monitoring access. Permission status refreshes without triggering consent prompts. Input Monitoring enables the conversation key, which defaults to Right Shift. The picker also offers right Command, Option, and Control. The **Start talking** button works without the shortcut.

If macOS requires a relaunch after permission changes, choose **Reopen Computah**. Reopening ends voice and computer tasks, then loads the saved API key from Keychain.

## Hands-free activation

In Computah settings, leave **Listen for “Hey, computah”** enabled and choose **Allow wake listening** to grant Microphone and Speech Recognition access. Say “Hey, computah” while Computah is running to open the notch and start a conversation using your saved API key. Computah gives a brief spoken acknowledgment as soon as the voice connection is ready, then listens for your request. On-device English speech recognition must be available on the Mac; settings reports availability. The switch is saved across launches, and disabling it releases the microphone while idle.

Click outside the expanded notch to collapse it. This leaves voice and independent tasks running; use **End conversation** to stop voice.

## Use it

- Tap your configured conversation key to start or end a conversation.
- Hold that key and drag around something on the current display. Release to finish the selection, then ask about it. Press Escape to cancel.
- Ask about your screen or circled content. Computah reads the display under your pointer, including a separate crop when you circle a region. **Clear** removes that selection.
- Ask for research or preparation, including multiple jobs. Each task gets its own Codex process, but Computer Use shares your existing Mac applications and signed-in state.
- If a native app needs approval, choose **Allow once** or **Don't allow** in the task card. The answer returns to the same task so it can continue.
- When a worker needs non-secret information or confirmation, Computah names the task and asks the question through the active voice conversation. Give one clear answer. Unrelated speech remains part of the conversation; an ambiguous reply causes the question to repeat. You can also answer any worker question through the text form in its task card. Secret answers use the private field and never enter voice transport.
- Review task results and activity before consequential actions. The worker instructions require your explicit confirmation before sending, submitting, paying, publishing, accepting terms, or finalizing.
- **End conversation** stops audio and screen analysis while tasks continue. **Stop task** stops one worker; **Quit Computah** stops voice and all workers.

Workers run in YOLO mode with approval policy `never` and sandbox mode `danger-full-access`. Native app and plugin approvals are separate gates and may still appear. The task instructions require explicit user confirmation before sending, submitting, paying, publishing, accepting terms, or finalizing an application, but the runtime does not enforce that rule. Secret questions are not spoken or routed through the voice model.

## Microphone troubleshooting

Quit Computah and reopen the rebuilt app before retrying; the saved API key loads automatically.

Computah tries echo cancellation first. If your audio devices cannot start it, the app uses ordinary audio and shows a notice recommending headphones. If both modes fail, check the input and output devices in macOS Sound settings, close other apps using the microphone, and retry.

## Building without an Apple signing certificate

For local development, explicitly choose ad hoc signing:

```sh
COMPUTAH_SIGNING_IDENTITY=- zsh scripts/build.sh
open dist/Computah.app
```

This does not notarize the app, and macOS permission approvals can change after rebuilding. Keep the same tested app bundle for repeat demos.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| No Dock icon | Computah lives at the top of the display. Hover over or click the lime face. |
| Shortcut does nothing | Grant Input Monitoring, or use Start talking. Confirm the configured right-side modifier. |
| Screen unavailable | Grant Screen Recording in settings; reopen if macOS requests it. Voice can still work. |
| Codex unavailable | Install the Codex CLI at a detected location, sign in, then choose Check again. |
| Worker cannot use an app | Approve the native app or plugin request in the task card. Confirm that the capability works in the normal Codex app. |
| Worker is waiting for a voice answer | Keep the voice conversation active and answer the named task's question clearly. Ambiguous replies cause the question to repeat. |
| `no such module XCTest` | Select a full Xcode toolchain. Command-line tools alone may build the app but cannot run this suite. |

[Project overview](../README.md) · [Demo walkthrough](DEMO.md) · [Live site](https://computah.anselmlong.com)
