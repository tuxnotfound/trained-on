# Trained On

trainedon.me: is this AI training on my prompts? A public, dated record of what each AI
tool's terms say about training on your prompts. Each registry row quotes the clause that
says so. Every real change to that clause is diffed on a page of
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
   or the suggested verdict. When all three agree it is a real change (position, scope or
   disclosure), the event is published under the most cautious of their three labels, with a
   summary check picking the most cautious of their one-line summaries; it is marked
   `decided_by: panel`. Unanimous wording or churn is rejected. Disagreement on whether the
   change is real, low confidence, a failed reader, an extraction-flagged event or a lost
   anchor goes to a person. With fewer than three readers configured the panel only
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

## Deploy

Kamal to `tux-box`, the one Hetzner Cloud server every project shares behind Kamal 2's proxy
(decided 2026-09-28; the build plan's own CX22 is withdrawn). CX33, 4 vCPU, 8 GB, x86, Nuremberg,
IP `2.28.203.124`, Ubuntu 26.04.1, keys-only SSH, Hetzner firewall allowing 22, 80 and 443.
`builder.arch` stays amd64. The full decision and who else lands on the box are in the control
tower: `HOSTING.md` at its root and `projects/trained-on/STATUS.md`, section "Hosting". Never
rescale one of the older servers instead; they keep pre-June-2026 prices.

SQLite, the corpus clone and local backup copies live on the `trained_on_storage` volume. Solid
Queue runs inside Puma. A nightly job copies the database, gzips it and ships it to Cloudflare
R2, a launch precondition on a shared box.

### Runbook, in this order

1. **On this Mac:** Docker Desktop running (`docker info` answers), and the deploy key in the
   agent (`ssh-add -l` lists `tuxnotfound@cioga.eu`; if not, `ssh-add --apple-load-keychain`).
   The key has a passphrase; Kamal takes it from the agent and never prompts.
2. **Secrets.** `.kamal/secrets` reads each name from the shell or, failing that, from the
   gitignored `.env` (see `bin/secret`). `.env` already has the three AI keys and the admin
   user and password. Add the rest:
   ```
   echo "RAILS_MASTER_KEY=$(cat config/master.key)" >> .env
   echo 'KAMAL_REGISTRY_PASSWORD=ghp_...' >> .env   # classic GitHub token, scope write:packages only
   echo 'R2_ACCESS_KEY_ID=...' >> .env; echo 'R2_SECRET_ACCESS_KEY=...' >> .env
   echo 'R2_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com' >> .env; echo 'R2_BUCKET=trained-on-backups' >> .env
   # optional, the email digest: TRAINED_ON_REVIEWER, TRAINED_ON_MAIL_FROM, SMTP_ADDRESS, SMTP_USERNAME, SMTP_PASSWORD
   ```
   The R2 pair comes from Cloudflare: R2, create bucket `trained-on-backups`, then Manage R2 API
   Tokens, Create, permission Object Read and Write, restricted to that bucket only. The R2 and
   SMTP settings are read the same way as the secrets, so no deploy depends on what the shell
   happens to have exported.
3. **Shell for this session:** `export TRAINED_ON_SERVER_IP=2.28.203.124`
4. **DNS before the first boot**, because kamal-proxy asks Let's Encrypt for the certificate on
   the first request and the challenge must reach the box. In Cloudflare: Add a site,
   `trainedon.me`, free plan; A record `@` to `2.28.203.124` with the proxy **off** (grey
   cloud), plus `www` the same way; then at GoDaddy replace the nameservers with the two
   Cloudflare gives. Wait until `dig +short trainedon.me` prints `2.28.203.124`.
5. **Deploy:**
   ```
   bin/kamal setup       # installs Docker on the box, boots kamal-proxy, builds and pushes the image, boots the app
   bin/kamal bootstrap   # clone the corpus, seed, rebuild history, replay review decisions
   bin/kamal backup      # first backup to R2, to prove the route before launch
   bin/kamal app logs    # should show Puma serving and the backup upload
   ```
   `curl -sI https://trainedon.me/up` must return 200 with a Let's Encrypt certificate.
   If `setup` fails installing Docker on 26.04, Rebuild the server with Ubuntu 24.04 from the
   Hetzner console (same IP, disk wiped), add the tuxnotfound public key to root again, and rerun.
6. **Then Cloudflare's proxy on:** first fix the trusted-proxies item in the control tower's
   BUGS.md for this project (behind the proxy Rails sees Cloudflare's address as every client,
   which breaks the admin rate limit), deploy that, and only then switch both records to
   proxied (orange cloud) and set SSL/TLS to Full (strict). Flexible would loop against
   `force_ssl`.
7. **Cloudflare cache rule, once, before any launch.** The app sends `Cache-Control: public,
   max-age=60, s-maxage=600` on every plain 200 GET of a public page outside preview
   (`PublicCache`), and `private` on everything else, but Cloudflare only caches HTML when a
   rule says so. Caching, Cache Rules, Create rule, name `public pages`, expression
   `(http.host eq "trainedon.me" and not starts_with(http.request.uri.path, "/admin") and not http.cookie contains "preview=")`,
   Cache eligibility: Eligible for cache, Edge TTL: use cache-control header if present and
   bypass if not, Browser TTL: respect origin. If the free plan refuses the cookie clause, drop
   it: preview responses are `private` so they are never stored, and a preview look at a page
   that is already cached needs a throwaway query string (`/?x=1`) to reach the box. Verify:
   `curl -sI https://trainedon.me/` twice, the second says `cf-cache-status: HIT`;
   `curl -sI https://trainedon.me/admin/login` says `DYNAMIC` or `BYPASS`. Public pages set no
   cookie (the CSRF token is only rendered in preview), because the edge never stores a
   response that carries `Set-Cookie`.
8. **Log it** in the control tower: `projects/trained-on/CHANGELOG.md` and the `tux-box` row and
   Domains table in `HOSTING.md`.

To restore a backup: download the newest `trained-on/production-*.sqlite3.gz` from the bucket,
gunzip it, stop the app, put it at `storage/production.sqlite3` on the volume, start the app.

The image is `ghcr.io/tuxnotfound/trained-on`, the host `trainedon.me`, and the server is
reached as root with `~/.ssh/id_ed25519_tuxnotfound`, all set in `config/deploy.yml`.

## Layout

- `app/services/trained_on/`: normaliser, net, locator, corpus, backfill, extraction check, word diff, panel, readers, decisions.
- `db/seeds/`: `anchors.yml` (what is tracked), `tiers.yml` (registry rows), `reviews.yml` (suggested verdicts).
- `scripts/denoise.rb` and `results/`: the original go/no-go test, its report, and the 2026-09-25 human read.
- `test/fixtures/files/`: real OTA documents behind the regression tests.
- `corpus/`: gitignored OTA clone.
