# Computah architecture and maintenance

Computah is a native macOS 14+ executable built with Swift Package Manager, SwiftUI, and AppKit. There are no declared third-party package dependencies. The app coordinates remote model requests and local browser worker processes; the models do not run on the Mac.

[Demo site](https://computah2.anselmlong.com) · [Demo video](https://youtu.be/WGbVYat8Lmg) · [Project overview](README.md)

## How we built it

We split the experience into three lifecycles: a native companion, a voice conversation, and independent browser tasks. `AppModel` coordinates them on the main actor. SwiftUI observes state while AppKit owns window placement and manual browser presentation.

1. **Start with the Mac interaction.** An accessory app hosts a borderless notch panel. A right-modifier event tap supports talking and lasso selection without taking over the user's pointer.
2. **Connect voice and screen context.** AVFoundation converts microphone input to 24 kHz PCM and plays streamed responses. ScreenCaptureKit captures the display under the pointer. Routing runs after a one-second transcript pause, choosing conversation, vision, browser work, or showing a browser.
3. **Give each delegated job its own workspace.** The task manager creates a WebKit session and a Codex app-server process. JSON-RPC connects six browser tools to the worker; calls within one browser are serialized so navigation and clicks stay ordered.
4. **Bring results back to the conversation.** Generation identifiers reject stale callbacks after cancellation. Task batches return bounded text summaries to the originating voice session. Taking over stops the worker and unlocks manual browsing.
5. **Package a reproducible demo.** Swift Package Manager builds the app. Local fixtures exercise browser preparation; a capture harness renders the actual native views with illustrative data. Tagged releases package an app and matching static website download with a checksum manifest.

## Why these choices

| Decision | Benefit | Tradeoff |
| --- | --- | --- |
| SwiftUI + AppKit | Native audio, permissions, windows, and notch interaction | macOS only |
| Separate voice, routing, and task models | Conversation can continue during longer browser work | Multiple remote requests, model-access requirements, and network latency |
| One worker and browser per task | Independent jobs and user-controlled review | Memory/process cost grows with tasks; no admission queue or fixed cap |
| Page JavaScript disabled during preparation | Restricts scripted side effects while using fixed DOM tools | Modern portals often require takeover |
| Nonpersistent browser and temporary worker directories | Avoids reusing the user's browser or Codex profile | Sign-in and tasks are not restored after relaunch |
| Static website with no frontend build | Simple deployment and accessible HTML fallback | Public documentation must be maintained alongside repository guides |

## Request flow

```mermaid
flowchart TD
    User[Voice and conversation key] --> App[AppModel]
    App <--> Audio[AudioEngine and LiveConnection]
    Audio <--> Voice[Configured voice model: gpt-live-1]
    App --> Capture[ScreenContext: display and optional crop]
    App --> Route[RouteService: gpt-5.6-luna]
    Capture --> Route
    Route --> Direct[Direct conversation]
    Route --> Vision[VisionService: gpt-5.6-luna]
    Route --> Tasks[ComputerTaskManager]
    Route --> Show[Show existing browser]
    Vision --> Findings[Text findings returned to voice]
    Tasks --> Worker[One Codex app-server per task: gpt-5.6-sol]
    Worker <--> Browser[One private WKWebView per task]
    Worker --> Findings
    Browser --> Review[Manual takeover stops worker]
```

The model names above are configured identifiers in this repository, not a claim that every API account has access to them.

When a new utterance arrives, the app attempts to capture the display under the pointer. Routing waits for a brief transcript pause, then classifies the request using conversation context and available screenshots. It chooses direct conversation, screen interpretation, independent browser work, or showing an existing browser. Screen interpretation produces text for the voice session. Independent jobs receive separate browser sessions and worker processes; dependent steps stay in one task.

Ending voice cancels screen analysis and clears the selection while browser tasks continue. Each task retains its own status and result. Watching or closing a browser window leaves work running. Taking over stops that worker and enables manual interaction. Quitting or reopening the app stops all workers; sessions are not restored after relaunch.

## Code map

Paths below are relative to `Sources/Computah/`.

| File | Responsibility |
| --- | --- |
| `main.swift`, `Panel.swift` | App startup, notch window, conversation, settings, and task controls |
| `AppModel.swift` | Conversation state, routing, screen analysis, task batches, and result delivery |
| `AudioEngine.swift` | Microphone conversion, echo cancellation with fallback, and audio playback |
| `LiveConnection.swift`, `Protocol.swift` | Voice WebSocket lifecycle, bounded send queue, protocol messages, and transcript ledger |
| `Routing.swift` | Structured request classification and Responses transport |
| `ScreenContext.swift` | ScreenCaptureKit screenshots, optional crop, and vision findings |
| `ComputerTask.swift` | Independent task lifecycle, cancellation, results, and manual takeover |
| `CodexWorker.swift` | CLI discovery, isolated process environment, JSON-RPC, and browser tool dispatch |
| `BrowserWorkspace.swift`, `BrowserWindow.swift` | Private WebKit session, browser tools, navigation restrictions, and watch/review window |
| `Hotkey.swift`, `Permissions.swift` | Configurable right-modifier gesture, selection overlay, and permission state |
| `KeychainCredentialStore.swift` | API key persistence through macOS Keychain |

## Data and execution boundaries

The voice connection sends microphone audio to OpenAI. Routing and vision can send the full captured display plus a selected crop; selecting a region does not limit transmission to that crop. Computah excludes its own windows from display capture. A crop remains selected until cleared or voice ends, while later utterances can refresh the full-display image.

Each browser task uses a nonpersistent WebKit data store and a Codex process with temporary home, configuration, and working directories. The app supplies its API key to that process and enables live web search for public website discovery while disabling built-in execution, apps, and other host capabilities. The process requests a read-only sandbox. These are application-level restrictions and requested sandbox settings, not proof of complete system isolation.

The custom OpenAI provider explicitly enables `supports_standalone_web_search`; Codex models using Responses Lite need that capability as well as `web_search="live"`. Search events are permitted; native execution events still stop the worker.

The worker searches for exact organizations and programs, verifies official sources, and opens discovered URLs in the browser. Page observations include visible link destinations to avoid guessed deep links. Private application details must not enter public search queries.

The six supplied tools navigate, observe, click, type, scroll, and request review. Preparation disables website JavaScript and blocks form submissions, non-GET navigation, and recognized action controls. This limits compatibility with scripted sites and cannot guarantee every GET destination is harmless. Manual review enables website JavaScript for subsequent navigation; it does not automatically reload or submit.

## Build and validation

Use `swift build` for compilation and `swift test` for the test suite. Tests include local WebKit fixtures and a Codex handshake with a dummy credential; they do not establish authenticated model behavior. The installed-CLI handshake test skips when no executable is found. Current observed results belong in [docs/VALIDATION.md](docs/VALIDATION.md), including failures or skipped coverage.

`zsh scripts/build.sh` builds release output, creates a staged app from `Resources/Info.plist`, stamps its local build number and UTC date, signs and verifies it, then replaces `dist/Computah.app`. It chooses an existing signing identity or uses `COMPUTAH_SIGNING_IDENTITY`. It preserves the previous bundle if staging or signing fails. It does not run tests or notarize the app. `dist/` and `.build/` are ignored by Git.

The optional `zsh scripts/audio-smoke-test.sh` uses the microphone and audio output. Run it only when hardware testing is intended. It is separate from compilation and automated unit tests.

The `Check and release` workflow runs CI on a hosted Mac. Version tags then use the private repository’s personal Mac runner to package, deploy, verify the public download, and install/open the same bundle. Website source lives in `website/`. See [RELEASES.md](RELEASES.md) for the deployment boundary and rollback limitations.

## Remaining production work

The current implementation is a hackathon prototype. Before a broad release, complete an authenticated voice-and-vision rehearsal on the supported Mac/device matrix, provision Developer ID signing and notarization, and test downloaded builds through normal macOS installation. Long-running use also needs task dismissal/resource limits and a worker deadline. The current transport limits queues and individual requests, but does not impose a total runtime limit on a browser task.

Browser navigation checks are not a network firewall: WebKit subresources and DNS changes need a stronger boundary before claiming hostile-site isolation. See [data and limits](docs/PRIVACY.md) and the [validation record](docs/VALIDATION.md).

## Keeping documentation current

Update documentation in the same change as the behavior it describes:

| Change | Documentation to maintain |
| --- | --- |
| Setup, CLI discovery, signing, permissions, or troubleshooting | `docs/SETUP.md` and `website/docs.html` |
| User capabilities, task lifecycle, or product constraints | `PRODUCT.md` and affected README usage notes |
| Visible controls, subtitles, layout, shortcuts, or accessibility | `DESIGN.md` and affected README usage notes |
| Module responsibilities, model routing, tools, or data flow | `ARCHITECTURE.md` and README data/model tables |
| Validation or release preparation | `docs/VALIDATION.md` with date, source revision, commands, and actual results |

Describe implemented behavior and label unverified behavior explicitly. Keep source compilation, automated tests, hardware checks, and authenticated end-to-end validation distinct. Do not carry a previous passing test count forward as evidence for a new revision, or predict a shared release number from the local bundle counter.
