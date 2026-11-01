/* =====================================================================
   ARMDD - More Rhythm | Profiling: 2ª ronda (dúvidas da 1ª ronda)
   ===================================================================== */
USE MoreRhythm;
GO

/* F1 - As 2 faturas com products_total <> SUM(line_total)
   Hipótese: são as faturas que têm linhas com sinal trocado. */
WITH l AS (
  SELECT invoice_stamp_id, SUM(line_total) s_total, SUM(line_vat) s_iva,
         SUM(CASE WHEN quantity < 0 OR unit_price < 0 THEN 1 ELSE 0 END) linhas_sinal_trocado
  FROM invoices_lines GROUP BY invoice_stamp_id)
SELECT i.invoice_stamp_id, i.products_total, l.s_total, i.shipping_cost,
       i.total_for_vat, i.vat_value, l.s_iva, i.final_total, l.linhas_sinal_trocado
FROM invoices i JOIN l ON l.invoice_stamp_id = i.invoice_stamp_id
WHERE ABS(i.products_total - l.s_total) > 0.01
   OR ABS(i.total_for_vat - (i.products_total + i.shipping_cost)) > 0.01
   OR l.linhas_sinal_trocado > 0;

/* F2 - O frete paga IVA?
   Hipótese A: vat_value = SUM(line_vat)          (frete sem IVA)
   Hipótese B: vat_value = total_for_vat * 23%    (frete com IVA)  */
WITH l AS (SELECT invoice_stamp_id, SUM(line_vat) s_iva FROM invoices_lines GROUP BY invoice_stamp_id)
SELECT COUNT(*) faturas,
  SUM(CASE WHEN ABS(i.vat_value - l.s_iva) <= 0.01 THEN 1 ELSE 0 END)                faturas_hip_A,
  SUM(CASE WHEN ABS(i.vat_value - i.total_for_vat * 0.23) <= 0.01 THEN 1 ELSE 0 END) faturas_hip_B
FROM invoices i JOIN l ON l.invoice_stamp_id = i.invoice_stamp_id;

/* F3 - Produtos incompletos: são os mesmos 2? São vendidos?
   E quantos dos 12 sem fornecedor aparecem em vendas? */
SELECT p.reference, p.designation, p.family, p.category, p.supplyer, p.vat_rate,
       (SELECT COUNT(*) FROM invoices_lines il WHERE il.product = p.reference) n_linhas_venda
FROM products p
WHERE p.family IS NULL OR p.category IS NULL OR p.supplyer IS NULL
   OR p.designation IS NULL OR p.vat_rate IS NULL
ORDER BY n_linhas_venda DESC;

/* F4 - Duplicado 10 / 18: o que difere entre eles e quem tem faturas? */
SELECT c.*, (SELECT COUNT(*) FROM invoices i WHERE i.customer = c.number) n_faturas
FROM customers c WHERE c.number IN (10, 18);

/* F5 - Clientes com problemas (sem zona, cidade vazia) e duplicados aproximados.
   Com 26 clientes dá para inspecionar a olho. */
SELECT number, name, taxpayer_number, clity, zip_code, zone, [type], segment,
       (SELECT COUNT(*) FROM invoices i WHERE i.customer = c.number) n_faturas
FROM customers c
ORDER BY name;

/* F6 - Vendas a clientes "Funcionário"/"Interno": existem? */
SELECT c.[type], COUNT(DISTINCT i.invoice_stamp_id) n_faturas, SUM(i.products_total) total
FROM invoices i JOIN customers c ON c.number = i.customer
GROUP BY c.[type];