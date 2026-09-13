# Demo walkthrough

[Open the demo site](https://computah.anselmlong.com) · [Watch the demo video](https://youtu.be/WGbVYat8Lmg)

## The 30-second pitch

Computah is a voice companion that lives in your Mac's notch. Talk about what's on your screen, circle something to give it context, and hand off computer work while you keep working. Each task gets its own Codex worker and uses native Computer Use in your existing applications. We built it to make complex personal projects, such as researching and preparing master's applications, feel like a conversation instead of another pile of tabs.

## A three-minute walkthrough

| Beat | Show | Say or ask |
| --- | --- | --- |
| 0:00–0:30 · Meet Computah | The character and expanded notch panel | “A little companion for the projects that take more than one tab.” Tap Right Shift to talk. |
| 0:30–1:00 · Give it context | A public program page; circle a requirement | “Explain this requirement.” Wait for actual screen findings. |
| 1:00–2:00 · Delegate | A research task while you keep using the Mac | “Find the official NUS Master of Computing General Track admissions requirements. Summarize them with source links.” |
| 2:00–2:30 · Approve and review | The task card and an existing Mac app | Answer any native app approval. If the worker asks a confirmation question, answer it through the voice conversation, then inspect the result. |
| 2:30–3:00 · Explain the build | Architecture overview and the demo links | “Native Swift, live voice, screen understanding, and a normal Codex worker using my installed apps. I keep the final say.” |

Timings are a presenter outline, not latency promises. Research completion depends on network, account access, and the website. Only describe actions the running app actually completed.

## Rehearse before presenting

- Keep one tested app bundle and grant permissions before the presentation. Rebuilding with ad hoc signing can change permission approvals.
- Confirm the API account can use the configured voice and routing models. Confirm the signed-in Codex account can start `gpt-5.6-sol` and access the required native apps.
- Run a complete voice → screen → computer task → native app approval → worker voice question → same-task continuation sequence on the presentation Mac, using public information. This remains a required release check even if compilation passes.
- Confirm microphone and speaker routing; use headphones if echo cancellation is unavailable.
- Open the live site and video, and check the download. Keep the architecture page available for questions.
- Clear unrelated windows and old demo tasks. Computer Use shares the desktop and existing application sessions. Quitting stops tasks; ending voice alone does not.

## If the live task stalls

Keep the explanation honest: show the recorded demo, or walk through the site's labeled native screenshots. Answer missing-information and confirmation questions only with facts the user provided. Do not describe the fictional application screenshots as a live university application.

To reproduce those screenshots:

```sh
zsh scripts/render-pitch-previews.sh
```

This legacy harness uses SwiftUI views and the retired WebKit fixture path with the fictional form in `scripts/fixtures/masters-application.html`. It writes four illustrative PNGs into `.build/pitch-previews/`. It does not exercise the current native Computer Use runtime, load credentials, invoke a model, or submit an application. Provenance is recorded in `website/assets/screenshots.json` and the PNG metadata.

## What is ready, and what comes next

The native interface, routing, normal Codex worker transport, app-approval UI, and release tooling are implemented. See the [validation record](VALIDATION.md) for observed test results. Build 22 is signed with Developer ID and notarized. A full authenticated voice, vision, and native Computer Use rehearsal, wider hardware testing, enforced review controls, and resource limits for long-running use remain open.
