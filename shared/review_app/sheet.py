# Build and validate review workbooks; import this module from a study script.
import csv
import re
from collections import Counter
from pathlib import Path

import openpyxl


TEXT_HEADERS = ["事例の内容", "背景要因", "改善策"]
CODEBOOK_HEADERS = ["変数", "英語コード", "日本語ラベル", "定義"]
RESERVED = {"選択肢", "設定", "判定ログ"}
FORBIDDEN = {"修正_組入れ", "修正_協議済み"}


def fail(issues):
    if issues:
        raise ValueError("\n".join(issues))


def codebook_data(rows, items, header):
    issues = []
    if header not in (CODEBOOK_HEADERS, CODEBOOK_HEADERS + ["必須"]):
        issues.append("Codebook: invalid header")
    labels = {}
    seen = set()
    required = set()
    for number, row in enumerate(rows, 2):
        if set(row) != set(header) or any(not isinstance(value, str) for value in row.values()):
            issues.append(f"Codebook row {number}: invalid fields")
            continue
        item, code, label = [row.get(name, "") for name in CODEBOOK_HEADERS[:3]]
        if not item or not code or not label:
            issues.append(f"Codebook row {number}: empty item, code or label")
        if (item, label) in seen or code in labels.get(item, {}):
            issues.append(f"Codebook row {number}: duplicate label or code")
        seen.add((item, label))
        labels.setdefault(item, {})[code] = label
        if row.get("必須", "") not in ("", "必須"):
            issues.append(f"Codebook row {number}: invalid required marker")
        if row.get("必須") == "必須":
            required.add(item)
    if not set(labels) <= set(items):
        issues.append("Codebook: variable set differs from entry items")
    for item in items:
        if item in labels and len(labels[item]) < 2:
            issues.append(f"Codebook: fewer than two options for {item}")
    fail(issues)
    return labels, required


def load_codebook(path, items):
    with Path(path).open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
        header = reader.fieldnames or []
    labels, required = codebook_data(rows, items, header)
    return rows, labels, required


def validate_cells(tables):
    issues = []
    for tab, (header, rows) in tables.items():
        for number, row in enumerate([header] + rows, 1):
            if len(row) != len(header):
                issues.append(f"{tab} row {number}: invalid width")
            for col, value in enumerate(row, 1):
                if not isinstance(value, str) or len(value) >= 32767:
                    issues.append(f"{tab} row {number} column {col}: invalid string or length")
                elif re.search(r"[\x00-\x08\x0b\x0c\x0e-\x1f\ud800-\udfff\ufffe\uffff]", value):
                    issues.append(f"{tab} row {number} column {col}: illegal XML character")
    fail(issues)


def validate_log_rows(header, rows, tables, labels, actions=("agree", "modify", "clear")):
    issues = []
    for number, values in enumerate(rows, 2):
        if len(values) != len(header):
            issues.append(f"判定ログ row {number}: invalid width")
            continue
        row = dict(zip(header, values))
        tab = row["tab"]
        if tab not in tables or tab in RESERVED:
            issues.append(f"判定ログ row {number}: unknown tab")
            continue
        columns, cases = tables[tab]
        if row["事例ID"] not in {case[columns.index("事例ID")] for case in cases}:
            issues.append(f"判定ログ row {number}: unknown ID")
        if row["action"] not in actions:
            issues.append(f"判定ログ row {number}: invalid action")
        if not isinstance(row["reviewer"], str) or not row["reviewer"].strip():
            issues.append(f"判定ログ row {number}: missing reviewer")
        for name in header[5:]:
            if name.startswith("修正_") and row[name]:
                if name not in columns or (name[3:] in labels and row[name] not in labels[name[3:]].values()):
                    issues.append(f"判定ログ row {number}: invalid entry column or label")
    fail(issues)


def build_tables(tabs, codebook_rows, draft_prefix="下書き_", settings=None, log_rows=None,
                 codebook_header=None):
    issues = []
    if draft_prefix not in ("下書き_", "AI_", None):
        issues.append("Invalid draft prefix")
    names = list(tabs)
    if len(set(names)) != len(names) or RESERVED.intersection(names):
        issues.append("Reserved or duplicate tab name")
    fail(issues)
    items = {item for spec in tabs.values() for item in spec["items"]}
    code_header = codebook_header
    if code_header is None:
        code_header = list(codebook_rows[0]) if codebook_rows else CODEBOOK_HEADERS
    labels, _ = codebook_data(codebook_rows, items, code_header)
    tables = {}
    entries = []
    for tab, spec in tabs.items():
        items = spec["items"]
        display = spec["display"]
        bases = any("basis" in row for row in spec["rows"])
        header = ["事例ID", "報告年"] + display
        if bases:
            header += ["下書きの根拠_" + item for item in items]
        if draft_prefix:
            header += [draft_prefix + item for item in items]
        header += ["修正_" + item for item in items] + ["メモ"] + TEXT_HEADERS
        if len(set(header)) != len(header) or FORBIDDEN.intersection(header):
            issues.append(f"{tab}: duplicate or forbidden column")
        if any(name.startswith(("修正_", "AI_", "下書き_")) or name == "メモ" for name in display):
            issues.append(f"{tab}: entry or draft column in display")
        rows = []
        ids = set()
        for number, source in enumerate(spec["rows"], 2):
            identifier = source.get("事例ID", "")
            if not identifier or identifier in ids:
                issues.append(f"{tab} row {number}: empty or duplicate ID")
            ids.add(identifier)
            draft = source.get("draft", {})
            basis = source.get("basis", {})
            if set(draft) != set(items) or (bases and set(basis) != set(items)):
                issues.append(f"{tab} row {number}: incomplete draft or basis")
            for item in items:
                value = draft.get(item, "")
                if not isinstance(value, str) or (draft_prefix is None and value != ""):
                    issues.append(f"{tab} row {number}: invalid draft string")
                if value and (not draft_prefix or (item in labels and value not in labels[item].values())):
                    issues.append(f"{tab} row {number}: invalid draft label")
            row = [source.get(name) for name in ["事例ID", "報告年"] + display]
            if bases:
                row += [basis.get(item) for item in items]
            if draft_prefix:
                row += [draft.get(item) for item in items]
            row += [""] * (len(items) + 1)
            for name in TEXT_HEADERS:
                value = source.get(name)
                row.append(re.sub(r"[\r\n\t]", " ", value) if isinstance(value, str) else value)
            rows.append(row)
        # A frozen source table preserves columns and values when preparing consensus.
        if "source_table" in spec:
            header, rows = spec["source_table"]
            if len(set(header)) != len(header) or FORBIDDEN.intersection(header):
                issues.append(f"{tab}: duplicate or forbidden column")
            if {name[3:] for name in header if name.startswith("修正_")} != set(items):
                issues.append(f"{tab}: source entry items differ")
            if not set(["事例ID", "報告年", "メモ"] + TEXT_HEADERS).issubset(header):
                issues.append(f"{tab}: missing source column")
            else:
                if any(len(row) != len(header) for row in rows):
                    issues.append(f"{tab}: invalid source width")
                elif [row[header.index("事例ID")] for row in rows] != [row["事例ID"] for row in spec["rows"]]:
                    issues.append(f"{tab}: source ID sequence differs")
                else:
                    for row in rows:
                        for name, value in zip(header, row):
                            if name.startswith(("下書き_", "AI_")) and value:
                                item = name.split("_", 1)[1]
                                if item not in items or (item in labels and value not in labels[item].values()):
                                    issues.append(f"{tab}: invalid source draft label")
        tables[tab] = (header, rows)
        for name in header:
            if (name.startswith("修正_") or name == "メモ") and name not in entries:
                entries.append(name)
    tables["選択肢"] = (code_header, [[row[name] for name in code_header] for row in codebook_rows])
    if settings is not None:
        if not isinstance(settings.get("independent"), bool):
            raise ValueError("Settings: independent must be bool")
        tables["設定"] = (["項目", "値"],
                        [["独立判定", "はい" if settings["independent"] else "いいえ"]] +
                        [["判定者:" + email, name] for email, name in settings.get("names", {}).items()] +
                        [["参考:" + email, name] for email, name in settings.get("references", {}).items()])
    log_header = ["timestamp", "reviewer", "tab", "事例ID", "action"] + entries
    tables["判定ログ"] = (log_header, [] if log_rows is None else log_rows)
    fail(issues)
    validate_cells(tables)
    validate_log_rows(log_header, tables["判定ログ"][1], tables, labels)
    return tables


def write_summary(path, tables, lengths, title):
    lines = ["# " + title, ""]
    for tab, (header, rows) in tables.items():
        if tab in RESERVED:
            continue
        severe = "重篤" in header
        lines += [f"## {tab}", "", "| 件数 |" + (" 重篤 |" if severe else ""),
                  "| ---: |" + (" ---: |" if severe else "")]
        count = sum(row[header.index("重篤")] == "重篤" for row in rows) if severe else 0
        lines.append(f"| {len(rows)} |" + (f" {count} |" if severe else ""))
        for name in header:
            if not name.startswith("修正_"):
                continue
            item = name[3:]
            draft = next((prefix + item for prefix in ("下書き_", "AI_") if prefix + item in header), None)
            basis = "下書きの根拠_" + item
            counts = Counter(
                ((row[header.index(draft)] if draft else "") or "（空欄）",
                 (row[header.index(basis)] if basis in header else "") or "—")
                for row in rows
            )
            lines += ["", f"### {item}", "", "| 下書き値 | 下書きの根拠 | 件数 |", "| --- | --- | ---: |"]
            for (value, reason), count in sorted(counts.items()):
                lines.append(f"| {value} | {reason} | {count} |")
    lines += ["", "## 文字数の確認", "", "| タブ | 列 | 保存前最大 | 再読込最大 |",
              "| --- | --- | ---: | ---: |"]
    for tab, name, expected, observed in lengths:
        lines.append(f"| {tab} | {name} | {expected} | {observed} |")
    Path(path).write_bytes(("\n".join(lines) + "\n").encode("utf-8"))


def build(tabs, codebook_path, out_xlsx, summary_path, expected_count,
          draft_prefix="下書き_", title="確認用シート集計", settings=None, log_rows=None):
    items = {item for spec in tabs.values() for item in spec["items"]}
    rows, _, _ = load_codebook(codebook_path, items)
    with Path(codebook_path).open(encoding="utf-8-sig", newline="") as handle:
        code_header = next(csv.reader(handle), [])
    tables = build_tables(tabs, rows, draft_prefix, settings, log_rows, code_header)
    write_workbook(out_xlsx, tables)
    lengths = verify_workbook(out_xlsx, tables, expected_count)
    write_summary(summary_path, tables, lengths, title)
    return tables


def write_workbook(path, tables):
    validate_cells(tables)
    workbook = openpyxl.Workbook()
    workbook.remove(workbook.active)
    try:
        for tab, (header, rows) in tables.items():
            sheet = workbook.create_sheet(tab)
            for number, row in enumerate([header] + rows, 1):
                for col, value in enumerate(row, 1):
                    cell = sheet.cell(number, col, value)
                    cell.data_type = "s"
        workbook.save(path)
    finally:
        workbook.close()


def verify_sheet(sheet, header, rows, issues):
    actual = [["" if cell.value is None else cell.value for cell in row] for row in sheet.iter_rows()]
    if actual[0] != header:
        issues.append(f"{sheet.title}: header mismatch")
    if len(actual) != len(rows) + 1:
        issues.append(f"{sheet.title}: row count mismatch")
    if "事例ID" in header:
        col = header.index("事例ID")
        if [row[col] for row in actual[1:]] != [row[col] for row in rows]:
            issues.append(f"{sheet.title}: ID sequence mismatch")
    for col, name in enumerate(header):
        if sheet.title not in RESERVED and (name.startswith("修正_") or name == "メモ"):
            if any(row[col] != "" for row in actual[1:]):
                issues.append(f"{sheet.title}: entry cells are not empty")
    if actual != [header] + rows:
        issues.append(f"{sheet.title}: cell values differ")
    for row in sheet.iter_rows():
        if any(cell.value is not None and cell.data_type != "s" for cell in row):
            issues.append(f"{sheet.title} row {row[0].row}: non-string cell")
    return actual[1:]


def verify_workbook(path, tables, expected_count):
    issues = []
    lengths = []
    workbook = openpyxl.load_workbook(path, data_only=False)
    try:
        if workbook.sheetnames != list(tables):
            issues.append("Output tab names or order differ")
        total = 0
        for tab, (header, rows) in tables.items():
            if tab not in workbook.sheetnames:
                continue
            sheet = workbook[tab]
            if sheet.max_column != len(header):
                issues.append(f"{tab}: column count mismatch")
                continue
            actual = verify_sheet(sheet, header, rows, issues)
            if tab in RESERVED:
                continue
            total += len(actual)
            for name in TEXT_HEADERS:
                col = header.index(name)
                expected = max((len(row[col]) for row in rows), default=0)
                observed = max((len(str(row[col])) for row in actual), default=0)
                lengths.append((tab, name, expected, observed))
                if expected != observed or max(expected, observed) >= 32767:
                    issues.append(f"{tab}: text length mismatch or limit reached for {name}")
        if total != expected_count:
            issues.append("Total data rows differ from frozen target count")
    finally:
        workbook.close()
    fail(issues)
    return lengths
