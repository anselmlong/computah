# Computah interface

This document describes the current SwiftUI and AppKit implementation. The notch panel contains conversation, settings, and task previews. App control uses Codex's native Computer Use capability and shares the user's existing Mac application interface.

## Placement and shape

The borderless black panel sits at the top center of the first notched display, falling back to the main display. It remains visible across Spaces and can accompany full-screen apps. On the built-in display, its height follows the 32-point top safe area. Idle width is 273 points: the empty 185-point physical camera gap plus an 88-point shoulder for the lime face. Idle mode has no Ready label or chevron. A conversation or running task widens the compact panel to 377 points and shows status on the right shoulder.

Hovering over the lime face for 240 milliseconds expands the panel. Clicking the same face toggles it open or closed. Moving the pointer away does not close it, but clicking outside does. Expansion slides open over 320 milliseconds with animated geometry and clipping, revealing a dark scrollable panel with rounded lower corners. Conversation and settings use a compact width; app interaction happens through native Codex Computer Use. Available display dimensions limit the panel's width and height.

## Character and color

The character has two rounded eyes and a small mouth. It blinks, shifts its gaze while connecting or reading, opens its mouth while speaking, and draws microphone-responsive bars while listening. Errors change its lime color to warm orange. Reduce Motion pauses decorative animation and uses a fixed speaking shape.

The main accent is RGB `0.82, 0.95, 0.55`, approximately `#D1F28C`. Backgrounds are black and near-black, primary text is white, and secondary text is gray. A small lime mark at the panel's bottom indicates an active conversation.

## Conversation

The expanded header shows Computah and a plain-language state. Before the first utterance, the panel explains the right Shift shortcut. A single expanded live transcript shows both the user and Computah, distinguished by speaker labels. The panel does not repeat the full history in a second section. A screen-context row shows whether the current display or circled region is included, with a Clear action for a selection.

The main button starts or ends the conversation. Each concurrent task has a title, status, stop and review controls, and a result. A native app-approval request adds **Allow once** and **Don't allow** to the task card. Answering that request keeps the worker turn alive. Pausing voice does not stop these independent workers.

If echo cancellation cannot start, the conversation panel shows a headphones notice while ordinary audio remains available.

## Settings and review

Settings provide a secure API key field, a Conversation key picker, permission status, and Quit Computah. Right Shift is the default conversation key; right Command, Option, and Control are also available. The shortcut choice persists in UserDefaults. Each permission row has an Allow or Settings control, and permission status refreshes passively without consent prompts. Explicit Allow requests access once. Settings save, replace, or remove the API key in macOS Keychain. Starting a conversation also saves the entered key automatically. The app loads it at startup. Reopen Computah ends voice and all tasks, then reloads the saved key. The footer shows the incrementing build number and UTC build date.

The app has no custom Chrome extension installation, pairing controls, or separate helper check. Settings report whether the Codex CLI is installed. Account, plugin, and native app access are checked when a task starts. Each task uses a regular `codex app-server` process with the user's normal Codex account and plugins. It requests Astra with high reasoning effort and does not receive the API key saved for voice and screen reading.

Native Computer Use may ask for app approval through MCP elicitation. **Allow once** accepts one request and **Don't allow** declines it; both answer the app server without ending the turn. A request for missing information or a consequential action still stops the task for manual review. Concurrent reasoning tasks share existing applications, so the interface must not imply isolated browser tabs or independent desktops.

## Pointing and access

Holding right Shift reveals a temporary selection overlay on the display under the pointer. Dragging draws a lime lasso; the app captures its rectangular bounds as a crop alongside the whole display. Escape cancels. The Start talking button remains usable when Input Monitoring is unavailable.

The interface labels icon controls for accessibility, uses system typography, permits caption and result text selection, and responds to Reduce Motion. Native mouse and keyboard events used for pointing belong to the user; worker browser tools do not drive the system cursor.
