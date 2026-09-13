# Computah interface

This document describes the current SwiftUI and AppKit implementation. The notch panel contains conversation, settings, and task previews. A larger browser window shows the same private session for watching or manual interaction.

## Placement and shape

The borderless black panel sits at the top center of the first notched display, falling back to the main display. It remains visible across Spaces and can accompany full-screen apps. The compact panel is currently 377 by 40 points. Its 185-point physical camera gap stays empty, with the lime character on the left shoulder and status on the right.

Expansion slides open over 320 milliseconds with animated geometry and clipping, revealing a dark scrollable panel with rounded lower corners. Conversation and settings use a compact width; browser review expands to fit more of the page. Available display dimensions limit the panel's width and height.

## Character and color

The character has two rounded eyes and a small mouth. It blinks, shifts its gaze while connecting or reading, opens its mouth while speaking, and draws microphone-responsive bars while listening. Errors change its lime color to warm orange. Reduce Motion pauses decorative animation and uses a fixed speaking shape.

The main accent is RGB `0.82, 0.95, 0.55`, approximately `#D1F28C`. Backgrounds are black and near-black, primary text is white, and secondary text is gray. A small lime mark at the panel's bottom indicates an active conversation.

## Conversation

The expanded header shows Computah and a plain-language state. Before the conversation starts, the panel explains the configured shortcut. During a conversation, compact live subtitles show the latest user and Computah speech in separate labeled rows. The user row shows one line and the assistant row shows two, keeping the newest text visible. After the conversation ends, a scrollable transcript is available. A screen-context row shows whether the current display or circled region is included, with a Clear action for a selection.

The main button starts or ends the conversation. Each concurrent task has a title, status, private browser preview, open/review/stop controls, and result. Pausing voice does not stop these independent workers.

If echo cancellation cannot start, the conversation panel shows a headphones notice while ordinary audio remains available.

## Settings and review

Settings provide a secure API key field, a Conversation key picker, permission status, and Quit Computah. Right Shift is the default conversation key; right Command, Option, and Control are also available. The shortcut choice persists in UserDefaults. Each permission row has an Allow or Settings control, and permission status refreshes passively without consent prompts. Explicit Allow requests access once. Settings save, replace, or remove the API key in macOS Keychain. Starting a conversation also saves the entered key automatically. The app loads it at startup. Reopen Computah ends voice and all tasks, then reloads the saved key. The footer shows the incrementing build number and UTC build date.

Clicking the task thumbnail or asking to show the browser opens a larger window containing the selected task's private `WKWebView` session. Watching allows the task to continue, and closing the window does not stop it. Take over stops the worker and transfers control to the user for manual interaction. Website JavaScript is allowed on subsequent navigation, but the app does not reload automatically. The user may need to reload scripted pages manually. Close review returns to the conversation view.

## Pointing and access

Holding the configured conversation key (Right Shift by default) reveals a temporary selection overlay on the display under the pointer. Dragging draws a lime lasso; the app captures its rectangular bounds as a crop alongside the whole display. Escape cancels. The Start talking button remains usable when Input Monitoring is unavailable.

The interface labels icon controls for accessibility, uses system typography, permits caption and result text selection, and responds to Reduce Motion. Native mouse and keyboard events used for pointing belong to the user; worker browser tools do not drive the system cursor.
