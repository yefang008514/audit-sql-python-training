# 审计人员 SQL & Python 技能训练营

> 面向审计人员的数字化技能自学仓库：SQL（PostgreSQL + DuckDB）+ Python（pandas 数据清洗 + 自动化底稿）+ 审计实战案例 + AI 提示词。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## 这个仓库是什么

审计行业正在从「Excel 抽样」走向「全量数据分析」。本仓库把审计人员需要掌握的 SQL 和 Python 技能整理成一条可自学的路径，所有案例都来自真实审计场景：三单匹配、银行流水核对、JET 测试、大规模抽样、自动化底稿。

**目标读者**：有 Excel 基础、想提升数据处理能力的审计人员（财务审计 / IT 审计 / 内控审计）。

## 学习路径

```
第 1 周  → 01 学习资源 + 02 SQL 基础（SELECT / WHERE / GROUP BY）
第 2 周  → 02 SQL 进阶（JOIN / 子查询 / CTE / 窗口函数）+ OJ 刷题
第 3 周  → 03 Python 数据清洗与入库（pandas + DuckDB）
第 4 周  → 04 审计实战（跟着案例复现一遍）
持续     → 05 AI 提示词（让 AI 帮你写代码，但你要能验证）
```

## 目录

| 章节 | 内容 |
|---|---|
| [01 学习资源](docs/01-学习资源.md) | 常用 OJ 刷题网站、知识网站、公众号博主、B 站 UP 主、书单 |
| [02 SQL 基础](docs/02-SQL基础.md) | SQL 介绍、PostgreSQL + DuckDB 环境、常用函数与 Excel 对照表 |
| [03 Python 数据清洗与入库](docs/03-Python数据清洗与自动化底稿.md) | pandas 清洗序时账/余额表、入库 DuckDB/PG、openpyxl 自动化底稿 |
| [04 审计实战](docs/04-审计实战.md) | 业财核对（三单匹配、序时账与银行流水双向核对）、JET 测试、SQL 大规模抽样、自动化底稿 |
| [05 AI 提示词示例](docs/05-AI提示词示例.md) | 正则表达式生成、数据清洗、异常特征描述等提示词模板 |

代码示例在 [`code/`](code/) 目录：`code/sql/` 为可直接在 DuckDB/PG 运行的 SQL，`code/python/` 为可运行的 Python 脚本（含模拟数据生成）。

## 环境准备（最小化）

| 工具 | 用途 | 安装 |
|---|---|---|
| DuckDB | 嵌入式分析数据库，直接查 CSV/Excel/Parquet | `pip install duckdb` 或官网下载 CLI |
| PostgreSQL | 生产级数据库，承接大数据量底稿数据 | 官网安装包 + DBeaver 客户端 |
| Python 3.10+ | 数据清洗与自动化 | `pip install pandas openpyxl duckdb sqlalchemy psycopg2-binary` |
| DBeaver | 通用数据库客户端（免费社区版） | dbeaver.io |

> 零安装起步方案：先不装任何东西，直接用 DuckDB 在线 Shell（shell.duckdb.org）+ SQLBolt 在线练习。

## 参考与致谢

- [逆行的狗（nigo）](https://www.auditdog.cn/) —— 公众号「逆行的狗」，《IT审计：用SQL+Python提升工作效率》《审计效率手册》作者，本仓库多个实战案例的思路来源。
- 各章节末尾附有对应资源链接。

## License

MIT。案例数据均为虚构模拟数据，可直接用于教学。
