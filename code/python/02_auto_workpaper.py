"""02_auto_workpaper.py — 自动化底稿 pipeline：取数 → 核对 → 填模板出底稿

依赖第 01 步生成的 audit.duckdb（直接运行本脚本会自动补建）。
输出：货币资金底稿.xlsx（科目汇总 / 月度发生额 / JET 疑点 三张表）

    pip install pandas duckdb openpyxl
    python 02_auto_workpaper.py
"""
from pathlib import Path

import duckdb
import pandas as pd
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill
from openpyxl.utils import get_column_letter

DB = Path('audit.duckdb')
if not DB.exists():
    raise SystemExit('请先运行 01_clean_and_load.py 生成 audit.duckdb')

con = duckdb.connect(str(DB), read_only=True)

# ============ 1. 取数：三张分析表 ============
科目汇总 = con.sql('''
    SELECT 科目编码, COUNT(*) AS 笔数,
           ROUND(SUM(借方金额), 2) AS 借方合计,
           ROUND(SUM(贷方金额), 2) AS 贷方合计
    FROM journal GROUP BY 1 ORDER BY 1
''').df()

月度发生额 = con.sql('''
    SELECT 月份, 科目编码, ROUND(SUM(金额), 2) AS 净发生额
    FROM journal GROUP BY 1, 2 ORDER BY 1, 2
''').df()

jet疑点 = con.sql('''
    SELECT * FROM (
      SELECT 凭证号, 日期, 摘要, 金额,
        CASE WHEN extract(isodow FROM 日期) IN (6, 7) THEN 1 ELSE 0 END AS 周末记账,
        CASE WHEN 日期 >= last_day(日期) - 2 THEN 1 ELSE 0 END           AS 月末集中,
        CASE WHEN 金额 % 10000 = 0 AND abs(金额) >= 100000 THEN 1 ELSE 0 END AS 整数大额
      FROM journal
    ) t
    WHERE (周末记账 + 月末集中 + 整数大额) >= 2
    ORDER BY abs(金额) DESC
''').df()

# ============ 2. 生成底稿 ============
wb = Workbook()
header_font = Font(bold=True, color='FFFFFF')
header_fill = PatternFill('solid', fgColor='305496')

def write_sheet(name: str, df: pd.DataFrame, title: str):
    ws = wb.create_sheet(name)
    ws['A1'] = title
    ws['A1'].font = Font(bold=True, size=14)
    ws['A2'] = '数据来源：audit.duckdb / journal 表（自动生成，逻辑可复核）'
    for j, col in enumerate(df.columns, start=1):
        c = ws.cell(row=4, column=j, value=str(col))
        c.font, c.fill = header_font, header_fill
    for i, row in enumerate(df.itertuples(index=False), start=5):
        for j, v in enumerate(row, start=1):
            ws.cell(row=i, column=j, value=v)
    for j, col in enumerate(df.columns, start=1):
        width = max(len(str(col)) * 2, 12)
        ws.column_dimensions[get_column_letter(j)].width = width

wb.remove(wb.active)   # 去掉默认 Sheet
write_sheet('科目汇总', 科目汇总, '货币资金相关科目发生额汇总表')
write_sheet('月度发生额', 月度发生额, '分月净发生额明细')
write_sheet('JET疑点分录', jet疑点, '分录测试疑点清单（命中≥2项）')

out = Path('货币资金底稿.xlsx')
wb.save(out)
print(f'底稿已生成: {out.resolve()}')
print(f'  科目汇总 {len(科目汇总)} 行 / 月度发生额 {len(月度发生额)} 行 / JET疑点 {len(jet疑点)} 行')

# 实务扩展方向：
# 1. 用 load_workbook('模板.xlsx') 替代新建，往所内既有底稿模板里填数（格式零损失）
# 2. 把核对差异表、MUS 抽凭清单一并作为 Sheet 输出（SQL 见 code/sql/）
# 3. 每家客户一个文件夹，脚本参数化 客户名+期间，批量出底稿
