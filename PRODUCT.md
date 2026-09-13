# Computah

<!-- impeccable:product-schema 1 -->

## Platform

Native Swift macOS app using SwiftUI and AppKit. The app lives in the notch panel, described by the user as the Dynamic Island. It has no Dock icon or menu bar item. A larger task browser window is available alongside the notch panel. On a display without a physical notch, the panel uses a centered top-edge layout.

## Users

A personal working prototype for Jensen. The user keeps working on the Mac while delegated browser work runs independently.

## Product purpose

Have a spoken conversation about what is on screen, point by circling, and delegate longer browser tasks to a local Codex worker. Keep task status in the notch panel, with a larger view of the same browser session for watching and review.

## Capabilities and constraints

- `gpt-live-1` handles audio and text conversation. `gpt-5.6-luna` routes requests and interprets screenshots through the Responses API, then returns text findings to the voice model.
- The conversation key defaults to Right Shift. Tap to start or end a conversation; hold and drag to circle a region on the display under the pointer. Settings also offer right Command, Option, and Control. The shortcut preference persists in UserDefaults; the API key persists separately in macOS Keychain.
- Permission rows provide named Allow and Settings controls. Automatic refresh is passive; only explicit Allow requests access. A working input event tap also counts as shortcut access. Reopen Computah ends voice and tasks, then reloads the saved Keychain key.
- Screen context includes the full current display and a separate crop when selected. Screen Recording permission is required.
- Multiple independent tasks can run concurrently, each with its own title, worker, browser, and open/review/stop controls. There is no fixed task cap.
- Each local Codex app-server worker requests `gpt-5.6-sol` and uses only the supplied tools for its independent browser. The user's cursor and ordinary applications remain available.
- Preparation disables website JavaScript and blocks form submissions and non-GET navigation. Script-dependent websites can require manual review before preparation can proceed.
- Click the browser thumbnail or ask to show the browser to watch the same session in a larger window. Watching and closing that window leave the task running. Take over stops the worker for manual interaction.
- Applications and consequential actions require manual review. The worker stops before the user takes over; it does not submit on the user's behalf.
- Ending a conversation leaves browser tasks running. Stopping a task stops its worker; quitting stops all workers.
- Settings save, replace, or remove the API key in macOS Keychain. The app loads it at startup and supplies it to worker processes through their environments.
- Each task browser uses its own nonpersistent website data store, separately from the user's usual browser.
- Active conversation shows compact, labeled live subtitles for the user and assistant. A scrollable transcript appears after the conversation ends.
- Native desktop automation is outside this prototype's scope. It would need a separate desktop execution environment.

## Implementation decisions

The user chose Swift and asked to see the first version while development continued, explicitly waiving the understanding checkpoint for this implementation. The worker starts with an isolated temporary home and requests read-only access, with built-in execution tools disabled. It does not reuse the user's Codex configuration or account plugins.

This version builds locally and includes automated tests. Hosted CI passes the Swift suite (53 tests, one installed-CLI check skipped) and release tests. Local XCTest remains unavailable in the command-line-only toolchain; see README.md for dated verification status. Authenticated text routing and browser research have been verified against the official NUS Master of Computing General Track pages. Full voice/vision execution and a real application portal remain unverified.

## Brand commitments

The name is Computah. The lime face is an animated character whose eyes, mouth, and listening bars communicate activity. The compact panel is currently 377 by 40 points, with an empty 185-point physical camera gap. The character sits on the left shoulder and status on the right.
