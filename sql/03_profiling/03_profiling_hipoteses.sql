/* =====================================================================
   ARMDD - More Rhythm | Profiling inicial: validação de hipóteses
   Correr na BD MoreRhythm. Cada bloco testa UMA hipótese.
   Guardar o resultado de cada bloco (ou colar) para analisarmos.
   ===================================================================== */
USE MoreRhythm;
GO

/* H0 - Estrutura: chaves primárias/estrangeiras e precisão dos numeric
   Hipótese: existem PK em todas as tabelas, mas podem faltar FKs. */
SELECT tc.TABLE_NAME, tc.CONSTRAINT_TYPE, kcu.COLUMN_NAME
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu
  ON kcu.CONSTRAINT_NAME = tc.CONSTRAINT_NAME
ORDER BY tc.TABLE_NAME, tc.CONSTRAINT_TYPE;

SELECT TABLE_NAME, COLUMN_NAME, NUMERIC_PRECISION, NUMERIC_SCALE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE DATA_TYPE IN ('numeric','decimal')
ORDER BY TABLE_NAME, COLUMN_NAME;

/* H1 - Volumes de cada tabela */
SELECT 'customers' tabela, COUNT(*) n FROM customers UNION ALL
SELECT 'suplliers', COUNT(*) FROM suplliers UNION ALL
SELECT 'employees', COUNT(*) FROM employees UNION ALL
SELECT 'products', COUNT(*) FROM products UNION ALL
SELECT 'families', COUNT(*) FROM families UNION ALL
SELECT 'categories', COUNT(*) FROM categories UNION ALL
SELECT 'zones', COUNT(*) FROM zones UNION ALL
SELECT 'invoices', COUNT(*) FROM invoices UNION ALL
SELECT 'invoices_lines', COUNT(*) FROM invoices_lines;

/* H2 - Moedas: a BD não tem tabela de câmbios.
   Hipótese: há EUR e GBP; o câmbio terá de vir de fonte externa. */
SELECT currency, COUNT(*) n_faturas, MIN(invoice_date) desde, MAX(invoice_date) ate
FROM invoices GROUP BY currency;

/* H3 - Não há coluna de desconto.
   Hipótese: line_total = quantity * unit_price (sem desconto). */
SELECT COUNT(*) linhas,
       SUM(CASE WHEN ABS(line_total - quantity * unit_price) > 0.01 THEN 1 ELSE 0 END) linhas_diferentes
FROM invoices_lines;
-- se linhas_diferentes > 0, ver exemplos:
SELECT TOP 20 *, quantity * unit_price AS calculado
FROM invoices_lines
WHERE ABS(line_total - quantity * unit_price) > 0.01;

/* H4 - Coerência cabeçalho vs linhas.
   Hipóteses: products_total = SUM(line_total);
              total_for_vat = products_total + shipping_cost;
              final_total   = total_for_vat + vat_value;
              vat_value > SUM(line_vat)  => o frete também paga IVA. */
WITH l AS (
  SELECT invoice_stamp_id, SUM(line_total) s_total, SUM(line_vat) s_iva, COUNT(*) n_linhas
  FROM invoices_lines GROUP BY invoice_stamp_id)
SELECT COUNT(*) faturas,
  SUM(CASE WHEN l.invoice_stamp_id IS NULL THEN 1 ELSE 0 END)                                faturas_sem_linhas,
  SUM(CASE WHEN ABS(i.products_total - l.s_total) > 0.01 THEN 1 ELSE 0 END)                  dif_products_total,
  SUM(CASE WHEN ABS(i.total_for_vat - (i.products_total + i.shipping_cost)) > 0.01 THEN 1 ELSE 0 END) dif_total_for_vat,
  SUM(CASE WHEN ABS(i.final_total - (i.total_for_vat + i.vat_value)) > 0.01 THEN 1 ELSE 0 END)  dif_final_total,
  SUM(CASE WHEN i.vat_value - l.s_iva > 0.01 THEN 1 ELSE 0 END)                              iva_cab_maior_que_linhas,
  SUM(CASE WHEN i.shipping_cost = 0 THEN 1 ELSE 0 END)                                       faturas_sem_frete
FROM invoices i
LEFT JOIN l ON l.invoice_stamp_id = i.invoice_stamp_id;

/* H5 - IVA da linha.
   Hipótese: line_vat = line_total * taxa do produto (ver escala: 23 ou 0.23?). */
SELECT vat_rate, COUNT(*) n_produtos FROM products GROUP BY vat_rate;

SELECT COUNT(*) linhas,
  SUM(CASE WHEN il.line_vat IS NULL THEN 1 ELSE 0 END) iva_nulo,
  SUM(CASE WHEN ABS(il.line_vat - il.line_total * p.vat_rate / 100.0) > 0.01 THEN 1 ELSE 0 END) dif_taxa_percent,
  SUM(CASE WHEN ABS(il.line_vat - il.line_total * p.vat_rate) > 0.01 THEN 1 ELSE 0 END)         dif_taxa_fracao
FROM invoices_lines il
LEFT JOIN products p ON p.reference = il.product;

/* H6 - Integridade referencial (órfãos).
   Hipótese: existem registos órfãos que vão para tabelas de erro. */
SELECT 'invoices.customer'     rel, COUNT(*) orfaos FROM invoices i      WHERE NOT EXISTS (SELECT 1 FROM customers c  WHERE c.number = i.customer) UNION ALL
SELECT 'invoices.employee',    COUNT(*) FROM invoices i      WHERE NOT EXISTS (SELECT 1 FROM employees e  WHERE e.number = i.employee) UNION ALL
SELECT 'lines.invoice',        COUNT(*) FROM invoices_lines l WHERE NOT EXISTS (SELECT 1 FROM invoices i   WHERE i.invoice_stamp_id = l.invoice_stamp_id) UNION ALL
SELECT 'lines.product',        COUNT(*) FROM invoices_lines l WHERE NOT EXISTS (SELECT 1 FROM products p   WHERE p.reference = l.product) UNION ALL
SELECT 'products.family',      COUNT(*) FROM products p WHERE p.family    IS NOT NULL AND NOT EXISTS (SELECT 1 FROM families f   WHERE f.reference = p.family) UNION ALL
SELECT 'products.category',    COUNT(*) FROM products p WHERE p.category  IS NOT NULL AND NOT EXISTS (SELECT 1 FROM categories c WHERE c.Code = p.category) UNION ALL
SELECT 'products.supplyer',    COUNT(*) FROM products p WHERE p.supplyer  IS NOT NULL AND NOT EXISTS (SELECT 1 FROM suplliers s  WHERE s.number = p.supplyer) UNION ALL
SELECT 'customers.zone',       COUNT(*) FROM customers c WHERE c.zone     IS NOT NULL AND NOT EXISTS (SELECT 1 FROM zones z      WHERE z.code = c.zone) UNION ALL
SELECT 'suplliers.zone',       COUNT(*) FROM suplliers s WHERE s.zone     IS NOT NULL AND NOT EXISTS (SELECT 1 FROM zones z      WHERE z.code = s.zone) UNION ALL
SELECT 'employees.chief',      COUNT(*) FROM employees e WHERE e.chief    IS NOT NULL AND NOT EXISTS (SELECT 1 FROM employees x  WHERE x.number = e.chief);

/* H7 - Nulos nos atributos que as análises usam.
   Hipótese: há produtos sem família/categoria/fornecedor e clientes sem zona
   => será preciso um membro "Desconhecido" nas dimensões. */
SELECT
  SUM(CASE WHEN family IS NULL THEN 1 ELSE 0 END)      prod_sem_familia,
  SUM(CASE WHEN category IS NULL THEN 1 ELSE 0 END)    prod_sem_categoria,
  SUM(CASE WHEN supplyer IS NULL THEN 1 ELSE 0 END)    prod_sem_fornecedor,
  SUM(CASE WHEN designation IS NULL THEN 1 ELSE 0 END) prod_sem_designacao,
  SUM(CASE WHEN vat_rate IS NULL THEN 1 ELSE 0 END)    prod_sem_iva,
  SUM(CASE WHEN last_update_date IS NULL THEN 1 ELSE 0 END) prod_sem_data_update
FROM products;
SELECT SUM(CASE WHEN zone IS NULL THEN 1 ELSE 0 END) clientes_sem_zona FROM customers;

/* H8 - Clientes duplicados (exatos).
   Hipótese: o mesmo NIF ou nome aparece com números diferentes. */
SELECT taxpayer_number, COUNT(*) n, STRING_AGG(CAST(number AS varchar(20)), ', ') numeros
FROM customers GROUP BY taxpayer_number HAVING COUNT(*) > 1 ORDER BY n DESC;

SELECT UPPER(LTRIM(RTRIM(name))) nome_normalizado, COUNT(*) n,
       STRING_AGG(CAST(number AS varchar(20)), ', ') numeros
FROM customers GROUP BY UPPER(LTRIM(RTRIM(name))) HAVING COUNT(*) > 1 ORDER BY n DESC;

/* H9 - Domínios dos atributos de agrupamento (tipo, segmento, cidade, zona).
   Hipótese: há valores inconsistentes (maiúsculas, espaços, grafias). */
SELECT [type], COUNT(*) n FROM customers GROUP BY [type] ORDER BY [type];
SELECT segment, COUNT(*) n FROM customers GROUP BY segment ORDER BY segment;
SELECT clity, COUNT(*) n FROM customers GROUP BY clity ORDER BY clity;
SELECT code, zone FROM zones ORDER BY code;

/* H10 - Datas e valores estranhos.
   Hipóteses: payment_date >= invoice_date; quantidades e preços positivos;
              last_update >= create (base do carregamento incremental). */
SELECT MIN(invoice_date) primeira, MAX(invoice_date) ultima,
  SUM(CASE WHEN payment_date < invoice_date THEN 1 ELSE 0 END) pag_antes_fatura
FROM invoices;

SELECT
  SUM(CASE WHEN quantity <= 0 THEN 1 ELSE 0 END)  qtd_nao_positiva,
  SUM(CASE WHEN unit_price < 0 THEN 1 ELSE 0 END) preco_negativo,
  SUM(CASE WHEN unit_price = 0 THEN 1 ELSE 0 END) preco_zero
FROM invoices_lines;

SELECT 'invoices' t, SUM(CASE WHEN CAST(last_update_date AS datetime) + CAST(last_update_time AS datetime)
                              < CAST(create_date AS datetime) + CAST(create_time AS datetime) THEN 1 ELSE 0 END) update_antes_create
FROM invoices
UNION ALL
SELECT 'customers', SUM(CASE WHEN CAST(last_update_date AS datetime) + CAST(last_update_time AS datetime)
                              < CAST(create_date AS datetime) + CAST(create_time AS datetime) THEN 1 ELSE 0 END)
FROM customers;

/* H11 - Hierarquia de empregados (auto-relação chief).
   Hipótese: existe um topo (chief NULL) e poucos níveis. */
WITH h AS (
  SELECT number, chief, 1 AS nivel FROM employees WHERE chief IS NULL
  UNION ALL
  SELECT e.number, e.chief, h.nivel + 1 FROM employees e JOIN h ON e.chief = h.number)
SELECT nivel, COUNT(*) n FROM h GROUP BY nivel ORDER BY nivel;