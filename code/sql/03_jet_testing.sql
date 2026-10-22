-- JET 测试（Journal Entry Testing）：分录特征画像
-- DuckDB 可直接运行；PG 中 QUALIFY 需改写为子查询 + WHERE

-- ============ 模拟数据 ============
CREATE OR REPLACE TABLE journal AS
SELECT * FROM (VALUES
  ('记-101', DATE '2024-03-02', '张三', '支付货款',            50000.0),   -- 周六
  ('记-102', DATE '2024-03-31', '李四', '调整以前年度损益',    300000.0),  -- 月末+调整+整数大额
  ('记-103', DATE '2024-03-15', '王五', '销售产品',            87654.3),
  ('记-104', DATE '2024-03-30', '张三', '冲销上月暂估',       -120000.0),  -- 冲销+月末+整数
  ('记-105', DATE '2024-03-12', '赵六', '支付咨询费',          99999.0),   -- 略低于10万审批权限
  ('记-106', DATE '2024-03-13', '王五', '支付水电费',           3200.0)
) AS t(凭证号, 日期, 制单人, 摘要, 金额);

-- ============ 多标签疑点画像 ============
SELECT *,
  (周末记账 + 月末集中 + 整数大额 + 冲销调整 + 临界金额) AS 命中数
FROM (
  SELECT
    凭证号, 日期, 制单人, 摘要, 金额,
    CASE WHEN extract(isodow FROM 日期) IN (6, 7) THEN 1 ELSE 0 END          AS 周末记账,
    CASE WHEN 日期 >= last_day(日期) - 2 THEN 1 ELSE 0 END                    AS 月末集中,
    CASE WHEN 金额 % 10000 = 0 AND abs(金额) >= 100000 THEN 1 ELSE 0 END      AS 整数大额,
    CASE WHEN 摘要 ~ '冲销|调整|更正' THEN 1 ELSE 0 END                       AS 冲销调整,
    CASE WHEN 金额 BETWEEN 90000 AND 99999.99 THEN 1 ELSE 0 END               AS 临界金额
  FROM journal
) t
WHERE (周末记账 + 月末集中 + 整数大额 + 冲销调整 + 临界金额) >= 2   -- 命中 2 项以上的重点核查
ORDER BY abs(金额) DESC;

-- ============ 制单人集中度 ============
SELECT 制单人,
       COUNT(*)            AS 分录数,
       SUM(abs(金额))      AS 经手金额,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS 占比百分比
FROM journal
GROUP BY 制单人
ORDER BY 分录数 DESC;

-- 练习：增加一条测试规则"金额为 6666/8888 等吉利数"，加入画像。
-- 更多测试点（非工作时间、异常科目组合、高频同额）见 docs/04-审计实战.md 表格。
