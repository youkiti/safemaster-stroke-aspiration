# tanaka_stroke_aspiration: ウェブアプリ（safemaster-review）の2名分の判定ログを取り込み、
#   一致度・不一致一覧・最終結果を作る。レビューは2段階で、--stage1 か --stage2 を必ず指定する。
#
# 背景: 02_review_sheets.R が書いた xlsx を、著者2名が独立にアプリで判定する。アプリは判定をシートに
#   書かず、「判定ログ」タブへ append-only で記録し、管理者が CSV としてダウンロードする。本スクリプトは
#   2名分の CSV を取り込み、検証し、(事例ID) ごとに最終行勝ちで圧縮し、一致度を出し、不一致を1項目1行で
#   書き出す。合議の結果を consensus CSV に書いて再実行すると、その段階の最終結果を作る。
#
# 段階:
#   --stage1  全候補の適格性（記入欄 修正_適格性・修正_除外理由・メモ）。
#             最終結果: output/{prefix}_final_eligibility.csv（事例ID, 適格性, 除外理由, 一致）
#   --stage2  第1段階で組入れに確定した事例だけの分類（脳卒中の位置づけ … 直接介助者の当事者番号・メモ）。
#             第2段階の判定者は除外できない。除外したい事例があれば メモ に書く（要約に「運営の確認が必要」として並べる）。
#             最終結果は書かない。試行の一致度・不一致を出し、05b_stage2_final.R で最終化する。
#
# 入力（出力先フォルダは環境変数 TANAKA_OUT で差し替え可。既定 output。合成データでのテスト用）:
#   output/{prefix}_app_judgment_log_stage{1,2}_reviewer1.csv, ..._reviewer2.csv
#       アプリの判定ログ（UTF-8 BOM付き, RFC4180, ヘッダ行あり）。列は固定5列
#       (timestamp, reviewer, tab, 事例ID, action) ＋ 記入欄（xlsx の 修正_* と メモ）。
#       1回の保存=1行、append-only。圧縮: 事例ID ごとに timestamp 順（同時刻なら行順）で最終行勝ち。
#       最終行が action=clear なら未判定扱い。
#   output/{prefix}_review_sheets_stage{1,2}.xlsx  — 02_review_sheets.R の出力。存在する事例ID・記入欄・許容値の正。
#   output/{prefix}_consensus_stage{1,2}.csv       — 任意。{prefix}_disagreements_stage{1,2}.csv と同じ列で 合議結果 を埋めたもの。
#   第2段階だけ: output/{prefix}_final_eligibility.csv と output/{prefix}_intake_stamp_stage1.csv
#       （第1段階の stamp が現物と一致しなければ停止）、output/{prefix}_agreement_stage1.csv（適格性の一致度）。
#       第2段階の xlsx の事例IDは、第1段階で組入れに確定した事例IDと過不足なく一致しなければならない。
#
# 検証（失敗したら stop。どの行かを名指しする）:
#   ヘッダが「固定5列 ＋ xlsx の記入欄」の列集合と一致 / tab がデータタブ名（第1段階 候補・第2段階 組入れ） /
#   事例ID が xlsx に存在 / action が agree・modify・clear / プルダウン欄の値が選択肢タブの日本語ラベル /
#   直接介助者の当事者番号が空か 1〜10 の整数のカンマ区切り / agree なのに修正_* に値がある・modify なのに
#   修正_* が全て空は矛盾 / 1つのログの reviewer はちょうど1種類で、2つのログで異なる。
#
# 完全性（不完全な行は要約に並べ、最終化を止める。判定済みの行について）:
#   第1段階: 適格性が記入済み / 除外なら除外理由が記入済み / 組入れなら除外理由が空
#            （組入れに除外理由があってもメモに「組入れ」があれば理由を空にし、要約に記録する。それ以外は不完全）。
#   第2段階: 脳卒中の位置づけ・脳卒中病型・事故類型・摂取物・摂食介助状況・同席状況・嚥下評価・指示逸脱・
#            食事区分が全て記入済み（救命介入は事故類型が窒息・気道閉塞のときだけ必須）。
#
# 出力（{prefix}_ 付き。第1段階 / 第2段階で別）:
#   app_intake_summary_stage{1,2}.md   検証結果・件数・一致度・不一致の件数・最終化の可否（LF）
#   disagreements_stage{1,2}.csv       事例ID,変数,reviewer1,reviewer2,合議結果（空）（UTF-8 BOM付き）
#   第1段階: disagreement_context_stage1.csv（不一致事例の2名の除外理由・メモ。UTF-8 BOM付き）,
#             agreement_stage1.csv（適格性の一致度）, final_eligibility.csv, intake_stamp_stage1.csv
#   第2段階: agreement.csv（適格性の行は agreement_stage1.csv のコピー ＋ 分類項目の行。
#            variable,n,percent_agreement,kappa,ci_low,ci_high。解析が読む）, determinable.csv（摂食介助状況・
#            同席状況を判定できた割合, reviewer 別）。最終分類と stamp は05bが書く
#   stamp は最終結果を書いたときだけ。key,value。入力ファイルと最終結果の md5（tools::md5sum。合議ファイルは無ければ空）。
#       第2段階の stamp は第1段階の最終適格性と第1段階の stamp も覆う。derive_cohort.R が現物と照合し、食い違えば停止する。
#
# 古い最終結果を残さない: 実行の冒頭で、その段階の最終結果と stamp があれば消す。最終化できた実行だけが
#   それらを書き直す（検証エラーで止まった実行でも古い最終結果は残らない）。第1段階を実行し直すと
#   final_eligibility.csv が消え、第2段階の stamp（その md5 を含む）は現物と食い違う。
#
# 合議ファイルの規則:
#   - 合議結果が空の行は「未合議」。ただし 直接介助者の当事者番号 に限り、リテラル値「なし」は
#     「合議の結果、直接介助者を特定できない」を意味し、最終値は空になる。
#   - 行を置いてよいのは、不一致の行、（第2段階）事故類型が
#     不一致の事例の救命介入（合議で事故類型が窒息・気道閉塞に決まると救命介入が必須になるため）。
#   - 第1段階は適格性だけを合議する。除外に決まれば除外と判定した側の理由を採り、組入れなら理由は空。
#     除外理由の合議行は置けない。両者が除外で理由だけが違えば、選択肢タブで先の理由を採る（一致は agreed）。
#   - 合議ファイルの reviewer1 / reviewer2 列は、現在の（圧縮後の）判定値と一致していなければならない。
#     不一致の後に reviewer が判定を変えたのに古い合議を適用してしまうのを止める。
#
# 使い方（実行ディレクトリは projects/tanaka_stroke_aspiration/）:
#   Rscript analysis/03_app_intake.R --stage1            # 架空データの検証用（output/synth_*）
#   Rscript analysis/03_app_intake.R --stage2
#   Rscript analysis/03_app_intake.R --stage1 --prod     # 本番（output/prod_*）
#   TANAKA_OUT=/path/to/folder Rscript analysis/03_app_intake.R --stage1
# 注: Rscript はこの環境で成功時も exit 255/127 を返す。成否は出力ファイルで判定する。

ARGS   <- commandArgs(trailingOnly = TRUE)
PROD   <- "--prod" %in% ARGS
PREFIX <- if (PROD) "prod" else "synth"
STAGE1 <- "--stage1" %in% ARGS
STAGE2 <- "--stage2" %in% ARGS
if (STAGE1 == STAGE2) {
  stop("使い方: Rscript analysis/03_app_intake.R --stage1|--stage2 [--prod]\n",
       "  --stage1  全候補の適格性の取り込み（最終結果: {prefix}_final_eligibility.csv）\n",
       "  --stage2  第1段階で組入れの事例の分類の取り込み（最終結果の {prefix}_final_classification.csv は 05b_stage2_final.R が作る）\n",
       "  --stage1 と --stage2 は同時に指定できない")
}
STAGE <- if (STAGE1) "stage1" else "stage2"
OUT    <- Sys.getenv("TANAKA_OUT", "output")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

source(file.path("analysis", "candidates.R"))   # 入出力ヘルパー（read_char_csv_bom, write_csv_raw, write_lf_md, stamp_problems など）

p <- function(suffix) file.path(OUT, paste0(PREFIX, "_", suffix))
LOG_PATHS    <- c(p(paste0("app_judgment_log_", STAGE, "_reviewer1.csv")), p(paste0("app_judgment_log_", STAGE, "_reviewer2.csv")))
XLSX_PATH    <- p(paste0("review_sheets_", STAGE, ".xlsx"))
CONS_CSV     <- p(paste0("consensus_", STAGE, ".csv"))
DIS_CSV      <- p(paste0("disagreements_", STAGE, ".csv"))
SUMMARY_MD   <- p(paste0("app_intake_summary_", STAGE, ".md"))
ELIG_FINAL_CSV <- p("final_eligibility.csv")      # 第1段階の最終結果（第2段階の入力）
STAMP1_CSV   <- p("intake_stamp_stage1.csv")
AGREE1_CSV   <- p("agreement_stage1.csv")
if (STAGE1) {
  FINAL_CSV  <- ELIG_FINAL_CSV
  STAMP_CSV  <- STAMP1_CSV
  AGREE_CSV  <- AGREE1_CSV
} else {
  FINAL_CSV  <- p("final_classification.csv")
  STAMP_CSV  <- p("intake_stamp.csv")
  AGREE_CSV  <- p("agreement.csv")
  DETERM_CSV <- p("determinable.csv")
}
TAB_NAME <- if (STAGE1) "候補" else "組入れ"

# 古い最終結果と stamp を先に消す（最終化できた実行だけが書き直す）
stale_removed <- character(0)
for (f in c(FINAL_CSV, STAMP_CSV)) {
  if (file.exists(f)) {
    if (!file.remove(f)) stop("古いファイルを消せない: ", f)
    stale_removed <- c(stale_removed, basename(f))
  }
}
if (length(stale_removed)) message("前回の出力を削除した: ", paste(stale_removed, collapse = ", "))

FIXED5 <- c("timestamp", "reviewer", "tab", "事例ID", "action")
PARTY_NONE <- "なし"   # 直接介助者の当事者番号の合議値に限り「特定できない（最終値は空）」の意味
ACTION_LEVELS <- c("agree", "modify", "clear")

parse_ts <- function(x) {
  # ISO8601 例: 2026-10-20T09:00:00+09:00。strptime の %z はコロン無し (+0900) を要求するので除去してから読む。
  x2 <- gsub("([+-][0-9]{2}):([0-9]{2})$", "\\1\\2", x)
  as.POSIXct(x2, format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
}
pct1 <- function(x) ifelse(is.na(x) | is.nan(x), "-", sprintf("%.1f%%", x))
num2 <- function(x, k = 2) ifelse(is.na(x) | is.nan(x), "-", formatC(x, format = "f", digits = k))

# =============================================================================
# 1. xlsx（存在ID・記入欄・許容値の正）と、第2段階では第1段階の確定結果
# =============================================================================
if (!file.exists(XLSX_PATH)) stop("レビューシート xlsx が無い（先に 02_review_sheets.R --", STAGE, " を実行）: ", XLSX_PATH)
tabs <- readxl::excel_sheets(XLSX_PATH)
data_tabs <- setdiff(tabs, c("選択肢", "判定ログ"))
if (!identical(data_tabs, TAB_NAME)) {
  stop("xlsx のデータタブが「", TAB_NAME, "」1枚でない: ", paste(data_tabs, collapse = ", "))
}
if (!"選択肢" %in% tabs) stop("xlsx に選択肢タブが無い")
sheet    <- as.data.frame(readxl::read_xlsx(XLSX_PATH, sheet = TAB_NAME, col_types = "text"), stringsAsFactors = FALSE)
codebook <- as.data.frame(readxl::read_xlsx(XLSX_PATH, sheet = "選択肢", col_types = "text"), stringsAsFactors = FALSE)
if (!all(c("事例ID", "報告年") %in% names(sheet))) stop("xlsx のデータタブに 事例ID / 報告年 が無い")
if (anyDuplicated(sheet$事例ID)) stop("xlsx のデータタブの事例ID に重複がある")
if (!identical(names(codebook), c("変数", "英語コード", "日本語ラベル", "定義"))) stop("選択肢タブの列が想定と違う")
sheet_ids <- sheet$事例ID
N_CAND <- length(sheet_ids)

entry_fields <- names(sheet)[grepl("^修正_", names(sheet)) | names(sheet) == "メモ"]
if (length(entry_fields) == 0) stop("xlsx に記入欄が無い")
ALLOWED <- list()   # プルダウン欄 → 許容する日本語ラベル
for (f in grep("^修正_", entry_fields, value = TRUE)) {
  opts <- codebook$日本語ラベル[codebook$変数 == sub("^修正_", "", f)]
  if (length(opts) > 0) ALLOWED[[f]] <- opts
}
label_of <- function(variable, code, cb = codebook) {
  v <- cb$日本語ラベル[cb$変数 == variable & cb$英語コード == code]
  if (length(v) != 1) stop("選択肢に ", variable, "/", code, " が1行でない")
  v
}
F_ELIG <- "修正_適格性"; F_REASON <- "修正_除外理由"; F_TYPE <- "修正_事故類型"
F_RESCUE <- "修正_救命介入"; F_PARTY <- "修正_直接介助者の当事者番号"
REQ <- paste0("修正_", c("脳卒中の位置づけ", "脳卒中病型", "事故類型", "摂取物", "摂食介助状況",
                         "同席状況", "嚥下評価", "指示逸脱", "食事区分"))
need_fields <- if (STAGE1) c(F_ELIG, F_REASON) else c(REQ, F_RESCUE, F_PARTY)
if (!all(need_fields %in% entry_fields)) {
  stop("xlsx に必要な記入欄が無い: ", paste(setdiff(need_fields, entry_fields), collapse = ", "))
}
if (STAGE2 && any(c(F_ELIG, F_REASON) %in% entry_fields)) {
  stop("第2段階の xlsx に適格性・除外理由の記入欄がある（第2段階の判定者は除外できない）")
}
if (STAGE1 && any(c(REQ, F_RESCUE, F_PARTY) %in% entry_fields)) {
  stop("第1段階の xlsx に分類項目の記入欄がある")
}
# 適格性のラベルはリポジトリのコードブックから取る（第2段階の xlsx には適格性の行が無い）
codebook_repo <- read.csv(file.path("analysis", "review_codebook.csv"), colClasses = "character",
                          fileEncoding = "UTF-8-BOM", check.names = FALSE)
ELIG_INC <- label_of("適格性", "include", codebook_repo)
ELIG_EXC <- label_of("適格性", "exclude", codebook_repo)
if (STAGE1 && !all(c(ELIG_INC, ELIG_EXC) %in% ALLOWED[[F_ELIG]])) stop("xlsx の適格性の選択肢がコードブックと違う")
if (STAGE2) {
  CHOKE <- label_of("事故類型", "choking")
  UNK_ASSIST <- label_of("摂食介助状況", "unknown")
  UNK_PRESENT <- label_of("同席状況", "unknown")
}
KAPPA_FIELDS <- if (STAGE1) F_ELIG else c(REQ, F_RESCUE)   # 一致度を出す項目（当事者番号は自由記載なので出さない）
bare <- function(f) sub("^修正_", "", f)

s1 <- NULL
if (STAGE2) {
  if (!file.exists(ELIG_FINAL_CSV)) {
    stop("第1段階の最終適格性が無い（先に 03_app_intake.R --stage1 を最終化まで通す）: ", ELIG_FINAL_CSV)
  }
  bad1 <- stamp_problems(STAMP1_CSV, stage1_stamp_files(OUT, PREFIX))
  if (length(bad1)) {
    stop("第1段階の stamp が無い、または現物と一致しない（03_app_intake.R --stage1 を実行し直す）: ", paste(bad1, collapse = " ; "))
  }
  if (!file.exists(AGREE1_CSV)) stop("第1段階の一致度ファイルが無い（03_app_intake.R --stage1 を実行）: ", AGREE1_CSV)
  s1 <- read_char_csv_bom(ELIG_FINAL_CSV)
  if (!identical(names(s1), c("事例ID", "適格性", "除外理由", "一致"))) {
    stop("第1段階の最終適格性の列が想定と違う: ", paste(names(s1), collapse = ","))
  }
  if (anyDuplicated(s1$事例ID)) stop("第1段階の最終適格性の事例IDに重複がある")
  if (!all(s1$適格性 %in% c(ELIG_INC, ELIG_EXC))) stop("第1段階の最終適格性に想定外の値がある")
  s1_inc_ids <- s1$事例ID[s1$適格性 == ELIG_INC]
  if (!setequal(sheet_ids, s1_inc_ids)) {
    stop(sprintf("第2段階の xlsx の事例IDが、第1段階で組入れに確定した事例IDと一致しない: xlsx にあって組入れに無い %d 件 [%s] / 組入れにあって xlsx に無い %d 件 [%s]",
                 length(setdiff(sheet_ids, s1_inc_ids)), paste(setdiff(sheet_ids, s1_inc_ids), collapse = ","),
                 length(setdiff(s1_inc_ids, sheet_ids)), paste(setdiff(s1_inc_ids, sheet_ids), collapse = ",")))
  }
}

# =============================================================================
# 2. 判定ログの読み込みと検証
# =============================================================================
norm_party <- function(x) {
  x <- gsub("[[:space:]]", "", x)
  vapply(x, function(s) {
    if (s == "") return("")
    paste(sort(unique(as.integer(strsplit(s, ",", fixed = TRUE)[[1]]))), collapse = ",")
  }, "", USE.NAMES = FALSE)
}
party_ok <- function(x) {
  x <- gsub("[[:space:]]", "", x)
  ok <- x == "" | grepl("^[0-9]+(,[0-9]+)*$", x)
  ok[ok & x != ""] <- vapply(x[ok & x != ""], function(s) {
    all(as.integer(strsplit(s, ",", fixed = TRUE)[[1]]) %in% 1:10)
  }, TRUE)
  ok
}
rows_msg <- function(i) paste0("データ行 ", paste(i, collapse = ", "))

read_log <- function(path) {
  nm <- basename(path)
  if (!file.exists(path)) stop("判定ログが無い: ", path)
  lg <- read_char_csv_bom(path)
  expected <- c(FIXED5, entry_fields)
  if (anyDuplicated(names(lg)) || !setequal(names(lg), expected)) {
    stop(sprintf("[%s] ヘッダが「固定5列＋xlsx の記入欄」の列集合と一致しない。不足列: [%s] / 余分な列: [%s]",
                 nm, paste(setdiff(expected, names(lg)), collapse = ", "),
                 paste(setdiff(names(lg), expected), collapse = ", ")))
  }
  lg <- lg[, expected, drop = FALSE]
  lg[] <- lapply(lg, trimws)
  n <- nrow(lg)
  if (n == 0) stop("[", nm, "] 判定ログが0行")
  bad <- which(lg$tab != TAB_NAME)
  if (length(bad)) {
    stop(sprintf("[%s] tab が「%s」でない: %s, 値 %s", nm, TAB_NAME, rows_msg(bad),
                 paste(unique(lg$tab[bad]), collapse = ", ")))
  }
  bad <- which(!(lg$事例ID %in% sheet_ids))
  if (length(bad)) {
    why <- if (STAGE2) {
      ex <- intersect(lg$事例ID[bad], s1$事例ID[s1$適格性 == ELIG_EXC])
      sprintf("（第2段階の xlsx は第1段階で組入れに確定した事例だけ。うち第1段階で除外が確定した事例: %s）",
              if (length(ex)) paste(ex, collapse = ",") else "なし")
    } else ""
    stop(sprintf("[%s] 事例ID が xlsx に存在しない%s: %s, 値 %s", nm, why, rows_msg(bad),
                 paste(unique(lg$事例ID[bad]), collapse = ", ")))
  }
  bad <- which(!(lg$action %in% ACTION_LEVELS))
  if (length(bad)) {
    stop(sprintf("[%s] action が不正（許容: %s）: %s, 値 %s", nm, paste(ACTION_LEVELS, collapse = "/"),
                 rows_msg(bad), paste(unique(lg$action[bad]), collapse = ", ")))
  }
  for (f in names(ALLOWED)) {
    bad <- which(lg[[f]] != "" & !(lg[[f]] %in% ALLOWED[[f]]))
    if (length(bad)) {
      stop(sprintf("[%s] 列「%s」に許容ラベル外の値がある: %s, 値 %s", nm, f, rows_msg(bad),
                   paste(unique(lg[[f]][bad]), collapse = " | ")))
    }
  }
  if (F_PARTY %in% entry_fields) {
    # 全角の数字・カンマ（読点）と末尾のピリオドは、意味が明らかな表記ゆれとして半角にそろえる
    raw_party <- lg[[F_PARTY]]
    fixed <- chartr("０１２３４５６７８９，、", "0123456789,,", raw_party)
    fixed <- sub("[.。．]+$", "", gsub("[[:space:]]", "", fixed))
    changed <- which(fixed != raw_party)
    if (length(changed)) {
      message(sprintf("[%s] 列「%s」の表記ゆれを半角にそろえた: %s, 値 %s", nm, F_PARTY, rows_msg(changed),
                      paste(unique(paste0(raw_party[changed], "→", fixed[changed])), collapse = " | ")))
      lg[[F_PARTY]] <- fixed
    }
    bad <- which(!party_ok(lg[[F_PARTY]]))
    if (length(bad)) {
      stop(sprintf("[%s] 列「%s」が空でも 1〜10 の整数のカンマ区切りでもない: %s, 値 %s", nm, F_PARTY,
                   rows_msg(bad), paste(unique(lg[[F_PARTY]][bad]), collapse = " | ")))
    }
  }
  has_value <- Reduce(`|`, lapply(grep("^修正_", entry_fields, value = TRUE), function(f) lg[[f]] != ""))
  bad <- which(lg$action == "agree" & has_value)
  if (length(bad)) stop(sprintf("[%s] action=agree なのに修正_* に値がある（矛盾）: %s", nm, rows_msg(bad)))
  bad <- which(lg$action == "modify" & !has_value)
  if (length(bad)) stop(sprintf("[%s] action=modify なのに修正_* が全て空（矛盾）: %s", nm, rows_msg(bad)))
  rv <- unique(lg$reviewer)
  if (length(rv) != 1 || rv == "") {
    stop(sprintf("[%s] reviewer がちょうど1種類（空でない）でない: %s", nm,
                 paste0("'", rv, "'", collapse = ", ")))
  }
  ts <- parse_ts(lg$timestamp)
  bad <- which(is.na(ts))
  if (length(bad)) stop(sprintf("[%s] timestamp が ISO8601 として読めない: %s", nm, rows_msg(bad)))
  lg$.row <- seq_len(n)
  lg$.ts <- ts
  lg
}

logs <- lapply(LOG_PATHS, read_log)
REVIEWER <- vapply(logs, function(l) l$reviewer[1], "")
if (REVIEWER[1] == REVIEWER[2]) {
  stop("2つの判定ログの reviewer が同じ: ", REVIEWER[1], "（独立した2名の判定ログが必要）")
}
message("判定ログ検証: OK（", paste(basename(LOG_PATHS), "/", REVIEWER, collapse = " ; "), "）")

# =============================================================================
# 3. 圧縮（事例ID ごとに timestamp 順→行順で最終行勝ち。最終 clear は未判定）
# =============================================================================
build_judgments <- function(lg) {
  o <- order(lg$事例ID, lg$.ts, lg$.row)
  s <- lg[o, , drop = FALSE]
  last <- !duplicated(s$事例ID, fromLast = TRUE)
  win <- s[last, , drop = FALSE]
  n_raw <- table(lg$事例ID)
  m <- match(sheet_ids, win$事例ID)
  J <- data.frame(事例ID = sheet_ids, stringsAsFactors = FALSE)
  J$n_raw <- ifelse(is.na(m), 0L, as.integer(n_raw[sheet_ids]))
  J$status <- ifelse(is.na(m), "never", ifelse(win$action[m] == "clear", "cleared", win$action[m]))
  J$win_row <- ifelse(is.na(m), NA_integer_, win$.row[m])
  J$win_ts <- ifelse(is.na(m), NA_character_, win$timestamp[m])
  J$judged <- J$status %in% c("agree", "modify")
  for (f in entry_fields) {
    v <- ifelse(is.na(m), "", win[[f]][m])
    v[!J$judged] <- ""
    J[[f]] <- v
  }
  J$last_file_row <- ifelse(J$n_raw > 0,
                            vapply(sheet_ids, function(i) as.numeric(max(lg$.row[lg$事例ID == i], 0L)), 1,
                                   USE.NAMES = FALSE),
                            NA_real_)
  J
}
J <- lapply(logs, build_judgments)
cleared_reason_ids <- vector("list", 2)
if (STAGE1) {
  for (k in 1:2) {
    clear_reason <- J[[k]]$judged & J[[k]][[F_ELIG]] == ELIG_INC &
      J[[k]][[F_REASON]] != "" & grepl("組入れ", J[[k]][["メモ"]], fixed = TRUE)
    cleared_reason_ids[[k]] <- sheet_ids[clear_reason]
    J[[k]][[F_REASON]][clear_reason] <- ""
  }
}

incomplete_reason <- function(v) {
  if (STAGE1) {
    if (is_blank(v[F_ELIG])) return("適格性が未記入")
    if (v[F_ELIG] == ELIG_EXC) {
      if (is_blank(v[F_REASON])) return("除外理由が未記入")
      return("")
    }
    if (!is_blank(v[F_REASON])) {
      return("組入れなのに除外理由が記入されている（除外理由は除外のときだけ。除外理由を消すか適格性を直す）")
    }
    return("")
  }
  miss <- REQ[is_blank(v[REQ])]
  if (v[F_TYPE] == CHOKE && is_blank(v[F_RESCUE])) miss <- c(miss, F_RESCUE)
  if (length(miss)) return(paste0("未記入: ", paste(bare(miss), collapse = "・")))
  ""
}
for (k in 1:2) {
  J[[k]]$reason <- vapply(seq_len(N_CAND), function(i) {
    if (!J[[k]]$judged[i]) "" else incomplete_reason(unlist(J[[k]][i, entry_fields]))
  }, "")
  J[[k]]$complete <- J[[k]]$judged & J[[k]]$reason == ""
}
both_judged <- J[[1]]$judged & J[[2]]$judged
both_complete <- J[[1]]$complete & J[[2]]$complete

# =============================================================================
# 4. 一致度
# =============================================================================
cohen_kappa <- function(x, y) {
  n <- length(x)
  if (n == 0) return(c(n = 0, pa = NA, kappa = NA, lo = NA, hi = NA))
  lv <- sort(unique(c(x, y)))
  tb <- table(factor(x, levels = lv), factor(y, levels = lv))
  po <- sum(diag(tb)) / n
  pe <- sum(rowSums(tb) * colSums(tb)) / n^2
  if (n < 2 || pe >= 1) return(c(n = n, pa = 100 * po, kappa = NA, lo = NA, hi = NA))
  kappa <- (po - pe) / (1 - pe)
  se <- sqrt(po * (1 - po) / (n * (1 - pe)^2))
  # 漸近 CI は κ の範囲を外れることがあるので [-1, 1] に収める
  c(n = n, pa = 100 * po, kappa = kappa,
    lo = max(kappa - 1.96 * se, -1), hi = min(kappa + 1.96 * se, 1))
}
agree_rows <- list()
for (f in KAPPA_FIELDS) {
  a <- J[[1]][[f]]; b <- J[[2]][[f]]
  use <- both_judged & !is_blank(a) & !is_blank(b)
  if (f == F_RESCUE) use <- use & J[[1]][[F_TYPE]] == CHOKE & J[[2]][[F_TYPE]] == CHOKE
  r <- cohen_kappa(a[use], b[use])
  agree_rows[[length(agree_rows) + 1]] <- data.frame(
    variable = bare(f), n = as.integer(r["n"]), percent_agreement = unname(r["pa"]),
    kappa = unname(r["kappa"]), ci_low = unname(r["lo"]), ci_high = unname(r["hi"]),
    stringsAsFactors = FALSE)
}
agreement_stage <- do.call(rbind, agree_rows)
AGREE_NAMES <- c("variable", "n", "percent_agreement", "kappa", "ci_low", "ci_high")
if (STAGE1) {
  agreement <- agreement_stage
} else {
  agree1 <- read.csv(AGREE1_CSV, fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
  if (!identical(names(agree1), AGREE_NAMES)) stop("第1段階の一致度ファイルの列が想定と違う: ", AGREE1_CSV)
  agree1 <- agree1[agree1$variable == bare(F_ELIG), , drop = FALSE]
  if (nrow(agree1) != 1) stop("第1段階の一致度ファイルに「適格性」の行が1行でない: ", AGREE1_CSV)
  agreement <- rbind(agree1, agreement_stage)
  rownames(agreement) <- NULL
}
write_csv_raw(agreement, AGREE_CSV)

if (STAGE2) {
  determ_rows <- list()
  for (spec in list(list("修正_摂食介助状況", UNK_ASSIST), list("修正_同席状況", UNK_PRESENT))) {
    for (k in 1:2) {
      v <- J[[k]][[spec[[1]]]][both_judged]
      v <- v[!is_blank(v)]
      determ_rows[[length(determ_rows) + 1]] <- data.frame(
        variable = bare(spec[[1]]), reviewer = REVIEWER[k], n = length(v),
        n_determinable = sum(v != spec[[2]]),
        proportion = if (length(v)) 100 * sum(v != spec[[2]]) / length(v) else NA_real_,
        stringsAsFactors = FALSE)
    }
  }
  determinable <- do.call(rbind, determ_rows)
  write_csv_raw(determinable, DETERM_CSV)
}

# =============================================================================
# 5. 不一致一覧（両者が判定済みで完全な事例のみ）
#    第1段階: 適格性が不一致なら適格性の1行。除外理由は合議しない。
#    第2段階: 分類項目ごとに1行。
# =============================================================================
dis_rows <- list()
add_dis <- function(id, f, a, b) {
  dis_rows[[length(dis_rows) + 1]] <<- data.frame(
    事例ID = id, 変数 = bare(f), reviewer1 = a[[f]], reviewer2 = b[[f]], 合議結果 = "",
    stringsAsFactors = FALSE)
}
pair_idx <- which(both_complete)
for (i in pair_idx) {
  a <- unlist(J[[1]][i, entry_fields]); b <- unlist(J[[2]][i, entry_fields])
  id <- sheet_ids[i]
  if (STAGE1) {
    if (a[F_ELIG] != b[F_ELIG]) {
      add_dis(id, F_ELIG, a, b)
    }
  } else {
    for (f in c(REQ, F_RESCUE, F_PARTY)) {
      if (f == F_RESCUE && !(a[F_TYPE] == CHOKE || b[F_TYPE] == CHOKE)) next
      same <- if (f == F_PARTY) norm_party(a[f]) == norm_party(b[f]) else a[f] == b[f]
      if (!same) add_dis(id, f, a, b)
    }
  }
}
dis <- if (length(dis_rows)) do.call(rbind, dis_rows) else
  data.frame(事例ID = character(0), 変数 = character(0), reviewer1 = character(0),
             reviewer2 = character(0), 合議結果 = character(0), stringsAsFactors = FALSE)
rownames(dis) <- NULL
write_csv_raw(dis, DIS_CSV, bom = TRUE)
elig_dis_ids <- dis$事例ID[dis$変数 == bare(F_ELIG)]
if (STAGE1) {
  context_ids <- unique(dis$事例ID)
  m <- match(context_ids, sheet_ids)
  context <- data.frame(事例ID = context_ids,
                        判定者1_除外理由 = J[[1]][[F_REASON]][m], 判定者2_除外理由 = J[[2]][[F_REASON]][m],
                        判定者1_メモ = J[[1]][["メモ"]][m], 判定者2_メモ = J[[2]][["メモ"]][m],
                        stringsAsFactors = FALSE)
  write_csv_raw(context, p("disagreement_context_stage1.csv"), bom = TRUE)
  reason_order <- function(a, b) {
    reasons <- ALLOWED[[F_REASON]]
    reasons[min(match(c(a, b), reasons))]
  }
  ordered_reason_idx <- which(both_complete & J[[1]][[F_ELIG]] == ELIG_EXC &
                               J[[2]][[F_ELIG]] == ELIG_EXC & J[[1]][[F_REASON]] != J[[2]][[F_REASON]])
}

# =============================================================================
# 6. 合議ファイルの検証と適用
# =============================================================================
cons <- NULL
cons_msg <- paste0("なし（", basename(CONS_CSV), " が無い）")
if (file.exists(CONS_CSV)) {
  cons <- read_char_csv_bom(CONS_CSV)
  nm <- basename(CONS_CSV)
  if (!identical(names(cons), names(dis))) {
    stop(sprintf("[%s] 列が %s と一致しない: %s", nm, paste(names(dis), collapse = ","),
                 paste(names(cons), collapse = ",")))
  }
  cons[] <- lapply(cons, trimws)
  key <- paste(cons$事例ID, cons$変数, sep = "\t")
  if (anyDuplicated(key)) stop("[", nm, "] (事例ID, 変数) が重複している: ", rows_msg(which(duplicated(key))))
  ok_key <- paste(dis$事例ID, dis$変数, sep = "\t")
  if (STAGE2) {
    type_dis_ids <- dis$事例ID[dis$変数 == bare(F_TYPE)]
    ok_key <- c(ok_key, paste(type_dis_ids, bare(F_RESCUE), sep = "\t"))
  }
  bad <- which(!(key %in% ok_key))
  if (length(bad)) {
    stop(sprintf("[%s] 既存の不一致（%s）に無い行がある: %s, (事例ID, 変数) = %s",
                 nm, if (STAGE1) "適格性のみ。除外理由の行は置けない" else "事故類型が不一致の事例の救命介入を含む",
                 rows_msg(bad), paste(key[bad], collapse = " ; ")))
  }
  # reviewer1 / reviewer2 列は、現在の圧縮後の判定値と一致していなければならない
  cmp_norm <- function(f, x) if (f == F_PARTY) ifelse(party_ok(x), norm_party(x), x) else x
  stale_msgs <- character(0)
  for (j in seq_len(nrow(cons))) {
    f <- paste0("修正_", cons$変数[j])
    i <- match(cons$事例ID[j], sheet_ids)
    for (k in 1:2) {
      rec_v <- cmp_norm(f, cons[[paste0("reviewer", k)]][j])
      cur_v <- cmp_norm(f, J[[k]][[f]][i])
      if (!identical(rec_v, cur_v)) {
        stale_msgs <- c(stale_msgs, sprintf("事例ID %s / %s / reviewer%d（%s）: 合議ファイルの記録「%s」≠ 現在の判定「%s」",
                                            cons$事例ID[j], cons$変数[j], k, REVIEWER[k], rec_v, cur_v))
      }
    }
  }
  if (length(stale_msgs)) {
    stop(sprintf("[%s] reviewer1 / reviewer2 列が現在の判定と食い違う（不一致の後に判定が変わった可能性。%s を作り直して合議し直す）:\n%s",
                 nm, basename(DIS_CSV), paste(stale_msgs, collapse = "\n")))
  }
  for (j in seq_len(nrow(cons))) {
    v <- cons$合議結果[j]
    if (v == "") next
    f <- paste0("修正_", cons$変数[j])
    if (f == F_PARTY) {
      if (v != PARTY_NONE && !party_ok(v)) stop(sprintf("[%s] データ行 %d: 当事者番号が不正（番号か「%s」）: %s", nm, j, PARTY_NONE, v))
    } else if (!(v %in% ALLOWED[[f]])) {
      stop(sprintf("[%s] データ行 %d: 列「%s」の合議結果が許容ラベル外: %s", nm, j, f, v))
    }
  }
  cons_msg <- sprintf("あり（%d 行、うち記入済み %d 行）", nrow(cons), sum(cons$合議結果 != ""))
}
cons_get <- function(id, f) {
  if (is.null(cons)) return(NA_character_)
  k <- which(cons$事例ID == id & cons$変数 == bare(f) & cons$合議結果 != "")
  if (length(k) == 0) return(NA_character_)
  v <- cons$合議結果[k[1]]
  if (f == F_PARTY && v == PARTY_NONE) "" else v   # 「なし」= 合議済みの空（NA は未合議）
}

# 事例ごとの解決。why には未解決の理由を積む。
resolve_stage1 <- function(i) {
  id <- sheet_ids[i]
  a <- unlist(J[[1]][i, entry_fields]); b <- unlist(J[[2]][i, entry_fields])
  why <- character(0)
  used_cons <- FALSE
  rec <- c(setNames(rep("", 2), c(F_ELIG, F_REASON)))
  elig_same <- a[F_ELIG] == b[F_ELIG]
  if (elig_same) {
    elig <- a[F_ELIG]
  } else {
    cv <- cons_get(id, F_ELIG)
    if (is.na(cv)) {
      return(list(rec = c(setNames(c(NA_character_, ""), c(F_ELIG, F_REASON))), why = "合議待ち: 適格性", source = NA_character_))
    }
    used_cons <- TRUE
    elig <- cv
  }
  rec[F_ELIG] <- elig
  if (elig == ELIG_EXC) {
    if (elig_same) {
      rec[F_REASON] <- reason_order(a[F_REASON], b[F_REASON])
    } else {
      rec[F_REASON] <- if (a[F_ELIG] == ELIG_EXC) a[F_REASON] else b[F_REASON]
    }
  }
  list(rec = rec, why = why, source = if (id %in% dis$事例ID || used_cons) "consensus" else "agreed")
}

resolve_stage2 <- function(i) {
  id <- sheet_ids[i]
  a <- unlist(J[[1]][i, entry_fields]); b <- unlist(J[[2]][i, entry_fields])
  why <- character(0)
  used_cons <- FALSE
  pick <- function(f, same, va) {
    if (same) return(va)
    cv <- cons_get(id, f)
    if (is.na(cv)) {
      why <<- c(why, paste0("合議待ち: ", bare(f)))
      return(NA_character_)
    }
    used_cons <<- TRUE
    cv
  }
  fields <- c(REQ, F_RESCUE, F_PARTY)
  rec <- setNames(rep("", length(fields)), fields)
  for (f in REQ) rec[f] <- pick(f, a[f] == b[f], a[f])
  if (!is.na(rec[F_TYPE]) && rec[F_TYPE] == CHOKE) {
    same_r <- a[F_RESCUE] == b[F_RESCUE] && a[F_RESCUE] != ""
    if (same_r) {
      rec[F_RESCUE] <- a[F_RESCUE]
    } else {
      cv <- cons_get(id, F_RESCUE)
      if (is.na(cv)) {
        type_by_consensus <- a[F_TYPE] != b[F_TYPE]
        why <- c(why, if (type_by_consensus) {
          "合議待ち: 救命介入（合議で事故類型が窒息・気道閉塞になったため必須。救命介入の合議行が無い）"
        } else "合議待ち: 救命介入")
        rec[F_RESCUE] <- NA_character_
      } else {
        used_cons <- TRUE
        rec[F_RESCUE] <- cv
      }
    }
  }
  rec[F_PARTY] <- pick(F_PARTY, norm_party(a[F_PARTY]) == norm_party(b[F_PARTY]), norm_party(a[F_PARTY]))
  list(rec = rec, why = why, source = if (id %in% dis$事例ID || used_cons) "consensus" else "agreed")
}
resolve_one <- if (STAGE1) resolve_stage1 else resolve_stage2
resolved <- lapply(seq_len(N_CAND), function(i) if (both_complete[i]) resolve_one(i) else NULL)

unresolved_lines <- character(0)
n_fully_resolved <- 0L
for (i in seq_len(N_CAND)) {
  r <- resolved[[i]]
  if (is.null(r)) next
  if (length(r$why) == 0 && !anyNA(r$rec)) {
    n_fully_resolved <- n_fully_resolved + 1L
  } else {
    unresolved_lines <- c(unresolved_lines, paste0(sheet_ids[i], ": ", paste(unique(r$why), collapse = " / ")))
  }
}

# =============================================================================
# 7. 最終結果（全候補が2名とも判定済み・完全・全不一致が合議済みのときだけ）
# =============================================================================
blockers <- character(0)
for (k in 1:2) {
  nj <- sum(!J[[k]]$judged)
  if (nj > 0) blockers <- c(blockers, sprintf("%s: 未判定 %d 件", REVIEWER[k], nj))
  ni <- sum(J[[k]]$judged & !J[[k]]$complete)
  if (ni > 0) blockers <- c(blockers, sprintf("%s: 判定済みだが不完全 %d 件", REVIEWER[k], ni))
}
if (length(unresolved_lines) > 0) {
  blockers <- c(blockers, sprintf("不一致が未合議の事例 %d 件", length(unresolved_lines)))
}
if (STAGE2) blockers <- c(blockers, "第2段階の最終化は 05b_stage2_final.R で行う")
finalisable <- length(blockers) == 0 && n_fully_resolved == N_CAND
final_written <- FALSE
final <- NULL
if (finalisable) {
  recs <- do.call(rbind, lapply(resolved, function(r) r$rec))
  src <- vapply(resolved, function(r) r$source, "")
  if (STAGE1) {
    final <- data.frame(事例ID = sheet_ids, 適格性 = unname(recs[, F_ELIG]), 除外理由 = unname(recs[, F_REASON]),
                        一致 = src, stringsAsFactors = FALSE)
  } else {
    # 全候補（第1段階の最終適格性の順）。適格性・除外理由・除外の事例の一致は第1段階から、分類は第2段階から。
    final <- data.frame(事例ID = s1$事例ID, 適格性 = s1$適格性, 除外理由 = s1$除外理由, stringsAsFactors = FALSE)
    m <- match(sheet_ids, final$事例ID)
    for (f in c(REQ, F_RESCUE, F_PARTY)) {
      v <- rep("", nrow(final))
      v[m] <- unname(recs[, f])
      final[[bare(f)]] <- v
    }
    final$一致 <- s1$一致
    final$一致[m] <- src
  }
  write_csv_raw(final, FINAL_CSV, bom = TRUE)
  md5_of <- function(path) if (file.exists(path)) unname(tools::md5sum(path)) else ""
  stamp_files <- if (STAGE1) stage1_stamp_files(OUT, PREFIX) else stage2_stamp_files(OUT, PREFIX)
  # 論理位置を確かめる（このスクリプトが使ったパスと stamp の対象が同じであること）
  stopifnot(identical(unname(stamp_files[c("log_reviewer1", "log_reviewer2", "consensus", "review_sheets_xlsx")]),
                      c(LOG_PATHS, CONS_CSV, XLSX_PATH)))
  stamp <- data.frame(key = names(stamp_files), value = vapply(stamp_files, md5_of, ""), stringsAsFactors = FALSE)
  rownames(stamp) <- NULL
  write_csv_raw(stamp, STAMP_CSV)
  final_written <- TRUE
}

# =============================================================================
# 8. 要約 md
# =============================================================================
lines <- c()
add <- function(...) lines <<- c(lines, ...)
add(paste0("# tanaka_stroke_aspiration: 判定ログの取り込み（", if (STAGE1) "第1段階・適格性" else "第2段階・分類", "。",
           PREFIX, if (PROD) ", 本番" else ", 架空データ", "）"))
add("", "## 1. 入力と検証")
add(sprintf("- xlsx: `%s`（%s %d 件 / 選択肢 %d 行 / 記入欄 %d 個）", basename(XLSX_PATH), TAB_NAME, N_CAND,
            nrow(codebook), length(entry_fields)))
for (k in 1:2) {
  add(sprintf("- reviewer%d: `%s`（生 %d 行、reviewer = %s）", k, basename(LOG_PATHS[k]), nrow(logs[[k]]), REVIEWER[k]))
}
add(paste0("- 行単位検証（ヘッダ・tab・事例ID の存在・action・プルダウン値",
           if (STAGE2) "・当事者番号" else "", "・agree/modify の矛盾・reviewer・timestamp）: OK。合議ファイルがあれば、行の置き場所と reviewer 列が現在の判定と一致することも検証済み"))
add(paste0("- 合議ファイル: ", cons_msg))
if (STAGE2) {
  add(sprintf("- 第1段階の確定結果: `%s`（%d 件。組入れ %d / 除外 %d）。第1段階の stamp `%s` は現物と一致。第2段階の xlsx の事例IDは第1段階の組入れと過不足なく一致",
              basename(ELIG_FINAL_CSV), nrow(s1), sum(s1$適格性 == ELIG_INC), sum(s1$適格性 == ELIG_EXC), basename(STAMP1_CSV)))
}

add("", "## 2. 圧縮と判定状況（最終行勝ち）")
add("", "| reviewer | 生の行 | 事例ID（ログに出現） | 判定済み | うち完全 | 判定済みだが不完全 | 最終clear（未判定） | ログに無い（未判定） |",
    "|---|---|---|---|---|---|---|---|")
for (k in 1:2) {
  add(sprintf("| %s | %d | %d | %d | %d | %d | %d | %d |", REVIEWER[k], nrow(logs[[k]]),
              length(unique(logs[[k]]$事例ID)), sum(J[[k]]$judged), sum(J[[k]]$complete),
              sum(J[[k]]$judged & !J[[k]]$complete), sum(J[[k]]$status == "cleared"),
              sum(J[[k]]$status == "never")))
}
add("", "### 2.1 同じ事例を複数回保存した行（最終行が有効）")
any_multi <- FALSE
for (k in 1:2) {
  mi <- which(J[[k]]$n_raw > 1)
  for (i in mi) {
    any_multi <- TRUE
    note <- if (!is.na(J[[k]]$last_file_row[i]) && J[[k]]$win_row[i] != J[[k]]$last_file_row[i])
      "（ファイル上の最後の行ではなく timestamp が最新の行が有効）" else ""
    add(sprintf("- %s / %s: %d 行 → 有効は %d 行目（%s, action=%s）%s。現在の状態: %s",
                REVIEWER[k], sheet_ids[i], J[[k]]$n_raw[i], J[[k]]$win_row[i], J[[k]]$win_ts[i],
                J[[k]]$status[i], note,
                if (J[[k]]$complete[i]) "完全" else if (J[[k]]$judged[i]) paste0("不完全（", J[[k]]$reason[i], "）") else "未判定"))
  }
}
if (!any_multi) add("", "該当なし。")
add("", "### 2.2 最終行が clear の事例（未判定扱い）")
any_clear <- FALSE
for (k in 1:2) {
  for (i in which(J[[k]]$status == "cleared")) {
    any_clear <- TRUE
    add(sprintf("- %s / %s（生 %d 行）", REVIEWER[k], sheet_ids[i], J[[k]]$n_raw[i]))
  }
}
if (!any_clear) add("", "該当なし。")
add("", "### 2.3 一度もログに出ない候補（未判定）")
any_never <- FALSE
for (k in 1:2) {
  for (i in which(J[[k]]$status == "never")) {
    any_never <- TRUE
    add(sprintf("- %s / %s", REVIEWER[k], sheet_ids[i]))
  }
}
if (!any_never) add("", "該当なし。")
add("", "### 2.4 判定済みだが不完全な事例（最終化を止める）")
any_inc <- FALSE
for (k in 1:2) {
  for (i in which(J[[k]]$judged & !J[[k]]$complete)) {
    any_inc <- TRUE
    add(sprintf("- %s / %s（action=%s）: %s", REVIEWER[k], sheet_ids[i], J[[k]]$status[i], J[[k]]$reason[i]))
  }
}
if (!any_inc) add("", "該当なし。")
if (STAGE1) {
  add("", "### 2.5 メモの「組入れ」により除外理由を空にした判定")
  for (k in 1:2) {
    add(sprintf("- reviewer%d（%s）: %d 件。事例ID: %s", k, REVIEWER[k], length(cleared_reason_ids[[k]]),
                if (length(cleared_reason_ids[[k]])) paste(cleared_reason_ids[[k]], collapse = ", ") else "なし"))
  }
}

if (STAGE1) {
  add("", "## 3. 適格性の判定")
  add("", "| reviewer | 組入れ | 除外 |", "|---|---|---|")
  for (k in 1:2) {
    add(sprintf("| %s | %d | %d |", REVIEWER[k], sum(J[[k]][[F_ELIG]] == ELIG_INC), sum(J[[k]][[F_ELIG]] == ELIG_EXC)))
  }
  add("", "### 除外理由（reviewer 別）")
  reasons <- ALLOWED[[F_REASON]]
  add("", paste0("| 除外理由 | ", paste(REVIEWER, collapse = " | "), " |"), "|---|---|---|")
  for (r in reasons) {
    add(sprintf("| %s | %d | %d |", r, sum(J[[1]][[F_REASON]] == r & J[[1]][[F_ELIG]] == ELIG_EXC),
                sum(J[[2]][[F_REASON]] == r & J[[2]][[F_ELIG]] == ELIG_EXC)))
  }
} else {
  add("", "## 3. 運営の確認が必要なメモ（第2段階の判定者は除外できない。除外したい事例は メモ に書く）")
  any_memo <- FALSE
  for (k in 1:2) {
    for (i in which(!is_blank(J[[k]][["メモ"]]))) {
      if (!any_memo) add("", "最終行（有効な判定）に付いたメモの全件。運営が内容を見て、除外・再判定などを決める。", "")
      any_memo <- TRUE
      add(sprintf("- %s / %s（action=%s）: %s", REVIEWER[k], sheet_ids[i], J[[k]]$status[i], md_cell(J[[k]][["メモ"]][i])))
    }
  }
  if (!any_memo) add("", "該当なし（メモは1件も無い）。")
}

add("", paste0("## 4. 一致度（両者が判定した候補。κ は重みなし、95%CI は単純な漸近標準誤差）"))
add("", "| 項目 | n | 一致率 | κ | 95%CI |", "|---|---|---|---|---|")
for (i in seq_len(nrow(agreement))) {
  r <- agreement[i, ]
  add(sprintf("| %s | %d | %s | %s | %s |", r$variable, r$n, pct1(r$percent_agreement), num2(r$kappa),
              if (is.na(r$ci_low)) "-" else sprintf("%s to %s", num2(r$ci_low), num2(r$ci_high))))
}
if (STAGE1) {
  add("", "κ は表が縮退（一方の値しか使われない）のとき「-」。")
} else {
  add("", "適格性の行は第1段階の一致度ファイルのコピー。分類項目の n は、両者がその項目を記入済みの候補数（救命介入は両者が窒息・気道閉塞の候補）。κ は表が縮退（一方の値しか使われない）のとき「-」。")
  add("", "### 判定できた割合（不明でない割合。両者が判定した候補）", "",
      "| 項目 | reviewer | n | 判定できた n | 割合 |", "|---|---|---|---|---|")
  for (i in seq_len(nrow(determinable))) {
    r <- determinable[i, ]
    add(sprintf("| %s | %s | %d | %d | %s |", r$variable, r$reviewer, r$n, r$n_determinable, pct1(r$proportion)))
  }
}

add("", "## 5. 不一致")
add(sprintf("- 比較できた事例（両者が判定済みで完全）: %d 件 / 不一致の行: %d 行（%s）", length(pair_idx), nrow(dis),
            basename(DIS_CSV)))
add("", "| 項目 | 不一致の行数 |", "|---|---|")
for (v in unique(dis$変数)) {
  add(sprintf("| %s | %d |", v, sum(dis$変数 == v)))
}
if (nrow(dis) == 0) add("| （なし） | 0 |")
if (STAGE1) {
  add(sprintf("- 適格性が不一致の事例: %d 件。合議は適格性の1行だけ。除外なら除外と判定した側の理由を採り、組入れなら理由は空。除外理由の合議行は置けない。",
              length(elig_dis_ids)))
  add("- 両者が除外で除外理由だけが違う事例は不一致に含めず、選択肢タブの並び順で先の理由を採る（一致は agreed）。")
  add(sprintf("- 合議用の補足 CSV: `%s`（圧縮・補正後の除外理由とメモ）", basename(p("disagreement_context_stage1.csv"))))
  add("", "### 除外理由を並び順で決めた事例", sprintf("件数: %d", length(ordered_reason_idx)), "",
      "| 事例ID | reviewer1 の理由 | reviewer2 の理由 | 採った理由 |", "|---|---|---|---|")
  for (i in ordered_reason_idx) {
    a <- J[[1]][[F_REASON]][i]; b <- J[[2]][[F_REASON]][i]
    add(sprintf("| %s | %s | %s | %s |", sheet_ids[i], md_cell(a), md_cell(b), md_cell(reason_order(a, b))))
  }
} else {
  add(sprintf("- 合議の書き方: 合議結果が空の行は未合議。ただし「直接介助者の当事者番号」に限り、「%s」と書くと「合議の結果、直接介助者を特定できない」（最終値は空）として合議済みになる。", PARTY_NONE),
      "- 事故類型が不一致の事例では、合議で事故類型が窒息・気道閉塞に決まったら救命介入が必須になるので、救命介入の行を合議ファイルに足す（reviewer1 / reviewer2 列は現在の値、空でもよい）。")
}
add("- 合議ファイルの reviewer1 / reviewer2 列は現在の判定と一致している必要がある。判定が変わっていたら停止する（不一致一覧を作り直して合議し直す）。")

add("", "## 6. 最終化")
if (finalisable) {
  add(sprintf("- **最終結果を書き出した**: `%s`（%d 件。agreed %d / consensus %d）。入力の md5 を `%s` に記録した",
              basename(FINAL_CSV), nrow(final), sum(final$一致 == "agreed"), sum(final$一致 == "consensus"),
              basename(STAMP_CSV)))
  add("", "| 適格性 | n |", "|---|---|")
  for (v in unique(final$適格性)) add(sprintf("| %s | %d |", v, sum(final$適格性 == v)))
  if (STAGE1) {
    add("", paste0("次の手順: `02_review_sheets.R --stage2` で、組入れの ", sum(final$適格性 == ELIG_INC), " 件だけの第2段階シートを作る。"))
  }
} else {
  add("- **最終結果は書き出していない**。理由:")
  for (b in blockers) add(paste0("  - ", b))
  if (length(unresolved_lines)) {
    add("", "未合議の事例:")
    for (u in unresolved_lines) add(paste0("  - ", u))
  }
  if (length(blockers) == 0) add("  - 内部不整合: 全件が解決していない")
  add("", if (length(stale_removed)) {
    paste0("- 前回の出力 ", paste0("`", stale_removed, "`", collapse = ", "),
           " は古くなったので**削除した**（",
           if (STAGE1) "第2段階と報告書は" else "報告書は", "最終結果が書き直されるまで作れない）。")
  } else "- 削除した前回の最終結果・stamp: なし。")
}
write_lf_md(lines, SUMMARY_MD)
message("出力: ", SUMMARY_MD)
message(if (final_written) "最終結果を書き出した: " else "最終結果は書き出していない（理由は要約）: ",
        FINAL_CSV)
cat("done: 03_app_intake.R --", STAGE, "\n", sep = "")
