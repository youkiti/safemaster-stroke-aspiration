# tanaka_stroke_aspiration: AI 下書き（独立3回の項目別多数決）の一致と、実行間の割れを集計する。
#
# 入力（output/ 配下）:
#   ai_v2/ai_pilot10_r5vote.csv        試行10件に最終プロンプトを3回流した多数決（04_ai_v2_check.py の出力）
#   prod_stage2_pilot10_gold_v2.csv    試行10件の合議と改訂基準による参照分類（04a_pilot10_gold_v2.py の出力）
#   ai_v2/ai_rest38_vote.csv           残り38件の多数決（列「回ごとに割れた項目」「過半数なし」を含む）
#   derive_cohort.R が読む最終分類と、AI 下書きからの変更集計（prod_stage2_review_changes.csv）
# 出力:
#   output/prod_ai_agreement.csv       項目別の一致数（試行10件、空と空は一致として数える）
#   output/prod_ai_summary.md          一致・割れ・過半数なし・確認での変更の件数
# 試行10件はプロンプトを調整したのと同じ事例なので、一致は見かけの性能である。
# 実行（リポジトリ直下）: Rscript projects/tanaka_stroke_aspiration/analysis/06_ai_agreement.R --prod

prod <- "--prod" %in% commandArgs(trailingOnly = TRUE)
stopifnot(prod)
project <- Sys.glob("projects/tanaka_*")
project <- project[file.exists(file.path(project, "analysis", "candidates.R"))]
stopifnot(length(project) == 1L)
source(file.path(project, "analysis", "derive_cohort.R"))

ai_items <- c("脳卒中の位置づけ", "脳卒中病型", "事故類型", "摂取物", "摂食介助状況", "同席状況",
              "嚥下評価", "指示逸脱", "食事区分", "救命介入", "直接介助者の当事者番号")
ai_item_en <- c("Role of stroke", "Stroke type", "Event type", "Material taken", "Feeding assistance",
                "Presence of others", "Swallowing assessment", "Instruction deviation", "Meal",
                "Rescue intervention", "Direct assistant identifiers")
read_ai <- function(name, required) {
  x <- read.csv(file.path(OUT_DIR, name), colClasses = "character", check.names = FALSE,
                fileEncoding = "UTF-8-BOM", na.strings = character(0), stringsAsFactors = FALSE)
  stopifnot(all(required %in% names(x)), !anyDuplicated(x$事例ID),
            all(nzchar(x$事例ID)), !anyNA(x))
  x
}
ai_pilot <- read_ai("ai_v2/ai_pilot10_r5vote.csv", c("事例ID", ai_items))
ai_gold <- read_ai("prod_stage2_pilot10_gold_v2.csv", c("事例ID", ai_items))
ai_rest <- read_ai("ai_v2/ai_rest38_vote.csv",
                   c("事例ID", ai_items, "回ごとに割れた項目", "過半数なし"))
stopifnot(setequal(ai_pilot$事例ID, ai_gold$事例ID), nrow(ai_pilot) == n_pilot,
          nrow(ai_rest) == n_rest_review, !any(ai_rest$事例ID %in% ai_pilot$事例ID))
ai_gold <- ai_gold[match(ai_pilot$事例ID, ai_gold$事例ID), , drop = FALSE]
ai_match <- as.matrix(ai_pilot[ai_items]) == as.matrix(ai_gold[ai_items])
n_ai_agree <- sum(ai_match)
n_ai_items <- length(ai_match)
ai_agreement <- data.frame(Item = ai_item_en, Agreed = colSums(ai_match),
                           Compared = nrow(ai_match), check.names = FALSE)
count_items <- function(x) {
  vapply(x, function(s) if (!nzchar(trimws(s))) 0L else length(strsplit(s, " / ", fixed = TRUE)[[1]]), 1L)
}
n_ai_rest <- nrow(ai_rest)
n_ai_split_cases <- sum(nzchar(trimws(ai_rest$回ごとに割れた項目)))
n_ai_split_items <- sum(count_items(ai_rest$回ごとに割れた項目))
n_ai_no_majority <- sum(count_items(ai_rest$過半数なし))
n_meal_changed <- as.integer(review_changes$changed[review_changes$item == "食事区分"])
stopifnot(length(n_meal_changed) == 1L)

write.csv(ai_agreement, file.path(OUT_DIR, "prod_ai_agreement.csv"), row.names = FALSE, fileEncoding = "UTF-8")
lines <- c(
  "# AI draft classification: agreement and run-to-run disagreement (prod)",
  "",
  sprintf("- Pilot: final AI majority agreed with the reference classification on %d of %d item decisions (%d reports x %d items; matching blanks count as agreement). Apparent performance: the prompt was refined on the same reports.",
          n_ai_agree, n_ai_items, nrow(ai_pilot), length(ai_items)),
  sprintf("- Remaining reports: %d; reports with run-to-run disagreement on at least one item: %d; disagreeing item decisions: %d; items without a majority: %d.",
          n_ai_rest, n_ai_split_cases, n_ai_split_items, n_ai_no_majority),
  sprintf("- Single-reviewer check of retained reports: %d of %d saved item fields changed or filled; meal category changed in %d reports.",
          n_review_changed, n_review_items, n_meal_changed),
  "",
  "Per-item agreement on the pilot is in prod_ai_agreement.csv."
)
con <- file(file.path(OUT_DIR, "prod_ai_summary.md"), "wb")
writeBin(charToRaw(enc2utf8(paste0(paste(lines, collapse = "\n"), "\n"))), con)
close(con)
cat("done: 06_ai_agreement.R\n")
