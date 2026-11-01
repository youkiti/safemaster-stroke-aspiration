# Stroke inpatient aspiration and choking study

Classification and analysis materials for a descriptive study of aspiration and choking during food or fluid intake in stroke inpatients, using national adverse-event reports in Japan (lead author: Tatsuya Tanaka). The associated paper is in preparation.

This repository provides the search strategy, Japanese AI classification prompt, classification criteria, English translations and analysis code. It contains no source incident reports or review application judgement logs. Access to the report dataset alone is sufficient to reproduce candidate searches, but the final analyses also require the original review inputs and their provenance records.

## Contents

All study files are under `projects/tanaka_stroke_aspiration/`:

| Location | Contents |
|---|---|
| `analysis/candidates.R`, `analysis/01_feasibility_counts.R` | Search terms, structured-code filters and candidate counts |
| `analysis/ai_prompt_stage2_v2.md`, `analysis/ai_prompt_stage2_v2_en.md` | Prompt actually used in Japanese and a translation for readers |
| `criteria/classification_criteria_v2_ja.md`, `criteria/classification_criteria_v2_en.md` | Classification criteria and a translation for readers |
| `analysis/review_codebook.csv` | Permitted classification values and definitions |
| `analysis/code_labels.csv`, `analysis/factor_labels.csv` | Structured-code labels and reporting labels |
| `analysis/02_review_sheets.R`, `analysis/03_app_intake.R` | Review workbook generation and judgement-log intake |
| `analysis/04a_pilot10_gold_v2.py`, `analysis/04_ai_v2_check.py` | Revised pilot reference values and AI output validation/voting |
| `analysis/05_stage2_rest_sheets.py`, `analysis/05b_stage2_final.R` | Assignment of remaining cases and final classification assembly |
| `analysis/stage2_exclusions.csv` | Two additional exclusions identified during classification |
| `analysis/derive_cohort.R`, `analysis/report.Rmd` | Cohort derivation and the descriptive tables and figures |
| `analysis/06_ai_agreement.R` | Agreement of the AI draft with the pilot reference classification and run-to-run disagreement |
| `analysis/render_report.R` | Report build entry point |
| `analysis/make_synth_fixture.R` | Synthetic judgement fixtures for the earlier review stages |

Repository-level `shared/` contains the column-access helpers, flow-diagram functions and workbook builder used by these scripts. Generated files belong in the project's `output/` directory, which is excluded from version control.

## Data and prerequisites

Reports originate from the public database of the Japan Council for Quality Health Care (JCQHC), [Project to Collect Medical Near-Miss/Adverse Event Information](https://www.med-safe.jp/). Obtain the reports from that service under its applicable terms. Source reports, synthetic source data and derived review outputs are not distributed here. This repository does not contain a downloader or a converter from public database exports to the study's r19 schema.

For production runs, place `safemaster_r19_text.rds` in the repository-level `data/` directory. This must be an RDS data frame of the 2013–2024 r19 reports, read with **every column as character**, duplicate column names made unique with `make.unique`, and dictionary-defined unknown codes already converted to `NA`. Blank values and the string `.` represent missing data; the loaders also replace `.` with `NA`. Preserve the r19 column names and code system, including `患者区分 = 2` for inpatients. The newer 2013–2025 dataset has a different schema and inpatient coding and cannot be substituted. Production checks expect 54,310 reports, 48,441 inpatient reports and candidate tiers T1–T4 of 10, 39, 85 and 134.

The scripts use R with `dplyr`, `ggplot2`, `gtsummary`, `readxl`, `writexl`, `rmarkdown` and `knitr`, plus Pandoc for rendering. Python scripts use Python 3; workbook generation additionally requires `openpyxl`. A Japanese-capable font is needed for Japanese figure labels. On Windows, the report wrapper advises unsetting `LC_ALL`, `LANG` and `LC_CTYPE` before starting Rscript.

For synthetic runs (without `--prod`), set `SAFEMASTER_DIR` to a directory containing `記述研究のときのレガシーファイル/架空データ100行_r19.csv`. This variable is required only for synthetic data; there is no machine-specific default. The CSV must use the r19 schema and is not included. Synthetic fixtures support the earlier review stages; they do not supply the complete final-stage inputs required by `05b_stage2_final.R` or the report.

## Execution order

Start in `projects/tanaka_stroke_aspiration/` for the following commands. Commands are separate steps: review inputs must be supplied between them.

1. Count search candidates and create the stage 1 eligibility workbook:

   ```text
   Rscript analysis/01_feasibility_counts.R --prod
   Rscript analysis/02_review_sheets.R --prod --stage1
   ```

2. Two reviewers independently assessed eligibility in the review application. Judgement logs from the review application are not included. With the original logs saved as `output/prod_app_judgment_log_stage1_reviewer1.csv` and `output/prod_app_judgment_log_stage1_reviewer2.csv`, run:

   ```text
   Rscript analysis/03_app_intake.R --prod --stage1
   ```

   Resolve eligibility disagreements in `output/prod_consensus_stage1.csv` using the disagreement file's schema and rerun the same command. It writes `prod_final_eligibility.csv` and the stage 1 checksum stamp. The original review included 48 of 134 candidates.

3. Generate the stage 2 workbook:

   ```text
   Rscript analysis/02_review_sheets.R --prod --stage2
   ```

   The original process used a 10-case pilot assessed independently by two reviewers, followed by consensus and revised v2 reference values. Supply the original pilot IDs (`output/prod_stage2_pilot10_ids.csv`), stage 2 logs (`output/prod_app_judgment_log_stage2_reviewer1.csv` and `..._reviewer2.csv`) and consensus (`output/prod_consensus_stage2.csv`). The pilot selection and application-based consensus workflow are not automated here. With these inputs available, run:

   ```text
   python -I -X utf8 analysis/04a_pilot10_gold_v2.py
   Rscript analysis/03_app_intake.R --prod --stage2
   ```

   The pilot reference script updates the consensus file and applies the recorded case-specific v2 corrections. It is intended for the original pilot inputs, not an arbitrary new sample. Stage 2 intake calculates pilot agreement and determinability; final classification is assembled later.

4. AI draft classification used **Claude Sonnet 5.5**, model identifier `claude-sonnet-5-5`, in three independent runs with the Japanese prompt. Responses contain 11 values, source fields and supporting quotations. The AI invocation and case-JSONL export process are not included; prepare JSONL cases in the prompt's format and obtain three independent response files. Validate them and take an item-level majority vote, for example:

   ```text
   python -I -X utf8 analysis/04_ai_v2_check.py --cases output/ai_v2/cases_rest38.jsonl --ai output/ai_v2/run1.jsonl output/ai_v2/run2.jsonl output/ai_v2/run3.jsonl --out output/ai_v2/ai_rest38_vote.csv
   ```

   `04_ai_v2_check.py` checks case IDs, required items, permitted values, conditional blanks, staff-number format and quotation presence in the source field (ignoring whitespace). It leaves items without a majority blank and reports them. For the pilot, run the same checker with the pilot case and response files, `--gold output/prod_stage2_pilot10_gold_v2.csv` and `--out output/ai_v2/ai_pilot10_r5vote.csv`. `06_ai_agreement.R` reads that pilot vote file and `output/ai_v2/ai_rest38_vote.csv`. Pilot performance after revising the criteria is not independent external validation.

5. Set `SAFEMASTER_REVIEWER_TANAKA` and `SAFEMASTER_REVIEWER_SUEHIRO` to the intended reviewer email addresses in your local environment, then generate the remaining-case workbooks:

   ```text
   python -I -X utf8 analysis/05_stage2_rest_sheets.py
   ```

   This assigns 38 cases to two groups of 19 using the original fixed seed. Each case's AI draft was checked and corrected by one reviewer. The generated assignment CSV contains the configured reviewer addresses and belongs in the ignored `output/` directory.

   Google Sheets publishing, application deployment and review collection are not included. The original external workflow used `shared/review_app/publish.py`, `intake.py`, `independent.py` and `consensus.py`; these tools are absent. Supply the original returned `final.csv` and `diff.csv` files in `output/stage2_rest_intake_田中/` and `output/stage2_rest_intake_末廣/` to continue. Their required columns are checked by `05b_stage2_final.R`. Original distribution manifests and judgement logs are not included.

6. Assemble final classifications, including the two recorded additional exclusions:

   ```text
   Rscript analysis/03_app_intake.R --prod --stage2
   Rscript analysis/05b_stage2_final.R --prod
   ```

   The expected final cohort contains 46 reports. `candidates.R` defines the complete input lists in `stage1_stamp_files()` and `stage2_stamp_files()`. MD5 stamps tie results to the exact input files. Preserve original review workbooks and logs byte for byte when reusing their stamps. This public version removes a mail reference from `analysis/stage2_exclusions.csv`, so an original final-stage stamp will not match that file. With the complete original review inputs, rerun these two commands to regenerate the final classification and stamp; do not bypass the checksum checks.

Return to the repository root to build the tables, figures and AI agreement summary:

```text
Rscript projects/tanaka_stroke_aspiration/analysis/render_report.R --prod
Rscript projects/tanaka_stroke_aspiration/analysis/06_ai_agreement.R --prod
```

The report produces `prod_report.html` and `prod_report.docx`; the AI agreement script produces `prod_ai_agreement.csv` and `prod_ai_summary.md`, all in `projects/tanaka_stroke_aspiration/output/`. Both use `derive_cohort.R` and require the original review inputs and valid stamps. `Sys.glob("projects/tanaka_*")` resolves the renamed study directory.

For clarity, the files required by the stamp checks are listed below. All paths in this list are relative to the project's `output/` directory, except the two explicitly labelled analysis files. These generated or collected files are not distributed:

- Stage 1: `prod_app_judgment_log_stage1_reviewer1.csv`, `prod_app_judgment_log_stage1_reviewer2.csv`, `prod_consensus_stage1.csv` (optional when no consensus is needed), `prod_review_sheets_stage1.xlsx`, `prod_final_eligibility.csv` and `prod_intake_stamp_stage1.csv`. Stage 2 intake also reads `prod_agreement_stage1.csv`.
- Stage 2: `prod_app_judgment_log_stage2_reviewer1.csv`, `prod_app_judgment_log_stage2_reviewer2.csv`, `prod_consensus_stage2.csv`, `prod_stage2_pilot10_ids.csv`, `prod_stage2_pilot10_gold_v2.csv`, `prod_stage2_pilot10_gold_v2_stamp.csv`, `stage2_rest_intake_田中/final.csv`, `stage2_rest_intake_田中/diff.csv`, `stage2_rest_intake_末廣/final.csv`, `stage2_rest_intake_末廣/diff.csv`, `prod_agreement.csv`, `prod_determinable.csv`, `prod_stage2_review_changes.csv`, `prod_final_classification.csv` and `prod_intake_stamp.csv`. Stage 2 also checks the stage 1 final eligibility and stamp, plus the included `analysis/stage2_exclusions.csv` and `analysis/review_codebook.csv`.
- Workbook preparation and AI validation additionally require `prod_review_sheets_stage2.xlsx`, case JSONL files, independent AI response JSONL files and the two AI vote CSV files described above.

References to the absent `docs/severity-definition.md` and `shared/review_app/selftest.py` have been removed from code comments. The original project README and proposal directory are not included.

## Licensing

Code is available under the [MIT licence](LICENSE), copyright 2026 Yuki Kataoka and Tatsuya Tanaka. The prompt files `analysis/ai_prompt_stage2_v2*.md`, all files under `criteria/`, and `analysis/review_codebook.csv` are licensed under [CC BY 4.0](LICENSE-docs.md). These paths are relative to the study directory. Translations are provided for readers; the Japanese prompt was the one actually used.

Repository licences do not grant rights to JCQHC source data or judgement logs.

## Citation

Archived at Zenodo: https://doi.org/10.5281/zenodo.23857493 (version 1.0.0).

Please cite the associated manuscript: 〔citation to be added〕. When reusing the prompts or criteria, credit Yuki Kataoka and Tatsuya Tanaka, link to this repository and the CC BY 4.0 licence, and indicate any changes, including translation.
