# Computah

<!-- impeccable:product-schema 1 -->

## Platform

Native Swift macOS app using SwiftUI and AppKit. The app lives in the notch panel, described by the user as the Dynamic Island. It has no Dock icon or menu bar item. The app uses Codex's native Computer Use capability in existing Mac applications. On a display without a physical notch, the panel uses a centered top-edge layout.

## Users

A personal working prototype for Jensen. Reasoning tasks can run concurrently, while app interaction shares the user's existing Mac interface.

## Product purpose

Have a spoken conversation about what is on screen, point by circling, and delegate longer browser tasks to a local Codex worker. Keep task status in the notch panel, with task status and manual review.

## Capabilities and constraints

- `gpt-live-1` handles audio and text conversation. `gpt-5.6-luna` routes requests and interprets screenshots through the Responses API, then returns text findings to the voice model.
- The conversation key defaults to Right Shift. Tap to start or end a conversation; hold and drag to circle a region on the display under the pointer. Settings also offer right Command, Option, and Control. The shortcut preference persists in UserDefaults; the API key persists separately in macOS Keychain.
- Permission rows provide named Allow and Settings controls. Automatic refresh is passive; only explicit Allow requests access. A working input event tap also counts as shortcut access. Reopen Computah ends voice and tasks, then reloads the saved Keychain key.
- Screen context includes the full current display and a separate crop when selected. Screen Recording permission is required.
- Concurrent reasoning tasks use Codex's native Computer Use capability and share the user's Mac app interface. There are no isolated task browsers or desktops.
- Each task starts a regular `codex app-server` worker under the user's existing `HOME` and `CODEX_HOME`. It inherits the signed-in Codex account, configuration, and plugins, while parent-task identity variables and the voice API key are removed.
- The worker requests `gpt-6-astra` with high reasoning effort. Existing applications and signed-in state are used through native Computer Use, with no custom model provider, direct helper gate, custom Chrome extension, manual extension setup, or private-browser fallback.
- Native app access can pause on an MCP elicitation request. **Allow once** or **Don't allow** answers the request over the same RPC connection and keeps the turn alive. Missing information and consequential actions still stop the worker for manual review.
- Review locks the selected task and waits for dispatched actions. This is not a browser network boundary or a guarantee against every consequential click.
- Ending a conversation leaves reasoning tasks running. Stopping a task stops its worker; quitting stops all workers.
- Settings save, replace, or remove the API key in macOS Keychain. Starting a conversation also saves the entered key automatically. The app loads it at startup.
- Build 18 is installed, notarized, and accepted by Gatekeeper. All 66 Swift tests and 15 focused worker tests pass. The installed Codex handshake uses the user's normal configuration without the earlier protected-helper authentication error. A live Astra probe reached native Computer Use app approval, but the acceptance probe stalled before its tool request. Successful app observation and a complete Computer Use task are not yet claimed.
- The conversation shows one live transcript of user and assistant speech, without a duplicate full-history section.
- A separate desktop execution environment would be needed to isolate app control from the user's ongoing work.

## Implementation decisions

The user chose Swift and asked to see the first version while development continued, explicitly waiving the understanding checkpoint for this implementation. Each computer task runs in a separate process with a read-only sandbox and an ephemeral thread. The process uses the user's normal Codex home, account, configuration, and plugins. It does not receive Computah's OpenAI API key.

This version supports local build and tests. The Codex worker has reached native app approval with the signed-in user account. A complete voice, vision, and computer-task flow remains unverified.

Earlier builds called the protected Computer Use helper directly and received caller-authentication error `-10000`. The regular Codex worker replaces that unsupported route.

## Brand commitments

The name is Computah. The lime face is an animated character whose eyes, mouth, and listening bars communicate activity. On the built-in display, the idle panel is 273 by 32 points: the 185-point physical camera gap plus an 88-point shoulder for the face. Idle mode shows no Ready label or chevron. Active tasks or conversation widen the compact panel to 377 points.
