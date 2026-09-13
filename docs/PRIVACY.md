# Data and limits

Computah stores the API key in macOS Keychain, not UserDefaults or a plain settings file. Remove the saved key in settings when you no longer want startup access. Each Codex child process receives the key through its environment, along with an isolated temporary `HOME`, `CODEX_HOME`, and working directory instead of your existing Codex account, plugins, or project configuration. History persistence is disabled and the directory is removed when the worker exits normally. An abrupt process or system failure can leave temporary files behind.

Screenshots and captions remain in app memory rather than a Computah transcript archive. During conversation, new utterances trigger display capture, and routing sends the available display image and selected crop to OpenAI even when it ultimately chooses a direct answer. Screen interpretation also sends those images; circling does not mean only the crop leaves your Mac. Requests set `store: false`, which does not promise that OpenAI retains no request data under its service policies. Each task has a separate nonpersistent browser session. Its cookies remain within that session while it exists, without joining your usual browser profile.

The worker requests a read-only Codex sandbox, disables built-in execution tools, and accepts live web search and its supplied browser tools. These are prototype boundaries, not a claim of complete operating-system isolation. Submission checks also cannot prove that every website's GET link is harmless. Review prepared work and destinations before acting.


Microphone audio is sent to OpenAI during a conversation. Browser observations include page text and screenshots sent to the task model. Avoid exposing unrelated private information in the display used for a demo.

URL checks apply to navigations; they are not a network firewall for every WebKit subresource and do not eliminate DNS rebinding risks. Do not describe the browser as a security sandbox for hostile sites.

[Project overview](../README.md) · [Architecture](../ARCHITECTURE.md)
