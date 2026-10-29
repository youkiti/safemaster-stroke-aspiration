# tanaka_stroke_aspiration: 解析コホートと報告用オブジェクトの単一情報源（source して使う。ファイルは書かない）
#
# 入力:
#   架空100行 CSV（SAFEMASTER_DIR 配下）または本番 data/safemaster_r19_text.rds（candidates.R 経由）
#   output/{prefix}_final_classification.csv  05b_stage2_final.R が書く最終分類（適格性は第1段階、分類は第2段階）
#   output/{prefix}_intake_stamp.csv          05b_stage2_final.R が最終分類と同時に書く入力の md5。現物と食い違えば停止する
#   output/{prefix}_intake_stamp_stage1.csv   03_app_intake.R --stage1 が書く、第1段階の入力と最終適格性の md5（これも照合する）
#   output/{prefix}_agreement.csv             03_app_intake.R --stage2 が書く一致度（variable,n,percent_agreement,kappa,ci_low,ci_high）
#   analysis/factor_labels.csv, code_labels.csv, review_codebook.csv
# 本番か架空かは、呼び出し側の環境にある論理値 prod で決める（無ければ FALSE）。<<- は使わない。
# 実行ディレクトリは projects/tanaka_stroke_aspiration/ でもリポジトリ直下でもよい。
# 出力先を環境変数 TANAKA_OUT で差し替えられる（既定は <プロジェクト>/output）。
#
# 定義するオブジェクト（report.Rmd が使う）:
#   cohort, flow, cand_info, FALLBACK, n_*（スカラー）, agreement, determinable,
#   tbl1, tbl1b（gtsummary。tbl1b は脳卒中の位置づけ別）, table2, table3, table_s1, table_s2, table_s3, table_s4, fig_flow, fig2, PS_COLS, PS_EN

PROD   <- exists("prod") && is.logical(prod) && isTRUE(prod)
PREFIX <- if (PROD) "prod" else "synth"

# ---- 場所の解決（プロジェクト直下 / リポジトリ直下のどちらからでも動く） ----
if (file.exists(file.path("analysis", "candidates.R"))) {
  PROJ <- "."
  ROOT <- file.path("..", "..")
} else {
  PROJ <- Sys.glob("projects/tanaka_*")
  PROJ <- PROJ[file.exists(file.path(PROJ, "analysis", "candidates.R"))]
  stopifnot(length(PROJ) == 1L)
  ROOT <- "."
}
OUT_DIR <- Sys.getenv("TANAKA_OUT", file.path(PROJ, "output"))
ANA <- file.path(PROJ, "analysis")

source(file.path(ANA, "candidates.R"))
source(file.path(ROOT, "shared", "safe_cols.R"))
source(file.path(ROOT, "shared", "flow_diagram.R"))
suppressPackageStartupMessages(library(gtsummary))
if (PROD) options(safemaster.strict_cols = TRUE)

EN <- "–"
num <- function(x) suppressWarnings(as.numeric(x))
fmt_n <- function(x) formatC(x, big.mark = ",", format = "d")
norm_tilde <- function(x) gsub("[～〜]", "~", x)

# ---- ラベル表（日本語ラベル → 英語ラベル） ----
LAB <- read.csv(file.path(ANA, "factor_labels.csv"), colClasses = "character", check.names = FALSE,
                fileEncoding = "UTF-8-BOM")
stopifnot(identical(names(LAB), c("variable", "label_ja", "label_en")),
          !anyDuplicated(paste(LAB$variable, LAB$label_ja)))
LAB$label_ja <- norm_tilde(LAB$label_ja)
en <- function(variable, ja) {
  out <- rep(NA_character_, length(ja))
  ok <- !is.na(ja)
  m <- LAB$label_en[match(paste(variable, ja[ok], sep = "\x1f"), paste(LAB$variable, LAB$label_ja, sep = "\x1f"))]
  miss <- unique(ja[ok][is.na(m)])
  if (length(miss)) {
    stop(sprintf("factor_labels.csv has no English label for variable '%s': %s", variable,
                 paste(miss, collapse = " | ")))
  }
  out[ok] <- m
  out
}
lab_order <- function(variable) unique(LAB$label_en[LAB$variable == variable])
fct <- function(x, lv, unk = "Unknown") {
  has_unk <- any(is.na(x)) || unk %in% lv
  factor(ifelse(is.na(x), unk, x), levels = if (has_unk) unique(c(lv, unk)) else lv)
}
CODEL <- read_code_labels(file.path(ANA, "code_labels.csv"))
decode_na <- function(variable, codes) {
  norm_tilde(decode_codes(CODEL, variable, codes, strict = PROD, missing = NA_character_))
}

# ---- 読み込みと候補 ----
d <- load_safemaster_r19(PROD, ROOT)
cand <- build_candidates(d, synth_fallback = !PROD)
check_candidates(cand, PROD)
FALLBACK <- isTRUE(cand$synth_fallback_used)
n_all <- nrow(d)
n_inpt <- sum(cand$inpt)
n_cand <- sum(cand$T4)
if (PROD) {
  # 本番 r19 の全件数と入院件数（実測値。通すために数値を変えない）
  if (n_all != 54310 || n_inpt != 48441) {
    stop(sprintf("全件数または入院件数が実測と一致しない: 全件 %d (期待 54310) / 入院 %d (期待 48441)", n_all, n_inpt))
  }
}
if (anyDuplicated(d$事例ID)) stop("事例ID に重複がある")

# ---- 最終分類（試行の正解値・1名確認・運営除外の統合） ----
FINAL_PATH <- file.path(OUT_DIR, paste0(PREFIX, "_final_classification.csv"))
AGREE_PATH <- file.path(OUT_DIR, paste0(PREFIX, "_agreement.csv"))
DETERM_PATH <- file.path(OUT_DIR, paste0(PREFIX, "_determinable.csv"))
if (!file.exists(FINAL_PATH)) {
  stop("最終分類が無い: ", FINAL_PATH, "（第1段階・第2段階の判定が確定して 05b_stage2_final.R が最終分類を書くまで、報告書は作れない）")
}
# 最終分類は、05b_stage2_final.R が書いた stamp と現物が一致するときだけ使う。
# 第2段階の stamp の対象は stage2_stamp_files が定義する全入力と最終分類・変更集計。
# 第1段階の stamp（第1段階の入力と最終適格性を覆う）も別に照合する。
STAMP_PATH <- file.path(OUT_DIR, paste0(PREFIX, "_intake_stamp.csv"))
if (!file.exists(STAMP_PATH)) {
  stop("取り込みの stamp が無い: ", STAMP_PATH, "（03_app_intake.R --stage2、05b_stage2_final.R の順に実行し直す）")
}
stamp_bad <- stamp_problems(STAMP_PATH, stage2_stamp_files(OUT_DIR, PREFIX, ANA))
if (length(stamp_bad)) {
  stop("最終分類を書いた後に入力が変わっている、または stamp の形式が違う（md5 が stamp と一致しない）。",
       "03_app_intake.R --stage2、05b_stage2_final.R の順に実行し直す: ", paste(stamp_bad, collapse = " ; "))
}
stamp1_bad <- stamp_problems(file.path(OUT_DIR, paste0(PREFIX, "_intake_stamp_stage1.csv")),
                             stage1_stamp_files(OUT_DIR, PREFIX))
if (length(stamp1_bad)) {
  stop("第1段階の取り込みの stamp が現物と一致しない。03_app_intake.R --stage1 を実行し直す: ",
       paste(stamp1_bad, collapse = " ; "))
}
if (!file.exists(AGREE_PATH)) stop("一致度ファイルが無い（03_app_intake.R を実行）: ", AGREE_PATH)
final <- read_char_csv_bom(FINAL_PATH)
if (anyDuplicated(final$事例ID)) stop("最終分類の事例ID に重複がある")
t4_ids <- d$事例ID[cand$T4]
if (!setequal(final$事例ID, t4_ids)) {
  stop(sprintf("最終分類の事例IDとT4候補が一致しない: 候補にあって最終分類に無い %d 件 / 最終分類にあって候補に無い %d 件",
               length(setdiff(t4_ids, final$事例ID)), length(setdiff(final$事例ID, t4_ids))))
}
agreement <- read.csv(AGREE_PATH, fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
stopifnot(identical(names(agreement), c("variable", "n", "percent_agreement", "kappa", "ci_low", "ci_high")))
determinable <- if (file.exists(DETERM_PATH)) read.csv(DETERM_PATH, fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE) else NULL

# ---- 選択肢（コードブックの順序）と英語ラベル ----
codebook <- read.csv(file.path(ANA, "review_codebook.csv"), colClasses = "character",
                     fileEncoding = "UTF-8-BOM", check.names = FALSE)
cb_levels <- function(ja_var, key) {
  ja <- codebook$日本語ラベル[codebook$変数 == ja_var]
  stopifnot(length(ja) > 0)
  unique(en(key, ja))   # コードブックの全ラベルに英語ラベルがあることの確認を兼ねる
}
EXC_JA <- codebook$日本語ラベル[codebook$変数 == "適格性" & codebook$英語コード == "exclude"]
INC_JA <- codebook$日本語ラベル[codebook$変数 == "適格性" & codebook$英語コード == "include"]
stopifnot(all(final$適格性 %in% c(INC_JA, EXC_JA)))

# ---- フロー ----
excl <- final[final$適格性 == EXC_JA, , drop = FALSE]
incl <- final[final$適格性 == INC_JA, , drop = FALSE]
if (any(is_blank(excl$除外理由))) stop("除外なのに除外理由が空の事例がある")
excl_reason_en <- en("exclusion_reason", excl$除外理由)
excl_tab <- table(factor(excl_reason_en, levels = cb_levels("除外理由", "exclusion_reason")))
excl_stage2 <- excl$一致 == "operator_exclusion"
flow <- list(all = n_all, inpatient = n_inpt, candidates = n_cand, excluded = nrow(excl),
             excluded_stage1 = sum(!excl_stage2), excluded_stage2 = sum(excl_stage2),
             included = nrow(incl), reasons = excl_tab)
# Summary の分母は保存値の diff 全11項目（非窒息の従属項目の空も含む）。
review_changes <- read_char_csv_bom(file.path(OUT_DIR, paste0(PREFIX, "_stage2_review_changes.csv")))
if (!identical(names(review_changes), c("item", "kept", "changed", "filled", "unfilled")) ||
    sum(review_changes$item == "total") != 1L) stop("stage2_review_changes.csv の形式が想定と違う")
change_total <- as.numeric(unlist(review_changes[review_changes$item == "total", -1]))
if (anyNA(change_total) || any(change_total < 0)) stop("stage2_review_changes.csv の件数が不正")
n_review_items <- sum(change_total)
n_review_changed <- sum(change_total[2:3])
pilot_ids <- read_char_csv_bom(file.path(OUT_DIR, paste0(PREFIX, "_stage2_pilot10_ids.csv")))
n_pilot <- nrow(pilot_ids)
n_rest_review <- sum(final$一致 == "single_review") + flow$excluded_stage2
stopifnot(flow$candidates == flow$excluded + flow$included)
n_cohort <- flow$included
if (n_cohort == 0) stop("組入れが0件")

# ---- コホート（組入れ1報告 = 1行） ----
inc_ids <- incl$事例ID
ii <- match(inc_ids, d$事例ID)
cc <- function(name) col_first(d, name)[ii]

year <- as.integer(num(cc("報告年")))
period <- cut(year, c(2012, 2016, 2020, 2024), labels = c(paste0("2013", EN, "2016"), paste0("2017", EN, "2020"), paste0("2021", EN, "2024")))
if (anyNA(period)) stop("報告年が2013–2024の範囲外または欠測の事例がある")
age <- fct(en("age_band", decode_na("患者の年齢", cc("患者の年齢"))), lab_order("age_band"))
sex <- fct(en("sex", decode_na("患者の性別", cc("患者の性別"))), lab_order("sex"))
tb_ja <- decode_na("発生時間帯", cc("発生時間帯"))
time_band <- fct(en("time_band", tb_ja), lab_order("time_band"))
time_band4 <- fct(en("time_band4", tb_ja), lab_order("time_band4"), unk = "Other time or unknown")
basho <- cc("発生場所")
location <- factor(ifelse(is.na(basho), "Unknown", ifelse(flag(d, "病室")[ii], "Patient room", "Other location")),
                   levels = c("Patient room", "Other location", "Unknown"))
if (!any(location == "Unknown")) location <- droplevels(location)

# 直前の患者の状態（14項目の one-hot。印が付いていない行は欠測と区別できない）
PS_JA <- LAB$label_ja[LAB$variable == "patient_state"]
stopifnot(length(PS_JA) == 14)
assert_cols(d, PS_JA)
PS_EN <- en("patient_state", PS_JA)
PS_COLS <- sprintf("ps%02d", seq_along(PS_JA))
ps <- as.data.frame(lapply(PS_JA, function(cn) flag(d, cn)[ii]), col.names = PS_COLS)

discoverer <- fct(en("discoverer", decode_na("発見者", cc("発見者"))), lab_order("discoverer"))

jiko <- num(cc("事故の程度")); chiryo <- num(cc("治療の程度"))
death <- jiko %in% 1
severe <- jiko %in% 1 | (jiko %in% c(2, 3) & chiryo %in% 3)
sev_any123 <- jiko %in% 1:3
sev_or <- jiko %in% 1:3 | chiryo %in% 3

# 著者判定の変数（コードブックの順序の因子）
fin <- incl
make_rv <- function(ja_var, key, na_label = NULL) {
  lv <- cb_levels(ja_var, key)
  x <- fin[[ja_var]]
  x_en <- rep(NA_character_, length(x))
  nb <- !is_blank(x)
  x_en[nb] <- en(key, x[nb])
  if (!is.null(na_label)) {
    x_en[is.na(x_en)] <- na_label
    lv <- c(lv, na_label)
  } else if (anyNA(x_en)) {
    stop("組入れの事例に ", ja_var, " が空のものがある")
  }
  factor(x_en, levels = lv)
}
rv <- list(
  stroke_position = make_rv("脳卒中の位置づけ", "stroke_position"),
  stroke_type = make_rv("脳卒中病型", "stroke_type"),
  event_type = make_rv("事故類型", "event_type"),
  intake = make_rv("摂取物", "intake"),
  assistance = make_rv("摂食介助状況", "assistance"),
  presence = make_rv("同席状況", "presence"),
  swallow = make_rv("嚥下評価", "swallow"),
  deviation = make_rv("指示逸脱", "deviation"),
  meal = make_rv("食事区分", "meal"),
  rescue = make_rv("救命介入", "rescue", na_label = "Not applicable (not choking)"))
choke_en <- en("event_type", codebook$日本語ラベル[codebook$変数 == "事故類型" & codebook$英語コード == "choking"])
if (any(rv$event_type == choke_en & rv$rescue == "Not applicable (not choking)") ||
    any(rv$event_type != choke_en & rv$rescue != "Not applicable (not choking)")) {
  stop("救命介入が事故類型と整合しない（窒息・気道閉塞のときだけ記入されるはず）")
}

# 直接介助者（整数1つで特定できた報告だけ）の職種・経験・部署配属期間
party_raw <- gsub("[[:space:]]", "", fin$直接介助者の当事者番号)
party <- ifelse(grepl("^[0-9]+$", party_raw), suppressWarnings(as.integer(party_raw)), NA_integer_)
if (any(!is.na(party) & !party %in% 1:10)) stop("当事者番号が1〜10の範囲外")
job_ja <- rep(NA_character_, n_cohort)
exp_months <- rep(NA_real_, n_cohort)
tenure_months <- rep(NA_real_, n_cohort)
for (pn in 1:10) {
  r <- which(party %in% pn)
  if (!length(r)) {
    next
  }
  gi <- ii[r]
  job_ja[r] <- decode_na("当事者職種", col_first(d, paste0("当事者職種_", pn))[gi])
  to_months <- function(y_name, m_name) {
    y <- num(col_first(d, paste0(y_name, pn))[gi])
    m <- num(col_first(d, paste0(m_name, pn))[gi])
    if (any(!is.na(m) & !m %in% 0:11)) stop("月数が0–11の範囲外: ", m_name)
    y * 12 + m   # 年数か月数が欠測なら欠測のまま（端数を無言で切り捨てない）
  }
  exp_months[r] <- to_months("当事者職種経験（年数）_", "当事者職種経験（月数）_")
  tenure_months[r] <- to_months("当事者部署配属期間（年数）_", "当事者部署配属期間（月数）_")
}
job_en <- en("job", job_ja)
job <- factor(job_en, levels = names(sort(table(job_en), decreasing = TRUE)))
party_identified <- !is.na(party)

cohort <- data.frame(
  事例ID = inc_ids, year = year, period = period, age_band = age, sex = sex,
  time_band = time_band, time_band4 = time_band4, location = location,
  discoverer = discoverer, jiko = jiko, chiryo = chiryo,
  death = death, severe = severe, sev_any123 = sev_any123, sev_or = sev_or,
  rv, ps, party = party, party_job = job, exp_months = exp_months, tenure_months = tenure_months,
  check.names = FALSE, stringsAsFactors = FALSE)
rm(d)
invisible(gc())
stopifnot(nrow(cohort) == n_cohort, !anyDuplicated(cohort$事例ID))

n_severe <- sum(cohort$severe)
n_death <- sum(cohort$death)
sev_pct <- 100 * n_severe / n_cohort
severity_group <- factor(ifelse(cohort$severe, "Severe", "Not severe"), levels = c("Not severe", "Severe"))
cohort$severity_group <- severity_group

# ---- 表の部品 ----
ci_txt <- function(k, N) {
  if (N == 0) {
    return("-")
  }
  ci <- stats::binom.test(k, N)$conf.int * 100
  sprintf("%.1f to %.1f", ci[1], ci[2])
}
pct_txt <- function(k, N) if (N == 0) "-" else sprintf("%.0f", 100 * k / N)
nN_txt <- function(k, N) sprintf("%d/%d", k, N)

# ---- Table 1（gtsummary。p値なし） ----
T1_LABELS <- c(list(period = "Report-year period", age_band = "Patient age, years", sex = "Sex",
                    stroke_position = "Role of stroke in the admission", stroke_type = "Stroke type",
                    event_type = "Event type", intake = "Material taken", assistance = "Feeding assistance",
                    presence = "Presence of others", swallow = "Swallowing assessment",
                    deviation = "Instruction deviation or communication failure", time_band4 = "Time of occurrence",
                    location = "Location of occurrence", discoverer = "Discoverer"),
               setNames(as.list(paste0("Before the event: ", PS_EN)), PS_COLS))
T1_VARS <- c("period", "age_band", "sex", "stroke_position", "stroke_type", "event_type", "intake",
             "assistance", "presence", "swallow", "deviation", "time_band4", "location", PS_COLS, "discoverer")
make_tbl1 <- function() {
  dd <- cohort[, c(T1_VARS, "severity_group")]
  both_groups <- all(table(dd$severity_group) > 0)
  base <- if (both_groups) {
    tbl_summary(dd, by = severity_group, include = all_of(T1_VARS), label = T1_LABELS,
                type = list(all_of(PS_COLS) ~ "dichotomous"), value = setNames(rep(list(TRUE), length(PS_COLS)), PS_COLS),
                statistic = list(all_categorical() ~ "{n} ({p}%)"),
                digits = list(all_categorical() ~ c(0, 0)), missing = "no") |>
      add_overall(last = FALSE)
  } else {
    warning("severe / not severe の片方が0件のため、Table 1 は全体のみ", call. = FALSE)
    tbl_summary(dd, include = all_of(T1_VARS), label = T1_LABELS,
                type = list(all_of(PS_COLS) ~ "dichotomous"), value = setNames(rep(list(TRUE), length(PS_COLS)), PS_COLS),
                statistic = list(all_categorical() ~ "{n} ({p}%)"),
                digits = list(all_categorical() ~ c(0, 0)), missing = "no")
  }
  base |> modify_header(label ~ "**Characteristic**")
}
tbl1 <- make_tbl1()

# ---- Table 1b: Table 1 と同じ特性を脳卒中の位置づけ別に（p値なし。列見出しに層名が入る） ----
T1B_VARS <- setdiff(T1_VARS, "stroke_position")
make_tbl1b <- function() {
  dd <- cohort[, c(T1B_VARS, "stroke_position")]
  dd$stroke_position <- droplevels(dd$stroke_position)   # 該当が0件の層は列にしない
  tbl_summary(dd, by = stroke_position, include = all_of(T1B_VARS), label = T1_LABELS[T1B_VARS],
              type = list(all_of(PS_COLS) ~ "dichotomous"), value = setNames(rep(list(TRUE), length(PS_COLS)), PS_COLS),
              statistic = list(all_categorical() ~ "{n} ({p}%)"),
              digits = list(all_categorical() ~ c(0, 0)), missing = "no") |>
    add_overall(last = FALSE) |>
    modify_header(label ~ "**Characteristic**")
}
tbl1b <- make_tbl1b()

# ---- Table 2: 摂食介助・同席 × 事故類型の層（n・重篤 n・重篤 %・死亡） ----
t2_block <- function(stratified_by, stratum, mask) {
  rows <- list()
  for (v in c("assistance", "presence")) {
    x <- cohort[[v]]
    for (lv in levels(x)) {
      m <- mask & x == lv
      k <- sum(m & cohort$severe)
      rows[[length(rows) + 1]] <- data.frame(
        `Stratified by` = stratified_by, Stratum = stratum, Variable = if (v == "assistance") "Feeding assistance" else "Presence of others",
        Level = lv, n = sum(m), `Severe n` = k, `Severe %` = pct_txt(k, sum(m)), Deaths = sum(m & cohort$death),
        check.names = FALSE, stringsAsFactors = FALSE)
    }
  }
  do.call(rbind, rows)
}
table2 <- do.call(rbind, c(list(t2_block("Overall", "All events", rep(TRUE, n_cohort))),
                           lapply(levels(cohort$event_type), function(lv) t2_block("Event type", lv, cohort$event_type == lv)),
                           lapply(levels(cohort$stroke_position), function(lv) t2_block("Stroke position", lv, cohort$stroke_position == lv))))
rownames(table2) <- NULL

# ---- Table 3: 重篤 n/N（%）と正確二項 95%CI ----
t3_row <- function(subset, level, mask) {
  N <- sum(mask)
  k <- sum(mask & cohort$severe)
  data.frame(Subset = subset, Level = level, `Severe/N` = nN_txt(k, N), `%` = pct_txt(k, N),
             `95% CI` = ci_txt(k, N), check.names = FALSE, stringsAsFactors = FALSE)
}
t3 <- list()
for (v in c("assistance", "presence")) {
  nm <- if (v == "assistance") "Feeding assistance" else "Presence of others"
  for (lv in levels(cohort[[v]])) t3[[length(t3) + 1]] <- t3_row(nm, lv, cohort[[v]] == lv)
}
asst_lv <- levels(cohort$assistance)[1:2]
pres_lv <- levels(cohort$presence)[1:2]
for (a in asst_lv) {
  for (p in pres_lv) {
    t3[[length(t3) + 1]] <- t3_row("Assistance by presence (determinable cases only)", paste(a, "/", p),
                                   cohort$assistance == a & cohort$presence == p)
  }
}
for (lv in levels(cohort$event_type)) t3[[length(t3) + 1]] <- t3_row("Event type", lv, cohort$event_type == lv)
for (lv in levels(cohort$stroke_position)) t3[[length(t3) + 1]] <- t3_row("Role of stroke", lv, cohort$stroke_position == lv)
for (i in seq_along(PS_COLS)) {
  t3[[length(t3) + 1]] <- t3_row(paste("Patient state:", PS_EN[i]), "Marked", cohort[[PS_COLS[i]]])
  t3[[length(t3) + 1]] <- t3_row(paste("Patient state:", PS_EN[i]), "Not marked", !cohort[[PS_COLS[i]]])
}
table3 <- do.call(rbind, t3)
rownames(table3) <- NULL

# ---- Table S1: 重症度の定義を変えた感度分析 ----
s1 <- function(label, ev) {
  data.frame(Definition = label, N = n_cohort, Events = sum(ev), `%` = pct_txt(sum(ev), n_cohort),
             `95% CI` = ci_txt(sum(ev), n_cohort), check.names = FALSE, stringsAsFactors = FALSE)
}
table_s1 <- rbind(
  s1("Primary: death, or possible disability (high or low) with intensive treatment", cohort$severe),
  s1("Sensitivity: death or possible disability (high or low), any treatment", cohort$sev_any123),
  s1("Sensitivity: death or possible disability (high or low), or intensive treatment", cohort$sev_or))
rownames(table_s1) <- NULL

# ---- Table S2: 一致度 ----
VAR_EN <- c("適格性" = "Eligibility", "脳卒中の位置づけ" = "Role of stroke", "脳卒中病型" = "Stroke type",
            "事故類型" = "Event type", "摂取物" = "Material taken", "摂食介助状況" = "Feeding assistance",
            "同席状況" = "Presence of others", "嚥下評価" = "Swallowing assessment",
            "指示逸脱" = "Instruction deviation", "食事区分" = "Meal", "救命介入" = "Rescue intervention")
if (!all(agreement$variable %in% names(VAR_EN))) {
  stop("agreement.csv に想定外の変数名がある: ", paste(setdiff(agreement$variable, names(VAR_EN)), collapse = ", "))
}
fmt_k <- function(x) ifelse(is.na(x), "-", sprintf("%.2f", x))
table_s2 <- data.frame(
  Variable = unname(VAR_EN[agreement$variable]), n = agreement$n,
  `Agreement, %` = ifelse(is.na(agreement$percent_agreement), "-", sprintf("%.0f", agreement$percent_agreement)),
  Kappa = fmt_k(agreement$kappa),
  `95% CI` = ifelse(is.na(agreement$ci_low), "-", sprintf("%s to %s", fmt_k(agreement$ci_low), fmt_k(agreement$ci_high))),
  check.names = FALSE, stringsAsFactors = FALSE)

# ---- Table S3: 嚥下評価・指示逸脱・食事区分・救命介入・直接介助者 ----
s3_cat <- function(label, x, mask = rep(TRUE, n_cohort)) {
  lv <- levels(x)
  N <- sum(mask)
  data.frame(Variable = c(label, rep("", length(lv) - 1)), Level = lv,
             `n (%)` = vapply(lv, function(l) sprintf("%d (%s%%)", sum(mask & x == l), pct_txt(sum(mask & x == l), N)), ""),
             check.names = FALSE, stringsAsFactors = FALSE, row.names = NULL)
}
choke_mask <- cohort$event_type == choke_en
rescue_lv <- setdiff(levels(cohort$rescue), "Not applicable (not choking)")
s3_rescue <- s3_cat(sprintf("Rescue intervention (choking only, n = %d)", sum(choke_mask)),
                    factor(as.character(cohort$rescue), levels = rescue_lv), choke_mask)
num_row <- function(label, x) {
  x <- x[!is.na(x)]
  data.frame(Variable = label, Level = "Median [Q1, Q3], months",
             `n (%)` = if (length(x)) {
               q <- stats::quantile(x, c(0.25, 0.5, 0.75), names = FALSE)
               sprintf("%.1f [%.1f, %.1f] (n = %d)", q[2], q[1], q[3], length(x))
             } else "-",
             check.names = FALSE, stringsAsFactors = FALSE)
}
n_party <- sum(party_identified)
s3_job <- if (n_party > 0) {
  jb <- droplevels(cohort$party_job[party_identified])
  s3_cat(sprintf("Occupation of the direct assistant (identified, n = %d)", n_party), jb,
         rep(TRUE, length(jb)))
} else {
  data.frame(Variable = "Occupation of the direct assistant (identified, n = 0)", Level = "-", `n (%)` = "-",
             check.names = FALSE, stringsAsFactors = FALSE)
}
table_s3 <- rbind(
  s3_cat("Swallowing assessment", cohort$swallow),
  s3_cat("Instruction deviation", cohort$deviation),
  s3_cat("Meal", cohort$meal),
  s3_rescue,
  s3_job,
  num_row("Professional experience of the direct assistant", cohort$exp_months),
  num_row("Time in current department of the direct assistant", cohort$tenure_months))
rownames(table_s3) <- NULL

# ---- Figure 1: フロー ----
# 除外理由の内訳は図に入れず（箱が高くなって重なる）、表 S4 に出す
table_s4 <- do.call(rbind, lapply(c("Stage 1: eligibility review", "Stage 2: classification review"), function(stage) {
  mask <- if (stage == "Stage 1: eligibility review") !excl_stage2 else excl_stage2
  counts <- table(factor(excl_reason_en[mask], levels = names(flow$reasons)))
  data.frame(Stage = stage, `Reason for exclusion` = c(names(counts), "Stage subtotal"),
             n = c(as.integer(counts), sum(mask)), check.names = FALSE, stringsAsFactors = FALSE)
}))
table_s4 <- rbind(table_s4, data.frame(Stage = "All stages", `Reason for exclusion` = "Total excluded",
                                     n = flow$excluded, check.names = FALSE))
fig_flow <- flow_diagram(
  font = "",   # 英語のみ。en dash が非ASCII扱いで日本語フォントを探し、警告が出るのを避ける
  nodes = c(
    sprintf("All reports, 2013%s2024\nn = %s", EN, fmt_n(flow$all)),
    sprintf("Inpatient reports\nn = %s", fmt_n(flow$inpatient)),
    sprintf("Keyword candidates\n(stroke term, aspiration or choking,\nmeal or fluid intake)\nn = %s", fmt_n(flow$candidates)),
    sprintf("Eligible after stage 1 review\nn = %s", fmt_n(flow$candidates - flow$excluded_stage1)),
    sprintf("Included after stage 2 review\nn = %s (severe %s; deaths %s)", fmt_n(flow$included),
            fmt_n(n_severe), fmt_n(n_death))),
  exclusions = c(
    sprintf("Outpatient or unknown patient category\nn = %s", fmt_n(flow$all - flow$inpatient)),
    sprintf("No candidate keyword match\nn = %s", fmt_n(flow$inpatient - flow$candidates)),
    sprintf("Excluded at stage 1 review\nn = %s", fmt_n(flow$excluded_stage1)),
    sprintf("Excluded at stage 2 review\nn = %s", fmt_n(flow$excluded_stage2))))

# ---- Figure 2: 摂食介助・同席の件数と重篤割合（脳卒中の位置づけ別） ----
f2 <- list()
for (v in c("assistance", "presence")) {
  vn <- if (v == "assistance") "Feeding assistance" else "Presence of others"
  for (pos in levels(cohort$stroke_position)) {
    for (lv in levels(cohort[[v]])) {
      m <- cohort$stroke_position == pos & cohort[[v]] == lv
      f2[[length(f2) + 1]] <- data.frame(variable = vn, position = pos, level = lv, n = sum(m),
                                         severe = sum(m & cohort$severe), stringsAsFactors = FALSE)
    }
  }
}
f2 <- do.call(rbind, f2)
f2$variable <- factor(f2$variable, levels = c("Feeding assistance", "Presence of others"))
# 該当が0件の位置づけ（例 Unclear）は空の行になるので出さない
f2_pos <- levels(cohort$stroke_position)[levels(cohort$stroke_position) %in% unique(as.character(cohort$stroke_position))]
f2 <- f2[f2$position %in% f2_pos, , drop = FALSE]
f2$position <- factor(f2$position, levels = f2_pos)
# 両変数に共通の水準（Unknown）が並びの途中に入ると、同席状況の列だけ Unknown が先頭になる。
# 共通の水準を最後に回し、どちらの列でも Unknown を右端にそろえる。
f2_lv <- unique(c(levels(cohort$assistance), levels(cohort$presence)))
f2_common <- intersect(levels(cohort$assistance), levels(cohort$presence))
f2$level <- factor(f2$level, levels = c(setdiff(f2_lv, f2_common), f2_common))
f2_pct <- ifelse(f2$n == 0, "-", sprintf("%.0f", 100 * f2$severe / pmax(f2$n, 1)))
f2$label <- ifelse(f2$n == 0, "", sprintf("%d severe/%d (%s%%)", f2$severe, f2$n, f2_pct))
fig2 <- ggplot(f2, aes(x = level)) +
  geom_col(aes(y = n), fill = "grey80", colour = "black", width = 0.7) +
  geom_col(aes(y = severe), fill = "grey35", width = 0.7) +
  geom_text(aes(y = n, label = label), vjust = -0.4, size = 2.8) +
  facet_grid(position ~ variable, scales = "free_x", space = "free_x",
             labeller = labeller(position = label_wrap_gen(18))) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.25))) +
  labs(x = NULL, y = "Number of reports (dark bar = severe)") +
  theme_bw(base_size = 10) +
  theme(panel.grid.minor = element_blank(), strip.background = element_blank(),
        axis.text.x = element_text(angle = 20, hjust = 1),
        plot.background = element_rect(fill = "white", colour = NA))

cand_info <- list(T1 = sum(cand$T1), T2 = sum(cand$T2), T3 = sum(cand$T3), T4 = sum(cand$T4),
                  narr_col = cand$narr_col, naiyo_code_col = cand$naiyo_code_col)
n_party_identified <- n_party
