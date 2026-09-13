# Data and limits

Computah stores the voice and screen-reading API key in macOS Keychain, not UserDefaults or a plain settings file. Remove the saved key in settings when you no longer want startup access. Computer workers do not receive this key. They inherit the user's normal `HOME`, `CODEX_HOME`, signed-in Codex account, configuration, and plugins.

Screenshots and captions remain in app memory rather than a Computah transcript archive. During conversation, new utterances trigger display capture, and routing sends the available display image and selected crop to OpenAI even when it ultimately chooses a direct answer. Screen interpretation also sends those images. Circling does not mean only the crop leaves your Mac. Requests set `store: false`, which does not promise that OpenAI retains no request data under its service policies.

When "Listen for Hey, computah" is enabled and Microphone and Speech Recognition access are granted, Computah uses the microphone between conversations to recognize the wake phrase locally. Wake recognition requires on-device English support and never falls back to server recognition. Computah does not store background transcripts or send background audio to OpenAI. Turn the switch off in settings to stop wake listening. Wake listening pauses during conversations and resumes after they end. Quitting stops it entirely.

Microphone audio is sent to OpenAI during a conversation, including one started by "Hey, computah." Clicking outside the notch collapses the panel without ending the conversation or its microphone stream. Use **End conversation** or the conversation key to end voice. Avoid exposing unrelated private information on the display or in audible conversation.

Computer tasks use native Codex Computer Use in the user's existing applications. They share the desktop, application state, and signed-in sessions. There is no separate private browser, cookie store, or isolated desktop per task. A worker may observe unrelated content visible in an application it can access.

Each worker runs as the current user in YOLO mode with approval policy `never` and sandbox mode `danger-full-access`. Native app and plugin approvals remain separate and may still ask for consent. The task prompt prohibits reading or exporting credentials and requires explicit user confirmation before consequential actions. Those instructions are not operating-system isolation or an enforced runtime approval boundary.

When a worker requests non-secret information or confirmation, Computah sends the question, task title, and choices to the active voice session. The voice model asks the question but may not answer it. A separate routing call classifies the user's next complete utterance and returns only the user's actual answer to the matching waiting task. Unrelated speech is not used as an answer; ambiguous speech causes the question to repeat. Every worker question also appears as a task-card form. Secret questions use private fields there and do not enter voice transport.

Fresh Computer Use observation and actions are serialized across tasks, but the user and concurrent workers can still affect the same applications. Review waits for already-dispatched action handling before manual interaction. It does not block network traffic or prove that every consequential control was prevented.

Earlier builds used a private WebKit task browser with application-level navigation restrictions. That path is retired. The current runtime uses normal Codex capabilities and native Computer Use.

[Project overview](../README.md) · [Architecture](../ARCHITECTURE.md)
