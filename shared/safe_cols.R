# shared/safe_cols.R — fail-loud な列アクセス（セーフマスタ解析コードの共通基盤）
#
# 目的: 列名で参照する全アクセスをここに通し、**列が存在しないときに無言で全 NA を返す**
#       事故（kamijo_産婦人科 の outpatient 0% バグ）を構造的に防ぐ。旧来は各 00_prep.R が
#       ローカルに flag()/col_first() を定義し、該当列なし → rep(NA) を黙って返していた。
#       ここでは該当列なしを **warning()（既定）/ stop()（strict）** で必ず可視化する。
#
# 使い方:
#   source("shared/safe_cols.R")
#   orm  <- flag(d, "手術室")                 # one-hot フラグ: 該当="1"→TRUE / 列なし→warning+全FALSE
#   occ  <- col_first(d, "当事者職種_1")       # 値そのもの: 列なし→warning+全NA
#   outp <- flag_outpatient(d)                # 外来は集約列が無い→4列OR（救急外来含む既定）
#   assert_cols(d, c("手術室","分娩室","外来処置室"))  # 着手時に名前参照する全列の存在を一括検証
#
# strict モード: options(safemaster.strict_cols = TRUE) で列なしを stop に昇格（本番前の自己チェック向け）。

# 重複列名は make.unique で "name...N" になる（読込が全列 character のため）。コード列＝先頭を採用。
.sm_match_idx <- function(have, name) {
  which(have == name | startsWith(have, paste0(name, "...")))
}

# 列の値（character）を返す。列が無ければ warning（strict なら stop）して全 NA。
col_first <- function(d, name, .strict = getOption("safemaster.strict_cols", FALSE)) {
  idx <- .sm_match_idx(names(d), name)
  if (length(idx) == 0) {
    msg <- sprintf("[safe_cols] 列が見つかりません: '%s' → 全NAを返します（outpatient型の無言NAバグ防止）", name)
    if (isTRUE(.strict)) stop(msg, call. = FALSE) else warning(msg, call. = FALSE)
    return(rep(NA_character_, nrow(d)))
  }
  d[[idx[1]]]
}

# one-hot フラグ: 該当="1"→TRUE / 非該当・欠測→FALSE。列が無ければ warning（strict なら stop）+全FALSE。
# 後方互換: 旧来 flag(d$列) のようにベクトルを直接渡された場合（name 省略）はそのまま判定する。
flag <- function(d, name, .strict = getOption("safemaster.strict_cols", FALSE)) {
  if (missing(name)) {            # 旧シグネチャ flag(<vector>)
    col <- d
    return(!is.na(col) & col == "1")
  }
  col <- col_first(d, name, .strict = .strict)
  !is.na(col) & col == "1"
}

# 外来（outpatient）専用ヘルパ。発生場所に **集約「外来」列は存在しない**ため 4 列を OR で束ねる。
# 既定で救急外来を含む（kamijo_産婦人科, ユーザー決定 2026-06-24）。プロジェクトで除外したい場合は
# include_er = FALSE。各列の存在は flag() 経由で検証される（列名変更時は warning で気づける）。
flag_outpatient <- function(d, include_er = TRUE, .strict = getOption("safemaster.strict_cols", FALSE)) {
  cols <- c("外来処置室", "外来診察室", "外来待合室")
  if (isTRUE(include_er)) cols <- c(cols, "救急外来")
  Reduce(`|`, lapply(cols, function(cn) flag(d, cn, .strict = .strict)))
}

# 着手時アサート: 名前参照する全列が存在するか一括検証し、欠けていれば stop（本番を流す前の fail-loud）。
assert_cols <- function(d, cols) {
  have <- names(d)
  miss <- cols[!vapply(cols, function(n) length(.sm_match_idx(have, n)) > 0, logical(1))]
  if (length(miss)) {
    stop(sprintf("[safe_cols] 参照予定の列が存在しません: %s", paste(miss, collapse = ", ")), call. = FALSE)
  }
  invisible(TRUE)
}
