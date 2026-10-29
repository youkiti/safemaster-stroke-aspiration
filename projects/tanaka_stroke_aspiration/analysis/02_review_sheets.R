# tanaka_stroke_aspiration: 著者2名の独立レビュー用シート（ウェブアプリ safemaster-review が読む xlsx）を書き出す
#
# 方針（合意済みの計画）:
#   キーワード候補 T4（01_feasibility_counts.R と同じ定義）の全件を、著者2名がウェブアプリで
#   独立に判定する。AI の下書きは見せない（AI_ で始まる列を作らない・記入欄は空欄で渡す）。
#   2名の判定ログが戻ったら 03_app_intake.R で取り込み、不一致を合議して確定する。
#   レビューは2段階。第1段階は全候補の適格性だけ（--stage1）。第1段階が確定したら、組入れの事例だけを
#   対象に、分類項目を第2段階で独立に付けてもらう（--stage2）。一括（全項目を1枚）のモードは無い。
#
# ウェブアプリのシート規則（このスクリプトが守るもの）:
#   - 1行目がヘッダ。ID 列は 事例ID。報告年 列は一覧に表示される。
#   - データタブ = 「選択肢」「判定ログ」以外のタブ全部。判定ログタブはヘッダ行だけを入れて渡す。
#   - 記入欄 = 名前が 修正_ で始まる列と メモ。それ以外は表示専用。
#   - 修正_X は、選択肢タブに 変数 = X の行があればプルダウン、無ければ1行の自由記載になる。
#   - 修正_組入れ・修正_協議済み の名前はアプリが既定値を持つので使わない。AI_X 列は 修正_X を
#     先に埋めるので作らない。
#   - 本文として全文表示される列: 事例の内容・背景要因・改善策。他の表示列は小さなチップになる。
#
# 入力:  架空100行 CSV（SAFEMASTER_DIR 配下）または本番 data/safemaster_r19_text.rds
#        analysis/code_labels.csv（variable, code, label: コード列を日本語ラベルに直す）
#        analysis/review_codebook.csv（選択肢タブ。変数, 英語コード, 日本語ラベル, 定義）
# 出力（output/ は commit しない）:
#   output/{prefix}_review_sheets_stage{1,2}.xlsx            タブは 候補（第2段階は 組入れ）・選択肢・判定ログ（ヘッダのみ）
#   output/{prefix}_review_sheet_candidates_stage{1,2}.csv   データタブと同じ内容（UTF-8 BOM付き）
#   output/{prefix}_review_sheets_summary_stage{1,2}.md      件数・年次・記入欄の選択肢数・自由記載の全文性検証
# 第2段階だけの入力: output/{prefix}_final_eligibility.csv と、第1段階の stamp
#   （output/{prefix}_intake_stamp_stage1.csv。現物の md5 と一致しなければ停止）。
#   第2段階の表示列は第1段階と同じ ＋ 読み取り専用の「第1段階の判定」（2名一致 / 合議）。
#
# 使い方（実行ディレクトリは projects/tanaka_stroke_aspiration/。--stage1 か --stage2 が必須）:
#   Rscript analysis/02_review_sheets.R --stage1          # 架空100行（SAFEMASTER_DIR の指定が必須）
#   Rscript analysis/02_review_sheets.R --stage2
#   Rscript analysis/02_review_sheets.R --stage1 --prod   # 本番 r19
# 注: Rscript はこの環境で成功時も exit 255/127 を返す。成否は出力ファイルで判定する。

suppressPackageStartupMessages(library(dplyr))

ARGS   <- commandArgs(trailingOnly = TRUE)
PROD   <- "--prod" %in% ARGS
PREFIX <- if (PROD) "prod" else "synth"
# 第1段階 / 第2段階のどちらかを必ず指定する（両方・どちらも無しは停止）。
#   --stage1: 全候補を対象に、記入欄は 適格性・除外理由・メモ だけ。
#   --stage2: 第1段階で組入れに確定した事例だけを対象に、記入欄は分類項目とメモ。
STAGE1 <- "--stage1" %in% ARGS
STAGE2 <- "--stage2" %in% ARGS
if (STAGE1 == STAGE2) {
  stop("使い方: Rscript analysis/02_review_sheets.R --stage1|--stage2 [--prod]\n",
       "  --stage1  全候補の適格性レビュー用シート（出力名に _stage1）\n",
       "  --stage2  第1段階で組入れに確定した事例の分類レビュー用シート（出力名に _stage2。",
       "output/{prefix}_final_eligibility.csv と第1段階の stamp が現物と一致していること）\n",
       "  --stage1 と --stage2 は同時に指定できない")
}
SUFFIX <- if (STAGE1) "_stage1" else "_stage2"
DATA_TAB <- if (STAGE1) "候補" else "組入れ"   # 第2段階のデータタブ名に「除外」を含めない
OUT    <- Sys.getenv("TANAKA_OUT", "output")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

source(file.path("..", "..", "shared", "safe_cols.R"))
if (PROD) options(safemaster.strict_cols = TRUE)   # 本番は列が無ければ stop（無言NAを作らない）
source(file.path("analysis", "candidates.R"))

d <- load_safemaster_r19(PROD)
message(PREFIX, ": ", nrow(d), " 行 x ", ncol(d), " 列")
cand <- build_candidates(d, synth_fallback = !PROD)
check_candidates(cand, PROD)
if (sum(cand$T4) == 0) stop("T4 候補が0件")

num <- function(x) suppressWarnings(as.numeric(x))

PARTY_N <- 1:10
assert_cols(d, c("事例ID", "報告年", "事例に直接関連する疾患名",
                 "関連する疾患名１", "関連する疾患名２", "関連する疾患名３",
                 "患者の年齢", "患者の性別", "事故の程度", "治療の程度", "発生時間帯", "発見者",
                 "概要", "種類", "発生場所", "関連診療科", "直前の患者の状態",
                 "事例の背景要因の概要", "改善策", "実施した医療行為の目的",
                 "種類_その他（記述）", "事例の内容_その他（記述）",
                 "直前の患者の状態_その他特記する心身状態あり（記述）",
                 paste0("当事者職種_", PARTY_N),
                 paste0("当事者職種経験（年数）_", PARTY_N), paste0("当事者職種経験（月数）_", PARTY_N),
                 paste0("当事者部署配属期間（年数）_", PARTY_N), paste0("当事者部署配属期間（月数）_", PARTY_N)))

# ---- コード → 日本語ラベル（fail-loud: 表に無い非欠測コードは、本番では stop、架空データでは警告） ----
LABELS <- read_code_labels(file.path("analysis", "code_labels.csv"))
decode <- function(variable, codes) decode_codes(LABELS, variable, codes, strict = PROD)

# 自由記載は切り詰めない: 改行・タブを空白に置き換えるだけ
clean <- function(s) gsub("[\r\n\t]", " ", ifelse(is.na(s), "", s))

year <- num(col_first(d, "報告年"))
ids  <- col_first(d, "事例ID")
# T4 の行を 報告年 → 事例ID の順に並べる
idx  <- which(cand$T4)
idx  <- idx[order(year[idx], suppressWarnings(as.numeric(ids[idx])), ids[idx], na.last = TRUE)]
N_T4 <- length(idx)

codebook <- read.csv(file.path("analysis", "review_codebook.csv"), colClasses = "character",
                     fileEncoding = "UTF-8-BOM", check.names = FALSE)
stopifnot(identical(names(codebook), c("変数", "英語コード", "日本語ラベル", "定義")))
if (anyDuplicated(paste(codebook$変数, codebook$日本語ラベル))) stop("選択肢の日本語ラベルが変数内で重複している")

# ---- 第2段階: 第1段階の最終適格性（組入れ）だけを対象にする ----
stage1_status <- NULL   # 第2段階のとき、idx の各行の「第1段階の判定」（2名一致 / 合議）
if (STAGE2) {
  elig_final_path <- file.path(OUT, paste0(PREFIX, "_final_eligibility.csv"))
  stamp_path1 <- file.path(OUT, paste0(PREFIX, "_intake_stamp_stage1.csv"))
  if (!file.exists(elig_final_path)) {
    stop("第1段階の最終適格性が無い（先に 03_app_intake.R --stage1 を最終化まで通す）: ", elig_final_path)
  }
  bad1 <- stamp_problems(stamp_path1, stage1_stamp_files(OUT, PREFIX))
  if (length(bad1)) {
    stop("第1段階の stamp が現物と一致しない（03_app_intake.R --stage1 を実行し直す）: ", paste(bad1, collapse = " ; "))
  }
  elig_final <- read_char_csv_bom(elig_final_path)
  if (!identical(names(elig_final), c("事例ID", "適格性", "除外理由", "一致"))) {
    stop("第1段階の最終適格性の列が想定と違う: ", paste(names(elig_final), collapse = ","))
  }
  if (anyDuplicated(elig_final$事例ID)) stop("第1段階の最終適格性の事例IDに重複がある")
  if (!setequal(elig_final$事例ID, ids[idx])) {
    stop(sprintf("第1段階の最終適格性の事例IDと現在のT4候補が一致しない: 候補にあって最終適格性に無い %d 件 / 最終適格性にあって候補に無い %d 件",
                 length(setdiff(ids[idx], elig_final$事例ID)), length(setdiff(elig_final$事例ID, ids[idx]))))
  }
  ELIG_INC_LABEL <- codebook$日本語ラベル[codebook$変数 == "適格性" & codebook$英語コード == "include"]
  ELIG_EXC_LABEL <- codebook$日本語ラベル[codebook$変数 == "適格性" & codebook$英語コード == "exclude"]
  if (!all(elig_final$適格性 %in% c(ELIG_INC_LABEL, ELIG_EXC_LABEL))) stop("第1段階の最終適格性に想定外の値がある")
  if (!all(elig_final$一致 %in% c("agreed", "consensus"))) stop("第1段階の最終適格性の「一致」が agreed / consensus でない")
  inc_ids <- elig_final$事例ID[elig_final$適格性 == ELIG_INC_LABEL]
  if (length(inc_ids) == 0) stop("第1段階で組入れに確定した事例が0件")
  keep <- ids[idx] %in% inc_ids
  idx <- idx[keep]
  stage1_status <- ifelse(elig_final$一致[match(ids[idx], elig_final$事例ID)] == "agreed", "2名一致", "合議")
  message("第2段階の対象: 第1段階で組入れ ", length(idx), " 件（候補 ", N_T4, " 件中）")
}

dx_other <- vapply(idx, function(i) {
  v <- c(d[["関連する疾患名１"]][i], d[["関連する疾患名２"]][i], d[["関連する疾患名３"]][i])
  paste(v[!is.na(v) & trimws(v) != ""], collapse = " / ")
}, "")

# 当事者: 「N: 職種 職種経験Y年Mか月 部署配属Y年Mか月」を N=1..10 で連結
fmt_ym <- function(prefix, y, m) {
  if (is.na(y) && is.na(m)) {
    return(NULL)
  }
  y <- if (is.na(y)) 0 else y
  m <- if (is.na(m)) 0 else m
  sprintf("%s%d年%dか月", prefix, as.integer(round(y)), as.integer(round(m)))
}
party_codes <- lapply(PARTY_N, function(n) col_first(d, paste0("当事者職種_", n)))
party_text <- vapply(idx, function(i) {
  parts <- character(0)
  for (n in PARTY_N) {
    code <- party_codes[[n]][i]
    if (is.na(code) || trimws(code) == "") {
      next
    }
    job <- decode("当事者職種", code)
    ex <- fmt_ym("職種経験", num(col_first(d, paste0("当事者職種経験（年数）_", n))[i]),
                 num(col_first(d, paste0("当事者職種経験（月数）_", n))[i]))
    tn <- fmt_ym("部署配属", num(col_first(d, paste0("当事者部署配属期間（年数）_", n))[i]),
                 num(col_first(d, paste0("当事者部署配属期間（月数）_", n))[i]))
    parts <- c(parts, paste(c(paste0(n, ": ", job), ex, tn), collapse = " "))
  }
  paste(parts, collapse = " / ")
}, "")

CLASS_FIELDS <- paste0("修正_", c("脳卒中の位置づけ", "脳卒中病型", "事故類型",
                                  "摂取物", "摂食介助状況", "同席状況", "嚥下評価", "指示逸脱",
                                  "食事区分", "救命介入", "直接介助者の当事者番号"))
ENTRY_FIELDS <- if (STAGE1) c("修正_適格性", "修正_除外理由", "メモ") else c(CLASS_FIELDS, "メモ")

sheet <- data.frame(
  事例ID = ids[idx],
  報告年 = as.integer(year[idx]),
  直接関連する疾患名 = clean(col_first(d, "事例に直接関連する疾患名")[idx]),
  関連する疾患名 = dx_other,
  患者の年齢 = decode("患者の年齢", col_first(d, "患者の年齢")[idx]),
  患者の性別 = decode("患者の性別", col_first(d, "患者の性別")[idx]),
  事故の程度 = decode("事故の程度", col_first(d, "事故の程度")[idx]),
  治療の程度 = decode("治療の程度", col_first(d, "治療の程度")[idx]),
  発生時間帯 = decode("発生時間帯", col_first(d, "発生時間帯")[idx]),
  発見者 = decode("発見者", col_first(d, "発見者")[idx]),
  概要 = decode("概要", col_first(d, "概要")[idx]),
  種類 = decode("種類", col_first(d, "種類")[idx]),
  事例の内容コード = decode("事例の内容", d[[cand$naiyo_code_col]][idx]),
  発生場所 = clean(col_first(d, "発生場所")[idx]),
  関連診療科 = clean(col_first(d, "関連診療科")[idx]),
  直前の患者の状態 = clean(col_first(d, "直前の患者の状態")[idx]),
  当事者 = party_text,
  check.names = FALSE, stringsAsFactors = FALSE
)
# 候補の抽出（candidates.R の FREE_COLS）で検索した自由記載欄は、本文3列のほかもすべて載せる。
# 脳卒中や誤嚥の語がこれらの欄にしか無い候補でも、判定者が根拠を読めるようにするため。
sheet[["医療行為の目的"]] <- clean(col_first(d, "実施した医療行為の目的")[idx])
sheet[["種類（その他の記述）"]] <- clean(col_first(d, "種類_その他（記述）")[idx])
sheet[["事例の内容（その他の記述）"]] <- clean(col_first(d, "事例の内容_その他（記述）")[idx])
sheet[["患者の状態（その他の記述）"]] <-
  clean(col_first(d, "直前の患者の状態_その他特記する心身状態あり（記述）")[idx])
if (STAGE2) {
  sheet[["第1段階の判定"]] <- stage1_status   # 表示専用のチップ（修正_ で始まらない）
}
for (f in ENTRY_FIELDS) {
  sheet[[f]] <- rep("", nrow(sheet))
}
sheet$事例の内容 <- clean(d[[cand$narr_col]][idx])
sheet$背景要因   <- clean(col_first(d, "事例の背景要因の概要")[idx])
sheet$改善策     <- clean(col_first(d, "改善策")[idx])

if (anyDuplicated(sheet$事例ID)) {
  stop("候補の事例ID に重複がある: ", paste(unique(sheet$事例ID[duplicated(sheet$事例ID)]), collapse = ", "))
}
if (any(grepl("^AI_", names(sheet))) || any(c("修正_組入れ", "修正_協議済み") %in% names(sheet))) {
  stop("アプリが既定値を持つ列名（AI_*, 修正_組入れ, 修正_協議済み）を作ってはいけない")
}
EXCEL_CELL_MAX <- 32767L
maxn <- function(v) max(nchar(ifelse(is.na(v), "", v)), 0)
for (cn in c("事例の内容", "背景要因", "改善策")) {
  if (maxn(sheet[[cn]]) >= EXCEL_CELL_MAX) stop(cn, " が Excel のセル上限を超える（切り詰めない方針なので停止）")
}

# ---- 選択肢タブ ----
entry_vars <- sub("^修正_", "", grep("^修正_", ENTRY_FIELDS, value = TRUE))
codebook <- codebook[codebook$変数 %in% entry_vars, , drop = FALSE]
n_opts <- vapply(entry_vars, function(v) sum(codebook$変数 == v), 1L)
no_opts <- setdiff(names(n_opts)[n_opts == 0], "直接介助者の当事者番号")
if (length(no_opts)) stop("選択肢が0件の記入欄: ", paste0("修正_", no_opts, collapse = ", "))
orphan <- setdiff(unique(codebook$変数), entry_vars)
if (length(orphan)) stop("対応する記入欄が無い選択肢の変数: ", paste(orphan, collapse = ", "))

# ---- 書き出し ----
xlsx_path <- file.path(OUT, paste0(PREFIX, "_review_sheets", SUFFIX, ".xlsx"))
# 判定ログタブはヘッダ行だけを入れておく（固定5列 ＋ 記入欄）。アプリの初期設定関数は
# 既定の対象シートを書き換えるので、このプロジェクトでは実行しない。
LOG_HEADER <- c("timestamp", "reviewer", "tab", "事例ID", "action", ENTRY_FIELDS)
log_tab <- as.data.frame(setNames(replicate(length(LOG_HEADER), character(0), simplify = FALSE), LOG_HEADER),
                         check.names = FALSE, stringsAsFactors = FALSE)
tab_list <- setNames(list(sheet, codebook, log_tab), c(DATA_TAB, "選択肢", "判定ログ"))
writexl::write_xlsx(tab_list, path = xlsx_path)
write_csv_raw(sheet, file.path(OUT, paste0(PREFIX, "_review_sheet_candidates", SUFFIX, ".csv")), bom = TRUE)

# ---- 読み戻し検証 ----
tabs <- readxl::excel_sheets(xlsx_path)
if (!identical(tabs, c(DATA_TAB, "選択肢", "判定ログ"))) {
  stop("xlsx のタブが ", DATA_TAB, " / 選択肢 / 判定ログ の3枚でない: ", paste(tabs, collapse = ", "))
}
if (STAGE2 && any(grepl("除外", tabs))) stop("第2段階の xlsx のタブ名に「除外」が含まれている")
log_back <- readxl::read_xlsx(xlsx_path, sheet = "判定ログ", col_types = "text")
if (!identical(names(log_back), LOG_HEADER) || nrow(log_back) != 0) stop("判定ログタブのヘッダが期待と違う、または行がある")
back <- readxl::read_xlsx(xlsx_path, sheet = DATA_TAB, col_types = "text")
if (any(grepl("^AI_", names(back))) || any(c("修正_組入れ", "修正_協議済み") %in% names(back))) {
  stop("読み戻した xlsx に禁止列名がある")
}
if (!identical(names(back), names(sheet))) stop("読み戻した列名が書き出した列名と違う")
if (nrow(back) != nrow(sheet)) stop("読み戻した行数が違う")
if (!identical(back$事例ID, sheet$事例ID)) stop("読み戻した事例IDが書き出した事例IDと違う")
if (STAGE2) {
  if (!setequal(back$事例ID, inc_ids) || length(back$事例ID) != length(inc_ids)) {
    stop("第2段階の xlsx の事例IDが、第1段階で組入れに確定した事例IDと一致しない")
  }
  if (any(c("修正_適格性", "修正_除外理由") %in% names(back))) stop("第2段階の xlsx に適格性・除外理由の記入欄がある")
  if (!identical(back$第1段階の判定, stage1_status)) stop("読み戻した「第1段階の判定」が違う")
}
for (f in ENTRY_FIELDS) {
  if (any(!is.na(back[[f]]) & back[[f]] != "")) stop("記入欄が空欄でない: ", f)
}
chk <- data.frame(col = c("事例の内容", "背景要因", "改善策"), stringsAsFactors = FALSE)
chk$data_max <- vapply(chk$col, function(cn) maxn(sheet[[cn]]), 1)
chk$xlsx_max <- vapply(chk$col, function(cn) maxn(back[[cn]]), 1)
if (any(chk$data_max != chk$xlsx_max)) {
  stop("自由記載の最大文字数が xlsx で変わった（切れ）: ",
       paste(chk$col[chk$data_max != chk$xlsx_max], collapse = ", "))
}

# ---- サマリ md ----
jiko <- num(col_first(d, "事故の程度")); chiryo <- num(col_first(d, "治療の程度"))
severe <- (!is.na(jiko) & jiko == 1) | (!is.na(jiko) & jiko %in% c(2, 3) & !is.na(chiryo) & chiryo == 3)
yrs <- year[idx]
lines <- c()
add <- function(...) lines <<- c(lines, ...)
add(paste0("# レビューシート書き出しサマリ（", PREFIX, if (PROD) ", 本番r19" else ", 架空100行", "）— tanaka_stroke_aspiration"))
if (isTRUE(cand$synth_fallback_used)) {
  add("", "**注意: 架空データには脳卒中語が無いため、入院の先頭30件（事例ID順）を T3・T4 の代替候補にした。件数・年次・重症度はすべて意味を持たない。**")
}
add("", paste0("- 段階: ", if (STAGE1) "第1段階（適格性。全候補）" else "第2段階（分類。第1段階で組入れに確定した事例のみ）"))
add(paste0("- 全 N = ", nrow(d), " 行 / 候補（T4）= ", N_T4, " 行 / このシートの行 = ", nrow(sheet), " 行"))
if (STAGE2) {
  add(paste0("- 第1段階の判定: 2名一致 ", sum(stage1_status == "2名一致"), " 件 / 合議 ", sum(stage1_status == "合議"), " 件"))
}
add(paste0("- 事例の内容の同定: コード列 `", cand$naiyo_code_col, "` / 本文列 `", cand$narr_col, "`"))
add("", "## 段階別の候補件数（入院に限定・累積）", "", "| 段階 | n |", "|---|---|")
for (nm in c("T1", "T2", "T3", "T4")) {
  add(paste0("| ", nm, " | ", sum(cand[[nm]]), " |"))
}
add("", paste0("## 年次分布（このシートの ", nrow(sheet), " 件）"), "", "| 報告年 | n | うち重篤 |", "|---|---|---|")
for (y in sort(unique(yrs))) {
  add(paste0("| ", y, " | ", sum(yrs == y, na.rm = TRUE), " | ", sum(severe[idx][yrs == y], na.rm = TRUE), " |"))
}
add("", paste0("- 重篤（死亡 OR（事故の程度 2・3 かつ治療の程度 3））: ", sum(severe[idx]), " 件"))
add("", "## 記入欄と選択肢の数", "", "| 記入欄 | 種別 | 選択肢の数 |", "|---|---|---|")
for (f in ENTRY_FIELDS) {
  v <- sub("^修正_", "", f)
  k <- sum(codebook$変数 == v)
  add(paste0("| ", f, " | ", if (f == "メモ" || k == 0) "自由記載" else "プルダウン", " | ", if (f == "メモ") "-" else k, " |"))
}
add("", paste0("- 選択肢タブ: ", nrow(codebook), " 行 / 変数 ", length(unique(codebook$変数)), " 個"))
add("", "## 自由記載の全文性検証（切れ検知）", "",
    "| 列 | データ max nchar | xlsx読戻し max nchar | 一致 |", "|---|---|---|---|")
for (i in seq_len(nrow(chk))) {
  add(paste0("| ", chk$col[i], " | ", chk$data_max[i], " | ", chk$xlsx_max[i], " | OK |"))
}
add("", paste0("- 記入欄はすべて空欄（読み戻して確認）。タブは ", DATA_TAB, " / 選択肢 / 判定ログ（ヘッダのみ）の3枚。AI_ 列・修正_組入れ・修正_協議済み は無い。"))
write_lf_md(lines, file.path(OUT, paste0(PREFIX, "_review_sheets_summary", SUFFIX, ".md")))

message("done: ", PREFIX, "_review_sheets", SUFFIX, ".xlsx / _review_sheet_candidates", SUFFIX, ".csv / _review_sheets_summary", SUFFIX, ".md")
