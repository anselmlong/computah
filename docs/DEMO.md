# Demo walkthrough

[Open the demo site](https://computah2.anselmlong.com) · [Watch the demo video](https://youtu.be/WGbVYat8Lmg)

## The 30-second pitch

Computah is a voice companion that lives in your Mac's notch. Talk about what's on your screen, circle something to give it context, and hand off browser research while you keep working. Each task gets its own browser. When the work is ready, you can inspect it and take over. We built it to make complex personal projects—like researching and preparing master's applications—feel like a conversation instead of another pile of tabs.

## A three-minute walkthrough

| Beat | Show | Say or ask |
| --- | --- | --- |
| 0:00–0:30 · Meet Computah | The character and expanded notch panel | “A little companion for the projects that take more than one tab.” Tap Right Shift to talk. |
| 0:30–1:00 · Give it context | A public program page; circle a requirement | “Explain this requirement.” Wait for actual screen findings. |
| 1:00–2:00 · Delegate | A browser research task while you keep using the Mac | “Find the official NUS Master of Computing General Track admissions requirements. Summarize them with source links.” |
| 2:00–2:30 · Watch and review | Open the task browser; inspect the result | Show that the task used its own session. Take over before interacting. |
| 2:30–3:00 · Explain the build | Architecture overview and the demo links | “Native Swift, live voice, screen understanding, and a local worker per browser task. You keep the final say.” |

Timings are a presenter outline, not latency promises. Research completion depends on network, account access, and the website. Only describe actions the running app actually completed.

## Rehearse before presenting

- Keep one tested app bundle and grant permissions before the presentation. Rebuilding with ad hoc signing can change permission approvals.
- Confirm the API account can use the configured voice, routing, and worker models, and that Computah can find the Codex CLI.
- Run a complete voice → screen → browser → takeover sequence on the presentation Mac, using public information. This remains a required release check even if compilation passes.
- Confirm microphone and speaker routing; use headphones if echo cancellation is unavailable.
- Open the live site and video, and check the download. Keep the architecture page available for questions.
- Clear unrelated windows and old demo tasks. Quitting clears browser sessions; ending voice alone does not stop browser work.

## If the live task stalls

Keep the explanation honest: show the recorded demo, or walk through the site's labeled native screenshots. Use Take over when a scripted site, sign-in, or missing information blocks preparation. Do not describe the fictional application screenshots as a live university application.

To reproduce those screenshots:

```sh
zsh scripts/render-pitch-previews.sh
```

This harness uses production SwiftUI views and browser tools with the fictional fixture in `scripts/fixtures/masters-application.html`. It fills three fields, checks that submission requires review, and writes four PNGs into `.build/pitch-previews/`. It does not load credentials, invoke a model, or submit an application. Provenance is recorded in `website/assets/screenshots.json` and the PNG metadata.

## What is ready, and what comes next

The native interface, routing, worker transport, browser controls, and release tooling are implemented. See the [validation record](VALIDATION.md) for observed test results. Broad distribution still needs Developer ID signing/notarization, a full authenticated voice/vision rehearsal, wider hardware testing, and resource controls for long-running use. The current browser restrictions are prototype boundaries, not a complete isolation guarantee.
