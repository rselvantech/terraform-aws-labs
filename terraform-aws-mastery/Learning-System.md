# Terraform AWS Mastery — Learning System

> Last updated: Demo 00 complete and committed.
> All decisions below are locked based on Demo 00 experience.

---

## Why This System Exists

You can complete 29 demos, understand every concept in context, and still
freeze under production pressure — because knowing something while reading
is not the same as recalling it cold when a pipeline fails at 2am.

This system uses four reinforcement layers from learning science:

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  LAYER 1 — ANKI (Spaced Repetition)                                 │
│  Every concept, command, and behaviour across all 29 demos.          │
│  15 min daily review. After 60 days: automatic recall.              │
│                                                                      │
│  LAYER 2 — SPACED RECALL (Retrieval Practice)                        │
│  3 questions from the previous demo at the START of each new demo.   │
│  Forces cold recall before new content. Struggle = learning.        │
│                                                                      │
│  LAYER 3 — BREAK-FIX (Diagnostic Skill)                             │
│  One deliberately broken config per demo.                            │
│  Diagnose using error messages only. Builds production reflexes.    │
│                                                                      │
│  LAYER 4 — QUIZ (Cert Simulation)                                    │
│  5-10 TA-004 style MCQ per demo.                                     │
│  Same format, same traps as the real exam.                          │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘

Each layer is unique — they reinforce, not repeat each other:

  Anki         = breadth recall — everything, spaced over time
  Spaced recall = retrieval practice — previous demo highlights, cold recall
  Break-fix    = diagnostic skill — real error patterns under pressure
  Quiz         = cert simulation — MCQ format, TA-004 exam traps
```

---

## Setup — One Time (Windows + Android)

| Platform | App | Cost | Where |
|---|---|---|---|
| Windows desktop | **Anki Desktop** | Free | [apps.ankiweb.net](https://apps.ankiweb.net) |
| Android mobile | **AnkiDroid** | Free | Google Play Store |
| Sync between both | **AnkiWeb account** | Free | [ankiweb.net](https://ankiweb.net) |

> ⚠️ Beware fake "Anki" apps on app stores charging subscriptions.
> Legitimate apps only: Anki Desktop, AnkiDroid (developer: AnkiDroid
> Open Source Team), AnkiWeb (browser free), AnkiMobile (iOS $24.99 one-time).

```
1. Install Anki Desktop on Windows
   → apps.ankiweb.net → download .exe → install

2. Create free sync account
   → ankiweb.net → Sign Up

3. Connect desktop to AnkiWeb
   → Anki Desktop → Tools → Preferences → Syncing → log in
   → click cloud icon in toolbar to sync

4. Set daily card limits to unlimited (do this FIRST — one time)
   → gear ⚙ next to "Terraform AWS Mastery" deck → Options
   → New cards/day: 9999
   → Maximum reviews/day: 9999
   → Save  (cascades to all subdecks automatically)

5. Install AnkiDroid on Android
   → Play Store → search "AnkiDroid" → Install
   → Settings → AnkiDroid → Sync account → log in same credentials

Done. Changes on Windows sync to Android automatically.
```

---

## Layer 1 — Anki: Spaced Repetition

### One File Per Demo

Every demo produces one Anki CSV named after the demo folder:

```
00-tf-hcl-basics/
├── README.md
├── 00-tf-hcl-basics-anki.csv     ← import into Anki
└── 00-tf-hcl-basics-quiz.md
```

### CSV File Format

Every CSV has a 3-line header that auto-creates the subdeck hierarchy:

```
#deck:Terraform AWS Mastery::Phase 1 - Foundations::00-tf-hcl-basics
#separator:Comma
#columns:Front,Back,Tags
"Front question","Back answer","demo00,tag,ta004-obj1"
```

The `::` separator in the deck name creates nested subdecks automatically
on import — no manual deck creation needed.

### Import Workflow

```
1. Open Anki Desktop
2. File → Import
3. Select NN-demo-name-anki.csv
4. Verify: Field separator = Comma
5. Click Import
   → subdecks created automatically from #deck header
6. Click cloud icon → sync to AnkiDroid
```

### Anki Deck Hierarchy

```
Terraform AWS Mastery                     ← review ALL cards from here
├── Phase 1 - Foundations
│   ├── 00-tf-hcl-basics                  ← ~34 cards
│   ├── 01-tf-fundamentals-s3
│   └── ...
├── Phase 2 - Modules
├── Phase 3 - AWS Patterns
├── Phase 4 - HCP & CI/CD
└── Phase 5 - Advanced
```

### Storage and Limits — Confirmed Facts

- **AnkiWeb free storage:** 100MB compressed / 250MB uncompressed
  (text + scheduling data only — not media)
- **Our cards:** pure text, no images, no audio
- **Estimated usage:** ~34 cards/demo × 29 demos = ~1,000 cards
  ≈ 1.5MB — well within free limits even with 5 additional DevOps series
- **Daily card limit:** default is 20 new/day — change to 9999 (see setup above)
- **Multiple series:** all DevOps topic series fit in one free AnkiWeb
  account with room to spare

### Card Design Principle — Scenario-First

Cards use scenario-based questions — the same mental model triggered
under production pressure:

```
❌ Definition-first (weak recall):
   Front: "Define idempotency"
   Back:  "Same operation multiple times = same result"

✅ Scenario-first (strong recall):
   Front: "You run terraform apply twice with no config changes.
           What happens on the second run and why?"
   Back:  "Plan shows 0 to add, 0 to change, 0 to destroy.
           No API calls made. Terraform compares desired state (.tf)
           against current state (.tfstate), finds no diff.
           This is idempotency."
```

### Daily Review Habit

```
Time:    15 minutes — morning, before demos or work
Goal:    Clear the daily review queue to zero
Import:  Add each demo's cards immediately after completing the demo
Sync:    Cloud sync after every import

After 30 days:  commands recalled without looking up
After 60 days:  concepts are automatic — cert exam ready
```

### Master CSV — Generated End of Each Phase

Per-demo CSVs are the primary workflow. Phase master files for fresh
installs or sharing:

| Trigger | File | Cards (approx) |
|---|---|---|
| End Phase 1 (Demo 08) | `phase-1-master-anki.csv` | ~240 cards |
| End Phase 2 (Demo 13) | `phase-2-master-anki.csv` | ~150 cards |
| End Phase 3 (Demo 20) | `phase-3-master-anki.csv` | ~200 cards |
| End Phase 4 (Demo 24) | `phase-4-master-anki.csv` | ~120 cards |
| Series complete | `terraform-aws-mastery-master-anki.csv` | ~700+ cards |

---

## Layer 2 — Spaced Recall: Retrieval Practice

Each demo README begins with **3 questions from the previous demo**.
Answer from memory before reading anything new. Struggling is the
mechanism — retrieval under difficulty strengthens memory more than
re-reading.

### Format in Every README

```markdown
## Recall Check

Answer from memory before reading:

1. [Question referencing previous demo concept]
2. [Question referencing previous demo command/behaviour]
3. [Question referencing previous demo decision/rule]

<details>
<summary>Answers</summary>
...
</details>
```

Demo 00 has no prior demo — its recall check is a forward reference,
asking the reader to return and answer after completing Demo 00.

---

## Layer 3 — Break-Fix: Diagnostic Skill

### What It Is

Every demo ends with a deliberately broken configuration. Diagnose
and fix using only `terraform validate`, `terraform plan`, and the
error messages. Never look at answers first.

### Directory Convention — Locked

```
src/
├── versions.tf          ← working lab files
├── variables.tf
├── main.tf
├── outputs.tf
└── break-fix/           ← separate directory — always
    └── broken.tf        ← ALL break-fix code in ONE file including
                            terraform {} block inline at top
```

**Why one file only (`broken.tf`):**
- `fill_files.sh` indexes files by basename — a `versions.tf` in
  `break-fix/` would collide with `src/versions.tf` and write wrong content
- Simpler: one file, self-contained, includes its own `terraform {}` block

**Why separate directory:**
A broken config in the same directory blocks `terraform apply` on the
working lab. Always isolate.

### Protocol

```
1. Read the broken config in the README
2. Do NOT look at the answers
3. cd src/break-fix/
4. terraform init
5. terraform validate    ← catches syntax errors
6. terraform plan        ← catches schema and reference errors
7. Read error messages carefully
8. Edit broken.tf to fix each error
9. Repeat until both validate and plan are clean
10. Reveal answers in <details> block to compare
```

---

## Layer 4 — Quiz: Cert Exam Simulation

### One File Per Demo

```
00-tf-hcl-basics/
├── README.md
├── 00-tf-hcl-basics-anki.csv
└── 00-tf-hcl-basics-quiz.md     ← standalone quiz file
```

### Format

- 8-10 questions per demo, TA-004 exam style
- One correct answer per question unless stated
- Plausible distractors — same traps as the real exam
- Answer in `<details>` collapse — attempt before revealing
- Explanation covers WHY wrong answers are wrong (not just right answer)

### When to Use

```
After completing the demo lab:   attempt the quiz cold
Score below 80%:                 re-read relevant README section, retry
Score 80% or above:              proceed to next demo
End of each phase:               all phase quizzes back-to-back timed
Cert prep (last 2 weeks):        all quizzes at 1.5 min/question pace
```

### Score Guide

| Score | Action |
|---|---|
| 100% | Solid — proceed |
| 80–90% | Good — review wrong answers in Anki |
| 60–70% | Re-read relevant sections, retry |
| Below 60% | Re-read full demo before proceeding |

---

## Files Per Demo — Final Locked Structure

Every demo produces exactly **3 deliverable files**:

```
NN-demo-name/
├── README.md                      ← full demo content
│                                     theory + lab + break-fix + recall check
│                                     all .tf files embedded as labelled code blocks
│                                     anki CSV + quiz embedded as appendices
│                                     (appendices removed after create_files.sh run)
├── NN-demo-name-anki.csv          ← Anki cards with #deck subdeck header
└── NN-demo-name-quiz.md           ← standalone quiz (also in README appendix)
```

### README Appendix Workflow

```
1. README is generated with two appendix sections at the end:
   ## Appendix — Anki Cards   (contains the anki CSV content)
   ## Appendix — Quiz         (contains the quiz content)

2. Run create_files.sh from the demo root directory:
   bash ~/scripts/create_files.sh
   → creates directory tree from ## Directory Structure block
   → extracts all labelled files including anki CSV and quiz

3. Manually remove both appendix sections from README
   → README in the repo is the clean version without appendices

4. Commit: README.md + anki CSV + quiz.md + all .tf files
```

---

## create_files.sh — Script Rules (Locked)

Both scripts (`create_tree.sh` + `fill_files.sh`) have specific requirements
that every README must meet:

### Rule 1 — Directory Structure Comments Use `#` Not `←`

```
# CORRECT — script strips # comments
├── versions.tf             # terraform block + required_providers

# WRONG — script does NOT strip ← (Unicode U+2190)
├── versions.tf             ← terraform block + required_providers
```

The `clean_line` function uses regex `\s+#.*$` to strip comments.
The `←` character is Unicode and not matched by this regex — it becomes
part of the filename, breaking `create_tree.sh`.

### Rule 2 — File Label Format for fill_files.sh

Every `.tf` file section uses **two label lines** — both are required:

```markdown
#### `filename.tf` — Short description of what this file does
                     ↑ GitHub heading — human navigation, ignored by script

**Purpose:** explanation of what the file does...
**Why it matters:** explanation of why it is separate...

**filename.tf:**     ← fill_files.sh matches THIS line only
```hcl
...file content...
```
```

Rules:
- The `####` heading is for GitHub rendering and human navigation.
  `fill_files.sh` ignores it completely.
- The `**filename.tf:**` line is what `fill_files.sh` matches.
  It must be on its own line within 8 lines of the opening ``` fence.
- Explanation paragraphs go between the heading and the label line —
  this is fine as long as they are under 7 lines total.
- Never use one without the other — always both heading AND label.

Confirmed working from Demo 00 committed version on GitHub.

### Rule 3 — No Duplicate Filenames Across Directories

`fill_files.sh` indexes files by basename only — first found wins.
If `src/versions.tf` and `src/break-fix/versions.tf` both exist, the script
writes the wrong content to one of them.
**Solution:** break-fix uses only `broken.tf` (self-contained with inline
`terraform {}` block) — no other files in `break-fix/`.

### Rule 4 — Max 8 Lines Between Label and Fence

`fill_files.sh` uses a lookahead of max 8 lines between a label line
and the opening ` ``` ` fence. Keep any explanation text under 7 lines,
or put explanation after the code block.

---

## Cert Exam Preparation — Final 4 Weeks

```
Week -4:   All demos complete. All Anki decks imported. Queue current.

Week -3:   Full sweep of all Anki cards tagged ta004-*.
           Identify topics below 80% recall.
           Re-read README cert tips sections for weak areas.

Week -2:   All phase quizzes back-to-back, timed.
           Target pace: 1.5 minutes per question (57q / 60min).
           Flag any objective below 80%.

Week -1:   Targeted Anki review for flagged objectives only.
           One full mock exam: 57 questions, 60 minutes.
           Book exam at Certiverse.

Exam day:  TA-004 — 57 questions, 60 minutes, ~70% passing score.
           Online via Certiverse with live proctor.
           Valid 2 years. Recertification: retake exam.
```

---

## Demo and File Index

| Demo | Folder | Anki CSV | Quiz |
|---|---|---|---|
| 00 | `00-tf-hcl-basics` | `00-tf-hcl-basics-anki.csv` | `00-tf-hcl-basics-quiz.md` |
| 01 | `01-tf-fundamentals-s3` | `01-tf-fundamentals-s3-anki.csv` | `01-tf-fundamentals-s3-quiz.md` |
| 02 | `02-providers` | `02-providers-anki.csv` | `02-providers-quiz.md` |
| 03 | `03-core-workflow` | `03-core-workflow-anki.csv` | `03-core-workflow-quiz.md` |
| 04 | `04-state-backends` | `04-state-backends-anki.csv` | `04-state-backends-quiz.md` |
| 05 | `05-variables-locals-outputs` | `05-variables-locals-outputs-anki.csv` | `05-variables-locals-outputs-quiz.md` |
| 06 | `06-data-sources-expressions` | `06-data-sources-expressions-anki.csv` | `06-data-sources-expressions-quiz.md` |
| 07 | `07-functions` | `07-functions-anki.csv` | `07-functions-quiz.md` |
| 08 | `08-lifecycle-provisioners` | `08-lifecycle-provisioners-anki.csv` | `08-lifecycle-provisioners-quiz.md` |
| 09 | `09-modules-basics` | `09-modules-basics-anki.csv` | `09-modules-basics-quiz.md` |
| 10 | `10-public-registry-modules` | `10-public-registry-modules-anki.csv` | `10-public-registry-modules-quiz.md` |
| 11 | `11-vpc-module` | `11-vpc-module-anki.csv` | `11-vpc-module-quiz.md` |
| 12 | `12-three-tier-modules` | `12-three-tier-modules-anki.csv` | `12-three-tier-modules-quiz.md` |
| 13 | `13-workspaces` | `13-workspaces-anki.csv` | `13-workspaces-quiz.md` |
| 14 | `14-ecs-fargate` | `14-ecs-fargate-anki.csv` | `14-ecs-fargate-quiz.md` |
| 15 | `15-lambda-api-gateway` | `15-lambda-api-gateway-anki.csv` | `15-lambda-api-gateway-quiz.md` |
| 16 | `16-rds-postgresql` | `16-rds-postgresql-anki.csv` | `16-rds-postgresql-quiz.md` |
| 17 | `17-dynamodb` | `17-dynamodb-anki.csv` | `17-dynamodb-quiz.md` |
| 18 | `18-eks` | `18-eks-anki.csv` | `18-eks-quiz.md` |
| 19 | `19-cloudwatch-observability` | `19-cloudwatch-observability-anki.csv` | `19-cloudwatch-observability-quiz.md` |
| 20 | `20-iam-least-privilege` | `20-iam-least-privilege-anki.csv` | `20-iam-least-privilege-quiz.md` |
| 21 | `21-hcp-terraform` | `21-hcp-terraform-anki.csv` | `21-hcp-terraform-quiz.md` |
| 22 | `22-cicd-github-actions` | `22-cicd-github-actions-anki.csv` | `22-cicd-github-actions-quiz.md` |
| 23 | `23-policy-as-code` | `23-policy-as-code-anki.csv` | `23-policy-as-code-quiz.md` |
| 24 | `24-devsecops-scanning` | `24-devsecops-scanning-anki.csv` | `24-devsecops-scanning-quiz.md` |
| 25 | `25-remote-state-cross-stack` | `25-remote-state-cross-stack-anki.csv` | `25-remote-state-cross-stack-quiz.md` |
| 26 | `26-drift-import` | `26-drift-import-anki.csv` | `26-drift-import-quiz.md` |
| 27 | `27-terraform-testing` | `27-terraform-testing-anki.csv` | `27-terraform-testing-quiz.md` |
| 28 | `28-capstone` | `28-capstone-anki.csv` | `28-capstone-quiz.md` |