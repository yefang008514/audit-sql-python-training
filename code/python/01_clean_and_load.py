"""01_clean_and_load.py — 序时账清洗 + 借贷平衡检查 + 入 DuckDB

运行方式（无需外部数据，脚本会先生成带脏数据的模拟序时账）：
    pip install pandas duckdb openpyxl
    python 01_clean_and_load.py
"""
import numpy as np
import pandas as pd
import duckdb

# ============ 0. 生成带"典型脏数据"的模拟序时账 ============
# 每张凭证一借一贷两行（金额相等，保证借贷平衡），模拟真实序时账结构
rng = np.random.default_rng(42)
n = 500  # 500 张凭证 = 1000 行分录
amts = rng.uniform(100, 500000, n)
# 日期覆盖 2024 全年（含周末/月末），故意混入三种格式：斜杠、横杠、Excel 序列数
base_dates = pd.Timestamp('2024-01-01') + pd.to_timedelta(rng.integers(0, 365, n), unit='D')
fmt = rng.integers(0, 3, n)
date_strs = [
    f'{d.year}/{d.month}/{d.day}' if f == 0 else
    d.strftime('%Y-%m-%d') if f == 1 else
    str((d - pd.Timestamp('1899-12-30')).days)
    for d, f in zip(base_dates, fmt)
]
debit = pd.DataFrame({
    '凭证号': [f'记-{i:04d}' for i in range(n)],
    '日期': date_strs,                                                      # 混合格式（含 Excel 序列数）
    '科目编码': rng.choice(['1122', '6001', '6602'], n).astype(str),
    '摘要': rng.choice(['收货款', '报销差旅费', '销售产品\n含换行'], n),
    '借方金额': [f'{x:,.2f}' for x in amts],                              # 带千分位
    '贷方金额': ['0.00'] * n,
    '客户名称': rng.choice([' 甲公司', '乙公司 ', '丙公司'], n),
})
credit = pd.DataFrame({
    '凭证号': [f'记-{i:04d}' for i in range(n)],
    '日期': debit['日期'],
    '科目编码': rng.choice(['100201', '2202'], n).astype(str),
    '摘要': debit['摘要'],
    '借方金额': ['0.00'] * n,
    '贷方金额': [f'{x:,.2f}' for x in amts],
    '客户名称': debit['客户名称'],
})
df_raw = pd.concat([debit, credit]).sort_values('凭证号').reset_index(drop=True)
# 模拟导出问题：第 500 行重复出现表头，末尾加合计行
df_raw.loc[500] = ['凭证号', '日期', '科目编码', '摘要', '借方金额', '贷方金额', '客户名称']
df_raw.loc[1001] = [None, None, '合计', None, None, None, None]
df_raw.to_excel('mock_journal_dirty.xlsx', index=False)
print('已生成模拟脏数据 mock_journal_dirty.xlsx')

# ============ 1. 清洗 ============
df = pd.read_excel('mock_journal_dirty.xlsx', dtype=str)   # 全按文本读，避免类型猜错
n0 = len(df)

# 1.1 去重复表头行 / 合计行 / 空行
df = df[df['凭证号'].notna() & (df['凭证号'] != '凭证号')]
df = df[(df['科目编码'] != '合计')]
print(f'去表头/合计行: {n0} -> {len(df)}')

# 1.2 金额：去千分位 → 数值
for col in ['借方金额', '贷方金额']:
    df[col] = pd.to_numeric(
        df[col].str.replace(',', '', regex=False).str.replace('￥', '', regex=False),
        errors='coerce'
    ).fillna(0)

# 1.3 日期：混合格式统一；对无法解析的再尝试按 Excel 序列数补救（注意先留原始值）
date_raw = df['日期'].copy()
df['日期'] = pd.to_datetime(date_raw, errors='coerce', format='mixed')
serial = pd.to_numeric(date_raw[df['日期'].isna()], errors='coerce')
df['日期'] = df['日期'].fillna(pd.to_datetime(serial, unit='D', origin='1899-12-30', errors='coerce'))
bad_dates = df[df['日期'].isna()]
if len(bad_dates):
    bad_dates.to_csv('errors.csv', index=False)
    print(f'警告：{len(bad_dates)} 行日期无法解析，已存 errors.csv（不静默丢弃）')
    df = df[df['日期'].notna()]

# 1.4 文本：去首尾空格、去摘要内换行
for col in ['科目编码', '客户名称']:
    df[col] = df[col].astype(str).str.strip()
df['摘要'] = df['摘要'].astype(str).str.replace(r'[\r\n\t]', ' ', regex=True)

# 1.5 派生字段：带符号金额 + 月份键
df['金额'] = df['借方金额'] - df['贷方金额']
df['月份'] = df['日期'].dt.strftime('%Y-%m')

# ============ 2. 质量检查：借贷平衡 ============
check = df.groupby('凭证号')['金额'].sum()
bad = check[check.abs() > 0.005]
print(f'借贷不平凭证: {len(bad)} 张', bad.index.tolist()[:5])

# ============ 3. 入 DuckDB ============
con = duckdb.connect('audit.duckdb')
con.register('df_journal', df)
con.execute('CREATE OR REPLACE TABLE journal AS SELECT * FROM df_journal')
print('\n入库完成，按科目汇总预览：')
print(con.sql('''
    SELECT 科目编码, COUNT(*) AS 笔数, ROUND(SUM(借方金额), 2) AS 借方合计
    FROM journal GROUP BY 1 ORDER BY 3 DESC
''').df())
