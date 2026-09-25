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
4. **Panel**: three readers, one model from each of three companies (Claude, GPT, Gemini),
   each classify the change from the old and new text alone. None sees the others' answers
   or the suggested verdict. When all three agree it is a change of position, a scope change
   or a disclosure, a summary check picks the most cautious of their one-line summaries and
   the event is published, marked `decided_by: panel`. Unanimous wording or churn is
   rejected. Disagreement, low confidence, a failed reader, an extraction-flagged event or a
   lost anchor goes to a person. With fewer than three readers configured the panel only
   advises. Registry rows work the same way: the quote is checked mechanically against the
   latest capture, and the answer label is confirmed by the three readers or by a person.
5. **Review**: `/admin` behind a login. What the panel could not settle is decided by a
   person, with the readers' answers side by side. A row whose latest capture is over 30
   days old shows as stale.

Public pages: `/` is the registry, `/vendors/:slug` a vendor's plans and full clause
history, `/changes` and `/changes/:date-:vendor-:document` the change pages, `/methodology`
and `/data`. Feeds and files: `/changes.atom`, `/vendors/:slug.atom`, `/api/v1/vendors`,
`/api/v1/changes`, `/data/registry.csv`, `/data/changes.csv`. All data is under ODC-By 1.0.

## Run it locally

Ruby 3.4.9 and git. The OTA corpus is a gitignored clone under `corpus/`, made on first run:

```
bundle install
cp .env.example .env             # then set TRAINED_ON_ADMIN_PASSWORD in .env
bin/rails db:prepare
bin/rails trained_on:bootstrap   # clone corpus if missing, seed, rebuild history (about 45 s),
                                 # load suggested verdicts, replay review decisions
bin/dev                          # admin at /admin, with the user and password from .env
```

`.env` is gitignored and loaded in development only. `.env.example` lists every setting.

Nothing is public until reviewed. The registry shows only what `db/seeds/decisions.yml` publishes. Open `/admin`, press
**Preview the public site with drafts** to see everything marked as draft, then work
through the queue. In development, `?preview=1` also works.

## Reviewing

- **Panel first.** Put the three API keys in `.env`, run `bin/rails trained_on:panel_check`
  to confirm keys and model ids, then `bin/rails trained_on:panel` (or the button in
  `/admin`). It prints what was published, what was rejected, and what waits for a person.
- **Queue** (`/admin`): what is left shows the word diff, the evidence commits, the OTA
  extraction flag, each reader's answer and the reason the panel did not decide. Publish
  needs a public classification (position, scope or disclosure) and a one-line summary.
- **Registry rows**: the quote must be verbatim in the tracked clause (enforced) and present
  in the latest capture (checked on every rebuild). The answer label is confirmed by the
  panel, or by you with **Confirm answer**. When a vendor changes position, update the row
  in `db/seeds/tiers.yml`; the digest tells you when a quote drops out of the latest capture.
- **Decisions are files, not database rows.** Every publish, reject and verification made in
  development is written to `db/seeds/decisions.yml` straight away. Commit it: git is the audit
  trail, and a deploy replays it with `trained_on:apply_decisions`. A decision whose clause has
  changed since the review is not applied, and the event goes back to pending.
- **Anchors** (`/admin/documents/:id`): add or remove phrases, then rebuild. Copy the
  change into `db/seeds/anchors.yml` so a fresh database has it too. The same page lists
  training language the net found that no anchor covers.

## Nightly refresh

`NightlyRefreshJob` runs at 04:00 through Solid Queue (`config/recurring.yml`). It pulls
the corpus, cloning it on first run, rebuilds every document, re-checks registry quotes,
runs the panel over new events and unconfirmed rows, and emails `TRAINED_ON_REVIEWER` what
was published and what waits. Nothing is published unless three readers agree. Run it by
hand with `bin/rails runner NightlyRefreshJob.perform_now`.

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
export ANTHROPIC_API_KEY=... OPENAI_API_KEY=... GEMINI_API_KEY=...                    # the panel; all three or it only advises
bin/kamal setup
bin/kamal bootstrap   # clone the corpus, seed, rebuild history, replay review decisions
```

Put Cloudflare in front for the launch spike. `bin/kamal backup` writes a SQLite copy to
`storage/backups`. Shipping it off the box, to R2 for example, is not wired up yet.

## Layout

- `app/services/trained_on/`: normaliser, net, locator, corpus, backfill, extraction check, word diff, panel, readers, decisions.
- `db/seeds/`: `anchors.yml` (what is tracked), `tiers.yml` (registry rows), `reviews.yml` (suggested verdicts).
- `scripts/denoise.rb` and `results/`: the original go/no-go test, its report, and the 2026-09-25 human read.
- `test/fixtures/files/`: real OTA documents behind the regression tests.
- `corpus/`: gitignored OTA clone.
