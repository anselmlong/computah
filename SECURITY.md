# Security boundaries

Computah is a personal macOS prototype. Review [data and limits](docs/PRIVACY.md)
before granting access to a desktop containing private work.

## Delegated actions

Workers inherit the current user's Codex identity, configuration, plugins, and
desktop sessions. They run with `approvalPolicy: never` and
`sandbox: danger-full-access`. A task prompt asks them to obtain confirmation
before sending, submitting, paying, or publishing; this is an instruction to a
model, not an enforced authorization control. Native app/plugin consent requests
remain distinct gates.

A malicious page, document, or app can put instructions in material a worker
observes. The prompt's requirement to ignore those instructions does not make
the desktop a safe environment for adversarial content. Use a dedicated macOS
account with only demo data and signed-in accounts you intend the worker to use
when presenting unfamiliar tasks. Ending a voice conversation leaves computer
tasks running; review the task cards and stop active work separately.

## Credentials and capture

The voice API key is stored in Keychain and is not passed to computer workers.
That does not isolate workers from other credentials accessible to the current
user. Screen capture can include both a full display image and the selected
crop. A circled region is not a boundary on what leaves the machine. Secret
question fields stay out of voice transport, but ordinary questions and answers
can enter the active voice conversation.

## Release trust

Source review, app signing, and notarization address different risks. A valid
signature does not prove the worker respected confirmation instructions. A ZIP
checksum ties a download to its manifest, but a manifest from the same
compromised origin is not an independent trust anchor.

Only trusted maintainers should modify workflows or release tags. Tagged
releases can run as the logged-in user on the personal Mac runner, deploy the
website, and replace the installed app. Never use that runner for untrusted
pull-request code. Keep the repository private while this runner arrangement is
in use; see [release instructions](RELEASES.md).

## Reporting an issue

Send the maintainer the affected source commit/build, a minimal reproduction
using synthetic data, and the observed versus expected behavior. Avoid putting
API keys, screen captures of private content, voice recordings, or account
credentials in a public issue. Rotate an exposed credential through its issuer;
removing it from a report does not revoke it.
