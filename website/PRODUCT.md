# Computah pitch website

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

People considering Computah for everyday computer tasks and larger projects on their Mac. The pitch spans applications, travel research, surveys/forms, and understanding visible emails. The master's application remains one illustrative walkthrough.

## Product Purpose

Explain the native Computah app through a concrete application workflow, show its interface, and let visitors download the Mac prototype. The site is static HTML/CSS with small progressive-enhancement JavaScript where useful, deployed as the existing Vercel project `computah2`.

## Capabilities and Constraints

Computah is a native voice companion in a notch panel. It can interpret the current display and a selected crop, then route requests into computer tasks. Each task starts a normal Codex worker and uses native Computer Use in the user's existing Mac applications. The app requires the user's OpenAI API key for voice and screen reading; computer work uses the account already signed in through the Codex CLI. Workers are instructed to ask for explicit confirmation before consequential actions, and Computah routes the user's voice answer back to the same waiting task. That rule is not enforced by the YOLO-mode runtime.

The download is an Apple silicon macOS 14+ prototype, with version and size stamped by the release pipeline. The packaged binary is separate from development-interface screenshots. No production-readiness, admissions outcomes, testimonials, usage counts, or authenticated end-to-end validation are established.

## Evidence on Hand

The native source is in `Sources/Computah/` in this repository. Reproducible captures use real SwiftUI components and the retired WebKit fixture path with explicitly illustrative transcripts and a fictional master's application. The captures do not exercise the current native Computer Use runtime and are not an authenticated live AI session or a real university application. Screenshots must carry that distinction in visible captions and in their provenance record.

## Brand Commitments

Use the native app’s black-and-lime identity across the website. Retain the real app’s notch panel and lime character inside screenshots. Keep the download functional and its metadata accurate.

## Public documentation

`docs.html` provides setup, architecture, and data-sharing notes without requiring access to the private repository. The canonical site is https://computah.anselmlong.com and the demo recording is https://youtu.be/WGbVYat8Lmg.

The user selected the native lime face as the primary website brand mark. Use it in the header, footer, and favicon; use black backgrounds, lime actions, and soft off-white text throughout.

The companion blinks and looks around on the site, with a tap-to-greet interaction. This is decorative personality, not a live voice or model session. Provide pause controls, reduced-motion support, and offscreen/background suspension.

The hero keeps “Computah,” fixed and cycles through the user-supplied requests with typing and deletion. These are example requests, not claims of direct inbox integration or autonomous booking/submission. Nearby use-case descriptions explain supported scope.
