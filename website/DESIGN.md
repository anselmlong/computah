---
name: Computah website
description: The native black-and-lime companion, carried onto the web.
colors:
  paper: "#0b0d0b"
  ink: "#f3f5ed"
  muted: "#a9b1a4"
  line: "#30372d"
  lime: "#d1f28c"
  lime-hover: "#e1ffab"
  wash: "#171c15"
  on-lime: "#17200c"
typography:
  display:
    fontFamily: "Manrope, sans-serif"
    fontWeight: 600
    lineHeight: 1.12
    letterSpacing: "-0.04em"
  body:
    fontFamily: "Manrope, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.85
---

# A little company, in black and lime

The user selected the native app's lime face, black backgrounds, and lime accents as the website's visual identity. This replaces the earlier paper, blue, and rust identity. The homepage persuades through an animated companion and real interface captures; `docs.html` uses the same identity for reading.

## Brand and type

Self-hosted Manrope at 400 and 600 remains the typeface. The primary mark is the idle `CompanionFace` geometry from `Sources/Computah/Panel.swift`: two rounded lime eyes and a small curved smile. Inline SVG enables motion in headers, footers, and the hero. `assets/icon.svg` is the static favicon and repository mark. Text labels supply accessible names; decorative SVGs are hidden from assistive technology.

The near-black canvas uses soft white headings and muted green-gray body text. Lime identifies actions, selected workflow stages, and headline emphasis. The installation section inverts to lime with dark text and a dark download button. Screenshots keep their original colors and illustrative-data captions.

## Composition

The homepage retains its project narrative: introduction, problem, research/prepare/review walkthrough, companion capabilities, download, and setup FAQ. The opening pairs the pitch with an interactive notch-shaped companion above a native conversation screenshot. The illustration is the actual character geometry, not a new mascot.

The shell is capped at 1328px with 48px desktop padding, 36px below 1100px, 24px below 760px, and 20px below 400px. Hero and paired sections stack below 760px. The header wraps instead of overflowing. Documentation uses a narrower reading column, in-page navigation, ordered architecture steps, and native links.

## Motion and interaction

- Eyes blink once per six-second cycle; gaze shifts on a twelve-second cycle.
- The hero notch opens once through a 700ms clip-path reveal. Text and primary actions are available immediately.
- Tap or keyboard-activate the companion for a brief nod and greeting. This is a decorative interaction, not live AI or microphone access. Greetings use a polite live region.
- Pause animation toggles all decorative motion; the control exposes its pressed state and changes to Resume animation.
- IntersectionObserver pauses faces outside the viewport. Page visibility pauses animations in background tabs.
- Reduce Motion disables decorative movement and the entrance, retains readable selected/focus states, and hides the redundant pause control.
- Workflow tabs retain arrow/Home/End keyboard behavior, roving focus, and a short clip transition. Hash changes reveal the matching panel. Without JavaScript all workflow panels remain readable.
- Downloads and text-link arrows respond subtly to hover. No autoplay audio, cursor replacement, scroll interception, or animation dependency is used.

## Accessibility and evidence

Controls retain visible lime focus outlines; the lime installation section uses dark outlines. Screenshots retain aspect ratio, full-size links, and accurate captions. Disclosure rows remain native `details` elements. Core information is never hidden pending a scroll animation.

The three-pixel selected-tab underline is functional state feedback, not a card accent. Browser visual QA is pending because the current environment has no connected browser. Automated tests cover workflow behavior, motion controls, offscreen/background suspension, and greetings; these do not establish rendering quality or animation performance.

The detector also flags `stroke-width` on the SVG smile as a width transition. It changes a bounded SVG stroke, not layout geometry; this is an intentional 200ms hover response. Direct palette contrast checks measured muted body text above 7.8:1 on both dark surfaces and dark text above 8.1:1 on lime. Rendered checks remain pending.

## Rotating request heading

The hero fixes “Computah,” above a lime request that cycles through applying for a master’s, booking a flight ticket, filling a survey, and checking emails. Characters type at 75ms and delete at 38ms, with a 2.2-second reading hold and a 350ms empty pause. Invisible measurement spans reserve the tallest phrase; a fixed accessible heading avoids character-by-character announcements. The shared pause button, page visibility, offscreen detection, and live Reduce Motion preference stop the timer. Without JavaScript or with Reduce Motion, the first phrase stays readable. Four open text columns introduce the use cases; they become two columns on mobile and one on small phones.
