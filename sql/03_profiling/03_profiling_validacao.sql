/* =====================================================================
   ARMDD - More Rhythm | Validação das afirmações do relatório (cap. 2 a 5)
   Cada bloco confirma (ou não) uma frase do relatório.
   ===================================================================== */
USE MoreRhythm;
GO

/* V1 (2.5) - registos com a data de alteração anterior à de criação */
SELECT 'suplliers' t, COUNT(*) n FROM suplliers
WHERE CAST(last_update_date AS datetime) + CAST(last_update_time AS datetime)
    < CAST(create_date AS datetime) + CAST(create_time AS datetime)
UNION ALL
SELECT 'products', COUNT(*) FROM products
WHERE CAST(last_update_date AS datetime) + CAST(last_update_time AS datetime)
    < CAST(create_date AS datetime) + CAST(create_time AS datetime);

/* V2 (2.5) - faturas alteradas depois de criadas e máximo de dias */
SELECT SUM(CASE WHEN CAST(last_update_date AS datetime) + CAST(last_update_time AS datetime)
              > CAST(create_date AS datetime) + CAST(create_time AS datetime) THEN 1 ELSE 0 END) alteradas,
       MAX(DATEDIFF(DAY, create_date, last_update_date)) max_dias
FROM invoices;

/* V3 (2.5) - o prefixo do invoice_stamp_id antes da vírgula não é único */
SELECT LEFT(invoice_stamp_id, CHARINDEX(',', invoice_stamp_id) - 1) prefixo, COUNT(*) n
FROM invoices
GROUP BY LEFT(invoice_stamp_id, CHARINDEX(',', invoice_stamp_id) - 1)
HAVING COUNT(*) > 1;

/* V4 (5.2 DataPagamentoKey) - payment_date é a data real de pagamento
   ou a data de vencimento (data da fatura + prazo do cliente)?
   Se igual_prazo = 37, é o vencimento e não o pagamento real. */
SELECT COUNT(*) faturas,
  SUM(CASE WHEN i.payment_date = DATEADD(DAY, c.days_pay_invoices, i.invoice_date) THEN 1 ELSE 0 END) igual_prazo,
  SUM(CASE WHEN i.payment_date = i.invoice_date THEN 1 ELSE 0 END) mesmo_dia
FROM invoices i JOIN customers c ON c.number = i.customer;

/* V5 (3.3 P2) - "o cabeçalho usou o preço de tabela".
   Se s_tabela = products_total nas 2 faturas, confirma-se. */
SELECT i.invoice_stamp_id, i.products_total,
       SUM(il.line_total) s_linhas,
       SUM(ABS(il.quantity) * p.current_sell_price / 1000000.0) s_tabela
FROM invoices i
JOIN invoices_lines il ON il.invoice_stamp_id = i.invoice_stamp_id
JOIN products p ON p.reference = il.product
GROUP BY i.invoice_stamp_id, i.products_total
HAVING ABS(i.products_total - SUM(il.line_total)) > 0.01;

/* V6 (3.3) - "os preços de tabela estão multiplicados por 1 000 000".
   Compara o preço de tabela /1 000 000 com o preço praticado nas linhas. */
SELECT COUNT(*) linhas,
  SUM(CASE WHEN ABS(ABS(il.unit_price) - p.current_sell_price / 1000000.0) <= 0.01 THEN 1 ELSE 0 END) igual_tabela
FROM invoices_lines il JOIN products p ON p.reference = il.product;

/* V7 (3.3) - "10 faturas anteriores à criação do cliente" */
SELECT COUNT(*) faturas_antes_cliente
FROM invoices i JOIN customers c ON c.number = i.customer
WHERE i.invoice_date < c.create_date;

/* V8 (5.5) - "a classificação é constante dentro da família"
   (base da hierarquia Classificação → Família → Produto). Esperado: vazio. */
SELECT family, COUNT(DISTINCT classification) n_classificacoes
FROM products
WHERE family IS NOT NULL AND classification IS NOT NULL
GROUP BY family HAVING COUNT(DISTINCT classification) > 1;

/* V9 (3.1) - "nenhum produto se repete na mesma fatura". Esperado: vazio. */
SELECT invoice_stamp_id, product, COUNT(*) n
FROM invoices_lines GROUP BY invoice_stamp_id, product HAVING COUNT(*) > 1;

/* V10 (3.1) - "5 datas, nenhuma ao fim de semana" e "19 prefixos" */
SELECT invoice_date, DATENAME(WEEKDAY, invoice_date) dia_semana, COUNT(*) n_faturas
FROM invoices GROUP BY invoice_date ORDER BY invoice_date;

SELECT COUNT(DISTINCT LEFT(invoice_stamp_id, CHARINDEX(',', invoice_stamp_id) - 1)) n_prefixos
FROM invoices;

/* V11 (5.4) - cidades em mais do que uma zona
   (se devolver linhas, Zona → Cidade não é uma hierarquia estrita) */
SELECT LTRIM(SUBSTRING(zip_code, 9, 50)) cidade_postal, COUNT(DISTINCT zone) n_zonas
FROM customers
WHERE zone IS NOT NULL
GROUP BY LTRIM(SUBSTRING(zip_code, 9, 50))
HAVING COUNT(DISTINCT zone) > 1;

/* V12 (3.3) - os fornecedores técnicos estão associados a produtos vendidos?
   Resultado: 0 produtos e 0 linhas vendidas nos dois. */
SELECT s.number, s.name, COUNT(DISTINCT p.reference) n_produtos, COUNT(il.invoice_line_stamp_id) n_linhas_vendidas
FROM suplliers s
LEFT JOIN products p ON p.supplyer = s.number
LEFT JOIN invoices_lines il ON il.product = p.reference
WHERE s.name IN ('Compras a Dinheiro', 'MaisRitmo (interno)')
GROUP BY s.number, s.name;