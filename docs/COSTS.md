# Bring your own key and usage costs

Computah uses **your OpenAI API key**. Paste it into the app's Settings and save it to macOS Keychain. OpenAI bills usage to that API account. An API key with access to the configured models is required; Computah does not supply shared credits.

## Published rates

Checked September 13, 2026; USD, before tax. These are standard API rates for the configured models, not a Computah subscription price.

| Component | Rate | Official source |
| --- | --- | --- |
| Voice: `gpt-live-1` | $0.05 per minute, metered per second | [GPT-Live pricing](https://developers.openai.com/api/docs/models/gpt-live-1) |
| Routing/vision: `gpt-5.6-luna` | $0.20 per million input tokens; $1.20 per million output tokens | [Luna pricing](https://developers.openai.com/api/docs/models/gpt-5.6-luna) |
| Browser worker: `gpt-5.6-sol` | $4 per million input tokens; $20 per million output tokens | [Sol pricing](https://developers.openai.com/api/docs/models/gpt-5.6-sol) |
| Web search | $0.01 per call, plus search-content tokens at model rates | [Tool pricing](https://developers.openai.com/api/docs/pricing#tools) |

Sol's listed rates are promotional through at least November 21, 2026. Check rates again before treating these figures as a budget commitment.

## Illustrative budgets

These are arithmetic scenarios, **not measured app usage or guaranteed typical costs**. Each token count is the total billed across all requests, including image/search inputs and output reasoning tokens. Input tokens are assumed uncached; individual requests stay below the long-context pricing threshold. Cache writes, retries, taxes, and optional extra tools are excluded.

| Scenario | Voice minutes | Luna input / output | Sol input / output | Searches | Estimated total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Short demo with a small browser task | 10 | 20,000 / 2,000 | 20,000 / 2,000 | 2 | **$0.65** |
| Research and preparation session | 30 | 60,000 / 6,000 | 150,000 / 15,000 | 10 | **$2.52** |
| Heavier session with several tasks | 60 | 120,000 / 12,000 | 500,000 / 50,000 | 30 | **$6.34** |

For example, the 30-minute scenario is $1.50 voice + $0.0192 Luna + $0.90 Sol + $0.10 search = $2.5192. Twenty sessions at that assumed usage would be about $50.38.

```text
USD = 0.05 × voice minutes
    + (0.20 × Luna input tokens + 1.20 × Luna output tokens) / 1,000,000
    + (4 × Sol input tokens + 20 × Sol output tokens) / 1,000,000
    + 0.01 × web searches
```

## What changes the bill

The browser worker uses high reasoning effort and can make many model requests per task. Page observations include screenshots and text; repeated context, long tasks, multiple workers, and retries can make token use exceed these examples. Ordinary conversation also triggers routing with available screen context, so the voice-only rate is not the whole app cost.

End the voice conversation when finished; separately stop browser tasks you no longer need. Closing a browser window leaves the task running. The app has no total task-cost cap or total worker runtime deadline. Use your OpenAI usage dashboard to measure a representative session before budgeting regular use. No paid model calls were made to calculate these estimates.

[Setup](SETUP.md) · [Architecture](../ARCHITECTURE.md) · [Live site](https://computah.anselmlong.com)
