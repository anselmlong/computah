# Bring your own key and usage costs

Computah uses **your OpenAI API key** for voice and screen reading. Paste it into the app's Settings and save it to macOS Keychain. OpenAI bills that usage to the API account. Computer tasks use your separately signed-in Codex account and do not receive this key.

## Published rates

Checked September 13, 2026; USD, before tax. These are standard API rates for the models called with the saved API key, not a Computah subscription price.

| Component | Rate | Official source |
| --- | --- | --- |
| Voice: `gpt-live-1` | $0.05 per minute, metered per second | [GPT-Live pricing](https://developers.openai.com/api/docs/models/gpt-live-1) |
| Routing/vision: `gpt-5.6-luna` | $0.20 per million input tokens; $1.20 per million output tokens | [Luna pricing](https://developers.openai.com/api/docs/models/gpt-5.6-luna) |

Computer workers request `gpt-5.6-sol` through the user's normal Codex account. Their usage follows that account's Codex plan and limits rather than the API-key calculation below.

## Illustrative budgets

These are arithmetic scenarios, **not measured app usage or guaranteed typical costs**. Each token count is the total billed across routing and vision requests. Input tokens are assumed uncached. Cache writes, retries, taxes, and Codex account usage are excluded.

| Scenario | Voice minutes | Luna input / output | Estimated API total |
| --- | ---: | ---: | ---: |
| Short demo | 10 | 20,000 / 2,000 | **$0.51** |
| Research and preparation session | 30 | 60,000 / 6,000 | **$1.52** |
| Heavier session | 60 | 120,000 / 12,000 | **$3.04** |

For example, the 30-minute scenario is $1.50 voice plus $0.0192 Luna, or $1.5192 before Codex account usage. Twenty sessions at that assumed API usage would be about $30.38, plus whatever limits or charges apply to the signed-in Codex account.

```text
USD = 0.05 × voice minutes
    + (0.20 × Luna input tokens + 1.20 × Luna output tokens) / 1,000,000
```

## What changes the bill

Ordinary conversation triggers routing with available screen context, so the voice-only rate is not the whole API cost. Large or repeated screenshots and retries can increase Luna input usage. Computer workers use high reasoning effort and can consume substantial Codex plan capacity during long or concurrent tasks.

End the voice conversation when finished; separately stop computer tasks you no longer need. The app has no total cost cap or worker runtime deadline. Use the OpenAI usage dashboard for API usage and the Codex usage view for worker limits before budgeting regular use. No paid model calls were made to calculate these estimates.

[Setup](SETUP.md) · [Architecture](../ARCHITECTURE.md) · [Live site](https://computah.anselmlong.com)
