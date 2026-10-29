# tanaka_stroke_aspiration: 03_app_intake.R の動作確認用に、架空の判定ログ2本を作る（架空データ専用。--prod は拒否）
#
# 段階を必ず指定する（--stage1 か --stage2）。
#   --stage1  入力: output/synth_review_sheet_candidates_stage1.csv（02_review_sheets.R --stage1 の出力）
#   --stage2  入力: output/synth_review_sheet_candidates_stage2.csv（02_review_sheets.R --stage2 の出力）と
#             output/synth_final_eligibility.csv（03_app_intake.R --stage1 の最終適格性）。
#             第2段階シートの事例IDが、最終適格性の組入れと一致していなければ停止する。
#   analysis/review_codebook.csv
# 出力（output/）:
#   synth_app_judgment_log_stage{1,2}_reviewer1.csv, synth_app_judgment_log_stage{1,2}_reviewer2.csv
#       アプリの判定ログと同じ形式（UTF-8 BOM付き, RFC4180, ヘッダ行あり）。列は
#       timestamp, reviewer, tab, 事例ID, action, 記入欄（修正_* と メモ。シートの順）。
#       tab は第1段階が 候補、第2段階が 組入れ。
#   synth_fixture_notes_stage{1,2}.md   どの事例にどの仕掛けを入れたか
#   synth_consensus_stage{1,2}.csv      --complete のときだけ。不一致を全て解決した合議ファイル
#
# 既定（第1ラウンド）は、取り込みの検証に使う次の仕掛けを入れる:
#   A  reviewer1 が2回保存（最初は不完全、後の行が有効）
#   B  reviewer2 が2回保存。timestamp が新しい行をファイル上は先に置く（timestamp 順の最終行勝ちを確かめる）
#   C  reviewer1 の最終行が clear（未判定扱い）
#   D  reviewer2 が一度も判定しない候補
#   E  reviewer1 が修正_* を何も入れずに保存（agree。判定済みだが不完全）
#   第1段階: 適格性の不一致 4 件（組入れ→除外と除外→組入れの両方向）、両者が除外で除外理由だけが違う 1 件 (G)
#   第2段階: 全事例の約20%で reviewer2 の分類項目が1つ違う
# --complete を付けると、第1ラウンドの行に、C・D・E を完全に判定した後の行を追記し、合議ファイルも書く。
#   第1段階の合議: 適格性の不一致は両方向とも解決（4件のうち2件が除外に決まり、その2件は除外理由の合議行も入れる）。
#   第2段階の合議: P（直接介助者の当事者番号の不一致 → 「なし」）、R（事故類型が 誤嚥 vs 判定不能 →
#                  窒息・気道閉塞に決め、救命介入の合議行も入れる）を含む。
#
# 使い方（実行ディレクトリは projects/tanaka_stroke_aspiration/）:
#   Rscript analysis/make_synth_fixture.R --stage1 [--complete]
#   Rscript analysis/make_synth_fixture.R --stage2 [--complete]

args <- commandArgs(trailingOnly = TRUE)
if ("--prod" %in% args) stop("make_synth_fixture.R は架空データ専用（--prod は拒否）")
STAGE1 <- "--stage1" %in% args
STAGE2 <- "--stage2" %in% args
if (STAGE1 == STAGE2) {
  stop("使い方: Rscript analysis/make_synth_fixture.R --stage1|--stage2 [--complete]（架空データ専用）")
}
SN <- if (STAGE1) "stage1" else "stage2"
TAB <- if (STAGE1) "候補" else "組入れ"
COMPLETE <- "--complete" %in% args
OUT <- Sys.getenv("TANAKA_OUT", "output")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

source(file.path("analysis", "candidates.R"))   # 入出力ヘルパー

cand_path <- file.path(OUT, paste0("synth_review_sheet_candidates_", SN, ".csv"))
if (!file.exists(cand_path)) stop("先に 02_review_sheets.R --", SN, " を実行: ", cand_path)
cand <- read_char_csv_bom(cand_path)
codebook <- read.csv(file.path("analysis", "review_codebook.csv"), colClasses = "character",
                     fileEncoding = "UTF-8-BOM", check.names = FALSE)

ids <- cand$事例ID
n <- length(ids)
entry_fields <- names(cand)[grepl("^修正_", names(cand)) | names(cand) == "メモ"]
judge_fields <- grep("^修正_", entry_fields, value = TRUE)
REVIEWERS <- c("synthetic_reviewer1", "synthetic_reviewer2")

opts <- function(variable) codebook$日本語ラベル[codebook$変数 == variable]
L <- function(variable, code) {
  v <- codebook$日本語ラベル[codebook$変数 == variable & codebook$英語コード == code]
  stopifnot(length(v) == 1)
  v
}
CHOKE <- L("事故類型", "choking")
ELIG_INC <- L("適格性", "include")
ELIG_EXC <- L("適格性", "exclude")
F_ELIG <- "修正_適格性"; F_REASON <- "修正_除外理由"; F_TYPE <- "修正_事故類型"
F_RESCUE <- "修正_救命介入"; F_PARTY <- "修正_直接介助者の当事者番号"
REQ <- paste0("修正_", c("脳卒中の位置づけ", "脳卒中病型", "事故類型", "摂取物", "摂食介助状況",
                         "同席状況", "嚥下評価", "指示逸脱", "食事区分"))
if (STAGE1) {
  stopifnot(identical(entry_fields, c(F_ELIG, F_REASON, "メモ")))
} else {
  stopifnot(identical(entry_fields, c(REQ, F_RESCUE, F_PARTY, "メモ")))
  elig_final_path <- file.path(OUT, "synth_final_eligibility.csv")
  if (!file.exists(elig_final_path)) stop("第1段階の最終適格性が無い（先に 03_app_intake.R --stage1 を最終化まで通す）: ", elig_final_path)
  ef <- read_char_csv_bom(elig_final_path)
  if (!setequal(ids, ef$事例ID[ef$適格性 == ELIG_INC]) || anyDuplicated(ids)) {
    stop("第2段階シートの事例IDが、第1段階で組入れに確定した事例IDと一致しない（02_review_sheets.R --stage2 を作り直す）")
  }
}

set.seed(20261012)
n_parties <- pmax(1L, lengths(strsplit(cand$当事者, " / ", fixed = TRUE)))

blank_vec <- function() setNames(rep("", length(entry_fields)), entry_fields)
wpick <- function(variable, codes, prob) {
  lab <- vapply(codes, function(cd) L(variable, cd), "")
  sample(lab, 1, prob = prob)
}
random_excluded <- function() {
  v <- blank_vec()
  v[F_ELIG] <- ELIG_EXC
  v[F_REASON] <- sample(opts("除外理由"), 1)
  v
}
included_elig <- function() {
  v <- blank_vec()
  v[F_ELIG] <- ELIG_INC
  v
}
random_classified <- function(i) {
  v <- blank_vec()
  v["修正_脳卒中の位置づけ"] <- wpick("脳卒中の位置づけ", c("primary", "comorbid", "unclear"), c(.65, .25, .10))
  v["修正_脳卒中病型"] <- wpick("脳卒中病型", c("infarct", "ich", "sah", "unspecified"), c(.55, .30, .10, .05))
  v[F_TYPE] <- wpick("事故類型", c("choking", "aspiration", "unclear"), c(.40, .55, .05))
  v["修正_摂取物"] <- wpick("摂取物", c("food", "fluid", "both", "unknown"), c(.60, .25, .05, .10))
  v["修正_摂食介助状況"] <- wpick("摂食介助状況", c("assisted", "self", "unknown"), c(.50, .35, .15))
  v["修正_同席状況"] <- wpick("同席状況", c("present", "alone", "unknown"), c(.50, .35, .15))
  v["修正_嚥下評価"] <- wpick("嚥下評価", c("done", "not_done", "unknown"), c(.40, .20, .40))
  v["修正_指示逸脱"] <- wpick("指示逸脱", c("yes", "no_unknown"), c(.25, .75))
  v["修正_食事区分"] <- wpick("食事区分", c("breakfast", "lunch", "dinner", "other_unknown"), c(.20, .25, .25, .30))
  if (v[F_TYPE] == CHOKE) {
    v[F_RESCUE] <- wpick("救命介入", c("yes", "no", "unknown"), c(.50, .30, .20))
  }
  if (runif(1) < 0.7) {
    k <- n_parties[i]
    v[F_PARTY] <- if (k >= 2 && runif(1) < 0.15) "1,2" else as.character(sample.int(k, 1))
  }
  v
}

# ---- 各事例の「真の」判定と、reviewer2 の食い違い ----
flip_to_exc <- flip_to_inc <- IDX_G <- integer(0)
chg_idx <- integer(0)
if (STAGE1) {
  n_inc <- round(0.6 * n)
  is_inc <- rep(FALSE, n)
  is_inc[sample.int(n, n_inc)] <- TRUE
  truth <- lapply(seq_len(n), function(i) if (is_inc[i]) included_elig() else random_excluded())
  j1 <- truth
  j2 <- truth
  flip_to_exc <- sample(which(is_inc), 2)      # reviewer1 組入れ → reviewer2 除外
  flip_to_inc <- sample(which(!is_inc), 2)     # reviewer1 除外 → reviewer2 組入れ
  for (i in flip_to_exc) j2[[i]] <- random_excluded()
  for (i in flip_to_inc) j2[[i]] <- included_elig()
  # G: 両者が除外で、除外理由だけが違う
  IDX_G <- sample(setdiff(which(!is_inc), flip_to_inc), 1)
  j2[[IDX_G]][F_REASON] <- sample(setdiff(opts("除外理由"), j1[[IDX_G]][F_REASON]), 1)
  special <- sample(setdiff(seq_len(n), c(flip_to_exc, flip_to_inc, IDX_G)), 5)
  partial_a <- blank_vec()
  partial_a[F_ELIG] <- ELIG_EXC   # 除外理由が無いので不完全
  first_b <- random_excluded()
} else {
  n_inc <- n
  truth <- lapply(seq_len(n), random_classified)
  j1 <- truth
  j2 <- truth
  special <- sample(seq_len(n), 5)
  # 全事例の約20%で、reviewer2 の分類項目を1つ変える
  n_chg <- max(1L, round(0.2 * n))
  chg_idx <- sort(sample(seq_len(n), n_chg))
  for (i in chg_idx) {
    f <- sample(REQ, 1)
    others <- setdiff(opts(sub("^修正_", "", f)), j2[[i]][f])
    j2[[i]][f] <- sample(others, 1)
    # 事故類型を変えたときは、救命介入を事故類型と整合させる
    if (j2[[i]][F_TYPE] == CHOKE && j2[[i]][F_RESCUE] == "") {
      j2[[i]][F_RESCUE] <- sample(opts("救命介入"), 1)
    } else if (j2[[i]][F_TYPE] != CHOKE) {
      j2[[i]][F_RESCUE] <- ""
    }
  }
  partial_a <- blank_vec()
  partial_a["修正_脳卒中の位置づけ"] <- L("脳卒中の位置づけ", "primary")   # 他が空なので不完全
  first_b <- random_classified(1L)
}
IDX_A <- special[1]; IDX_B <- special[2]; IDX_C <- special[3]; IDX_D <- special[4]; IDX_E <- special[5]
memo_idx <- sample.int(n, 3)
for (i in memo_idx) j1[[i]]["メモ"] <- "表現が曖昧なので要確認"
if (STAGE1) {
  # 適格性が不一致の組入れ側に残った除外理由は、メモの「組入れ」に従って空になる。
  IDX_H <- flip_to_exc[1]
  j1[[IDX_H]][F_REASON] <- opts("除外理由")[1]
  j1[[IDX_H]]["メモ"] <- "組入れと判定。除外理由は消し忘れ"
}
if (STAGE2) {
  j1[[memo_idx[1]]]["メモ"] <- "第1段階で除外すべき事例ではないか"   # 第2段階では除外できない。メモが要約に出ることを確かめる
}

# ---- 判定ログの行 ----
make_ts <- function(base, k) {
  # base は "YYYY-MM-DD HH:MM:SS"（日本時間の壁時計）。k 分後の ISO8601 を返す
  t <- as.POSIXct(base, tz = "UTC") + 60 * k
  paste0(format(t, "%Y-%m-%dT%H:%M:%S", tz = "UTC"), "+09:00")
}
mk_row <- function(rv, ts, id, v, action = NULL) {
  if (is.null(action)) {
    action <- if (any(v[judge_fields] != "")) "modify" else "agree"
  }
  as.data.frame(as.list(c(timestamp = ts, reviewer = rv, tab = TAB, 事例ID = id, action = action, v)),
                check.names = FALSE, stringsAsFactors = FALSE)
}
B1 <- "2026-10-20 09:00:00"; B2 <- "2026-10-21 10:00:00"; B3 <- "2026-10-23 09:00:00"

rows1 <- list(); rows2 <- list()
k1 <- 0L; k2 <- 0L
nx1 <- function() { k1 <<- k1 + 1L; k1 }
nx2 <- function() { k2 <<- k2 + 1L; k2 }
for (i in seq_len(n)) {
  id <- ids[i]
  # reviewer1
  if (i == IDX_A) {
    rows1[[length(rows1) + 1]] <- mk_row(REVIEWERS[1], make_ts(B1, nx1()), id, partial_a)
    rows1[[length(rows1) + 1]] <- mk_row(REVIEWERS[1], make_ts(B1, nx1()), id, j1[[i]])
  } else if (i == IDX_C) {
    rows1[[length(rows1) + 1]] <- mk_row(REVIEWERS[1], make_ts(B1, nx1()), id, j1[[i]])
    rows1[[length(rows1) + 1]] <- mk_row(REVIEWERS[1], make_ts(B1, nx1()), id, blank_vec(), action = "clear")
  } else if (i == IDX_E) {
    v <- blank_vec()
    v["メモ"] <- "後で判定する"
    rows1[[length(rows1) + 1]] <- mk_row(REVIEWERS[1], make_ts(B1, nx1()), id, v)
  } else {
    rows1[[length(rows1) + 1]] <- mk_row(REVIEWERS[1], make_ts(B1, nx1()), id, j1[[i]])
  }
  # reviewer2
  if (i == IDX_D) {
    next
  } else if (i == IDX_B) {
    ts_first <- make_ts(B2, nx2())
    ts_later <- make_ts(B2, nx2())
    # timestamp が新しい行をファイル上は先に置く
    rows2[[length(rows2) + 1]] <- mk_row(REVIEWERS[2], ts_later, id, j2[[i]])
    rows2[[length(rows2) + 1]] <- mk_row(REVIEWERS[2], ts_first, id, first_b)
  } else {
    rows2[[length(rows2) + 1]] <- mk_row(REVIEWERS[2], make_ts(B2, nx2()), id, j2[[i]])
  }
}
IDX_P <- NA_integer_; IDX_R <- NA_integer_
if (COMPLETE) {
  # C・E を reviewer1 が、D を reviewer2 が、完全に判定した後の行を追記する
  rows1[[length(rows1) + 1]] <- mk_row(REVIEWERS[1], make_ts(B3, 1), ids[IDX_C], j1[[IDX_C]])
  rows1[[length(rows1) + 1]] <- mk_row(REVIEWERS[1], make_ts(B3, 2), ids[IDX_E], j1[[IDX_E]])
  rows2[[length(rows2) + 1]] <- mk_row(REVIEWERS[2], make_ts(B3, 3), ids[IDX_D], j2[[IDX_D]])
  if (STAGE2) {
    # 他の仕掛けに使っていない事例から、乱数を使わずに先頭2件を選ぶ（第1ラウンドの乱数列を変えない）
    pool <- setdiff(seq_len(n), c(chg_idx, IDX_A, IDX_B, IDX_C, IDX_D, IDX_E))
    if (length(pool) < 2) stop("--complete の追加の仕掛けに使える事例が2件未満")
    IDX_P <- pool[1]; IDX_R <- pool[2]
    # P: 直接介助者の当事者番号が不一致（合議は「なし」= 特定できない）。両者が判定を直した行を追記する
    j1[[IDX_P]][F_PARTY] <- "1"; j2[[IDX_P]][F_PARTY] <- "1,2"
    # R: 事故類型が 誤嚥 vs 判定不能（どちらも救命介入は不要）。合議で窒息・気道閉塞に決め、救命介入も合議で決める
    j1[[IDX_R]][F_TYPE] <- L("事故類型", "aspiration"); j2[[IDX_R]][F_TYPE] <- L("事故類型", "unclear")
    j1[[IDX_R]][F_RESCUE] <- ""; j2[[IDX_R]][F_RESCUE] <- ""
    rows1[[length(rows1) + 1]] <- mk_row(REVIEWERS[1], make_ts(B3, 4), ids[IDX_P], j1[[IDX_P]])
    rows2[[length(rows2) + 1]] <- mk_row(REVIEWERS[2], make_ts(B3, 5), ids[IDX_P], j2[[IDX_P]])
    rows1[[length(rows1) + 1]] <- mk_row(REVIEWERS[1], make_ts(B3, 6), ids[IDX_R], j1[[IDX_R]])
    rows2[[length(rows2) + 1]] <- mk_row(REVIEWERS[2], make_ts(B3, 7), ids[IDX_R], j2[[IDX_R]])
  }
}
log1 <- do.call(rbind, rows1)
log2 <- do.call(rbind, rows2)
cols <- c("timestamp", "reviewer", "tab", "事例ID", "action", entry_fields)
write_csv_raw(log1[, cols], file.path(OUT, paste0("synth_app_judgment_log_", SN, "_reviewer1.csv")), bom = TRUE, eol = "\r\n")
write_csv_raw(log2[, cols], file.path(OUT, paste0("synth_app_judgment_log_", SN, "_reviewer2.csv")), bom = TRUE, eol = "\r\n")

# ---- 合議ファイル（--complete のときだけ）。第1ラウンドでは古いものを消す ----
cons_path <- file.path(OUT, paste0("synth_consensus_", SN, ".csv"))
if (COMPLETE) {
  cons_rows <- list()
  add_c <- function(id, f, a, b, val) {
    cons_rows[[length(cons_rows) + 1]] <<- data.frame(
      事例ID = id, 変数 = sub("^修正_", "", f), reviewer1 = a[[f]], reviewer2 = b[[f]], 合議結果 = val,
      stringsAsFactors = FALSE)
  }
  norm_party <- function(x) {
    if (x == "") return("")
    paste(sort(unique(as.integer(strsplit(gsub(" ", "", x), ",", fixed = TRUE)[[1]]))), collapse = ",")
  }
  if (STAGE1) {
    # 適格性が不一致の4件: flip_to_exc[1] → 組入れ（reviewer1 を採る）、flip_to_exc[2] → 除外（reviewer2 を採る）、
    #   flip_to_inc[1] → 除外（reviewer1 を採る）、flip_to_inc[2] → 組入れ（reviewer2 を採る）。
    # 除外理由は除外と判定した側のものを採るため、合議行は適格性だけ。
    to_exc_by <- list(list(i = flip_to_exc[2], who = 2), list(i = flip_to_inc[1], who = 1))
    to_inc <- c(flip_to_exc[1], flip_to_inc[2])
    for (i in to_inc) add_c(ids[i], F_ELIG, j1[[i]], j2[[i]], ELIG_INC)
    for (e in to_exc_by) {
      i <- e$i
      add_c(ids[i], F_ELIG, j1[[i]], j2[[i]], ELIG_EXC)
    }
  } else {
    for (i in seq_len(n)) {
      a <- j1[[i]]; b <- j2[[i]]; id <- ids[i]
      for (f in c(REQ, F_RESCUE, F_PARTY)) {
        if (f == F_RESCUE && !(a[F_TYPE] == CHOKE || b[F_TYPE] == CHOKE)) next
        same <- if (f == F_PARTY) norm_party(a[f]) == norm_party(b[f]) else a[f] == b[f]
        if (same) next
        # reviewer1 の事故類型が窒息でないなら、救命介入は最終的に不要なので合議行を作らない
        if (f == F_RESCUE && a[F_TYPE] != CHOKE) next
        # P の当事者番号は「なし」（特定できない）、R の事故類型は窒息・気道閉塞で合議する
        val <- if (i %in% IDX_P && f == F_PARTY) "なし" else if (i %in% IDX_R && f == F_TYPE) CHOKE else a[f]
        add_c(id, f, a, b, val)
      }
      # R: 合議で窒息・気道閉塞に決まったので、救命介入の合議行を足す（reviewer 列は現在の値 = 空）
      if (i %in% IDX_R) add_c(id, F_RESCUE, a, b, L("救命介入", "yes"))
    }
  }
  cons <- do.call(rbind, cons_rows)
  rownames(cons) <- NULL
  write_csv_raw(cons, cons_path, bom = TRUE)
} else if (file.exists(cons_path)) {
  invisible(file.remove(cons_path))
}

# ---- 仕掛けの控え ----
nt <- c(paste0("# 架空の判定ログ（make_synth_fixture.R --", SN, "）の仕掛け"), "",
        paste0("- モード: ", if (COMPLETE) "--complete（C・D・E を完全に判定した行を追記。合議ファイルあり）" else "第1ラウンド（合議ファイルなし）"),
        paste0("- 対象 ", n, " 件", if (STAGE1) paste0(" / 真の組入れ ", n_inc, " 件（約60%）") else "（第1段階で組入れに確定した事例）"),
        paste0("- A（reviewer1 が2回保存。最初は不完全、後の行が有効）: ", ids[IDX_A]),
        paste0("- B（reviewer2 が2回保存。timestamp が新しい行をファイル上は先に置く）: ", ids[IDX_B]),
        paste0("- C（reviewer1 の最終行が clear）: ", ids[IDX_C]),
        paste0("- D（reviewer2 が一度も判定しない）: ", ids[IDX_D]),
        paste0("- E（reviewer1 が修正_* 空で保存 = agree、メモのみ）: ", ids[IDX_E]),
        if (STAGE1) paste0("- 適格性が不一致（reviewer1 組入れ → reviewer2 除外）: ", paste(ids[flip_to_exc], collapse = ", ")),
        if (STAGE1) paste0("- 適格性が不一致（reviewer1 除外 → reviewer2 組入れ）: ", paste(ids[flip_to_inc], collapse = ", ")),
        if (STAGE1) paste0("- G（両者が除外で除外理由だけが違う）: ", ids[IDX_G]),
        if (STAGE1) paste0("- H（組入れに残った除外理由をメモの「組入れ」により空にする）: ", ids[IDX_H]),
        if (STAGE1 && COMPLETE) paste0("- 合議: 組入れに決める ", paste(ids[c(flip_to_exc[1], flip_to_inc[2])], collapse = ", "),
                                      " / 除外に決める（除外側の理由を採る）", paste(ids[c(flip_to_exc[2], flip_to_inc[1])], collapse = ", ")),
        if (STAGE2 && COMPLETE) paste0("- P（直接介助者の当事者番号が 1 vs 1,2 で不一致。合議は「なし」= 特定できない）: ", ids[IDX_P]),
        if (STAGE2 && COMPLETE) paste0("- R（事故類型が 誤嚥 vs 判定不能。合議で窒息・気道閉塞とし、救命介入の合議行も入れる）: ", ids[IDX_R]),
        if (STAGE2) paste0("- 分類項目を1つ変えた事例（reviewer2、", length(chg_idx), " 件）: ", paste(ids[chg_idx], collapse = ", ")),
        paste0("- reviewer1 がメモを付けた事例: ", paste(ids[memo_idx], collapse = ", ")),
        paste0("- ログの行数: reviewer1 ", nrow(log1), " 行 / reviewer2 ", nrow(log2), " 行"))
write_lf_md(nt, file.path(OUT, paste0("synth_fixture_notes_", SN, ".md")))
message("done: fixture --", SN, " ", if (COMPLETE) "(--complete)" else "(round 1)", " log1=", nrow(log1), " rows, log2=", nrow(log2), " rows")
