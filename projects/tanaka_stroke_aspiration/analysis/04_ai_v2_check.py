"""第2段階 AI 下読み（判定基準 v2）の検査: 選択肢の妥当性、引用の実在、多数決、正解値との一致。

使い方（実行ディレクトリは projects/tanaka_stroke_aspiration/）:
  python -I -X utf8 analysis/04_ai_v2_check.py --cases output/ai_v2/cases_pilot10.jsonl \
      --ai output/ai_v2/ai_pilot10_raw_r3a.jsonl output/ai_v2/ai_pilot10_raw_r3b.jsonl ... \
      --out output/ai_v2/ai_pilot10.csv [--gold output/prod_stage2_pilot10_gold_v2.csv]

- --ai は独立に判定した結果を1本以上。各結果を次のとおり検査し、1つでも問題があれば停止する。
  値が選択肢（analysis/review_codebook.csv）に無い、事例IDの過不足・重複、項目の欠け。
  quote が空でなければ、source の列に（空白を除いて比べて）含まれること。
  救命介入は事故類型が窒息・気道閉塞のときだけ値を持つ。直接介助者の当事者番号は空か「1」「1,2」の形。
- 複数あれば項目ごとに過半数の値を採る。過半数が無い項目は「過半数なし」として一覧にし、値と根拠を空文字にする。
  多数決で事故類型が窒息以外になったのに救命介入に値が残る組み合わせは、救命介入を空にする。
- --out には、採った値（事例ID＋11項目）、根拠_<項目>（採った値を出した最初の結果の [source] quote）、
  全項目をつないだ AIの根拠、回ごとに値が割れた項目、過半数なしの項目名をそれぞれ「 / 」でつないで書く。
  quote が空なら項目ごとの根拠は空文字にする。
- --gold があれば全項目の一致を数え、食い違いを一覧にする。全一致なら exit 0、食い違いか多数決なしがあれば exit 3。
"""
import argparse
import collections
import csv
import json
import re
import sys

VARS = ['脳卒中の位置づけ', '脳卒中病型', '事故類型', '摂取物', '摂食介助状況', '同席状況',
        '嚥下評価', '指示逸脱', '食事区分', '救命介入', '直接介助者の当事者番号']
CHOKING = '窒息・気道閉塞'


def squash(s):
    return re.sub(r'\s+', '', s or '')


def load_jsonl(path):
    out = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            if not line.strip():
                continue
            d = json.loads(line)
            if d['事例ID'] in out:
                sys.exit(f'{path}: 事例IDが重複 {d["事例ID"]}')
            out[d['事例ID']] = d
    return out


def check_run(path, run, cases, options):
    """1本の結果を検査し、{事例ID: {項目: (値, source, quote)}} を返す。"""
    if set(run) != set(cases):
        sys.exit(f'{path}: 事例IDの過不足 AI のみ {sorted(set(run) - set(cases))} / 入力のみ {sorted(set(cases) - set(run))}')
    errors, parsed = [], {}
    for cid in sorted(cases):
        items = run[cid].get('items', {})
        missing = [v for v in VARS if v not in items]
        if missing:
            errors.append(f'{cid}: 項目が無い {missing}')
            continue
        parsed[cid] = {}
        for v in VARS:
            it = items[v]
            val = (it.get('value') or '').strip()
            src, quote = it.get('source') or '', it.get('quote') or ''
            if v == '救命介入':
                if items['事故類型'].get('value') == CHOKING:
                    if val not in options[v]:
                        errors.append(f'{cid} {v}: 選択肢に無い値 {val!r}')
                elif val:
                    errors.append(f'{cid} {v}: 窒息以外なのに値がある {val!r}')
            elif v == '直接介助者の当事者番号':
                if val and not re.fullmatch(r'(10|[1-9])(,(10|[1-9]))*', val):
                    errors.append(f'{cid} {v}: 形式が不正 {val!r}')
            elif val not in options[v]:
                errors.append(f'{cid} {v}: 選択肢に無い値 {val!r}')
            if quote:
                if src not in cases[cid]:
                    errors.append(f'{cid} {v}: source の列が無い {src!r}')
                elif squash(quote) not in squash(cases[cid][src]):
                    errors.append(f'{cid} {v}: 引用が {src} に無い {quote!r}')
            parsed[cid][v] = (val, src, quote)
    if errors:
        print(f'[{path}]')
        print('\n'.join(errors))
        sys.exit(f'検査エラー {len(errors)} 件')
    return parsed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--cases', required=True)
    ap.add_argument('--ai', required=True, nargs='+')
    ap.add_argument('--out', required=True)
    ap.add_argument('--gold')
    a = ap.parse_args()

    options = {}
    with open('analysis/review_codebook.csv', encoding='utf-8-sig', newline='') as f:
        for r in csv.DictReader(f):
            options.setdefault(r['変数'], set()).add(r['日本語ラベル'])
    cases = load_jsonl(a.cases)
    runs = [check_run(p, load_jsonl(p), cases, options) for p in a.ai]
    n_runs = len(runs)

    rows, no_majority, split = [], [], 0
    for cid in sorted(cases):
        row, basis, splits, missing_majority = {'事例ID': cid}, [], [], []
        for v in VARS:
            vals = [r[cid][v][0] for r in runs]
            top, cnt = collections.Counter(vals).most_common(1)[0]
            if cnt * 2 <= n_runs:
                no_majority.append((cid, v, vals))
                missing_majority.append(v)
                top = ''
            if len(set(vals)) > 1:
                splits.append(f'{v}=' + '|'.join(vals))
            row[v] = top
            if v == '救命介入' and row['事故類型'] != CHOKING:
                row[v] = ''
            src, quote = '', ''
            if v not in missing_majority and row[v] == top:
                src, quote = next((r[cid][v][1], r[cid][v][2]) for r in runs if r[cid][v][0] == top)
            row[f'根拠_{v}'] = f'[{src}] {quote}' if quote else ''
            if quote:
                basis.append(f'{v}: [{src}] {quote}')
        row['AIの根拠'] = ' / '.join(basis)
        row['回ごとに割れた項目'] = ' / '.join(splits)
        row['過半数なし'] = ' / '.join(missing_majority)
        split += len(splits)
        rows.append(row)

    with open(a.out, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.DictWriter(f, fieldnames=['事例ID'] + VARS + [f'根拠_{v}' for v in VARS]
                           + ['AIの根拠', '回ごとに割れた項目', '過半数なし'])
        w.writeheader()
        w.writerows(rows)
    print(f'検査 OK: {n_runs} 本 × {len(rows)} 件、引用はすべて原文に実在 → {a.out}')
    if n_runs > 1:
        print(f'回ごとに値が割れた項目: {split} / {len(rows) * len(VARS)}、過半数なし: {len(no_majority)}')
        for cid, v, vals in no_majority:
            print(f'  過半数なし {cid} {v}: {vals}')

    if not a.gold:
        sys.exit(3 if no_majority else 0)
    with open(a.gold, encoding='utf-8-sig', newline='') as f:
        gold = {r['事例ID']: r for r in csv.DictReader(f)}
    if set(gold) != set(cases):
        sys.exit('正解値と入力の事例IDが一致しない')
    diffs = []
    per_var = {v: 0 for v in VARS}
    for r in rows:
        for v in VARS:
            if r[v] == gold[r['事例ID']][v]:
                per_var[v] += 1
            else:
                diffs.append((r['事例ID'], v, gold[r['事例ID']][v], r[v]))
    n = len(rows)
    print(f'正解値との一致: {n * len(VARS) - len(diffs)}/{n * len(VARS)} 項目、'
          f'全項目一致の事例 {n - len({d[0] for d in diffs})}/{n} 件')
    for v in VARS:
        print(f'  {v}: {per_var[v]}/{n}')
    for cid, v, g, x in diffs:
        print(f'  食い違い {cid} {v}: 正解 {g!r} / AI {x!r}')
    sys.exit(3 if diffs or no_majority else 0)


if __name__ == '__main__':
    main()
