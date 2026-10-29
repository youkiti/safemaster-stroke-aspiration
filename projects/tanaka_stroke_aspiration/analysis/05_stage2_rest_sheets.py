# 目的: 第2段階の残り38件を無作為に19件ずつ割り付け、AI下読みを確認する配布シートを作る。
# 入力: output/prod_review_sheets_stage2.xlsx、output/prod_stage2_pilot10_ids.csv、
#       output/ai_v2/ai_rest38_vote.csv、analysis/review_codebook.csv（すべてプロジェクト起点）。
# 出力: output/prod_stage2_rest_{tanaka,suehiro}.{xlsx,md}、
#       output/prod_stage2_rest_assignment.csv、output/prod_stage2_rest_codebook.csv。
# 実行: python -I -X utf8 analysis/05_stage2_rest_sheets.py（cwd に依存しない）。
import csv
import os
import random
import sys
from pathlib import Path

import openpyxl


PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT.parents[1] / "shared" / "review_app"))
import sheet


ITEMS = [
    "脳卒中の位置づけ", "脳卒中病型", "事故類型", "摂取物", "摂食介助状況", "同席状況",
    "嚥下評価", "指示逸脱", "食事区分", "救命介入", "直接介助者の当事者番号",
]
REQUIRED = set(ITEMS[:9])
REVIEWERS = [
    ("tanaka", "田中", "SAFEMASTER_REVIEWER_TANAKA"),
    ("suehiro", "末廣", "SAFEMASTER_REVIEWER_SUEHIRO"),
]


def fail(message):
    sys.exit(message)


def read_csv(path, required):
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        header = reader.fieldnames or []
        if len(header) != len(set(header)) or not set(required) <= set(header):
            fail(f"{path.name}: 列の欠け・重複")
        rows = list(reader)
    if any(set(row) != set(header) or any(value is None for value in row.values()) for row in rows):
        fail(f"{path.name}: 行の列数が不正")
    return rows


def index_ids(rows, name):
    identifiers = [row["事例ID"] for row in rows]
    if any(not identifier.strip() for identifier in identifiers) or len(identifiers) != len(set(identifiers)):
        fail(f"{name}: 事例IDが空・重複")
    return dict(zip(identifiers, rows))


def source_rows(path):
    workbook = openpyxl.load_workbook(path, read_only=True, data_only=False)
    try:
        if "組入れ" not in workbook.sheetnames:
            fail("元の xlsx: 組入れタブが無い")
        values = workbook["組入れ"].values
        header = list(next(values, []))
        needed = ["事例ID", "報告年"] + sheet.TEXT_HEADERS
        if not set(needed) <= set(header) or len(header) != len(set(header)):
            fail("元の xlsx: 列の欠け・重複")
        first_entry = next((i for i, name in enumerate(header) if isinstance(name, str) and name.startswith("修正_")), None)
        if header[:2] != ["事例ID", "報告年"] or first_entry is None or first_entry < 2:
            fail("元の xlsx: 表示列の位置が不正")
        display = header[2:first_entry]
        rows = [dict(zip(header, ["" if value is None else str(value) for value in row])) for row in values]
    finally:
        workbook.close()
    return rows, display


def write_csv(path, header, rows):
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=header, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main():
    reviewers = []
    for slug, name, variable in REVIEWERS:
        email = os.environ.get(variable, "").strip()
        if not email:
            fail(f"Set {variable} to the reviewer's email address before generating sheets.")
        reviewers.append((slug, name, email))
    output = PROJECT / "output"
    rows, display = source_rows(output / "prod_review_sheets_stage2.xlsx")
    cases = index_ids(rows, "組入れ")
    pilot_rows = read_csv(output / "prod_stage2_pilot10_ids.csv", ["事例ID"])
    pilot = index_ids(pilot_rows, "試行10件")
    if len(cases) != 48 or len(pilot) != 10:
        fail(f"件数が不正: 組入れ {len(cases)} / 試行 {len(pilot)}")
    if not set(pilot) <= set(cases):
        fail("試行10件に組入れタブに無い事例IDがある")
    rest = set(cases) - set(pilot)
    ai_columns = ["事例ID"] + ITEMS + ["根拠_" + item for item in ITEMS] + ["回ごとに割れた項目", "過半数なし"]
    votes = index_ids(read_csv(output / "ai_v2" / "ai_rest38_vote.csv", ai_columns), "AI多数決")
    if set(votes) != rest:
        fail(f"残り38件とAIの事例IDが不一致: AIのみ {sorted(set(votes) - rest)} / 組入れのみ {sorted(rest - set(votes))}")

    code_rows = read_csv(PROJECT / "analysis" / "review_codebook.csv", sheet.CODEBOOK_HEADERS)
    code_rows = [{name: row[name] for name in sheet.CODEBOOK_HEADERS} for row in code_rows if row["変数"] in ITEMS]
    for row in code_rows:
        row["必須"] = "必須" if row["変数"] in REQUIRED else ""
    code_header = sheet.CODEBOOK_HEADERS + ["必須"]
    labels, required = sheet.codebook_data(code_rows, ITEMS, code_header)
    if set(labels) != set(ITEMS[:-1]) or required != REQUIRED:
        fail("選択肢の項目・必須項目が不正")
    for identifier, vote in votes.items():
        for item in ITEMS:
            value = vote[item]
            if value and item in labels and value not in labels[item].values():
                fail(f"{identifier} {item}: 選択肢に無いAI値 {value!r}")

    identifiers = sorted(rest)
    random.Random(20261025).shuffle(identifiers)
    assignment = []
    tabs_by_reviewer = []
    for number, (slug, name, email) in enumerate(reviewers):
        assigned = identifiers[number * 19:(number + 1) * 19]
        assignment.extend({"事例ID": identifier, "判定者": name, "reviewer": email} for identifier in assigned)
        selected = set(assigned)
        prepared = []
        for source in rows:
            identifier = source["事例ID"]
            if identifier not in selected:
                continue
            vote = votes[identifier]
            row = {key: source[key] for key in ["事例ID", "報告年"] + display + sheet.TEXT_HEADERS}
            notices = []
            if vote["回ごとに割れた項目"]:
                notices.append("3本で割れた: " + vote["回ごとに割れた項目"])
            if vote["過半数なし"]:
                notices.append("過半数なし: " + vote["過半数なし"])
            row["下読みの注意"] = " / ".join(notices)
            row["draft"] = {item: vote[item] for item in ITEMS}
            if vote["事故類型"] != "窒息・気道閉塞":
                row["draft"]["救命介入"] = ""
            row["basis"] = {item: vote["根拠_" + item] for item in ITEMS}
            prepared.append(row)
        tabs = {"組入れ": {"items": ITEMS, "display": display + ["下読みの注意"], "rows": prepared}}
        tabs_by_reviewer.append((slug, name, tabs))

    code_path = output / "prod_stage2_rest_codebook.csv"
    write_csv(code_path, code_header, code_rows)
    for slug, name, tabs in tabs_by_reviewer:
        prefix = output / ("prod_stage2_rest_" + slug)
        sheet.build(
            tabs, code_path, prefix.with_suffix(".xlsx"), prefix.with_suffix(".md"),
            expected_count=19, draft_prefix="AI_", title=f"第2段階 残り38件 AI下読みの確認（{name}先生）",
        )
        print(f"{name}: 組入れ 19 件 → {prefix.with_suffix('.xlsx')}")
    write_csv(output / "prod_stage2_rest_assignment.csv", ["事例ID", "判定者", "reviewer"], assignment)
    print(f"割り付け: {len(assignment)} 件、重複なし（seed=20261025）")


if __name__ == "__main__":
    main()
