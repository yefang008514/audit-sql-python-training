# 02 SQL 基础：PostgreSQL + DuckDB

## 一、为什么审计人员要学 SQL

- Excel 单表 10 万行开始卡，序时账动辄几百万行 —— SQL 是为这个量级设计的。
- 核对、汇总、抽样的本质是 `JOIN`、`GROUP BY`、`WHERE`，SQL 一句话顶 Excel 半天透视表。
- 查出来的逻辑写在 SQL 里，**可复现、可复核、可留痕** —— 这本身就是审计语言。

SQL 语句五大家族（先知道名字，用到再查）：

| 类别 | 关键字 | 审计中干嘛用 |
|---|---|---|
| DQL 查询 | SELECT | 99% 的时间在用它 |
| DDL 定义 | CREATE / ALTER | 建表存序时账、流水 |
| DML 操作 | INSERT / UPDATE / DELETE | 清洗后回写 |
| DCL 权限 | GRANT | 了解即可 |
| TCL 事务 | COMMIT / ROLLBACK | 批量导入出错回滚 |

## 二、两个数据库：怎么选

| | PostgreSQL（PG） | DuckDB |
|---|---|---|
| 定位 | 生产级数据库服务 | 嵌入式分析引擎（"分析版 SQLite"） |
| 安装 | 装服务端 + 客户端（DBeaver） | `pip install duckdb`，一个文件 |
| 数据量 | 千万行级以上、多人共用 | 单机千万行内分析飞快 |
| 杀手锏 | 稳定、权限、并发 | **直接查询 CSV/Excel/Parquet，不落库** |
| 审计场景 | 所内数据平台、长期项目库 | 现场单机快速取数核对 |

DuckDB 直接查文件的例子（不用建表！）：

```sql
-- 直接查 CSV
SELECT * FROM read_csv_auto('序时账.csv') LIMIT 10;

-- 直接查 Excel（需先 INSTALL excel; LOAD excel;）
SELECT * FROM read_xlsx('余额表.xlsx', sheet='Sheet1');

-- 直接对 CSV 做汇总，结果导出 Excel
COPY (
  SELECT 科目编码, SUM(借方金额) AS 借方合计, SUM(贷方金额) AS 贷方合计
  FROM read_csv_auto('序时账.csv')
  GROUP BY 科目编码
) TO '科目汇总.xlsx' WITH (FORMAT xlsx);
```

> 建议：**单机分析学 DuckDB，团队/所内建库学 PG**。两者 SQL 语法 95% 通用，下文函数对照表会标注差异。

## 三、核心语法 30 分钟速览

```sql
-- 1. 过滤：找大额分录
SELECT 凭证号, 日期, 科目编码, 借方金额
FROM journal
WHERE 借方金额 >= 100000;

-- 2. 聚合：按科目汇总（= Excel 数据透视表）
SELECT 科目编码, SUM(借方金额 - 贷方金额) AS 净发生额
FROM journal
GROUP BY 科目编码
HAVING ABS(SUM(借方金额 - 贷方金额)) > 10000;   -- HAVING 是对"汇总结果"再过滤

-- 3. 连接：序时账对科目表（= Excel XLOOKUP）
SELECT j.凭证号, j.科目编码, a.科目名称, j.借方金额
FROM journal j
LEFT JOIN accounts a ON j.科目编码 = a.科目编码;

-- 4. CTE：把复杂逻辑分层写（可读性远好于嵌套子查询）
WITH 月度汇总 AS (
  SELECT 月份, SUM(金额) AS 月总额
  FROM journal GROUP BY 月份
)
SELECT * FROM 月度汇总 WHERE 月总额 > (SELECT AVG(月总额) FROM 月度汇总);

-- 5. 窗口函数：每组内部排序取 Top N（Excel 极难做的事）
SELECT * FROM (
  SELECT 科目编码, 凭证号, 借方金额,
         ROW_NUMBER() OVER (PARTITION BY 科目编码 ORDER BY 借方金额 DESC) AS rn
  FROM journal
) t
WHERE rn <= 3;   -- 每个科目金额最大的 3 笔分录
```

## 四、常用函数与 Excel 对照表

### 4.1 汇总与查找

| Excel | SQL | 说明 |
|---|---|---|
| 数据透视表 | `GROUP BY` + 聚合 | `SELECT 科目, SUM(金额) ... GROUP BY 科目` |
| SUMIFS | `SUM(...) FILTER (WHERE ...)` 或 `SUM(CASE WHEN ... THEN x ELSE 0 END)` | PG/DuckDB 都支持 FILTER |
| COUNTIFS | `COUNT(*) FILTER (WHERE ...)` | 同上 |
| AVERAGEIFS | `AVG(...) FILTER (WHERE ...)` | |
| VLOOKUP / XLOOKUP | `LEFT JOIN` | 匹配不到时 JOIN 结果保留左表并填 NULL，语义同 XLOOKUP 的 if_not_found |
| 多条件匹配 | `JOIN ... ON a.k1=b.k1 AND a.k2=b.k2` | Excel 里要数组公式的事，SQL 一句话 |
| 去重（数据→删除重复项） | `SELECT DISTINCT 列` | |
| IF / IFS | `CASE WHEN ... THEN ... ELSE ... END` | |
| IFERROR(x, 0) | `COALESCE(x, 0)` | 处理 NULL |

### 4.2 文本处理

| Excel | SQL（PG / DuckDB 通用） | 说明 |
|---|---|---|
| LEFT(x, n) | `left(x, n)` 或 `substr(x, 1, n)` | 取科目编码前 4 位=一级科目 |
| MID(x, s, n) | `substr(x, s, n)` | |
| RIGHT(x, n) | `right(x, n)` | |
| LEN | `length(x)` | |
| TRIM | `trim(x)` | 客户/供应商名称清洗必备 |
| UPPER / LOWER | `upper(x)` / `lower(x)` | |
| CONCAT / & | `concat(a, b)` 或 `a \|\| b` | |
| SUBSTITUTE(x, 旧, 新) | `replace(x, 旧, 新)` | |
| FIND | `position(子串 IN 字符串)` | |
| TEXTSPLIT（按分隔符拆分） | `split_part(x, 分隔符, n)` / `string_split`（DuckDB） | 拆分"摘要-经手人"这类复合字段 |
| 通配符筛选 | `LIKE '1002%'`（前匹配）/ `%关键字%` | `%` 任意多字符，`_` 单字符 |
| 正则 | `regexp_replace(x, 模式, 替换)`、`regexp_matches` | 提取发票号、银行账号，见第 05 章 |

### 4.3 日期处理

| Excel | PostgreSQL | DuckDB | 说明 |
|---|---|---|---|
| YEAR(d) / MONTH(d) | `extract(year from d)` 或 `date_part('year', d)` | 同 PG，也支持 `year(d)` | 按月汇总发生额 |
| TEXT(d,"yyyy-mm") | `to_char(d, 'YYYY-MM')` | `strftime(d, '%Y-%m')` | 生成"月份"分组键 |
| DATEDIF / 天数差 | `d2 - d1`（整数天数） | `date_diff('day', d1, d2)` | 账龄计算 |
| TODAY() | `current_date` | 同 | |
| 月末日期 | `date_trunc('month', d) + interval '1 month - 1 day'` | `last_day(d)` | 月末集中测试用 |
| WEEKDAY | `extract(isodow from d)`（1=周一…7=周日） | 同 | 周末记账测试用 |

### 4.4 窗口函数（Excel 没有对应物，重点学）

| 需求 | SQL |
|---|---|
| 组内排名取 Top N | `ROW_NUMBER() OVER (PARTITION BY 组 ORDER BY 金额 DESC)` |
| 与上期比较 | `LAG(金额) OVER (ORDER BY 月份)` |
| 累计发生额 | `SUM(金额) OVER (ORDER BY 日期)` |
| 组内占比 | `金额 / SUM(金额) OVER (PARTITION BY 组)` |

## 五、练习

1. 用 DuckDB 打开任意一张 CSV 序时账，写出"各月借方发生额 Top 3 科目"。
2. 把你在 Excel 里用 SUMIFS 做过的一张表，用 `GROUP BY + FILTER` 重写。
3. 牛客网 SQL 题库刷 10 题，重点做多表连接题。

下一章：[03 Python 数据清洗与自动化底稿](03-Python数据清洗与自动化底稿.md)
