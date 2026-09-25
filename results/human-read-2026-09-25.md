# Human read of the 49 word-change transitions

Read 2026-09-25 against `denoise-report.md` (corpus HEAD `32cdf25`). This is the
"meaning-bearing" call the mechanical report explicitly left open. Every transition
was word-diffed old-vs-new; the two suspicious ChatGPT removals were checked against
the corpus commits directly.

## Verdict

| | Count |
|---|---:|
| Transitions with a **change of position** on training (what is used, by default, by whom, opt-out) | 14 |
| ...of which distinct **events** (same-day ToS + privacy pairs collapsed) | 12 |
| ...distinct **vendors** with at least one position change | 8 of 11 located |
| Scope changes (a plan, product or data source added to an existing rule) | 8 |
| Disclosures (new description of practice, position unchanged) | 7 |
| Wording only (renames, links, punctuation, restatement) | 13 |
| Locator churn (paragraph left or entered the block set; the document did not change that clause) | 6 |
| Not about training at all | 1 |
| **Total** | **49** |

Gate was 6 meaning-bearing transitions. Measured: 14 (12 events). **PASS, human-read.**

Corrected denoising story: 1,689 versions to 76 states to 49 word-changes to **12 real
changes of position**. Six of the 49 are locator artefacts, confirming BUGS.md: the
per-vendor anchor is needed before anything is published.

## The 12 events (the pages the product would consist of)

1. **Claude.ai, 2025-08-29** (Privacy Policy + Terms of Service). "We will not train our models on your Inputs or Outputs unless [feedback, flagged, opted in]" became "We may use your Inputs and Outputs to train our models and improve our Services, unless you opt out through your account settings." Default flipped from opt-in to opt-out. The single clearest change in the corpus.
2. **Grok, 2025-08-01** (Terms of Service + Privacy Policy). A blanket licence "to develop, train, test, improve and operate the Services (including our AI models)" became an election: "you can select whether or not you want us to use your User Content to ... train our models", and logged-out use grants "full rights ... for product development and model training". Privacy policy adds that public X posts of over-18s are training data and that you can object in settings.
3. **Microsoft Copilot, 2025-10-11** (Privacy Policy). New: "In certain markets, we use conversation data to train the generative AI models in Copilot, unless you choose to opt-out of such training." First statement that consumer Copilot conversations train models.
4. **GitHub Copilot, 2026-04-27** (Terms of Service). "For GitHub Copilot Free users, the data collected ... may be used for AI Model training where permitted and if you allow in your settings" became a licence to GitHub *and its Affiliates* to use Your Content "for the purpose of training, developing, and improving artificial intelligence and machine learning models", including private-repository inputs to AI features, opt-out via section J.3. Affiliates may use Inputs and Outputs unless you opt out; sharing with third-party model providers is excluded.
5. **Grok (xAI enterprise), 2026-05-18** (Commercial Terms). "User Content is automatically deleted within 30 days" removed. De-identified data may now be used "for any lawful purpose" and xAI "will own all right, title, and interest" in it. The no-training promise on User Content survives but "subject to Section 3.2" is gone and it is now qualified by Zero Data Retention election.
6. **Grok, 2026-05-18** (Privacy Policy). New carve-out: content from Google Apps connected via OAuth "shall not" be used for training.
7. **Cursor, 2025-06-14** (Terms of Service). The Privacy Mode paragraph became "ANYSPHERE WILL NOT USE CONTENT TO TRAIN, OR ALLOW ANY THIRD PARTY TO TRAIN, ANY AI MODELS, UNLESS YOU'VE EXPLICITLY AGREED". Same default, stronger form, third parties now covered.
8. **Codeium / Windsurf, 2026-07-01** (Terms of Service, after the Cognition acquisition). Removed: "We will never use your Autocomplete User Content to improve generative machine learning models", the anonymisation promise, and a settings opt-out for all users. Added: "Cognition may use Customer Data for model training purposes"; opt-out only "if you subscribe to a paid Service Tier", and on Teams only an administrator may exercise it. Free users lost their opt-out.
9. **DeepSeek, 2025-02-23** (Privacy Policy). First explicit training purpose: "to train and improve our technology, such as our machine learning models and algorithms", plus public internet data "in order to train our models". Before this the policy said only "review, improve".
10. **DeepSeek, 2025-12-23** (Privacy Policy). New right: "to opt-out of using your Personal Data for training our models or optimizing our technologies."
11. **ChatGPT, 2026-05-18** (Privacy Policy). Removed: "We don't use your content to market our services or create advertising profiles of you—we use it to make our models more helpful." Ads personalisation added. Training default unchanged; the use-of-inputs promise narrowed. Counted because the removed sentence was part of the training clause.
12. **ChatGPT, 2026-08-25** (Privacy Policy). "Usage Data (including ads data)" added to the data listed under "improve and develop our Services ... when we train and improve our models". Generic ads for Free and Go users. Borderline between scope and position; listed here because it widens the training input list.

## Scope changes (real, small, worth a dated line on the vendor page)

- ChatGPT Business Privacy 2025-11-20: "ChatGPT for Teachers" added to the not-trained-by-default list.
- ChatGPT Business Privacy 2026-01-09: "ChatGPT for Healthcare" added; "connectors" renamed "apps".
- Claude.ai ToS 2025-11-28: "and to develop other products and services" re-added to the use-of-Materials sentence.
- Claude.ai Privacy 2026-06-08: "train Anthropic AI models" (was "our models"); transfer to US servers "to train our models" stated; Study Participation Data added.
- Microsoft Copilot Privacy 2025-07-15: "Xbox's AI-enhanced features do not use children's data for model training."
- Codeium ToS 2025-05-09: models labelled "(no ZDR)" let the provider store Customer Data; Recipes, Trajectory Sharing, Deploys, Reviews, Knowledge Base added to the persistent-storage list.
- Codeium ToS 2025-02-25: "These limits supersede the usage rights in Section 10"; Web Retrieval added.
- DeepSeek Privacy 2026-02-10: corporate-group entities perform "foundation model training and optimization" on user data.

## Disclosures (position unchanged; good quote material, not change events)

- ChatGPT Privacy 2024-06-10: purpose table introduced, legal basis "legitimate interests ... broader society ... when we train our models".
- ChatGPT Privacy 2025-07-31: long new section stating the default in plain words ("ChatGPT ... improves by further training on the conversations people have with it, unless you opt out"), Sora and Operator included, Temporary Chat excluded. Best quotable statement of the OpenAI consumer default.
- Claude.ai Privacy 2025-09-01: model-training notice paragraphs enter the policy.
- Claude.ai Privacy 2025-11-01: legal-basis table for training.
- Claude.ai Privacy 2026-07-08: "Notice" becomes "Policy"; pre-training and refinement stages described.
- Grok Privacy 2025-08-01: covered under event 2.
- DeepSeek Privacy 2026-02-10: covered under scope.

## Wording only

ChatGPT Business 2025-08-30 (Team to Business); ChatGPT P2B 2024-07-23 (believes/believe); ChatGPT Privacy 2024-08-20, 2024-11-05 ("may use", bullets); ChatGPT ToS 2024-06-10, 2025-05-17 (opt-out link text); Claude.ai Privacy 2025-09-27, 2026-01-12 ("for example for"); Grok Privacy 2025-12-10; Cursor ToS 2025-04-19 ("opt-in to allow" to "allow", default unchanged); Codeium ToS 2025-04-08 (Windsurf rename), 2025-06-10 (definitions, e-mail opt-out route dropped), 2026-04-15 (Devin added to list); DeepSeek Privacy 2025-04-28 ("information" to "Personal Data").

## Locator churn (the report says "changed", the document's clause did not)

- ChatGPT Privacy 2026-09-17: reported the Temporary Chat sentence removed. Corpus commit `7346836` still contains it, three times, before and after. False removal.
- ChatGPT Privacy 2026-07-15: an ad-controls sentence really was removed (commit `a7b3532`), but it is not the training clause.
- Claude.ai Commercial Terms 2026-03-12: indemnification paragraphs dropped out of the block set.
- Cursor ToS 2025-06-19: "Limitations for Suggestions" paragraph re-entered the block set after the 06-14 restructure.
- DeepSeek Privacy 2025-07-04 and 2025-07-18: the same legal-basis table left and returned. Two transitions, zero change.

## Not about training

- Le Chat Privacy 2025-09-03: Memory feature row. Le Chat ToS 2025-10-08: sub-processor list. (Second one also churn.)

## Vendors with no position change in the window

Perplexity, Jasper, Le Chat: located, clause stable. Google and Midjourney: not located (corpus gap, see STATUS.md). Every located vendor except those three has at least one dated event above.
