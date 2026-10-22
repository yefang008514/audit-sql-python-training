-- SQL 大规模数据抽样：简单随机 / 货币单位抽样 MUS / 分层抽样
-- DuckDB 可直接运行

-- ============ 模拟数据：100 笔分录，金额服从不均匀分布 ============
CREATE OR REPLACE TABLE journal AS
SELECT
  '记-' || lpad(range::VARCHAR, 4, '0')  AS 凭证号,
  DATE '2024-01-01' + CAST(range % 365 AS INTEGER) AS 日期,
  '摘要' || range                        AS 摘要,
  round(exp(4 + random() * 10), 2)       AS 金额        -- 60 ~ 120万 的对数均匀分布
FROM range(100);

-- ============ 1. 简单随机抽样 ============
SELECT * FROM journal USING SAMPLE 10 ROWS;      -- 固定抽 10 行
-- 通用写法（各数据库通用）：SELECT * FROM journal ORDER BY random() LIMIT 10;

-- ============ 2. 货币单位抽样 MUS（金额大者更易被抽中） ============
-- 原理：把每笔分录金额看成数轴上的线段，等间隔下"刻度"，刻度落在哪笔就抽哪笔
WITH cum AS (
  SELECT *,
         SUM(abs(金额)) OVER (ORDER BY 凭证号) AS 累计金额,
         SUM(abs(金额)) OVER ()                AS 总体金额
  FROM journal
),
params AS (
  SELECT 总体金额 / 20 AS 抽样间隔 FROM cum LIMIT 1   -- 目标 20 个样本
)
SELECT c.凭证号, c.日期, c.摘要, c.金额, round(c.累计金额, 2) AS 累计金额
FROM cum c, params p
WHERE floor(c.累计金额 / p.抽样间隔)
   <> floor((c.累计金额 - abs(c.金额)) / p.抽样间隔)
ORDER BY c.凭证号;

-- ============ 3. 分层抽样：大额全查 + 小额随机抽 ============
SELECT *, '重点全查' AS 抽样层
FROM journal WHERE abs(金额) >= 500000

UNION ALL

SELECT *, '随机抽样' AS 抽样层
FROM (SELECT * FROM journal WHERE abs(金额) < 500000 ORDER BY random() LIMIT 15) t;

-- 练习：
-- 1. MUS 抽出的样本金额均值 vs 总体金额均值，差多少？为什么？（这正是 MUS 的设计意图）
-- 2. 用 abs(金额) < 500000 层的"分层随机"改为"按月份分层、每层抽 2 笔"。
