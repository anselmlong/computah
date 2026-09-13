---
name: Computah pitch website
description: The established blue and rust identity with native app demonstrations.
colors:
  paper: "#f5f7fa"
  ink: "#202d3d"
  muted: "#566477"
  line: "#d5dce5"
  blue: "#1765c1"
  blue-hover: "#104e98"
  rust: "#ad430b"
  wash: "#e5ecf5"
  white: "#ffffff"
typography:
  display:
    fontFamily: "Manrope, sans-serif"
    fontSize: "clamp(44px, 4.7vw, 67px)"
    fontWeight: 600
    lineHeight: 1.12
    letterSpacing: "-0.04em"
  headline:
    fontFamily: "Manrope, sans-serif"
    fontSize: "clamp(28px, 3vw, 40px)"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "-0.035em"
  body:
    fontFamily: "Manrope, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.85
  action:
    fontFamily: "Manrope, sans-serif"
    fontSize: "15px"
    fontWeight: 600
rounded:
  button: "8px"
  preview: "12px"
  number: "50%"
components:
  button-primary:
    backgroundColor: "{colors.blue}"
    textColor: "{colors.white}"
    rounded: "{rounded.button}"
    padding: "16px 22px"
    typography: "{typography.action}"
  button-primary-hover:
    backgroundColor: "{colors.blue-hover}"
  screenshot-surface:
    backgroundColor: "{colors.wash}"
    rounded: "{rounded.preview}"
    padding: "22px"
---

# Design System: Computah pitch website

## Overview

**Creative North Star: "A little computah."**

The established identity pairs clear Manrope typography and a pale field with blue actions and rust emphasis. Spacious editorial sections frame actual native interface captures. Black notch panels and the lime character belong to the photographed application; they do not replace the website palette.

This record applies only to the standalone website in `static/computah2`. It does not govern the parent game's interface or the native app. `PRODUCT.md` owns product facts; the route surface brief owns the master's-application narrative. This is a scan of the built `index.html`, `style.css`, and `site.js`, refreshed after the documentation finding in `.impeccable/review/finish-review.md`.

**Key Characteristics:**

- Self-hosted Manrope with restrained rust emphasis and blue actions.
- Pale screenshot grounds, fine section rules, and open text columns.
- Real native captures with visible illustrative-data captions.
- Accessible progressive enhancement and readable mobile stacking.

## Colors

The cool neutral field supports two distinct accents: action blue and expressive rust. Frontmatter values are normative and match the CSS custom properties.

### Primary

- **Action blue** (`blue`): downloads, selected tabs, inline links, numbered steps, and focus outlines. `blue-hover` deepens primary actions on hover.

### Secondary

- **Rust** (`rust`): wordmark, display emphasis, and sample spoken requests.

### Neutral

- **Paper** (`paper`): page ground.
- **Ink** (`ink`): headings and main text; **Muted** (`muted`): explanations, captions, and metadata.
- **Line** (`line`): section boundaries and disclosure rules.
- **Wash** (`wash`): screenshot surrounds and the full-width installation band.
- **White** (`white`): primary action and selected-number text.

## Typography

Self-hosted Manrope ships in regular and semibold weights (400 and 600), with `sans-serif` fallback and synthetic faces disabled. Display and section-heading roles are recorded above; section variants range from 28–44px. The desktop wordmark is 32px with negative tracking (-0.035em). The hero introduction is 20px/1.5 and supporting copy 16px/1.8 with a 48ch maximum. Workflow body text uses the body role; rust quotations use 17px/1.7. Labels and metadata range from 10–15px. Headings use balanced wrapping. Release metadata and numbered markers use tabular numerals. This is a set of observed roles, not a fixed modular scale.

## Layout

A centered shell has a 1328px maximum width including 48px side padding. The nonsticky header has a 100px minimum height. Desktop sections alternate open columns, fine horizontal rules, and a wash installation band. Most section vertical padding lies between 42px and 64px; gaps vary with content instead of using a universal card grid.

The current opening is a two-line promise and actions beside a conversation capture, in 1.2:1 columns with a 48px gap. Workflow panels use 0.8:1.7 columns, a 50px gap, and a 635px minimum height. Portrait screenshot surrounds have a 545px minimum height; landscape captures retain their aspect ratio without that minimum. Download/installation and setup/FAQ are paired columns. Route-specific content order is recorded in the surface brief.

- At 1100px and below: shell padding is 36px; hero columns become 1.13:1 with a 30px gap; display type uses `clamp(39px, 4.7vw, 55px)`. Workflow columns become 0.9:1.6 with a 32px gap; captions stack.
- At 760px and below: shell padding is 24px and the header minimum is 82px. Hero, premise, workflow, companion, download, and setup stack. Display type uses `clamp(38px, 7.5vw, 54px)`. Tabs divide the width equally. Panels lose their minimum height, captions return to a row, and footer items wrap. Landscape screenshots remain previews with explicit full-size links.
- At 400px and below: shell padding is 20px, display type is 36px, the hero download fills the width, tabs tighten, header icons disappear, and screenshot captions stack again.
- At 360px and below: the first header navigation link hides; the download navigation remains.

## Elevation & Depth

Section rules and pale tonal surfaces supply most depth. Screenshot panels are flat. Primary downloads use `0 5px 12px #17457518` at rest and `0 8px 18px #17457525` on hover; active state removes the shadow and uses `#0d3f7d`. There is no site glass or floating-card system.

## Shapes

Downloads and screenshot surrounds use the frontmatter radii. Sequence numbers are circles; tabs themselves remain square. Section and disclosure rules are 1px. The selected tab has an intentional 3px blue bottom border: this is a functional selection underline, not a rounded-card accent stripe. The detector warning for that declaration is a regex false positive. Outline SVGs normally use a 1.7px stroke, round joins/caps, and no fill.

## Components

### Actions and navigation

Downloads are links to the ZIP with a minimum height of 58px, an icon, and the primary style. Secondary actions are text links with inline arrows and a minimum height of 44px. Header links use a similar touch target. Hover turns text links blue; secondary body links also underline. The wordmark is rust with a blue terminal dot.

Links, buttons, summaries, and focusable panels have a 3px blue focus outline offset by 5px. The skip link appears on keyboard focus and targets main content. The page uses smooth anchor scrolling except under reduced motion.

### Workflow tabs

Research, Prepare, and Review form one progressively enhanced sequence. Without JavaScript, the tab strip stays hidden and all three articles remain visible. With JavaScript, roles and relationships become `tablist`, `tab`, and `tabpanel`; inactive panels hide, and selected tabs use roving tabindex. Initial location hashes `#research`, `#prepare`, and `#review` select the matching panel; otherwise Research is selected. Clicking tabs does not update the URL hash.

Left/Right arrows wrap and activate the adjacent tab; Home/End activate the first/last. Keyboard navigation moves focus to the new tab. Panels are keyboard focusable. Selected tabs show the blue underline and a filled blue number; unselected numbers have fine outlines. Hover adds wash. Desktop panels above 760px enter over 0.3s with a small clip/opacity transition using `cubic-bezier(.16,1,.3,1)`. Ordinary control transitions last 0.18s. Reduced motion disables all animations/transitions and smooth scrolling.

### Screenshot figures

Captures sit within pale rounded surrounds or, for landscape browser frames, a dark edge with no inner padding. Images retain aspect ratio. Each links to the original in a new tab with `noopener`, descriptive accessible text, and an adjacent caption. Workflow figures also expose a visible “Open full size” link. The hero loads eagerly with high priority; workflow images are lazy loaded. Visible captions and a shared demo note distinguish illustrative content from observed browser interactions.

### Installation and disclosures

Installation uses an ordered three-step list with outlined number circles and text aligned beside them. The four FAQ rows are native `details`/`summary`, all closed by default. The chevron rotates when open; hover changes summary text to blue. These disclosures function without JavaScript. No editable form fields, chips, or application inputs are implemented on the marketing page; form fields visible in its screenshots belong to the native demo.

## Do's and Don'ts

### Do:

- Do preserve Manrope, blue actions, rust emphasis, and pale screenshot surfaces.
- Do keep screenshots proportional, captioned, and linked to readable originals.
- Do preserve keyboard tab behavior, visible focus, default-visible fallback content, and reduced-motion support.
- Do keep release metadata tied to `downloads/Computah.zip`, separately from development-interface captures.

### Don't:

- Don't describe illustrative transcripts, fictional institutions, or local demo fields as a real admissions result or authenticated AI session.
- Don't imply the screenshot interface is guaranteed to match the downloadable build.
- Don't remove the functional selected-tab underline to satisfy the detector's generic border warning.
- Don't apply this website record to the parent game or native app design system.
