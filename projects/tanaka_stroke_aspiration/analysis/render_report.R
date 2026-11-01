# Render the descriptive report (html and docx) from the repository root.
# Run: Rscript projects/tanaka_*/analysis/render_report.R          (synthetic 100-row data)
#      Rscript projects/tanaka_*/analysis/render_report.R --prod   (production r19)
# Resolve the project folder with Sys.glob.
# Unset LC_ALL, LANG and LC_CTYPE before running Rscript on Windows.
# Outputs: output/{synth,prod}_report.html and output/{synth,prod}_report.docx.
# The report needs output/{prefix}_final_classification.csv from analysis/05b_stage2_final.R.
root <- normalizePath(".", winslash = "/", mustWork = TRUE)
stopifnot(file.exists(file.path(root, "README.md")),
          file.exists(file.path(root, "shared", "safe_cols.R")))
project <- Sys.glob("projects/tanaka_*")
project <- project[file.exists(file.path(project, "analysis", "candidates.R"))]
stopifnot(length(project) == 1L)
# prod is the flag shared with derive_cohort.R; it must be a top-level logical (never assigned with <<-)
prod <- "--prod" %in% commandArgs(trailingOnly = TRUE)
prefix <- if (prod) "prod" else "synth"
outdir <- file.path(root, project, "output")
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)
rmd <- file.path(project, "analysis/report.Rmd")
rmarkdown::render(rmd, output_format = rmarkdown::html_document(toc = TRUE, self_contained = TRUE),
  output_file = paste0(prefix, "_report.html"), output_dir = outdir, knit_root_dir = root, envir = globalenv())
rmarkdown::render(rmd, output_format = rmarkdown::word_document(),
  output_file = paste0(prefix, "_report.docx"), output_dir = outdir, knit_root_dir = root, envir = globalenv())
