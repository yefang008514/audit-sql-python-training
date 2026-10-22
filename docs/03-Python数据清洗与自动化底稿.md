# 03 Python 数据清洗与入库 + 自动化底稿

> 本章代码见 `code/python/01_clean_and_load.py`、`code/python/02_auto_workpaper.py`，均含模拟数据生成，clone 后可直接运行。

## 一、最小环境

```bash
pip install pandas openpyxl duckdb sqlalchemy psycopg2-binary
```

- `pandas`：清洗主力
- `openpyxl`：读写 Excel（底稿模板填充）
- `duckdb`：本地分析库，pandas 的好搭档
- `sqlalchemy + psycopg2-binary`：连 PostgreSQL

## 二、审计数据清洗的典型问题与对策

拿到手的序时账/余额表/流水，常见问题基本就这几类：

| 脏数据 | 例子 | pandas 对策 |
|---|---|---|
| 金额带千分位/货币符号 | `"1,234,567.89"`、`"￥5,000"` | `str.replace` 去符号 → `pd.to_numeric` |
| 借贷方向单列 | `"借"/"贷"` + 正数金额 | `np.where(方向=='贷', -金额, 金额)` 统一成带符号金额 |
| 日期格式混乱 | `2024/1/5`、`2024-01-05`、`45000`（Excel 序列数） | `pd.to_datetime(..., errors='coerce', format='mixed')` |
| 多余表头/合计行 | 每隔 50 行重复表头、末尾"合计" | 按条件过滤掉 |
| 空行/空格 | 客户名前后空格、`"   "` | `str.strip()`，空串转 `NA` |
| 编码对不上 | 科目编码一处是文本一处是数值 | 统一 `.astype(str).str.strip()` 再 JOIN |
| 重复行 | 重复导入 | `drop_duplicates(subset=[唯一键])` |
| 非法字符 | 换行符、Tab 混在摘要里 | `str.replace(r'[\r\n\t]', ' ', regex=True)` |

### 清洗序时账骨架代码

```python
import pandas as pd
import numpy as np

df = pd.read_excel('序时账.xlsx', dtype=str)   # 先全按文本读，避免类型猜错

# 1. 去多余表头/合计行
df = df[df['凭证号'].notna() & (df['凭证号'] != '凭证号') & (df['科目编码'] != '合计')]

# 2. 金额清洗：去千分位、转数值
for col in ['借方金额', '贷方金额']:
    df[col] = pd.to_numeric(df[col].str.replace(',', '').str.replace('￥', ''), errors='coerce').fillna(0)

# 3. 日期统一
df['日期'] = pd.to_datetime(df['日期'], errors='coerce', format='mixed')

# 4. 文本字段去空格
for col in ['科目编码', '摘要', '客户名称']:
    df[col] = df[col].astype(str).str.strip()

# 5. 生成带符号金额与月份键（后续核对、汇总都用它）
df['金额'] = df['借方金额'] - df['贷方金额']
df['月份'] = df['日期'].dt.strftime('%Y-%m')

# 6. 质量检查：借贷不平的分录单列出来（这在审计里是必查项！）
check = df.groupby('凭证号')['金额'].sum()
bad = check[check.abs() > 0.005]
print(f'借贷不平凭证 {len(bad)} 张：', bad.index.tolist()[:10])
```

> 审计提示：**清洗日志本身就是底稿的一部分**——删了多少行、为什么删、借贷不平有多少，都要留痕。

## 三、入库：DuckDB 与 PostgreSQL

### 3.1 入 DuckDB（单机首选）

```python
import duckdb

con = duckdb.connect('audit.duckdb')          # 一个文件就是一个库
con.register('df_journal', df)                # DataFrame 直接注册成视图
con.execute('CREATE OR REPLACE TABLE journal AS SELECT * FROM df_journal')

# 之后全程可以用 SQL 操作
print(con.sql('SELECT 科目编码, SUM(金额) FROM journal GROUP BY 1 ORDER BY 2 DESC LIMIT 5').df())
```

### 3.2 入 PostgreSQL（团队共用）

```python
from sqlalchemy import create_engine

engine = create_engine('postgresql+psycopg2://user:password@localhost:5432/audit')
df.to_sql('journal', engine, if_exists='replace', index=False, chunksize=10000)
```

### 3.3 多文件批量入库

```python
from pathlib import Path

for f in Path('银行流水/').glob('*.xlsx'):
    bank = pd.read_excel(f, dtype=str)
    bank['来源文件'] = f.name          # 来源留痕，方便追溯
    # ...同样的清洗步骤...
    bank.to_sql('bank_flow', engine, if_exists='append', index=False)
```

## 四、自动化底稿：openpyxl 模板填充

思路：**模板与数据分离**。先让 Excel 高手做一张带格式的底稿模板（表头、公式、格式都画好），Python 只负责往指定单元格填数——格式零损失，复核人员看到的是熟悉的底稿。

```python
from openpyxl import load_workbook

wb = load_workbook('底稿模板.xlsx')          # 保留原格式
ws = wb['货币资金明细表']

# 填数：从 DuckDB 取汇总结果写入指定区域
result = con.sql("""
    SELECT 科目编码, 科目名称, SUM(金额) AS 期末数
    FROM journal GROUP BY 1, 2 ORDER BY 1
""").df()

for i, row in result.iterrows():
    ws.cell(row=i + 5, column=1, value=row['科目编码'])   # 第 5 行起为数据区
    ws.cell(row=i + 5, column=2, value=row['科目名称'])
    ws.cell(row=i + 5, column=3, value=row['期末数'])

wb.save('货币资金底稿_已填数.xlsx')
```

可自动化的常见底稿：

| 底稿 | 数据来源 | 核心逻辑 |
|---|---|---|
| 货币资金明细表 | 序时账 | 按科目汇总期初/发生/期末 |
| 账龄分析表 | 往来明细 | `当前日期 - 挂账日期` 分桶（1年内/1-2年/2-3年/3年以上） |
| 函证清单 | 往来+流水 | 按余额/发生额筛选 + 抽样 |
| 收入截止性测试表 | 序时账 | 期末前后 N 天的收入分录 |
| 三单匹配差异表 | 订单/收货/发票 | 见第 04 章 |

## 五、完整 pipeline（一章串起来）

```
原始 Excel/CSV → pandas 清洗 → 入 DuckDB → SQL 核对/汇总 → openpyxl 填模板 → 输出底稿
```

每一步都是独立脚本，出错只重跑该步；所有中间结果落库留痕。

## 练习

1. 找一张真实序时账（脱敏后），用上面的骨架代码跑通"清洗 → 借贷平衡检查"。
2. 把它入 DuckDB，用 SQL 输出月度发生额，再让 openpyxl 填进任意一张模板。
3. 进阶：把清洗步骤封装成 `def clean_journal(path) -> pd.DataFrame`，处理一整个文件夹。

上一章：[02 SQL 基础](02-SQL基础.md) ｜ 下一章：[04 审计实战](04-审计实战.md)
