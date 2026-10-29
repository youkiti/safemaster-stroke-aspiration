# tanaka_stroke_aspiration: 試行10件の改訂基準による正解値と、AI 下書きの1名確認を統合する。
#
# 目的: 第1段階の適格性を維持し、第2段階で判明した不適格を運営決定で除外して最終分類を作る。
#   試行10件は2名の独立判定・合議後の v2 正解値、残り38件は AI 下書きを田中先生が確認した値を使う。
# 入力（TANAKA_OUT、既定 output。{prefix} は --prod なら prod、それ以外は synth）:
#   {prefix}_final_eligibility.csv / intake_stamp_stage1.csv（stage1_stamp_files で現物照合）,
#   {prefix}_stage2_pilot10_ids.csv / stage2_pilot10_gold_v2.csv,
#   stage2_rest_intake_{田中,末廣}/{final,diff}.csv, analysis/stage2_exclusions.csv,
#   {prefix}_app_judgment_log_stage2_reviewer{1,2}.csv / consensus_stage2.csv / agreement.csv / determinable.csv。
#   2名のログ・合議・一致度は先に 03_app_intake.R --stage2 で検証・更新する。
# 検証: 第1段階 stamp、ID の一意性と集合（試行10・残り38）、選択肢、当事者番号、必須9項目と
#   窒息の救命介入、未判定が運営除外だけであること、diff の全事例×11項目と final の整合。
#   失敗はファイル・項目・事例ID を名指しして stop。運営除外の分類値は使わない。
# 整形: 非窒息の救命介入を空にし、当事者番号は03と同じ表記補正・ソート・重複除去を行う。
# 出力（CSV は UTF-8 BOM、md は LF）:
#   {prefix}_final_classification.csv: 全候補、第1段階の順。事例ID,適格性,除外理由,11項目,一致。
#   {prefix}_stage2_review_changes.csv: 除外以外の残り事例の diff を item 別と total で集計。
#   {prefix}_intake_stamp.csv: stage2_stamp_files の全入力・最終分類・変更集計の md5（key,value）。
#   {prefix}_stage2_final_summary.md: 件数・由来・追加除外・変更集計・救命介入の整形。
# 古い最終結果と stamp は冒頭で削除し、すべての検証が通ったときだけ書く。
# 使い方（プロジェクト直下）:
#   Rscript analysis/03_app_intake.R --prod --stage2
#   Rscript analysis/05b_stage2_final.R --prod
#   TANAKA_OUT=/path/to/folder Rscript analysis/05b_stage2_final.R
# 合成入力が無い場合は停止する。本番の入力へフォールバックしない。

ARGS <- commandArgs(trailingOnly = TRUE)
PROD <- "--prod" %in% ARGS
PREFIX <- if (PROD) "prod" else "synth"
OUT <- Sys.getenv("TANAKA_OUT", "output")
source(file.path("analysis", "candidates.R"))
p <- function(s) file.path(OUT, paste0(PREFIX, "_", s))
FINAL_CSV <- p("final_classification.csv")
STAMP_CSV <- p("intake_stamp.csv")
for (f in c(FINAL_CSV, STAMP_CSV)) {
  if (file.exists(f) && !file.remove(f)) stop("古いファイルを消せない: ", f)
}
files <- stage2_stamp_files(OUT, PREFIX)
pilot10_gold_stamp_files <- function() {
  c(log_reviewer1 = p("app_judgment_log_stage2_reviewer1.csv"),
    log_reviewer2 = p("app_judgment_log_stage2_reviewer2.csv"),
    consensus = p("consensus_stage2.csv"),
    pilot10_ids = p("stage2_pilot10_ids.csv"),
    gold = p("stage2_pilot10_gold_v2.csv"))
}
bad <- stamp_problems(p("stage2_pilot10_gold_v2_stamp.csv"), pilot10_gold_stamp_files())
if (length(bad)) stop("試行10件の正解値が現在のログ・合議から作られていない。analysis/04a_pilot10_gold_v2.py を流し直す: ",
                      paste(bad, collapse = " ; "))
inputs <- files[!names(files) %in% c("final_classification", "review_changes")]
missing <- inputs[!file.exists(inputs)]
if (length(missing)) stop(if (PROD) "入力が無い: " else "合成データの入力が無い: ", paste(missing, collapse = ", "))
bad <- stamp_problems(p("intake_stamp_stage1.csv"), stage1_stamp_files(OUT, PREFIX))
if (length(bad)) stop("第1段階の stamp が現物と一致しない: ", paste(bad, collapse = " ; "))

REQ <- c("脳卒中の位置づけ", "脳卒中病型", "事故類型", "摂取物", "摂食介助状況",
         "同席状況", "嚥下評価", "指示逸脱", "食事区分")
FIELDS <- c(REQ, "救命介入", "直接介助者の当事者番号")
cb <- read_char_csv_bom(file.path("analysis", "review_codebook.csv"))
label_of <- function(v, code) {
  x <- cb$日本語ラベル[cb$変数 == v & cb$英語コード == code]
  if (length(x) != 1L) stop("review_codebook.csv: 選択肢が1行でない: ", v, "/", code)
  x
}
INC <- label_of("適格性", "include")
EXC <- label_of("適格性", "exclude")
CHOKE <- label_of("事故類型", "choking")
read_checked <- function(path, columns) {
  x <- read_char_csv_bom(path)
  if (anyDuplicated(names(x)) || !identical(names(x), columns)) stop(path, ": 列が想定と違う")
  if ("事例ID" %in% columns && (any(is_blank(x$事例ID)) || anyDuplicated(x$事例ID))) {
    stop(path, ": 事例ID が空または重複: ", paste(x$事例ID[is_blank(x$事例ID) | duplicated(x$事例ID)], collapse = ", "))
  }
  x
}
check_ids <- function(got, expected, path) {
  if (!setequal(got, expected)) stop(path, ": 事例ID が不一致。不足 [", paste(setdiff(expected, got), collapse = ","),
                                    "] / 余分 [", paste(setdiff(got, expected), collapse = ","), "]")
}
s1 <- read_checked(p("final_eligibility.csv"), c("事例ID", "適格性", "除外理由", "一致"))
if (any(!s1$適格性 %in% c(INC, EXC))) stop("final_eligibility.csv: 適格性が不正")
inc_ids <- s1$事例ID[s1$適格性 == INC]
if (PROD && (nrow(s1) != 134L || length(inc_ids) != 48L)) stop("final_eligibility.csv: 本番の134件・組入れ48件と一致しない")
ex <- read_checked(files[["stage2_exclusions"]], c("事例ID", "除外理由", "備考", "決定"))
if (any(!ex$事例ID %in% inc_ids)) stop("stage2_exclusions.csv: 第1段階の組入れに無い: ", paste(setdiff(ex$事例ID, inc_ids), collapse = ","))
if (any(!ex$除外理由 %in% cb$日本語ラベル[cb$変数 == "除外理由"])) stop("stage2_exclusions.csv: 除外理由が選択肢に無い")
pilot <- read_checked(p("stage2_pilot10_ids.csv"), "事例ID")
if (nrow(pilot) != 10L || any(!pilot$事例ID %in% inc_ids)) stop("stage2_pilot10_ids.csv: 第1段階の組入れの10件でない")
gold <- read_checked(p("stage2_pilot10_gold_v2.csv"), c("事例ID", FIELDS))
check_ids(gold$事例ID, pilot$事例ID, "stage2_pilot10_gold_v2.csv")
if (any(ex$事例ID %in% pilot$事例ID)) stop("stage2_exclusions.csv: 試行10件の除外は想定外")

rest <- lapply(c("rest_tanaka_final", "rest_suehiro_final"), function(k) {
  read_checked(files[[k]], c("tab", "事例ID", "status", "reviewer", "timestamp", "メモ", FIELDS))
})
r <- do.call(rbind, rest)
if (anyDuplicated(r$事例ID)) stop("残り final.csv: 2シートの事例ID が重複")
if (nrow(r) != 38L) stop("残り final.csv: 合わせて38件でない")
check_ids(r$事例ID, setdiff(inc_ids, pilot$事例ID), "残り final.csv")
bad <- r$事例ID[r$status != "judged" & !r$事例ID %in% ex$事例ID]
if (length(bad)) stop("残り final.csv: 除外以外の未判定: ", paste(bad, collapse = ","))
if (any(r$tab != "組入れ")) stop("残り final.csv: tab が組入れでない")

# diff は画面の保存値との対応を、整形前に照合する。除外行は集計しない。
changes <- c("kept", "changed", "filled", "unfilled")
diffs <- lapply(seq_along(rest), function(i) {
  path <- files[[c("rest_tanaka_diff", "rest_suehiro_diff")[i]]]
  x <- read_char_csv_bom(path)
  if (!identical(names(x), c("tab", "事例ID", "item", "draft", "final", "change"))) stop(path, ": 列が想定と違う")
  # 運営除外の事例は未判定（change = unjudged）のことがあるので、照合の前に外す。
  x <- x[!x$事例ID %in% ex$事例ID, , drop = FALSE]
  kept_ids <- setdiff(rest[[i]]$事例ID, ex$事例ID)
  key <- paste(x$事例ID, x$item, sep = "\t")
  expected <- as.vector(outer(kept_ids, FIELDS, paste, sep = "\t"))
  if (anyDuplicated(key) || !setequal(key, expected)) stop(path, ": 事例ID×11項目の過不足または重複")
  if (any(x$tab != "組入れ") || any(!x$change %in% changes)) stop(path, ": tab または change が不正")
  for (f in FIELDS) {
    j <- which(x$item == f)
    if (any(x$final[j] != rest[[i]][[f]][match(x$事例ID[j], rest[[i]]$事例ID)])) stop(path, ": final.csv と不一致: ", f)
  }
  expected_change <- ifelse(x$draft == "", ifelse(x$final == "", "unfilled", "filled"),
                            ifelse(x$final == x$draft, "kept", "changed"))
  if (any(x$change != expected_change)) stop(path, ": draft / final と change が不一致")
  x
})
diff <- do.call(rbind, diffs)
counts <- table(factor(diff$item, levels = FIELDS), factor(diff$change, levels = changes))
review_changes <- data.frame(item = FIELDS, as.data.frame.matrix(counts), check.names = FALSE, row.names = NULL)
review_changes <- rbind(review_changes, data.frame(item = "total", as.list(colSums(counts)), check.names = FALSE))

cleared <- character(0)
validate_values <- function(x, path, normalize_rescue = FALSE) {
  party <- "直接介助者の当事者番号"
  x[[party]] <- chartr("０１２３４５６７８９，、", "0123456789,,", x[[party]])
  x[[party]] <- sub("[.。．]+$", "", gsub("[[:space:]]", "", x[[party]]))
  for (i in seq_len(nrow(x))) {
    id <- x$事例ID[i]
    v <- x[[party]][i]
    if (v != "") {
      if (!grepl("^[0-9]+(,[0-9]+)*$", v)) stop(path, ": 当事者番号が不正: ", id, " / ", v)
      nums <- suppressWarnings(as.integer(strsplit(v, ",", fixed = TRUE)[[1]]))
      if (anyNA(nums) || any(!nums %in% 1:10)) stop(path, ": 当事者番号が1〜10でない: ", id)
      x[[party]][i] <- paste(sort(unique(nums)), collapse = ",")
    }
    if (x$事故類型[i] != CHOKE && x$救命介入[i] != "") {
      if (!normalize_rescue) stop(path, ": 非窒息なのに救命介入がある: ", id)
      cleared <<- c(cleared, id)
      x$救命介入[i] <- ""
    }
    for (f in c(REQ, "救命介入")) {
      v <- x[[f]][i]
      required <- f %in% REQ || x$事故類型[i] == CHOKE
      if ((required && is_blank(v)) || (v != "" && !v %in% cb$日本語ラベル[cb$変数 == f])) {
        stop(path, ": 必須項目が空または選択肢外: ", id, " / ", f, " / ", v)
      }
    }
  }
  x
}
gold <- validate_values(gold, "stage2_pilot10_gold_v2.csv")
r <- r[!r$事例ID %in% ex$事例ID, c("事例ID", FIELDS), drop = FALSE]
r <- validate_values(r, "残り final.csv", normalize_rescue = TRUE)
cons <- read_char_csv_bom(files[["consensus"]])
if (!all(c("事例ID", "合議結果") %in% names(cons))) stop("consensus_stage2.csv: 事例ID / 合議結果 が無い")
cons_ids <- unique(cons$事例ID[!is_blank(cons$合議結果)])
final <- s1[, c("事例ID", "適格性", "除外理由"), drop = FALSE]
values <- rbind(gold, r)
for (f in FIELDS) {
  final[[f]] <- ""
  final[[f]][match(values$事例ID, final$事例ID)] <- values[[f]]
}
final$一致 <- s1$一致
final$一致[match(gold$事例ID, final$事例ID)] <- ifelse(gold$事例ID %in% cons_ids, "consensus", "agreed")
final$一致[match(r$事例ID, final$事例ID)] <- "single_review"
m <- match(ex$事例ID, final$事例ID)
final$適格性[m] <- EXC
final$除外理由[m] <- ex$除外理由
final$一致[m] <- "operator_exclusion"
if (PROD && (sum(final$適格性 == INC) != 46L || sum(final$適格性 == EXC) != 88L || nrow(ex) != 2L)) {
  stop("最終分類: 本番の組入れ46・除外88・追加除外2件と一致しない")
}
write_csv_raw(final, FINAL_CSV, bom = TRUE)
write_csv_raw(review_changes, p("stage2_review_changes.csv"), bom = TRUE)
stamp <- data.frame(key = names(files), value = vapply(files, function(f) unname(tools::md5sum(f)), ""), row.names = NULL)
write_csv_raw(stamp, STAMP_CSV)
lines <- c(paste0("# 第2段階の最終分類（", PREFIX, "）"), "",
           sprintf("- 全候補 %d 件。組入れ %d / 除外 %d（第1段階 %d / 第2段階追加 %d）。", nrow(final),
                   sum(final$適格性 == INC), sum(final$適格性 == EXC), sum(s1$適格性 == EXC), nrow(ex)),
           "", "## 追加除外", "", "| 事例ID | 除外理由 | 備考 | 決定 |", "|---|---|---|---|")
for (i in seq_len(nrow(ex))) lines <- c(lines, paste0("| ", paste(vapply(ex[i, ], md_cell, ""), collapse = " | "), " |"))
lines <- c(lines, "", "## 由来（一致列）", "",
           "試行10件は v2 正解値を採用し、合議結果の記入済み行がある事例は consensus、無い事例は agreed。",
           "残りの組入れは single_review（AI 下書きを1名が確認）、追加除外は operator_exclusion（運営決定）。",
           "第1段階の除外の agreed / consensus は第1段階の由来を保持する。",
           "", "| 適格性 | 由来 | n |", "|---|---|---|")
for (e in c(INC, EXC)) for (v in unique(final$一致)) {
  lines <- c(lines, sprintf("| %s | %s | %d |", e, v, sum(final$適格性 == e & final$一致 == v)))
}
lines <- c(lines, "", "## AI 下書きからの変更（追加除外を除く、整形前の diff）", "",
           "changed は記入済み値の変更（空への変更も含む）、filled は空からの補完。変更数は changed + filled。",
           "kept は記入済み値を維持、unfilled は空のまま。従属項目の空も分母に含む。",
           "", "| item | kept | changed | filled | unfilled |", "|---|---|---|---|---|")
for (i in seq_len(nrow(review_changes))) lines <- c(lines, paste0("| ", paste(review_changes[i, ], collapse = " | "), " |"))
lines <- c(lines, "", sprintf("- 非窒息の救命介入を空にした: %d 件。事例ID: %s", length(cleared),
                             if (length(cleared)) paste(cleared, collapse = ", ") else "なし"))
write_lf_md(lines, p("stage2_final_summary.md"))
message("最終分類を書き出した: ", FINAL_CSV)
