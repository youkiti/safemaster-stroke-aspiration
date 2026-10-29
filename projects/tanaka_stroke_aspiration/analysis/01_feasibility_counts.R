# フィージビリティ件数の実測 — tanaka_stroke_aspiration
#   （脳卒中患者の食事・飲水関連 誤嚥・窒息事故）
#
# プロポーザル5.2「候補事例の抽出方法」に沿い、
#   脳卒中関連語（疾患名欄／自由記載） × 誤嚥・窒息（事例の内容=47 誤嚥 ／自由記載）
#   × 食事・飲水（種類=40 経口摂取, 77 食事介助, 78 食事中 ／自由記載） × 患者区分=2 入院
# の候補件数を、狭い定義から広い定義まで段階的に数える。
# 真の適格件数は個別レビュー前に確定しない（自由記載キーワードは偽陽性を含む）。
#
#   Rscript analysis/01_feasibility_counts.R          # 架空100行（ロジック確認・実値ゼロ）
#   Rscript analysis/01_feasibility_counts.R --prod   # 本番 r19
# 実行ディレクトリ: projects/tanaka_stroke_aspiration/
# 注: Rscript はこの環境で成功時も exit 255/127 を返す。成否は出力ファイルで判定する。

suppressPackageStartupMessages(library(dplyr))

PROD   <- "--prod" %in% commandArgs(trailingOnly = TRUE)
PREFIX <- if (PROD) "prod" else "synth"

MASTER <- Sys.getenv("SAFEMASTER_DIR")
if (!PROD && !nzchar(trimws(MASTER))) {
  stop("Set SAFEMASTER_DIR to the folder containing 記述研究のときのレガシーファイル/架空データ100行_r19.csv for synthetic data.")
}
LEGACY <- file.path(MASTER, "記述研究のときのレガシーファイル")

# ===== 検索語（プロポーザル5.2 ＋ 同義語補完。感度優先） =====
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

load_data <- function() {
  if (!PROD) {
    d <- read.csv(file.path(LEGACY, "架空データ100行_r19.csv"),
                  fileEncoding = "UTF-8-BOM", check.names = FALSE,
                  colClasses = "character")
  } else {
    d <- readRDS(file.path("../..", "data", "safemaster_r19_text.rds"))
  }
  names(d) <- make.unique(names(d))   # 重複列名を一意化
  d[d == "."] <- NA
  d
}

d <- load_data()
message(PREFIX, ": ", nrow(d), " 行 x ", ncol(d), " 列")
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

naiyo  <- num(d[[NAIYO_CODE]]); shurui <- num(d$種類); gaiyo <- num(d$概要)
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

# 重症度
jiko <- num(d$事故の程度); chiryo <- num(d$治療の程度); year <- num(d$報告年)
death   <- !is.na(jiko) & jiko == 1
# 重篤の定義: 死亡は OR
severe  <- death | ((!is.na(jiko) & jiko %in% c(2, 3)) & (!is.na(chiryo) & chiryo == 3))
# プロポーザル7章の記載どおり: 事故の程度∈{1,2,3} AND 治療の程度=3
sev_and <- (!is.na(jiko) & jiko %in% c(1, 2, 3)) & (!is.na(chiryo) & chiryo == 3)

OUT <- "output"; dir.create(OUT, showWarnings = FALSE)
con <- file(file.path(OUT, paste0(PREFIX, "_feasibility_counts.md")), open = "w", encoding = "UTF-8")
w <- function(...) writeLines(c(...), con)

w(paste0("# フィージビリティ件数の実測（", PREFIX, "）— tanaka_stroke_aspiration"))
w("", paste0("N = ", nrow(d), " 行 / ", ncol(d), " 列",
             if (!PROD) "（架空100行・数値に意味なし）" else "（本番 r19, 2013–2024）"))
w("", paste0("事例ID の重複: ", sum(duplicated(d$事例ID)), " 行"))
w("", paste0("列の同定: コード列=`", NAIYO_CODE, "` / 本文=`", NARR, "`"))

w("", "## 部品ごとの件数（全レコード）", "", "| 条件 | n |", "|---|---|")
w(paste0("| 患者区分=2 入院 | ", sum(inpt), " |"))
w(paste0("| 直接関連する疾患名が脳卒中語 | ", sum(stroke_direct), " |"))
w(paste0("| 疾患名4欄のいずれかが脳卒中語 | ", sum(stroke_dx), " |"))
w(paste0("| 疾患名4欄または自由記載に脳卒中語 | ", sum(stroke_any), " |"))
w(paste0("| 事例の内容=47 誤嚥 | ", sum(code47), " |"))
w(paste0("| 自由記載に誤嚥・窒息語 | ", sum(event_tx), " |"))
w(paste0("| 種類=40 経口摂取 / 77 食事介助 / 78 食事中 | ", sum(!is.na(shurui) & shurui == 40), " / ",
         sum(!is.na(shurui) & shurui == 77), " / ", sum(!is.na(shurui) & shurui == 78), " |"))
w(paste0("| 事例の内容=47 かつ 種類∈{40,77,78} | ", sum(code47 & meal_cd), " |"))
w(paste0("| 入院 かつ（誤嚥・窒息） かつ（食事・飲水）※脳卒中を問わない | ", sum(inpt & event & meal), " |"))

tier <- list(
  "T1 直接疾患名=脳卒中 × 内容=47 × 種類∈{40,77,78}（構造化のみ）" = T1,
  "T2 直接疾患名=脳卒中 ×（誤嚥・窒息）×（食事・飲水）" = T2,
  "T3 疾患名4欄のいずれか=脳卒中 ×（誤嚥・窒息）×（食事・飲水）" = T3,
  "T4 自由記載の脳卒中語も含む ×（誤嚥・窒息）×（食事・飲水）" = T4)
w("", "## 候補件数（入院に限定・段階別）", "",
  "| 段階 | n | 重篤（死亡 OR） | 重篤（提案書 AND） | 死亡 | 経管・注入語あり | 内容=47 | 種類∈{40,77,78} |",
  "|---|---|---|---|---|---|---|---|")
for (nm in names(tier)) {
  s <- tier[[nm]]
  w(paste0("| ", nm, " | ", sum(s), " | ", sum(s & severe), " | ", sum(s & sev_and), " | ",
           sum(s & death), " | ", sum(s & tube_tx), " | ", sum(s & code47), " | ",
           sum(s & meal_cd), " |"))
}

tab <- function(title, head, x) {
  w("", title, "", paste0("| ", head, " | n |"), "|---|---|")
  t <- table(x, useNA = "ifany")
  for (i in seq_along(t)) w(paste0("| ", names(t)[i], " | ", as.integer(t)[i], " |"))
}
tab("## T3 の年度分布", "報告年", year[T3])
tab("## T3 の事故の程度", "事故の程度", jiko[T3])
tab("## T3 の治療の程度", "治療の程度", chiryo[T3])
tab("## T3 の概要（大分類）", "概要コード", gaiyo[T3])
tab("## T3 の種類コード", "種類コード", shurui[T3])
tab("## T3 の事例の内容コード", "事例の内容コード", naiyo[T3])
tab("## T3 の窒息語（窒息・気道閉塞・食塊・詰ま）の有無", "窒息語",
    grepl(re(CHOKE_TERMS), free_txt[T3]))

# 対象を広げた場合の候補件数（疾患名4欄の語で群を作る。入院 ×（誤嚥・窒息）×（食事・飲水））
# 候補はキーワード一致で、脳卒中の T3 では下読みで適格だったのは半数弱。
dx_all <- paste(dx_direct_txt, dx_other_txt)
grp_pd    <- grepl("パーキンソン", dx_all)
grp_dem   <- grepl("認知症|アルツハイマー|レビー小体", dx_all)
grp_nm    <- grepl(paste0("筋萎縮性側索硬化症|ＡＬＳ|ALS|筋ジストロフィー|脊髄小脳変性|多系統萎縮|",
                          "進行性核上性|重症筋無力|大脳皮質基底核"), dx_all)
grp_dysph <- grepl("嚥下障害|嚥下機能|嚥下困難|誤嚥性肺炎|嚥下性肺炎", dx_all)
grp_neuro <- stroke_dx | grp_pd | grp_dem | grp_nm
wide <- list(
  "脳卒中（T3 と同じ）" = stroke_dx,
  "パーキンソン病・症候群" = grp_pd,
  "認知症" = grp_dem,
  "神経筋疾患・変性疾患（ALS・筋ジストロフィー・脊髄小脳変性症など）" = grp_nm,
  "神経疾患いずれか（上の4群の和集合）" = grp_neuro,
  "嚥下障害・誤嚥性肺炎が疾患名にある" = grp_dysph,
  "神経疾患いずれか または 嚥下障害・誤嚥性肺炎" = grp_neuro | grp_dysph,
  "疾患を問わない（入院全体）" = rep(TRUE, nrow(d)))
w("", "## 対象を広げた場合の候補件数（疾患名4欄・入院に限定）", "",
  "| 群 | 候補 n | うち内容=47 かつ 種類∈{40,77,78} | 重篤（死亡 OR） | 死亡 |",
  "|---|---|---|---|---|")
for (nm in names(wide)) {
  s <- inpt & wide[[nm]] & event & meal
  w(paste0("| ", nm, " | ", sum(s), " | ", sum(s & code47 & meal_cd), " | ",
           sum(s & severe), " | ", sum(s & death), " |"))
}

# スニペット目視（適合率の体感用）
w("", paste0("## スニペット（T3 の先頭20件・列: ", NARR, "・140字）— 必ず目視"), "")
for (i in head(which(T3), 20)) {
  s <- d[[NARR]][i]; if (is.na(s)) s <- "(欠測)"
  w(paste0("- [", i, "] ", substr(gsub("[\r\n]", " ", s), 1, 140)))
}
close(con)
message("出力: ", file.path(OUT, paste0(PREFIX, "_feasibility_counts.md")))

# 適格性・判定可能率の下見用: T3 から無作為40件の全文を書き出す（本番のみ・commit しない）
if (PROD && sum(T3) > 0) {
  set.seed(20261012)
  cand <- which(T3)   # sample() は長さ1のベクトルを 1:x と解釈するので添字で引く
  pick <- sort(cand[sample.int(length(cand), min(40, length(cand)))])
  con2 <- file(file.path(OUT, "prod_feasibility_sample40.md"), open = "w", encoding = "UTF-8")
  for (i in pick) {
    f <- function(cn) { s <- d[[cn]][i]; if (is.na(s)) "(欠測)" else gsub("[\r\n]+", " ", s) }
    writeLines(c(
      paste0("## ", d$事例ID[i], "（", year[i], "年・事故の程度=", jiko[i], "・治療の程度=", chiryo[i],
             "・内容=", naiyo[i], "・種類=", shurui[i], "）"),
      paste0("- 直接疾患名: ", f(DX_DIRECT), " / 関連: ", dx_other_txt[i]),
      paste0("- 内容: ", f(NARR)),
      paste0("- 背景要因: ", f("事例の背景要因の概要")), ""), con2)
  }
  close(con2)
  message("出力: ", file.path(OUT, "prod_feasibility_sample40.md"))
}

# 適格数の下見用: T4 の全候補を1件1行（段階・コード・疾患名・本文の先頭300字）で書き出す
if (PROD && sum(T4) > 0) {
  lab  <- ifelse(T1, "T1", ifelse(T2, "T2", ifelse(T3, "T3", "T4")))
  con3 <- file(file.path(OUT, "prod_feasibility_candidates.md"), open = "w", encoding = "UTF-8")
  for (i in which(T4)) {
    s <- d[[NARR]][i]; if (is.na(s)) s <- "(欠測)"
    writeLines(paste0("- ", lab[i], " | ", d$事例ID[i], " | ", year[i], " | 程度", jiko[i],
                      "/治療", chiryo[i], " | 内容", naiyo[i], "/種類", shurui[i], " | ",
                      dx_direct_txt[i], " ／ ", dx_other_txt[i], " | ",
                      substr(gsub("[\r\n]+", " ", s), 1, 300)), con3)
  }
  close(con3)
  message("出力: ", file.path(OUT, "prod_feasibility_candidates.md"))
}
