# Trained On

A public, dated record of which AI tools train on your inputs, with the actual
contract clause quoted and diffed over time. Not a registry: a change-event
record. The corpus is Open Terms Archive's `genai-contrib` collection
(ODC-By 1.0, attribution to Open Terms Archive contributors); the product is the
denoising on top of it.

The plan, the reasoning and the pass conditions live in the control tower at
`control-tower/projects/trained-on/STATUS.md`. This repo holds the code.

## State

Nothing built yet. The first action is not the 16-hour Rails build. It is the
go/no-go test in `scripts/denoise.rb`: does the corpus contain enough real,
dated clause changes to be worth a product at all?

| Gate | Build needs | Drop below |
|---|---:|---:|
| Distinct clause states across 13 vendors | 20 | 10 |
| Transitions where words actually changed | 6 | 3 |
| Vendors where the locator finds the clause | 10 of 13 | misses more than 3 |

Below the drop line, this project ends. 16 hours would buy a worse Shieldra.

## Run the test

```
git clone https://github.com/OpenTermsArchive/genai-contrib-versions corpus/genai-contrib-versions
ruby scripts/denoise.rb
```

Ruby 3.4 (see `.ruby-version`), stdlib only, no gems, no network after the
clone. It writes `results/denoise-report.md` with the verdict table, a
per-vendor summary, and every transition with the new clause text quoted, so
the "meaning-bearing" call can be made by reading rather than trusting.

## What the script does

normalise (NFC, strip zero-width chars, replace links with their text so
rotating tracking params vanish, collapse whitespace) → locate (paragraphs that
mention training a model AND the user's material, minus known false positives)
→ hash the located block → walk every git version of every document → collapse
runs of identical hashes → classify each transition as reflow-only or
word-change → report.

## Layout

- `scripts/denoise.rb`: the test.
- `results/`: committed reports, one per run worth keeping.
- `corpus/`: gitignored clone of the OTA versions repo.
