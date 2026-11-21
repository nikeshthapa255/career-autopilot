# Prose clarity and anti-slop reference examples

Use these concrete examples when reviewing or rewriting longer drafts.

## 1. Prose clarity fixes

| Pattern | Weak | Clear |
| :--- | :--- | :--- |
| **Zombie nouns (nominalizations)** | The team conducted an investigation into the failure and made a decision to perform a rollback. | The team investigated the failure and rolled back the release. |
| **False agency** | The metrics argue that onboarding needs simplification. | Onboarding metrics show users drop off at step 3, so we should cut two form fields. |
| **Delayed subject and verb** | After three weeks of benchmarking across four regions and reviewing vendor pricing, the team selected Postgres. | The team selected Postgres after three weeks of benchmarking across four regions and a vendor pricing review. |
| **Stacked nouns** | Update the regional enterprise account billing preference validation logic. | Update how we validate billing preferences for regional enterprise accounts. |
| **Reversed cause and effect** | Latency spiked by 40% because the cache TTL was reduced from 10 minutes to 30 seconds during the deploy. | During the deploy, we cut the cache TTL from 10 minutes to 30 seconds, which raised latency by 40%. |
| **Rule mixed with history** | Requests over 10 MB are rejected by the gateway, which blocked 14,200 uploads last month after the mobile release. | The gateway rejects requests over 10 MB. Last month, after the mobile release, it blocked 14,200 uploads. |

## 2. AI slop fixes

| Pattern | Slop | Natural |
| :--- | :--- | :--- |
| **Fake contrast** | This release isn't just a speed boost; it's a fundamental rethinking of how caching works. | This release cuts cache lookup time by 60% by moving keys into local memory. |
| **Negative listing** | Not a wrapper. Not a plugin. A complete compiler. | It is a standalone compiler. |
| **Colon reveal** | The best part: it runs offline. | It also runs offline. |
| **Dramatic one-liner** | Queue depth dropped to zero in four minutes. That is the real win. | Queue depth dropped to zero in four minutes. |
| **Throat-clearing and hook question** | Here's the thing: have you ever wondered why builds slow down over time? Let's dive in. | Builds slow down when uncached dependencies accumulate in the Docker layer. |
| **False range** | The tool supports everything from solo hobbyists to global infrastructure teams. | Both solo developers and large infrastructure teams use the tool. |
| **Synonym cycling** | We upgraded Redis last week. The in-memory store now uses half the RAM, and the caching layer handles twice the traffic. | We upgraded Redis last week. It now uses half the RAM and handles twice the traffic. |
| **Copula avoidance** | The CLI serves as the primary interface and boasts built-in retry logic. | The CLI is the primary interface and has built-in retry logic. |
| **Trailing "-ing" rider** | We added rate limits on Tuesday, underscoring our commitment to platform stability. | We added rate limits on Tuesday to stop traffic spikes from taking down the API. |
| **Vague attribution** | Experts agree that smaller pull requests lead to faster reviews. | Google's engineering practices guide recommends keeping pull requests small so reviews finish faster. |
| **Inline-header bullets** | - **Fast setup:** Installs in 10 seconds.<br>- **Small footprint:** Uses 12 MB of RAM. | It installs in 10 seconds and uses 12 MB of RAM. |
| **Compulsive wrap-up** | Overall, these changes mark a meaningful step forward for our reliability journey. | Next, we will add alerting on p99 latency before Friday's launch. |

## 3. Over-correction check (keep human voice)

Do not strip genuine tone or nuance when removing AI tells:

- *Too flat (over-corrected):* "The migration failed. Logs were missing. Fix scheduled Monday."
- *Natural human prose:* "The migration failed at 02:00 UTC, and because log rotation wiped the worker output, we still do not know which shard timed out. We are rerunning it Monday with verbose logging enabled."
