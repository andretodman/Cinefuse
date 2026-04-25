# MONETIZATION.md — Cinefuse Sparks Economy and Pricing

This file defines what users pay, what we pay, and where the money goes. Numbers here are grounded in 2026 video-model API pricing as observed in publicly-quoted rate cards (see `PLAN.md` references). They will move; the framework for adjusting them is documented at the end of this file.

## The Spark

A Spark is the unit of in-app currency. **1 Spark equals approximately $0.01 USD** of effective spend at the standard tier. This is a soft anchor, not a guarantee — users do not get to redeem Sparks for cash, and bulk-purchase discounts mean a user who buys the 14,000-Spark pack pays less per Spark than one who buys the 500-Spark pack. The anchor exists so that a user can quickly map "this shot will cost 70 Sparks" to "about 70 cents of cost" without doing math.

Sparks are persistent on the user's Pubfuse account and never expire. Sparks granted as part of a subscription cycle do roll over for the duration of the active subscription; if the user cancels Plus, granted Sparks remain on the balance until used.

The Spark balance lives on the Pubfuse user record (proposed field: `cinefuse_sparks_balance` integer, non-negative, default zero, with a separate ledger table `cinefuse_spark_transactions` that is the actual source of truth — the balance field is a denormalized cache for fast reads). All writes to the balance go through the `billing` MCP's `debit` and `credit` operations with idempotency keys. The hard-coded "all users start with a lot of Sparks" provision in the spec is implemented as a one-time grant of 100,000 Sparks on user creation, recorded as a normal credit transaction. This makes flipping IAP on (M6) a config change rather than a refactor — the ledger is already in production semantics.

## What things cost the user

These are the launch-target Sparks prices. Real prices will be tuned in beta based on observed COGS and conversion data.

**Script generation.** A beat sheet for a 5-minute short costs ~30 Sparks. Each scene revision is ~5 Sparks. Shot prompt generation is ~2 Sparks per scene. Total script-tab spend on a typical 5-minute project: ~80 Sparks (well under $1). Script costs are deliberately low — we want users to experiment freely with story structure without a Sparks anxiety on every "regenerate."

**Character creation.** Hero character (full Stand-In LoRA training): 500 Sparks. Bit character (IP-Adapter conditioning, no training): 50 Sparks. Most projects have 2–4 hero characters and 5–10 bit characters → typical character-tab spend: ~1,500–2,500 Sparks.

**Clip generation.** This is where most of the spend lives. Per 5-second clip (the most common shot length):

| Tier | Model used | Sparks cost | Our cost | Effective margin |
|---|---|---|---|---|
| Budget | Wan 2.6 (480p) | 50 | $0.25 | 50% |
| Budget | LTX-2 (480p, fast) | 40 | $0.20 | 50% |
| Standard | Kling 2.5 Turbo Pro (1080p) | 70 | $0.35 | 50% |
| Standard | Hailuo 2.3 Pro (1080p, flat-rate) | 90 | $0.49 | 46% |
| Standard | Wan 2.6 (1080p) | 80 | $0.40 | 50% |
| Premium | Veo 3.1 with audio (720p) | 250 | $2.00 | 20% |
| Premium | Sora 2 Pro (1080p) | 300 | $2.50 | 17% |
| Premium | Kling 3.0 Pro multi-shot (10s) | 500 | $1.50 | 67% |

(Costs sourced from publicly-quoted per-second pricing on fal.ai as of March 2026 — Wan 2.6 ~$0.05/sec, Kling 2.5 Turbo ~$0.07/sec, Veo 3.1 ~$0.20–$0.40/sec with audio, Sora 2 Pro ~$0.30–$0.50/sec.)

Premium tier is intentionally lower-margin because the absolute Sparks count is high enough that a tighter margin still pencils in real dollars per shot, and because Premium tier is a competitive moat — we want users on the cutting-edge models to default to using Cinefuse rather than going direct to fal.ai.

**Audio.** Dialogue (ElevenLabs): ~10 Sparks per spoken second. Score (Suno standard tier): ~30 Sparks per 30-second piece. SFX (library lookup): free; SFX (generated): ~15 Sparks per cue. Mixing: free. Lip-sync post-process: ~20 Sparks per minute of dialogue. Typical 5-minute project with substantial dialogue: ~1,500–2,500 Sparks total audio.

**Stitch and export.** Free for 1080p. 4K export: 200 Sparks per export (covers heavy encoding compute and Pubfuse storage). Re-export of an unchanged project: free.

**Total typical 5-minute short, Standard tier, ~30 shots, 4 characters, full audio**: ~10,000–15,000 Sparks ≈ $100–$150 effective spend. This compares favorably with hiring a freelancer or a stock-footage subscription + editing time; the comparison the marketing should make is *"a 5-minute short for the price of a nice dinner."*

## What users pay us

Spark packs are sold via Apple StoreKit 2 IAP in the Mac App Store (and via Stripe on the cinefuse.com web dashboard for users who prefer not to go through Apple — but the App Store path is featured in the app and is the default purchase flow). Apple takes their 30% cut on IAPs, dropping to 15% under the Small Business Program for the first year if Cinefuse qualifies (revenue under $1M).

The launch SKU table:

| SKU | Sparks | USD price | $ per Spark | Effective discount vs. 500 pack |
|---|---|---|---|---|
| sparks_500 | 500 | $4.99 | $0.00998 | — (anchor) |
| sparks_1200 | 1,200 | $9.99 | $0.00833 | 17% off |
| sparks_2700 | 2,700 | $19.99 | $0.00740 | 26% off |
| sparks_6500 | 6,500 | $49.99 | $0.00769 | 23% off |
| sparks_14000 | 14,000 | $99.99 | $0.00714 | 28% off |

The 2,700 and 14,000 packs are the highest-margin from a $-per-Spark standpoint; the 500 pack exists as a low-friction first purchase. The 6,500 pack is intentionally priced near the $50 psychological threshold to make the larger pack feel like a small step up.

**Cinefuse Plus subscription** (auto-renewing, StoreKit subscription product):

| Plan | Price | Monthly Sparks grant | Other benefits |
|---|---|---|---|
| Plus monthly | $19.99/mo | 2,500 Sparks/mo | 4K export, priority queue, 5 hero LoRAs cached |
| Plus annual | $179.99/yr ($14.99/mo eff.) | 30,000 Sparks/yr (granted upfront) | Same as monthly, plus Beta-features access |
| Pro monthly | $49.99/mo | 7,500 Sparks/mo | Plus, plus 4K, batch generation, project archives kept indefinitely |
| Pro annual | $499.99/yr ($41.66/mo eff.) | 90,000 Sparks/yr (granted upfront) | Same as Pro monthly, plus 1-on-1 onboarding session |

Subscriptions are deliberately positioned as "Sparks bulk + perks." A Plus monthly user pays $19.99 for 2,500 Sparks they'd otherwise pay $19.99-ish for in the 2,700 pack — so the Sparks themselves are roughly break-even with bulk-pack pricing, and what they're really paying for is the perks. This is the "Costco membership" framing — the membership pays for itself in any month they actively use the product.

## What we pay

The COGS table for the typical 5-minute short at standard tier, walking through every cost driver:

- 8–12 scenes generated → ~$0.05 in Anthropic API for script
- 2–4 hero characters → ~$2.00–$4.00 in Wan 2.x training compute (self-hosted in Phase 3 to ~$0.50)
- 5–10 bit characters → ~$0.50–$1.00 in IP-Adapter conditioning
- 25–35 video clips at standard tier, 5s each → ~$8.75–$12.25 in fal.ai (Kling)
- ~5 minutes of dialogue → ~$0.90 in ElevenLabs
- ~4 minutes of score → ~$0.80 in Suno
- ~10 SFX cues → ~$0.50 in Stable Audio
- Stitch + export compute → ~$0.10 in self-hosted ffmpeg
- Storage in Pubfuse Files (assume 200 MB per project for the 5-minute project + working files, retained 90 days hot then archived) → ~$0.05/month

Total COGS for a typical standard-tier 5-minute short: roughly **$13–$20**.

Total Sparks charged to user for the same project: **~10,000–15,000 Sparks** = $100–$150 at average $-per-Spark.

After 30% Apple cut on the IAP that funded those Sparks: net revenue ~$70–$105.

After COGS: gross profit ~$50–$85 per 5-minute project. Gross margin: 60–80% on a project basis (this is higher than the per-clip table suggests because the "long tail" of low-cost or free operations — script revisions, mixing, character reuse, etc. — improve the average).

## Realistic Year 1 revenue model

The market we're addressing is Mac-using indie creators and hobbyist filmmakers in English-speaking markets, plus a long tail of educators and small marketing teams. Conservative addressable market in Year 1: ~500K–1M people who would seriously consider a tool like this. Cinefuse cannot reach all of them; the App Store + content-marketing flywheel realistically reaches 50K–200K in Year 1 if we ship M7 on time and don't faceplant on App Review.

Three scenarios:

**Bear case** (no App Store featuring, 1% conversion to paid, average paying-user spend of $15/mo): 5,000 paying users × $15 × 12 months = **~$900K ARR**. This survives but doesn't fund a team larger than the founders + 2–3 engineers.

**Base case** (some App Store visibility, 2.5% conversion, average $22/mo): 15,000 paying users × $22 × 12 = **~$4M ARR**. This funds a real company — 12–15 person team, marketing budget, sustainable runway.

**Bull case** (App Store featured at launch + a viral demo, 5% conversion, average $25/mo): 50,000 paying users × $25 × 12 = **~$15M ARR**. This is "raise a Series A and build the iOS version and the web editor" territory. It is achievable but not the planning case.

The base case is what we plan against. Bear case is what we survive. Bull case is the dream we don't depend on but build the architecture to support without rewriting.

A hidden assumption: a Cinefuse Plus annual subscriber costs us very little in COGS in months they don't actively use the product, so subscription revenue is high-margin. This is also a churn risk — users who don't use the product cancel — but in the meantime it's the cleanest revenue. Marketing should push annual plans hard for engaged users (a single in-app prompt at the start of month 3 of monthly use, offering 25% off the annual conversion).

## How prices change

The plan above is anchored to early-2026 pricing. Three things drive price changes:

**Upstream cost changes.** fal.ai or Veo or ElevenLabs raises (or lowers) their rates. We monitor the per-job `cost_to_us_cents` field weekly. A sustained 15%+ shift in cost on any tier triggers a re-pricing review by founders. The Spark cost of the affected operations is updated; *Sparks already in user balances do not lose purchasing power* — they buy slightly fewer or more units of the affected tier, but the same Spark always equals the same Spark. Future Spark pack USD prices adjust if needed (e.g., if costs structurally rise 30%, the 500 pack might rise to $5.99 over six months).

**Self-hosting wins.** When we deploy self-hosted Wan 2.2 on H100s in Phase 3, our budget-tier COGS drops from ~$0.05/sec to ~$0.015–$0.02/sec. We pocket the entire delta in gross margin for one full quarter (gives us cash to fund growth), then in the following quarter we cut budget-tier Sparks prices by 25% to drive volume and lock in price-sensitive users against competitors.

**Competitive response.** If a major competitor undercuts our standard-tier pricing by more than 30%, we evaluate whether to match, hold, or differentiate. Generally we hold and differentiate — Cinefuse's value is the workflow, not the price-per-clip. But if a credible competitor enters with a Mac-native generative film editor at half our price, we move.

## What gets metered, what doesn't

Metered (charged in Sparks): clip generation, character LoRA training, dialogue TTS, score generation, SFX generation, lipsync post-process, 4K export.

Not metered (free): script generation in unlimited revisions, character preview frames (low-cost image generation for verification), SFX library browsing and use, stitch / preview rendering, 1080p export, project archive download, sharing to Pubfuse community, all read operations (project load, balance check, etc.).

The deliberate principle is: *anything where regenerating is the natural part of the creative process should be free or near-free; anything that produces final-output bits costs Sparks.* Users should never feel that exploring an idea costs them money. The cost arrives when they commit to a take.

## Promotional and grant Sparks

New users get 2,500 Sparks at signup (post-M6; before M6 they get 100,000 to bypass the billing flow). 2,500 is enough for a small project at standard tier — about a 1-minute short with 6 shots, 1 character, basic audio — which is a "first finished thing" experience. This grant is the on-ramp; the conversion KPI is whether new-user-with-grant produces an exported project.

Referrals: Give 500 / get 500. The referrer gets 500 Sparks on the referred user's first IAP purchase (not just signup, to prevent farming).

Promotional grants for partnerships, contests, and educators are on a discretionary basis, granted via an admin tool gated to specific staff roles and audited.

Refund policy on Sparks: a generation that the system marks as failed automatically refunds. A generation the user is unhappy with, but the system marks as successful, is not refundable — but the user can re-generate at a 50%-off Sparks discount (the "give it another shot" pricing). Refund policy on IAP follows Apple's policy, with our server promptly processing refund webhooks to remove Sparks from the balance.

## Audit and compliance

The Spark ledger is append-only; rows are never updated after creation. Every transaction has an idempotency key, an actor (user or system), a related resource (project, shot, IAP receipt), and a timestamp. A nightly job reconciles the denormalized `cinefuse_sparks_balance` field on the user record against the sum of the ledger; mismatches page the on-call.

Apple StoreKit transactions are stored with the Apple transaction ID and receipt blob (encrypted at rest, retained 7 years for tax purposes). Refunds are processed automatically on receipt of Apple's webhook; the ledger entry that originally credited Sparks is debited back, and the user is notified by email and in-app.

Tax treatment of Spark sales: Apple handles VAT/sales tax in their jurisdictions on IAPs; on the web Stripe path, we use Stripe Tax for compliance. Sparks are a prepaid digital good, taxed at point of sale; consumption (generating clips) is not a taxable event because no value transfers at consumption — value transferred at purchase.

## What this enables (the "why bother" summary)

A user pays $20 for the 2,700 Spark pack. Of that, Apple takes $6 (or $3 under SBP), leaving us $14–$17 net. The user makes a 5-minute short with their 2,700 Sparks. Our COGS for that short is ~$3–$5. We net $9–$14 in gross profit on a $20 transaction. That's enough to fund the 30 minutes of engineering iteration that improved the experience for the next user, and enough left over to grow.

The economy works. It works because we're not in the bits business — fal.ai is. We're in the workflow business, and the workflow is worth more than the bits.
