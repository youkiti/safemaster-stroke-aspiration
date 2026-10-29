# 候補事例の定義（tanaka_stroke_aspiration）— 共通ヘルパー（source して使う。source しただけでは何も実行しない）
#
# 01_feasibility_counts.R の検索語とマスクをそのまま移したもの。候補 T1〜T4 を返す
# build_candidates() が、レビューシート作成（02）・判定ログ取り込み（03）・解析（derive_cohort.R）の
# 単一の入口になる。検索語や段階の定義を変えるときは 01 と見比べて同じ結果になることを確かめる。
#
# 提供するもの:
#   load_safemaster_r19(prod, repo_root)      架空100行 CSV または本番 RDS を全列 character で読む
#   build_candidates(d, synth_fallback)       T1〜T4 ほかの論理ベクトルと列名のリスト
#   check_candidates(cand, prod)              本番では T1〜T4 の件数が EXPECTED_PROD と一致しなければ stop
#   EXPECTED_PROD                             01 を本番 r19 で実測した件数（編集して通さない）
#   read_code_labels / decode_codes           コード列を日本語ラベルに直す（表に無い値は本番で stop）
#   stage1_stamp_files / stage2_stamp_files / stamp_problems   取り込み stamp（md5）が覆うファイルと、現物との照合
#   小さな入出力ヘルパー: read_char_csv_bom / write_csv_raw / write_lf_md / md_cell / blank / is_blank
#
# 使い方（実行ディレクトリは projects/tanaka_stroke_aspiration/）:
#   source("analysis/candidates.R")
#   d    <- load_safemaster_r19(PROD)
#   cand <- build_candidates(d, synth_fallback = !PROD)
#   check_candidates(cand, PROD)

suppressPackageStartupMessages(library(dplyr))

# 01_feasibility_counts.R を本番 r19 で実行して得た候補件数。実装を合わせるために数値を変えない。
EXPECTED_PROD <- c(T1 = 10, T2 = 39, T3 = 85, T4 = 134)

# ---- 入出力ヘルパー ----
# BOM は生の不可視文字としてソースに書かず、コードポイントから組み立てる。
BOM_CHAR <- intToUtf8(0xFEFF)

blank    <- function(x) ifelse(is.na(x), "", trimws(x))
is_blank <- function(x) is.na(x) | trimws(x) == ""

read_char_csv_bom <- function(path) {
  df <- read.csv(path, colClasses = "character", fileEncoding = "UTF-8-BOM",
                 check.names = FALSE, na.strings = character(0), stringsAsFactors = FALSE)
  names(df) <- gsub(paste0("^", BOM_CHAR), "", names(df))
  df
}

# CSV をバイト単位で書く（Windows のテキストモードによる改行変換を避ける）。
# 区切りはカンマ、必要なセルだけ二重引用符で囲む（RFC 4180）。
write_csv_raw <- function(df, path, bom = FALSE, eol = "\n") {
  quote_cell <- function(x) {
    x <- ifelse(is.na(x), "", as.character(x))
    needs <- grepl("[\",\r\n]", x)
    x[needs] <- paste0("\"", gsub("\"", "\"\"", x[needs], fixed = TRUE), "\"")
    x
  }
  header <- paste(quote_cell(names(df)), collapse = ",")
  body <- if (nrow(df) > 0) do.call(paste, c(lapply(df, quote_cell), sep = ",")) else character(0)
  content <- paste0(paste(c(header, body), collapse = eol), eol)
  con <- file(path, open = "wb")
  if (bom) {
    writeBin(charToRaw(BOM_CHAR), con)
  }
  writeBin(charToRaw(enc2utf8(content)), con)
  close(con)
}

write_lf_md <- function(lines, path) {
  content <- paste0(paste(lines, collapse = "\n"), "\n")
  con <- file(path, open = "wb")
  writeBin(charToRaw(enc2utf8(content)), con)
  close(con)
}

# ---- 第1段階（適格性）の取り込み結果の stamp 検証（02・03・derive_cohort.R が共有） ----
# 第1段階の入力ファイル（key → パス）。stamp の key 集合と一致していなければならない。
stage1_stamp_files <- function(out, prefix) {
  pp <- function(s) file.path(out, paste0(prefix, "_", s))
  c(log_reviewer1 = pp("app_judgment_log_stage1_reviewer1.csv"),
    log_reviewer2 = pp("app_judgment_log_stage1_reviewer2.csv"),
    consensus = pp("consensus_stage1.csv"),
    review_sheets_xlsx = pp("review_sheets_stage1.xlsx"),
    final_eligibility = pp("final_eligibility.csv"))
}

# 第2段階の取り込み stamp が覆うファイル（key → パス）。derive_cohort.R が現物と照合する。
stage2_stamp_files <- function(out, prefix, analysis_dir = "analysis") {
  pp <- function(s) file.path(out, paste0(prefix, "_", s))
  c(log_reviewer1 = pp("app_judgment_log_stage2_reviewer1.csv"),
    log_reviewer2 = pp("app_judgment_log_stage2_reviewer2.csv"),
    consensus = pp("consensus_stage2.csv"),
    stage1_final_eligibility = pp("final_eligibility.csv"),
    stage1_stamp = pp("intake_stamp_stage1.csv"),
    pilot10_ids = pp("stage2_pilot10_ids.csv"),
    pilot10_gold_v2 = pp("stage2_pilot10_gold_v2.csv"),
    pilot10_gold_v2_stamp = pp("stage2_pilot10_gold_v2_stamp.csv"),
    rest_tanaka_final = file.path(out, "stage2_rest_intake_田中", "final.csv"),
    rest_tanaka_diff = file.path(out, "stage2_rest_intake_田中", "diff.csv"),
    rest_suehiro_final = file.path(out, "stage2_rest_intake_末廣", "final.csv"),
    rest_suehiro_diff = file.path(out, "stage2_rest_intake_末廣", "diff.csv"),
    stage2_exclusions = file.path(analysis_dir, "stage2_exclusions.csv"),
    review_codebook = file.path(analysis_dir, "review_codebook.csv"),
    agreement = pp("agreement.csv"),
    determinable = pp("determinable.csv"),
    review_changes = pp("stage2_review_changes.csv"),
    final_classification = pp("final_classification.csv"))
}

# stamp（key,value の CSV）の md5 を現物と照合する。問題の文字列ベクトルを返す（空なら一致）。
# 現物が無いファイルの md5 は ""（合議ファイルは任意なので、記録も "" なら一致）。
stamp_problems <- function(stamp_path, files) {
  if (!file.exists(stamp_path)) return(paste0("stamp が無い: ", stamp_path))
  stamp <- read_char_csv_bom(stamp_path)
  if (!identical(names(stamp), c("key", "value")) || !setequal(stamp$key, names(files)) || anyDuplicated(stamp$key)) {
    return(paste0("stamp の形式が想定と違う（key: ", paste(names(files), collapse = ", "), "）: ", stamp_path))
  }
  bad <- character(0)
  for (k in names(files)) {
    recorded <- stamp$value[stamp$key == k]
    current <- if (file.exists(files[[k]])) unname(tools::md5sum(files[[k]])) else ""
    if (!identical(recorded, current)) {
      bad <- c(bad, sprintf("%s（記録 %s / 現在 %s）", basename(files[[k]]),
                            if (recorded == "") "なし" else recorded, if (current == "") "なし" else current))
    }
  }
  bad
}

md_cell <- function(x, max_chars = NULL) {
  x <- ifelse(is.na(x), "", x)
  x <- gsub("[\r\n]+", " ", x)
  x <- gsub("\\|", "／", x)
  x <- trimws(x)
  if (!is.null(max_chars)) {
    x <- ifelse(nchar(x) > max_chars, paste0(substr(x, 1, max_chars), "…"), x)
  }
  x
}

# ---- コード → 日本語ラベル（analysis/code_labels.csv: variable, code, label） ----
read_code_labels <- function(path) {
  lab <- read.csv(path, colClasses = "character", fileEncoding = "UTF-8-BOM", check.names = FALSE)
  stopifnot(identical(names(lab), c("variable", "code", "label")),
            !anyDuplicated(paste(lab$variable, lab$code)))
  lab
}
# fail-loud: 表に無い非欠測コードは strict（本番）なら stop、そうでなければ警告して「?コード」にする。
# 欠測・空は missing の値を返す。
decode_codes <- function(labels, variable, codes, strict, missing = "") {
  codes <- trimws(codes)
  out <- rep(missing, length(codes))
  ok <- !is.na(codes) & codes != ""
  tab <- labels[labels$variable == variable, , drop = FALSE]
  if (nrow(tab) == 0) stop("code_labels.csv に変数が無い: ", variable)
  lab <- tab$label[match(codes[ok], tab$code)]
  unk <- is.na(lab)
  if (any(unk)) {
    msg <- sprintf("code_labels.csv に無いコード（%s）: %s", variable,
                   paste(unique(codes[ok][unk]), collapse = ", "))
    if (strict) {
      stop(msg)
    }
    warning(msg, "（架空データのコードは乱数。先頭に ? を付けて出力）", call. = FALSE)
    lab[unk] <- paste0("?", codes[ok][unk])
  }
  out[ok] <- lab
  out
}

# ---- データ読み込み（01 と同じ: 全列 character、重複列名は make.unique、"." は欠測） ----
load_safemaster_r19 <- function(prod, repo_root = file.path("..", "..")) {
  if (!prod) {
    master <- Sys.getenv("SAFEMASTER_DIR")
    if (!nzchar(trimws(master))) {
      stop("Set SAFEMASTER_DIR to the folder containing 記述研究のときのレガシーファイル/架空データ100行_r19.csv for synthetic data.")
    }
    legacy <- file.path(master, "記述研究のときのレガシーファイル")
    d <- read.csv(file.path(legacy, "架空データ100行_r19.csv"),
                  fileEncoding = "UTF-8-BOM", check.names = FALSE,
                  colClasses = "character")
  } else {
    d <- readRDS(file.path(repo_root, "data", "safemaster_r19_text.rds"))
  }
  names(d) <- make.unique(names(d))   # 重複列名を一意化
  d[d == "."] <- NA
  d
}

# ===== 検索語（01_feasibility_counts.R と同一。プロポーザル5.2 ＋ 同義語補完。感度優先） =====
STROKE_TERMS <- c("脳卒中", "脳梗塞", "脳出血", "脳内出血", "くも膜下", "クモ膜下",
                  "蜘蛛膜下", "ｸﾓ膜下", "脳血管障害", "脳血管疾患", "脳塞栓", "脳血栓",
                  "ラクナ", "被殻出血", "視床出血", "小脳出血", "脳幹出血", "脳幹部出血",
                  "皮質下出血", "脳室内出血", "橋出血", "小脳梗塞", "脳幹梗塞",
                  "延髄梗塞", "延髄外側", "ワレンベルグ", "Wallenberg",
                  "ＳＡＨ", "SAH")
# 脳卒中として扱わないもの（プロポーザル5.2: TIA・外傷性頭蓋内出血・慢性硬膜下血腫）
# と、脳卒中語に部分一致するだけの語（脊髄くも膜下麻酔など）
STROKE_NOT   <- c("外傷性くも膜下", "外傷性クモ膜下", "外傷性蜘蛛膜下", "外傷性脳出血",
                  "外傷性脳内出血", "外傷性ＳＡＨ", "外傷性SAH",
                  "くも膜下麻酔", "クモ膜下麻酔", "くも膜下腔", "クモ膜下腔",
                  "くも膜下ブロック", "クモ膜下ブロック", "くも膜下ドレ", "クモ膜下ドレ")
EVENT_TERMS  <- c("誤嚥", "窒息", "気道閉塞", "食塊", "詰ま", "つまらせ", "喉につま",
                  "のどにつま")
CHOKE_TERMS  <- c("窒息", "気道閉塞", "食塊", "詰ま", "つまらせ", "喉につま", "のどにつま")
# 「パン」「ゼリー」「お茶」は「リハビリパンツ」「キシロカインゼリー」等に部分一致するので入れない
MEAL_TERMS   <- c("食事", "飲水", "経口摂取", "朝食", "昼食", "夕食", "間食", "おやつ",
                  "食べ", "飲み込", "摂食", "配膳", "嚥下食", "とろみ", "トロミ",
                  "粥", "水分摂取")
# 除外候補の目安（非経口の栄養投与・経口薬）。件数の目安であって除外の確定ではない。
TUBE_TERMS   <- c("経管栄養", "胃瘻", "胃ろう", "腸瘻", "経鼻胃管", "胃管", "経鼻栄養",
                  "ＮＧチューブ", "NGチューブ", "栄養チューブ", "ＰＥＧ", "PEG", "注入")
# ====================================================================

build_candidates <- function(d, synth_fallback = FALSE) {
  num <- function(x) suppressWarnings(as.numeric(x))
  re  <- function(terms) paste(terms, collapse = "|")
  need <- function(cn) {
    if (!cn %in% names(d)) stop("列が無い: ", cn)
    d[[cn]]
  }

  # 「事例の内容」は同名2列（コード列と自由記載本文）。接尾辞は読み込み経路で変わるので、
  # 平均文字数で判別する（短い方＝コード、長い方＝本文）。
  naiyo_cols <- grep("^事例の内容(\\.|$)", names(d), value = TRUE)
  if (length(naiyo_cols) != 2) stop("事例の内容 の同名列が2本でない: ", paste(naiyo_cols, collapse = ", "))
  mean_len   <- vapply(d[naiyo_cols], function(c) mean(nchar(ifelse(is.na(c), "", c))), numeric(1))
  NAIYO_CODE <- naiyo_cols[which.min(mean_len)]
  NARR       <- naiyo_cols[which.max(mean_len)]
  if (NAIYO_CODE == NARR) stop("事例の内容 のコード列と本文列を判別できない")

  DX_DIRECT <- "事例に直接関連する疾患名"
  DX_OTHER  <- c("関連する疾患名１", "関連する疾患名２", "関連する疾患名３")
  # 事故の場面を書く欄。「改善策」は再発防止の定型句（誤嚥予防・食事時の観察）で
  # 無関係な事例まで拾うので検索対象にしない。
  FREE_COLS <- c(NARR, "事例の背景要因の概要", "実施した医療行為の目的",
                 "種類_その他（記述）", "事例の内容_その他（記述）",
                 "直前の患者の状態_その他特記する心身状態あり（記述）")
  for (cn in c("事例ID", DX_DIRECT, DX_OTHER, FREE_COLS, "種類", "概要", "患者区分",
               "事故の程度", "治療の程度", "報告年")) need(cn)

  paste_cols <- function(cols)
    apply(d[cols], 1, function(r) paste(r[!is.na(r)], collapse = " "))
  # 脳卒中語の判定は、除外語（外傷性〜）を消してから行う
  has_stroke <- function(x) grepl(re(STROKE_TERMS), gsub(re(STROKE_NOT), "", x))

  dx_direct_txt <- ifelse(is.na(d[[DX_DIRECT]]), "", d[[DX_DIRECT]])
  dx_other_txt  <- paste_cols(DX_OTHER)
  free_txt      <- paste_cols(FREE_COLS)

  stroke_direct <- has_stroke(dx_direct_txt)            # 直接関連する疾患名が脳卒中
  stroke_dx     <- stroke_direct | has_stroke(dx_other_txt)  # 疾患名4欄のいずれか
  stroke_any    <- stroke_dx | has_stroke(free_txt)     # ＋自由記載

  naiyo  <- num(d[[NAIYO_CODE]]); shurui <- num(d$種類)
  code47   <- !is.na(naiyo) & naiyo == 47               # 事例の内容=47 誤嚥
  meal_cd  <- !is.na(shurui) & shurui %in% c(40, 77, 78) # 種類=40 経口摂取, 77 食事介助, 78 食事中
  event_tx <- grepl(re(EVENT_TERMS), free_txt)
  meal_tx  <- grepl(re(MEAL_TERMS), free_txt)
  tube_tx  <- grepl(re(TUBE_TERMS), free_txt)
  event    <- code47 | event_tx
  meal     <- meal_cd | meal_tx

  kubun <- num(d$患者区分)
  inpt  <- !is.na(kubun) & kubun == 2                   # 患者区分=2 入院（r19 辞書）

  # 候補の段階（すべて入院に限定）
  T1 <- inpt & stroke_direct & code47 & meal_cd         # 構造化コードだけで確定する最狭
  T2 <- inpt & stroke_direct & event & meal             # 直接疾患名が脳卒中
  T3 <- inpt & stroke_dx     & event & meal             # 疾患名4欄のいずれかが脳卒中
  T4 <- inpt & stroke_any    & event & meal             # 自由記載の脳卒中語も含む（最広）

  # 架空データには脳卒中語が無く T4 が 0 件になる。動作確認のためだけに、入院の先頭30件
  # （事例ID順）を T3・T4 に置き換える。本番では使わない。
  fallback_used <- FALSE
  if (synth_fallback && sum(T4) == 0) {
    ids <- d$事例ID
    ord <- order(suppressWarnings(as.numeric(ids)), ids)
    pick <- head(ord[inpt[ord]], 30)
    T4 <- rep(FALSE, nrow(d))
    T4[pick] <- TRUE
    T3 <- T4
    fallback_used <- TRUE
  }

  list(T1 = T1, T2 = T2, T3 = T3, T4 = T4, inpt = inpt,
       stroke_direct = stroke_direct, stroke_dx = stroke_dx, stroke_any = stroke_any,
       event = event, meal = meal, code47 = code47, meal_cd = meal_cd, tube_tx = tube_tx,
       narr_col = NARR, naiyo_code_col = NAIYO_CODE,
       synth_fallback_used = fallback_used)
}

check_candidates <- function(cand, prod) {
  got <- c(T1 = sum(cand$T1), T2 = sum(cand$T2), T3 = sum(cand$T3), T4 = sum(cand$T4))
  if (prod) {
    # sum() は integer、EXPECTED_PROD は double なので identical() では比べない
    if (!all(got == EXPECTED_PROD[names(got)])) {
      stop(sprintf("候補件数が01の本番実測と一致しない: 実際 %s / 期待 %s",
                   paste(names(got), got, sep = "=", collapse = ", "),
                   paste(names(EXPECTED_PROD), EXPECTED_PROD, sep = "=", collapse = ", ")))
    }
    message("候補件数チェック: OK（", paste(names(got), got, sep = "=", collapse = ", "), "）")
  } else {
    message("候補件数（架空データ・照合なし）: ", paste(names(got), got, sep = "=", collapse = ", "),
            if (isTRUE(cand$synth_fallback_used)) "（先頭30件の代替候補を使用）" else "")
  }
  invisible(got)
}
