-- 序时账与银行流水双向核对
-- 正向：流水有、账上无；反向：账上有、流水无
-- DuckDB 可直接运行

-- ============ 模拟数据 ============
CREATE OR REPLACE TABLE journal AS     -- 序时账（银行存款科目 1002）
SELECT * FROM (VALUES
  ('记-001', DATE '2024-03-01', '100201', '收货款',   100000.0, 0.0),
  ('记-002', DATE '2024-03-05', '100201', '付货款',   0.0, 50000.0),
  ('记-003', DATE '2024-03-10', '100201', '收货款',   80000.0, 0.0),
  ('记-004', DATE '2024-03-20', '100201', '收货款',   66000.0, 0.0)   -- 流水无此笔：虚假记账？
) AS t(凭证号, 日期, 科目编码, 摘要, 借方金额, 贷方金额);

CREATE OR REPLACE TABLE bank_flow AS   -- 银行流水
SELECT * FROM (VALUES
  ('L0001', DATE '2024-03-01', 100000.0, 0.0),
  ('L0002', DATE '2024-03-06', 0.0, 50000.0),      -- 比记账晚 1 天：在途
  ('L0003', DATE '2024-03-10', 80000.0, 0.0),
  ('L0004', DATE '2024-03-25', 30000.0, 0.0)       -- 账上无此笔：账外资金？
) AS t(流水号, 交易日期, 收入金额, 支出金额);

-- ============ 正向核对：流水有、账上无 ============
SELECT '流水有账上无' AS 核对方向, b.*
FROM bank_flow b
LEFT JOIN journal j
  ON j.科目编码 LIKE '1002%'
 AND ROUND(ABS(j.借方金额 - b.收入金额), 2) < 0.01
 AND ABS(b.交易日期 - j.日期) <= 3            -- 允许 3 天在途
WHERE j.凭证号 IS NULL AND b.收入金额 > 0

UNION ALL

SELECT '流水有账上无' AS 核对方向, b.*
FROM bank_flow b
LEFT JOIN journal j
  ON j.科目编码 LIKE '1002%'
 AND ROUND(ABS(j.贷方金额 - b.支出金额), 2) < 0.01
 AND ABS(b.交易日期 - j.日期) <= 3
WHERE j.凭证号 IS NULL AND b.支出金额 > 0;

-- ============ 反向核对：账上有、流水无 ============
SELECT '账上有流水无' AS 核对方向, j.*
FROM journal j
LEFT JOIN bank_flow b
  ON ROUND(ABS(j.借方金额 - b.收入金额), 2) < 0.01
 AND ABS(b.交易日期 - j.日期) <= 3
WHERE j.科目编码 LIKE '1002%' AND j.借方金额 > 0 AND b.流水号 IS NULL

UNION ALL

SELECT '账上有流水无' AS 核对方向, j.*
FROM journal j
LEFT JOIN bank_flow b
  ON ROUND(ABS(j.贷方金额 - b.支出金额), 2) < 0.01
 AND ABS(b.交易日期 - j.日期) <= 3
WHERE j.科目编码 LIKE '1002%' AND j.贷方金额 > 0 AND b.流水号 IS NULL;

-- 练习：把在途天数从 3 改为 1，看差异表多出哪些笔。
-- 实务提示：剩余差异再做 一对多/多对一 组合匹配；超 30 天未达账项单独列示。
