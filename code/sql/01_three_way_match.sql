-- 三单匹配：采购订单 / 收货单 / 发票
-- 可在 DuckDB 直接运行：把 orders/receipts/invoices 换成 read_csv_auto('xxx.csv') 即可查文件
-- 用法示例：duckdb -c ".read 01_three_way_match.sql"（需先建表或改读文件）

-- ============ 模拟数据（练习用，真实项目替换为自己的表） ============
CREATE OR REPLACE TABLE orders AS
SELECT * FROM (VALUES
  ('PO001', '供应商A', '钢材', 100, 50.0),
  ('PO002', '供应商B', '电缆', 200, 30.0),
  ('PO003', '供应商C', '轴承', 50,  80.0),
  ('PO004', '供应商D', '包装材料', 500, 2.0)
) AS t(po_no, supplier, material, qty, unit_price);

CREATE OR REPLACE TABLE receipts AS
SELECT * FROM (VALUES
  ('GRN001', 'PO001', 100, DATE '2024-03-05'),
  ('GRN002', 'PO002', 180, DATE '2024-03-08'),   -- 少收货 20
  ('GRN003', 'PO003', 60,  DATE '2024-03-10')    -- 超量收货
  -- PO004 无收货记录
) AS t(grn_no, po_no, qty_received, recv_date);

CREATE OR REPLACE TABLE invoices AS
SELECT * FROM (VALUES
  ('INV001', 'PO001', 5000.0, DATE '2024-03-06'),
  ('INV002', 'PO002', 6600.0, DATE '2024-03-12'), -- 发票金额超订单
  ('INV003', 'PO004', 1000.0, DATE '2024-03-15')  -- 无收货先收票
) AS t(inv_no, po_no, amount, inv_date);

-- ============ 匹配主逻辑 ============
WITH po AS (
  SELECT po_no, supplier, SUM(qty) AS po_qty, SUM(qty * unit_price) AS po_amt
  FROM orders GROUP BY 1, 2
),
grn AS (
  SELECT po_no, SUM(qty_received) AS grn_qty FROM receipts GROUP BY 1
),
inv AS (
  SELECT po_no, SUM(amount) AS inv_amt FROM invoices GROUP BY 1
)
SELECT
  po.po_no, po.supplier,
  po.po_qty, COALESCE(grn.grn_qty, 0) AS grn_qty,
  ROUND(po.po_amt, 2)                 AS po_amt,
  ROUND(COALESCE(inv.inv_amt, 0), 2)  AS inv_amt,
  CASE
    WHEN grn.po_no IS NULL THEN '异常：有订单无收货'
    WHEN inv.po_no  IS NULL THEN '关注：已收货未收票（暂估）'
    WHEN inv.inv_amt > po.po_amt * 1.01 THEN '异常：发票金额超订单'
    WHEN grn.grn_qty > po.po_qty THEN '异常：超量收货'
    WHEN grn.grn_qty < po.po_qty THEN '关注：收货短缺'
    ELSE '正常'
  END AS 匹配结论
FROM po
FULL OUTER JOIN grn ON po.po_no = grn.po_no
FULL OUTER JOIN inv ON po.po_no = inv.po_no
ORDER BY po.po_no;

-- 练习：把金额容差从 1% 改为 5%，再观察结论变化。
-- 实务提示：三单没有统一 po_no 时，用 供应商+物料+金额容差+日期窗口 模糊匹配。
