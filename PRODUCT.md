# Computah

<!-- impeccable:product-schema 1 -->

## Platform

Native Swift macOS app using SwiftUI and AppKit. The app lives in the notch panel, described by the user as the Dynamic Island. It has no Dock icon or menu bar item. Codex's native Computer Use capability works in existing Mac applications. On a display without a physical notch, the panel uses a centered top-edge layout.

## Users

People working through research and preparation on their Mac, starting with complex personal projects such as master's applications. Built as a hackathon prototype, Computah lets them keep talking while delegated tasks run in separate Codex worker processes. App interaction still shares the user's existing Mac interface.

## Product purpose

Have a spoken conversation about what is on screen, point by circling, and delegate longer computer tasks to local Codex workers. Keep task status and manual review in the notch panel.

## Capabilities and constraints

- `gpt-live-1` handles audio and text conversation. `gpt-5.6-luna` routes requests and interprets screenshots through the Responses API, then returns text findings to the voice model.
- The conversation key defaults to Right Shift. Tap to start or end a conversation; hold and drag to circle a region on the display under the pointer. Settings also offer right Command, Option, and Control.
- The shortcut preference persists in UserDefaults. The voice and screen-reading API key persists separately in macOS Keychain and is never passed to a Codex worker.
- Permission rows provide named Allow and Settings controls. Automatic refresh is passive; only explicit Allow requests access. Reopen Computah ends voice and tasks, then reloads the saved Keychain key.
- Screen context includes the full current display and a separate crop when selected. Screen Recording permission is required.
- Concurrent reasoning tasks use Codex's native Computer Use capability and share the user's Mac app interface. There are no isolated task browsers or desktops.
- Each task starts a regular `codex app-server` worker under the user's existing `HOME` and `CODEX_HOME`. It inherits the signed-in Codex account, configuration, and plugins, while parent-task identity variables are removed.
- The worker requests `gpt-6-astra` with high reasoning effort. It uses no custom model provider, direct helper gate, custom Chrome extension, manual extension setup, or private-browser fallback.
- Workers start in YOLO mode with approval policy `never` and sandbox mode `danger-full-access`. The task prompt requires explicit user confirmation before sending, submitting, paying, publishing, accepting terms, or finalizing an application. That instruction is not an enforced runtime approval boundary.
- Native app access can pause on an MCP elicitation request. **Allow once** or **Don't allow** answers the request over the same app-server connection and keeps the turn alive.
- Non-secret worker questions are spoken through the active `gpt-live-1` conversation with the task title and available choices. A complete relevant answer returns to the same waiting task. Unrelated speech does not consume the question, ambiguous replies cause a repeat, and the voice model cannot author the answer.
- Every worker question also appears as a text form in its task card. Secret questions use private text fields and are excluded from voice transport. Review waits for already-dispatched action handling, but it is not a network boundary or a guarantee against every consequential action.
- Ending a conversation leaves reasoning tasks running. Stopping a task stops its worker; quitting stops all workers.
- The conversation shows one live transcript of user and assistant speech, without a duplicate full-history section.
- A separate desktop execution environment would be needed to isolate app control from the user's ongoing work.

## Implementation decisions

The app is implemented in Swift with SwiftUI and AppKit. Each computer task runs in a separate process with an ephemeral thread. The process uses the user's normal Codex home, account, configuration, and plugins. It does not receive Computah's OpenAI API key.

Earlier builds called the protected Computer Use helper directly and received caller-authentication error `-10000`. The regular Codex worker replaces that unsupported route.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the implementation decisions and [docs/VALIDATION.md](docs/VALIDATION.md) for dated evidence and remaining coverage. The [demo site](https://computah.anselmlong.com) and [video](https://youtu.be/WGbVYat8Lmg) introduce the experience.

## Current validation

Build 21 is installed, signed, notarized, stapled, and accepted by Gatekeeper. All 80 Swift tests pass. Automated tests cover the installed Codex handshake, native approval continuation, concurrent task isolation, worker-question continuation, voice-answer grounding, task-card fallback, secret-field handling, wake-phrase matching, and notch dismissal. A live Astra probe reached native app approval, but its acceptance run stalled before the tool request. Successful app observation, a complete Computer Use task, and a live spoken worker-question exchange remain unverified.

## Brand commitments

The name is Computah. The lime face is an animated character whose eyes, mouth, and listening bars communicate activity. On the built-in display, the idle panel is 273 by 32 points: the 185-point physical camera gap plus an 88-point shoulder for the face. Idle mode shows no Ready label or chevron. Active tasks or conversation widen the compact panel to 377 points.
