# Computah

<img src="website/assets/icon.svg" width="95" height="80" alt="Computah's lime companion face">

**Talk about your screen. Hand off computer work. Keep using your Mac.**

Computah is a native macOS voice companion that lives in your notch. Ask about what you see, circle something to give it context, and delegate research or preparation to local Codex workers. Computer Use works through your existing Mac applications, so delegated tasks and your own work share the same interface.

[Live demo site](https://computah.anselmlong.com) · [Watch the demo](https://youtu.be/WGbVYat8Lmg) · [Setup guide](docs/SETUP.md) · [Architecture](ARCHITECTURE.md)

![Computah's native interface with an illustrative conversation](website/assets/masters-conversation.png)

*Real SwiftUI interface; the screenshot uses illustrative conversation data. Watch the linked video for the demo recording.*

## Why we built it

Complex personal projects spill across apps, notes, and half-finished forms. A master's application, for example, means researching programs, understanding requirements, and preparing details before making a decision. Computah brings the conversation and the computer work together in a small, persistent place on your Mac.

The interaction is simple: **talk, point, delegate, review.**

- **Talk naturally.** Tap Right Shift to start or end a voice conversation.
- **Point at context.** Hold the conversation key and circle a region, then ask about it.
- **Delegate independent jobs.** Each task gets its own local Codex worker. Ending voice leaves those tasks running.
- **Keep the final say.** Workers must ask for explicit confirmation before consequential actions such as sending, submitting, paying, or publishing. Computah speaks the question and returns your answer to the same waiting task.

## Try it

Download the Mac prototype from the [demo site](https://computah.anselmlong.com), or build from source:

```sh
zsh scripts/build.sh
open dist/Computah.app
```

You need macOS 14 or later, a Swift toolchain, and an existing signing identity for the default build. For local development without a certificate, use `COMPUTAH_SIGNING_IDENTITY=- zsh scripts/build.sh`. The website download targets Apple silicon.

The default build requires a Developer ID Application identity. To create a notarized build, set `COMPUTAH_NOTARY_PROFILE` to an existing `notarytool` Keychain profile:

```sh
COMPUTAH_NOTARY_PROFILE=computah-notary zsh scripts/build.sh
```

**Bring your own OpenAI API key for voice and screen reading.** Open the notch panel's settings, paste your key, and grant Microphone, Screen Recording, and Input Monitoring access as needed. The key needs access to `gpt-live-1` and `gpt-5.6-luna`. Computer tasks use your signed-in Codex account instead and require a compatible Codex CLI. See the [full setup and troubleshooting guide](docs/SETUP.md).

Hover over the lime face or click it to open the panel. Click the face again or click outside the panel to close it. Idle mode is only 273 by 32 points on the built-in display, including the 185-point camera gap. A live conversation or running task widens the compact panel to 377 points.

## How it works

| Layer | What we built |
| --- | --- |
| Native companion | SwiftUI views in an AppKit notch panel; no Dock icon or separate menu bar item |
| Voice | AVFoundation audio capture/playback and a WebSocket connection to `gpt-live-1` |
| Screen understanding | ScreenCaptureKit captures the current display and optional crop; `gpt-5.6-luna` routes requests and interprets images |
| Computer workers | One regular `codex app-server` process requesting `gpt-5.6-sol` with high reasoning effort per task |
| App control | Native Codex Computer Use in the user's existing Mac applications |
| Delivery | Swift Package Manager, hosted Mac CI, and a tagged app/site release pipeline |

Each computer worker inherits the user's normal `HOME`, `CODEX_HOME`, signed-in account, configuration, and plugins. Computah removes parent-task identity variables and does not pass the voice API key to the worker. Workers start ephemeral Codex threads in YOLO mode with runtime approval policy `never` and sandbox mode `danger-full-access`. The task instructions require explicit user confirmation before consequential actions, but the runtime does not enforce that instruction.

Native app access can trigger a Codex MCP elicitation request. The task card shows **Allow once** and **Don't allow**, then returns the choice over the same app-server connection so the turn can continue. App and plugin approvals remain separate gates even in YOLO mode.

When a worker asks for non-secret information or confirmation, Computah identifies the task and reads the question and choices through the active `gpt-live-1` conversation. The user's next complete, relevant answer is routed back to that exact waiting task. Unrelated speech is left in the conversation, and an ambiguous answer causes the question to be repeated. Every question also has a text form in its task card. Secret answers stay in that form and never enter voice transport. Computah never has the voice model invent or select an answer.

Earlier builds called the protected Computer Use helper directly and received `Computer Use server error -10000: Sender process is not authenticated`. The regular Codex worker replaces that unsupported route.

The models run remotely. The Mac hosts the interface, capture, audio, and worker processes. Vision returns text findings to the voice session. The [architecture guide](ARCHITECTURE.md) includes the request flow, code map, and implementation tradeoffs.

## Demo scope and data

Computah is a hackathon prototype. Computer Use shares your existing applications, signed-in state, and desktop rather than creating an isolated browser or desktop for each task. Fresh observation and action are serialized across tasks, but you and the workers can still affect the same applications.

The voice and screen-reading API key is stored in macOS Keychain. Audio and available screen images can be sent to OpenAI; circling a region does **not** limit sharing to that crop. Requests set `store: false`, which does not promise that OpenAI retains no request data under its service policies. Read [data and limits](docs/PRIVACY.md) before using sensitive content.

## Documentation

| Guide | Purpose |
| --- | --- |
| [Demo walkthrough](docs/DEMO.md) | Short pitch, presenter script, rehearsal, and fallback |
| [Setup and usage](docs/SETUP.md) | Build, credentials, permissions, controls, troubleshooting |
| [Architecture](ARCHITECTURE.md) | How we built it, data flow, modules, and tradeoffs |
| [Product](PRODUCT.md) / [Interface](DESIGN.md) | Implemented scope and native design |
| [Usage costs](docs/COSTS.md) | Published API rates and illustrative budgets |
| [Validation record](docs/VALIDATION.md) | Dated evidence, test commands, and remaining coverage |
| [Releases](RELEASES.md) | Packaging, signing, deployment, and rollback |
| [Website](website/README.md) | Static site development and public documentation |

Pushes to `main` deploy the website after CI passes, preserving the current app download. Version tags publish new app builds through the separate release job.

## Verification

Run `swift build`, `swift test`, and `python3 -m unittest discover -s scripts/tests -v` before releasing. Keep validation results tied to the revision tested; the demo checklist records what still needs a live rehearsal.

The Swift suite verifies an installed Codex handshake, approval continuation, concurrent task isolation, current-directory preservation, same-turn worker questions, grounded voice-answer routing, task-card fallback, and secret-field handling. An earlier live Astra probe loaded Computer Use and emitted a native app-approval request. Declining it produced the expected not-approved result. GPT-5.6 Sol still needs the same live check. A separate acceptance probe stalled before the tool request, so successful Calculator observation and a complete Computer Use task remain unverified. A live spoken worker-question exchange is also unverified.

With the user's authorization, local hardware checks verified nonzero microphone input after multichannel conversion, echo cancellation, and output completion. They did not save audio or send it to an API.

Build 22 is signed, notarized, stapled, accepted by Gatekeeper, installed at `/Applications/Computah.app`, and running. Its archive is `dist/Computah-build-22.zip`. All 80 Swift tests pass. Earlier installed-app checks confirmed the 273 by 32 point idle notch, the face as its only idle control, face-click opening and closing, normal Codex installed status, and all four permissions allowed. Hover opening, physical outside-click collapse, the in-app **Allow once** continuation, a live spoken worker-question exchange, successful Calculator observation, and the physical Right Shift tap-and-circle flow remain unverified in the installed app.

Protocol references: [OpenAI API documentation](https://platform.openai.com/docs) and [Codex app-server documentation](https://developers.openai.com/codex/app-server).
