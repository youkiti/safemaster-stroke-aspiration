"""試行10件の正解値（判定基準 v2）を作る。合議ファイルの AA479 当事者番号を「なし」にし、
2名一致の値＋合議の値に、v2 で直す3件の食事区分を当てる。
正解値を書いた後、ログ・更新後の合議・試行ID・正解値の md5 を来歴 stamp に記録する。"""
import csv, hashlib, io

CONS = 'output/prod_consensus_stage2.csv'
raw = open(CONS, 'rb').read()
bom = raw.startswith(b'\xef\xbb\xbf')
nl = '\r\n' if b'\r\n' in raw else '\n'
rows = list(csv.DictReader(io.StringIO(raw.decode('utf-8-sig'))))
fields = list(rows[0].keys())
hit = 0
for x in rows:
    if x['事例ID'] == 'AA479EF31C5606095' and x['変数'] == '直接介助者の当事者番号':
        x['合議結果'] = 'なし'; hit += 1
assert hit == 1
out = io.StringIO()
w = csv.DictWriter(out, fieldnames=fields, lineterminator=nl); w.writeheader(); w.writerows(rows)
open(CONS, 'wb').write((b'\xef\xbb\xbf' if bom else b'') + out.getvalue().encode('utf-8'))

VARS = ['脳卒中の位置づけ', '脳卒中病型', '事故類型', '摂取物', '摂食介助状況', '同席状況',
        '嚥下評価', '指示逸脱', '食事区分', '救命介入', '直接介助者の当事者番号']

def last(path):
    d = {}
    for x in csv.DictReader(open(path, encoding='utf-8-sig')):
        d[x['事例ID']] = x
    return d

def norm(v):
    return v.replace('，', ',').replace(' ', '').rstrip('.')

r1 = last('output/prod_app_judgment_log_stage2_reviewer1.csv')
r2 = last('output/prod_app_judgment_log_stage2_reviewer2.csv')
cons = {(x['事例ID'], x['変数']): x['合議結果'] for x in rows}
ids = [l.strip() for l in open('output/prod_stage2_pilot10_ids.csv', encoding='utf-8-sig')][1:]
assert sorted(ids) == sorted(r1) == sorted(r2), 'ids mismatch'
V2 = {('A908E63035B3EBB4C', '食事区分'): ('その他・不明', '夕食'),
      ('A2B07594030CF8006', '食事区分'): ('その他・不明', '夕食'),
      ('AF9865CC7B8086355', '食事区分'): ('その他・不明', '昼食'),
      ('A908E63035B3EBB4C', '嚥下評価'): ('評価済みが明記', '判定不能')}
gold = []
for cid in sorted(ids):
    g = {'事例ID': cid}
    for v in VARS:
        a, b = norm(r1[cid]['修正_' + v]), norm(r2[cid]['修正_' + v])
        if v == '救命介入' and g['事故類型'] != '窒息・気道閉塞':
            val = ''
        elif (cid, v) in cons:
            val = cons[(cid, v)]
            if v == '直接介助者の当事者番号' and val == 'なし':
                val = ''
        elif a == b:
            val = a
        else:
            raise SystemExit(f'未合議の不一致: {cid} {v} {a}|{b}')
        if (cid, v) in V2:
            old, new = V2[(cid, v)]
            assert val == old, (cid, v, val)
            val = new
        g[v] = val
    gold.append(g)
with open('output/prod_stage2_pilot10_gold_v2.csv', 'w', encoding='utf-8-sig', newline='') as f:
    w = csv.DictWriter(f, fieldnames=['事例ID'] + VARS); w.writeheader(); w.writerows(gold)
stamp_files = {
    'log_reviewer1': 'output/prod_app_judgment_log_stage2_reviewer1.csv',
    'log_reviewer2': 'output/prod_app_judgment_log_stage2_reviewer2.csv',
    'consensus': CONS,
    'pilot10_ids': 'output/prod_stage2_pilot10_ids.csv',
    'gold': 'output/prod_stage2_pilot10_gold_v2.csv',
}
with open('output/prod_stage2_pilot10_gold_v2_stamp.csv', 'w', encoding='utf-8', newline='') as f:
    w = csv.writer(f, lineterminator='\n'); w.writerow(['key', 'value'])
    for key, path in stamp_files.items():
        with open(path, 'rb') as source:
            w.writerow([key, hashlib.md5(source.read()).hexdigest()])
print('gold rows', len(gold))
for g in gold:
    print(g)
