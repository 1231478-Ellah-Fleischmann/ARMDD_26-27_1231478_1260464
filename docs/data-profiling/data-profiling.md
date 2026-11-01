# Data Profiling - BD operacional MoreRhythm

**Data da análise:** 01/11/2026
**Fonte:** BD `MoreRhythm` (amostra fornecida)
**Scripts:** `sql/03_profiling/03_profiling_hipoteses.sql` (H0–H11) e `sql/03_profiling/03_profiling_followup.sql` (F1–F6)

## 1. Abordagem

Cada característica da BD foi formulada como **hipótese** e testada com uma query. Todas as conclusões abaixo se baseiam nos resultados obtidos sobre a amostra fornecida. Com volumes maiores podem surgir outros casos.

## 2. Caracterização da fonte

| Tabela | Registos |
|---|---|
| customers | 26 |
| suplliers | 14 |
| employees | 6 |
| products | 67 |
| families | 17 |
| categories | 11 |
| zones | 5 |
| invoices | 37 |
| invoices_lines | 93 |

- As faturas vão de **31/01/2025 a 01/05/2025**. As últimas alterações (`last_update_date`) chegam a dez/2025.
- Todas as relações têm **chaves estrangeiras** definidas e não existem registos órfãos (H0, H6).
- Os valores monetários são `numeric(19,6)` e as quantidades `numeric(14,4)`. `vat_rate` é inteiro (23 = 23%).
- Data e hora estão em colunas separadas (`*_date`, `*_time`).
- Há nomes de objetos com erros ortográficos, a respeitar no mapeamento: `suplliers`, `clity`, `supplyer`, `departament`.

## 3. Regras de negócio inferidas (validadas na amostra)

| # | Regra | Evidência |
|---|---|---|
| R1 | Não existe desconto: `line_total = quantity × unit_price` | 89/93 linhas. As 4 exceções são erros de sinal (ver P1) |
| R2 | `line_vat = line_total × vat_rate / 100` | 93/93 linhas |
| R3 | O frete **não paga IVA**: `vat_value = Σ line_vat` | 37/37 faturas |
| R4 | `final_total = total_for_vat + vat_value` | 37/37 faturas |
| R5 | `total_for_vat = products_total + shipping_cost` | 35/37 faturas (ver P3) |
| R6 | **Frete = 2,5% × `products_total`** (calculado sobre o cabeçalho) | 35/37 faturas (ver P3) |

> As regras R6 e R3 são inferidas dos dados e devem ser confirmadas com o docente.

## 4. Problemas de qualidade identificados

| # | Problema | Casos | Tratamento proposto *(a decidir)* |
|---|---|---|---|
| P1 | Linhas com sinal trocado: quantidade ou preço negativo, mas `line_total` e `line_vat` positivos | 4 linhas | Aplicar `ABS()` e registar em tabela de erros |
| P2 | `products_total` ≠ Σ `line_total` (diferença de 5 €) | 2 faturas (…9092, …9337) | Usar as linhas como fonte de verdade |
| P3 | `shipping_cost` ≠ 2,5% × `products_total` (+2,50 € e +5,00 €) | 2 faturas (…8165, …9438) | Recalcular o frete ou manter e registar como erro |
| P4 | Clientes duplicados | 3 grupos (6 → 3 clientes) | Fuzzy Grouping + tabela de mapeamento (ver 4.1) |
| P5 | Produtos sem família, categoria, fornecedor, designação e/ou IVA | 12 produtos (nenhum vendido) | Membro "Desconhecido" nas dimensões |
| P6 | Clientes técnicos com NIF inválido (`0`, `00`, `000000000`, vazio), sem zona e/ou sem cidade | 4 clientes (2, 20, 24, 25), sem vendas | Carregar com "Desconhecido" / avaliar exclusão |
| P7 | Cidade vazia (cliente 21: a cidade está no `zip_code`) e grafias diferentes ("Bairro Além do Rio" / "Bairro Alem Rio") | 3 + 1 casos | Extrair do código postal / normalizar |
| P8 | Possível zona incoerente: clientes 11 e 19 (ambos Amadora) em zonas diferentes (Sul / Centro) | 1 cliente | Confirmar; manter a fonte e registar |
| P9 | Moeda gravada como `EURO` em vez do código ISO `EUR` | 37 faturas | Mapear para `EUR` na DimMoeda |

### 4.1 Clientes duplicados

| Grupo | Clientes | Tipo | Diferenças | Faturas |
|---|---|---|---|---|
| Eira e Beira, Lda | 10 / 18 | Exato | Mesmo NIF. Só diferem em `mobile` (espaço vs vazio) e nas datas de criação/alteração | 1 + 1 |
| Coro N. Sra. Assunção | 5 / 26 | Aproximado | NIF com dígitos trocados (300455644 / 300456544), nome abreviado, cidade com grafia diferente | 3 + 2 |
| Luz e Som, Lda | 8 / 22 | Aproximado | NIF com dígitos trocados (365564344 / 365564434), pontuação do nome | 1 + 1 |

O agrupamento por NIF **só deteta o grupo exato**. Para os outros dois é necessária correspondência aproximada (Fuzzy Grouping, por exemplo sobre nome + código postal). Como todos os clientes duplicados têm faturas, é obrigatório manter uma **tabela de mapeamento** (ID original → ID sobrevivente) para o carregamento dos factos.

## 5. Outras observações relevantes para o modelo

- **Moeda:** só existe EUR na amostra, e a BD não tem tabela de câmbios. A DimMoeda mantém-se por causa do requisito de expansão para o Reino Unido (GBP), e o câmbio terá de vir de fonte externa.
- **Tipos de cliente:** Cliente Final (18 faturas), Revendedor (18), Funcionário (1 fatura, 774 €), Interno (0). É preciso decidir se as vendas a funcionários entram no data mart.
- **Zonas:** `zones` mistura regiões (Norte, Centro, Sul, Ilhas) com um país (Espanha). Pode ser necessário um atributo país.
- **Fornecedor:** está associado ao **produto** (`products.supplyer`) e não à fatura.
- **Empregados:** a hierarquia (`chief`) tem **duas raízes** e 2 níveis.

## 6. Decisões pendentes

1. Linhas vs cabeçalho como fonte de verdade para o valor dos produtos.
2. Tratamento das linhas com sinal trocado.
3. Frete inconsistente: recalcular (2,5%) ou manter o valor faturado. Inclui as faturas em que o frete foi calculado sobre um `products_total` errado.
4. Critério para escolher o cliente sobrevivente nos duplicados.
5. Inclusão das vendas a funcionários.

## Anexo - Queries de validação do frete

```sql
-- R6: frete = 2,5% do products_total  → resultado: 35 de 37
SELECT COUNT(*) faturas,
  SUM(CASE WHEN ABS(shipping_cost - products_total * 0.025) <= 0.01 THEN 1 ELSE 0 END) frete_2_5_pct
FROM invoices;

-- Exceções → resultado: …8165 e …9438
SELECT invoice_stamp_id, products_total, shipping_cost,
       products_total * 0.025 AS frete_esperado
FROM invoices
WHERE ABS(shipping_cost - products_total * 0.025) > 0.01;
```