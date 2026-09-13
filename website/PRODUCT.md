# Computah pitch website

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

People considering Computah for complex work on their Mac. The user explicitly chose applying for a master's degree as the lead use case: a process involving research, requirements, preparation, and review.

## Product Purpose

Explain the native Computah app through a concrete application workflow, show its interface, and let visitors download the Mac prototype. The site is static HTML/CSS with small progressive-enhancement JavaScript where useful, deployed as the existing Vercel project `computah2`.

## Capabilities and Constraints

Computah is a native voice companion in a notch panel. It can interpret the current display and a selected crop, route requests into browser tasks, and run independent workers with separate browser sessions. Users can watch or take over those sessions. The app requires the user's OpenAI API key; browser work also needs the Codex CLI. Website JavaScript is disabled during preparation, so scripted portals and sign-in may require manual interaction. The worker does not submit applications, upload documents, or invent applicant qualifications.

The download is an Apple silicon macOS 14+ prototype, version 0.1.0 build 6. The packaged binary is separate from the current native source build. No production-readiness, admissions outcomes, testimonials, usage counts, or authenticated end-to-end validation are established.

## Evidence on Hand

The native source is in the sibling `computah2` repository. Reproducible captures use its real SwiftUI and WebKit components with explicitly illustrative transcripts and a fictional master's application. The browser form interactions can be exercised locally through production browser tools. These captures are not an authenticated live AI session or a real university application. Screenshots must carry that distinction in visible captions and in their provenance record.

## Brand Commitments

Preserve the existing Computah site identity while expanding the pitch. Retain the real app's black notch panel and lime character inside screenshots. Keep the download functional and its metadata accurate.
