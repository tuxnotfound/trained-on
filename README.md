# Trained On

A public, dated record of which AI tools train on your inputs. Each registry row quotes
the contract clause that says so. Every real change to that clause is diffed on a page of
its own. The corpus is Open Terms Archive's `genai-contrib` collection (ODC-By 1.0, by
Open Terms Archive contributors). The product is the denoising on top of it.

The plan, the reasoning and the pass conditions live in the control tower at
`control-tower/projects/trained-on/STATUS.md`. This repo holds the code.

## How it works

1,098 recorded versions of the 23 tracked documents reduce to 64 clause states and 41
candidate events. 883 of those versions are identical to the previous one once normalised.
The pipeline, in `app/services/trained_on/`:

1. **Normaliser**: link text kept and targets dropped, so rotating `openaicom-did` IDs
   vanish. Word joiners and zero-width characters are stripped, text is NFC-normalised,
   quotes are folded, "(opens in a new window)" is removed. Each document is split into
   segments at paragraphs, bullets and table cells.
2. **Locator**: finds the clause by hand-chosen **anchors**, stable phrases per document,
   kept in `db/seeds/anchors.yml`. When no anchor matches, the result is `anchor_lost`,
   never "no change". The old regex net (`Net`) only proposes unanchored training segments
   for review.
3. **Backfill**: walks every OTA version with `git log` and `git show`, then hashes and
   collapses runs into `ClauseVersion`s. It emits a `ClauseEvent` per real transition and
   flags events that coincide with an OTA "technical or declaration upgrade" commit. A
   rebuild carries review decisions over.
4. **Adjudicator**: Claude Haiku (`claude-haiku-4-5`) gives a first opinion on new events.
   It uses structured output, only when `ANTHROPIC_API_KEY` is set, and never publishes.
5. **Review**: `/admin` behind basic auth. Every event is published or rejected by a person.
   Registry rows are drafts until marked verified. A row not verified in 30 days shows as
   stale.

Public pages: `/` is the registry, `/vendors/:slug` a vendor's plans and full clause
history, `/changes` and `/changes/:date-:vendor-:document` the change pages, `/methodology`
and `/data`. Feeds and files: `/changes.atom`, `/vendors/:slug.atom`, `/api/v1/vendors`,
`/api/v1/changes`, `/data/registry.csv`, `/data/changes.csv`. All data is under ODC-By 1.0.

## Run it locally

Ruby 3.4.9 and git. The OTA corpus is a gitignored clone under `corpus/`, made on first run:

```
bundle install
bin/rails db:prepare
bin/rails trained_on:bootstrap   # clone corpus if missing, seed, rebuild history (about 45 s),
                                 # load suggested verdicts, replay review decisions
TRAINED_ON_ADMIN_USER=me TRAINED_ON_ADMIN_PASSWORD=secret bin/dev
```

Nothing is public until reviewed. The registry shows only what `db/seeds/decisions.yml` publishes. Open `/admin`, press
**Preview the public site with drafts** to see everything marked as draft, then work
through the queue. In development, `?preview=1` also works.

## Reviewing

- **Queue** (`/admin`): each candidate shows the word diff, the evidence commits, the OTA
  extraction flag, Haiku's opinion when available, and the suggested verdict. Publish needs
  a public classification (position, scope or disclosure) and a one-line summary.
- **Registry rows**: check each quote against the vendor's live page, then press
  **Verified today**. Quotes must be verbatim in the tracked clause, which the model enforces.
- **Decisions are files, not database rows.** Every publish, reject and verification made in
  development is written to `db/seeds/decisions.yml` straight away. Commit it: git is the audit
  trail, and a deploy replays it with `trained_on:apply_decisions`. A decision whose clause has
  changed since the review is not applied, and the event goes back to pending.
- **Anchors** (`/admin/documents/:id`): add or remove phrases, then rebuild. Copy the
  change into `db/seeds/anchors.yml` so a fresh database has it too. The same page lists
  training language the net found that no anchor covers.

## Nightly refresh

`NightlyRefreshJob` runs at 04:00 through Solid Queue (`config/recurring.yml`). It pulls
the corpus, cloning it on first run, and rebuilds every document. It asks Haiku about new
events and emails `TRAINED_ON_REVIEWER`. It never publishes. Run it by hand with
`bin/rails runner NightlyRefreshJob.perform_now`.

## Tests

```
bin/rails test                 # includes real-corpus regressions (about 90 s)
SKIP_CORPUS=1 bin/rails test   # without them
bin/rubocop && bin/brakeman
```

The regressions run the committed anchors over the real corpus. They assert that the six
locator artefacts from the human read stay gone, that Claude.ai's 2025-08-29 flip is still
found, and that every registry quote is verbatim.

## Deploy (not done yet)

Kamal to one small server, per the build plan (a Hetzner CX22). SQLite, backups and the
corpus clone live on the `trained_on_storage` volume. Solid Queue runs inside Puma.

```
export TRAINED_ON_SERVER_IP=... TRAINED_ON_HOST=... TRAINED_ON_REGISTRY=ghcr.io/<user>/trained-on
export KAMAL_REGISTRY_USERNAME=... KAMAL_REGISTRY_PASSWORD=... TRAINED_ON_ADMIN_PASSWORD=...
export TRAINED_ON_REVIEWER=... SMTP_ADDRESS=... SMTP_USERNAME=... SMTP_PASSWORD=...  # optional: email digest
export ANTHROPIC_API_KEY=...                                                          # optional: Haiku opinions
bin/kamal setup
bin/kamal bootstrap   # clone the corpus, seed, rebuild history, replay review decisions
```

Put Cloudflare in front for the launch spike. `bin/kamal backup` writes a SQLite copy to
`storage/backups`. Shipping it off the box, to R2 for example, is not wired up yet.

## Layout

- `app/services/trained_on/`: normaliser, net, locator, corpus, backfill, extraction check, word diff, adjudicator.
- `db/seeds/`: `anchors.yml` (what is tracked), `tiers.yml` (registry rows), `reviews.yml` (suggested verdicts).
- `scripts/denoise.rb` and `results/`: the original go/no-go test, its report, and the 2026-09-25 human read.
- `test/fixtures/files/`: real OTA documents behind the regression tests.
- `corpus/`: gitignored OTA clone.
