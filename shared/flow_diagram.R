# shared/flow_diagram.R — セーフマスタ共通: STROBE/CONSORT 風フロー図
#
# 目的: 各プロジェクトで毎回ハマる「座標手計算・外部パッケージ依存・日本語豆腐化」を
#   排除する。ggplot2 だけに依存し、ボックス位置・矢印・分岐を自動レイアウトする。
#   利用側はテキストと件数を渡すだけ。座標は一切書かない。
#
# 使い方:
#   source(".../shared/flow_diagram.R")
#   p <- flow_diagram(
#     nodes = c(
#       "Adverse-event reports, 2013–2024\nn = 54,310",
#       "Keyword candidates\n(MRI × stroke)\nn = 1,166",
#       "Eligible for analysis\nn = 31 (severe 9; death 3)"),
#     exclusions = c(NA, "Excluded on manual review\nn = 1,135"))  # 長さ = length(nodes)-1
#   save_flow(p, "output/fig1_flow.png")    # 大きさは自動算出
#   # 末尾分岐（最終ノードから K 本に分かれる）:
#   #   flow_diagram(nodes, exclusions, split = c("Prescribing\nn = 106", "Dispensing\nn = 69"))
#   # 分岐後の除外と最終ボックス（NA/"" の枝は分岐ボックスで終了）:
#   #   flow_diagram("All reports", split = c("Flagged", "Other"),
#   #     split_exclusions = c("Excluded on review", NA),
#   #     split_final = c("Analysed", NA))
#
# 設計上の約束:
#   - ggplot2 のみ（consort 等は不要）。返り値は ggplot オブジェクト。
#   - 既定は白背景・黒字・黒枠（論文体裁）。色は引数で変更可。
#   - 日本語を含むラベルは自動で日本語フォントに切替（Windows: Yu Gothic 系）。
#   - ボックス高さは行数から自動。除外ボックスはノード間ギャップの右へ枝分かれ。

suppressPackageStartupMessages(library(ggplot2))

# 日本語が含まれるか（ASCII 外があれば JP フォントへ）
.has_nonascii <- function(x) any(grepl("[^\x01-\x7F]", x), na.rm = TRUE)

.pick_font <- function(font, labels) {
  if (!is.null(font)) return(font)
  if (!.has_nonascii(labels)) return("")            # 英語のみ → 既定 sans
  for (f in c("Yu Gothic", "Meiryo", "MS Gothic", "Noto Sans CJK JP")) {
    ok <- tryCatch({ grDevices::windowsFonts(jp = grDevices::windowsFont(f)); TRUE },
                   error = function(e) FALSE)
    if (ok) return(f)
  }
  ""
}

flow_diagram <- function(nodes,
                         exclusions = NULL,   # 長さ length(nodes)-1。NA/"" でそのギャップは枝なし
                         split = NULL,        # 最終ノードから分岐する終端ボックス群
                         split_exclusions = NULL,
                         split_final = NULL,
                         font = NULL,
                         box_fill = "white", box_color = "black",
                         text_color = "black", text_size = 3.7,
                         main_w = 4.6, excl_w = 4.2, gap_x = 1.0,
                         line_h = 0.5, pad = 0.34, gap_v = 0.7) {
  stopifnot(length(nodes) >= 1)
  N <- length(nodes)
  if (is.null(split) && (!is.null(split_exclusions) || !is.null(split_final))) {
    stop("split_exclusions and split_final require split")
  }
  if (!is.null(split_exclusions) && length(split_exclusions) != length(split)) {
    stop("split_exclusions must have the same length as split")
  }
  if (!is.null(split_final) && length(split_final) != length(split)) {
    stop("split_final must have the same length as split")
  }
  has_final <- !is.na(split_final) & nzchar(split_final)
  has_excl <- !is.na(split_exclusions) & nzchar(split_exclusions)
  if (any(has_excl) && (is.null(split_final) || any(has_excl & !has_final))) {
    stop("Each split_exclusions label requires a split_final label on the same branch")
  }
  fam <- .pick_font(font, c(nodes, exclusions, split, split_exclusions, split_final))

  nlines <- function(s) vapply(strsplit(s, "\n", fixed = TRUE), length, 1L)

  # ---- 主軸ノードを縦に配置（y は上から下へ減少） ----
  x_main <- 0
  hN <- nlines(nodes) * line_h + pad
  ytop <- 0; ymin <- numeric(N); ymax <- numeric(N)
  for (i in seq_len(N)) {
    ymax[i] <- ytop; ymin[i] <- ytop - hN[i]
    ytop <- ymin[i] - gap_v
  }
  yc <- (ymin + ymax) / 2
  boxes <- data.frame(x = x_main, y = yc, w = main_w, h = hN,
                      lab = nodes, kind = "main", stringsAsFactors = FALSE)

  segs <- data.frame()
  add_seg <- function(x, xend, y, yend, head) segs <<- rbind(segs,
    data.frame(x = x, xend = xend, y = y, yend = yend, head = head))

  # ---- 主軸の矢印 ＋ 除外の枝分かれ ----
  x_excl <- x_main + main_w/2 + gap_x + excl_w/2
  for (i in seq_len(N - 1)) {
    jy <- (ymin[i] + ymax[i + 1]) / 2     # ノード間ギャップ中心
    ex <- if (!is.null(exclusions) && length(exclusions) >= i) exclusions[i] else NA
    if (!is.na(ex) && nzchar(ex)) {
      add_seg(x_main, x_main, ymin[i], jy, FALSE)         # ノード下→分岐点
      add_seg(x_main, x_main, jy, ymax[i + 1], TRUE)      # 分岐点→次ノード
      he <- nlines(ex) * line_h + pad
      boxes <- rbind(boxes, data.frame(x = x_excl, y = jy, w = excl_w, h = he,
                                       lab = ex, kind = "excl", stringsAsFactors = FALSE))
      add_seg(x_main, x_excl - excl_w/2, jy, jy, TRUE)    # 横へ枝分かれ
    } else {
      add_seg(x_main, x_main, ymin[i], ymax[i + 1], TRUE) # 単純に下へ
    }
  }

  # ---- 終端分岐（最終ノードから K ボックス） ----
  if (!is.null(split) && length(split) > 0) {
    K <- length(split); hs <- nlines(split) * line_h + pad
    sw <- main_w * 0.92
    span <- (K - 1) * (sw + 0.5)
    sx <- seq(-span/2, span/2, length.out = K)
    bus_y <- ymin[N] - gap_v                       # バス線の高さ
    sy_top <- bus_y - gap_v * 0.4
    add_seg(x_main, x_main, ymin[N], bus_y, FALSE) # 最終ノード→バス
    if (K > 1) add_seg(min(sx), max(sx), bus_y, bus_y, FALSE)  # 横バス
    for (k in seq_len(K)) {
      yc_k <- sy_top - hs[k]/2
      add_seg(sx[k], sx[k], bus_y, yc_k + hs[k]/2, TRUE)
      boxes <- rbind(boxes, data.frame(x = sx[k], y = yc_k, w = sw, h = hs[k],
                                       lab = split[k], kind = "split", stringsAsFactors = FALSE))
      if (!is.null(split_final) && has_final[k]) {
        split_bottom <- yc_k - hs[k]/2
        final_top <- split_bottom - gap_v
        hf <- nlines(split_final[k]) * line_h + pad
        boxes <- rbind(boxes, data.frame(x = sx[k], y = final_top - hf/2, w = sw, h = hf,
                                         lab = split_final[k], kind = "split_final",
                                         stringsAsFactors = FALSE))
        if (!is.null(split_exclusions) && has_excl[k]) {
          jy <- (split_bottom + final_top) / 2
          side <- if (sx[k] < 0) -1 else 1
          xe <- sx[k] + side * (sw/2 + gap_x + excl_w/2)
          he <- nlines(split_exclusions[k]) * line_h + pad
          add_seg(sx[k], sx[k], split_bottom, jy, FALSE)
          add_seg(sx[k], sx[k], jy, final_top, TRUE)
          boxes <- rbind(boxes, data.frame(x = xe, y = jy, w = excl_w, h = he,
                                           lab = split_exclusions[k], kind = "split_excl",
                                           stringsAsFactors = FALSE))
          add_seg(sx[k], xe - side * excl_w/2, jy, jy, TRUE)
        } else {
          add_seg(sx[k], sx[k], split_bottom, final_top, TRUE)
        }
      }
    }
  }

  boxes$xmin <- boxes$x - boxes$w/2; boxes$xmax <- boxes$x + boxes$w/2
  boxes$ymin <- boxes$y - boxes$h/2; boxes$ymax <- boxes$y + boxes$h/2

  arr <- arrow(length = unit(0.18, "cm"), type = "closed")
  p <- ggplot() +
    geom_rect(data = boxes, aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
              fill = box_fill, color = box_color, linewidth = 0.4) +
    geom_text(data = boxes, aes(x = x, y = y, label = lab),
              size = text_size, lineheight = 0.95, color = text_color, family = fam)
  if (nrow(segs)) {
    sp <- segs[!segs$head, , drop = FALSE]; sa <- segs[segs$head, , drop = FALSE]
    if (nrow(sp)) p <- p + geom_segment(data = sp, aes(x = x, xend = xend, y = y, yend = yend),
                                        color = box_color, linewidth = 0.4)
    if (nrow(sa)) p <- p + geom_segment(data = sa, aes(x = x, xend = xend, y = y, yend = yend),
                                        arrow = arr, color = box_color, linewidth = 0.4)
  }
  # 余白付きで描画範囲を固定。coord_fixed で x/y 等倍 → 設計どおりの形を保ち、
  # 縦伸び・ボックスのはみ出し（クリップ）を防ぐ。
  xr <- range(c(boxes$xmin, boxes$xmax)); yr <- range(c(boxes$ymin, boxes$ymax))
  mx <- diff(xr) * 0.04 + 0.25; my <- diff(yr) * 0.04 + 0.25
  p <- p + coord_fixed(ratio = 1, expand = FALSE,
                       xlim = c(xr[1]-mx, xr[2]+mx), ylim = c(yr[1]-my, yr[2]+my)) +
    theme_void()
  # save_flow 用に描画範囲（データ単位＝インチ換算の基準）を添付
  attr(p, "flow_size") <- c(width = diff(xr) + 2*mx, height = diff(yr) + 2*my)
  p
}

# 縦横比を保ったまま PNG 保存（大きさ自動）。in_per_unit でスケール、max_w で上限。
save_flow <- function(p, path, in_per_unit = 0.62, dpi = 150, max_w = 9) {
  sz <- attr(p, "flow_size"); if (is.null(sz)) sz <- c(width = 8, height = 6)
  scale <- min(in_per_unit, max_w / as.numeric(sz["width"]))
  ggsave(path, p, width = as.numeric(sz["width"]) * scale,
         height = as.numeric(sz["height"]) * scale, dpi = dpi,
         bg = "white", limitsize = FALSE)
  invisible(path)
}
