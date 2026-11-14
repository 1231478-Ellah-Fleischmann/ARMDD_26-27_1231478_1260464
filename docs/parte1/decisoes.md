# Registo de decisões

Este ficheiro tem duas partes:

1. **Decisões tomadas**: o que já está fechado e a justificação (base para o relatório).
2. **Decisões em aberto**: o que falta decidir em grupo, com as opções, prós e contras de cada uma. Quando uma decisão for tomada, passa para a parte 1 com a opção escolhida e a justificação.

---

# Parte 1 - Decisões tomadas

## D1 - Processo de negócio e grão

- **Processo de negócio:** vendas (faturação) a clientes.
- **Grão:** uma linha da tabela de factos = uma linha de fatura (`invoices_lines`), ou seja, um produto numa fatura.

**Justificação:** é o nível mais elementar disponível, como pede o enunciado. Só neste grão o produto (e, através dele, família, categoria e fornecedor) tem um valor único por linha, o que é necessário para as análises 1, 2, 3, 5, 6, 9 e 10. O nível da fatura obtém-se sempre por agregação (somando as linhas). O inverso, partir um total da fatura por produto, não é possível.

**Consequência:** o custo de expedição (`invoices.shipping_cost`) existe só ao nível da fatura e tem de ser repartido pelas linhas, proporcionalmente ao valor de cada linha. Como o frete é 2,5% de `products_total` (regra R6 do profiling), a repartição proporcional coincide com 2,5% do valor de cada linha.

**Raphael:** Aqui não havia muito para onde fugir, a granularidade máxima é cada linha da fatura como sendo a unidade minima, ainda mais com a regra de 2,5% do valor do produto para o frete, onde ele basicamente da para nós como dividir o frete entre os produtos. Sem essa regra talvez poderiamos escolher o grão como a fatura por si, visto que seria dificil separar o frete entre os itens de maneira simples e eficinete.
**Ellah:** Concordo. O grão da linha de fatura é o único que serve todas as análises por produto, família, categoria e fornecedor. A regra dos 2,5% (validada em 35 de 37 faturas; as 2 exceções são erros de dados) permite repartir o frete pelas linhas sem ambiguidade.
 
---

# Parte 2 - Decisões em aberto: dimensões

## Conceitos usados nesta secção

- **Dimensão:** tabela com o contexto de cada venda (quem comprou, o quê, quando, quem vendeu, em que moeda). Cada linha da tabela de factos aponta para uma linha de cada dimensão.
- **Surrogate key:** chave numérica criada no data mart (1, 2, 3, ...), independente do código da fonte. Permite ter várias versões do mesmo cliente/produto ao longo do tempo e juntar duplicados.
- **Hierarquia:** níveis dentro de uma dimensão, usados para drill down (descer de detalhe) e roll up (agregar). Exemplo: Produto → Família.
- **Desnormalizar:** copiar para dentro de uma dimensão atributos que na fonte estão noutra tabela (ex.: o nome da família dentro da DimProduto). É a abordagem recomendada por Kimball.
- **Snowflake:** o contrário, dimensões ligadas a outras dimensões em vez de diretamente à tabela de factos. Kimball desaconselha, porque complica as consultas.
- **SCD (Slowly Changing Dimension):** a forma de tratar alterações nos atributos de uma dimensão. Tipo 1 = sobrescrever (perde-se o valor antigo). Tipo 2 = criar uma nova versão da linha (mantém-se o histórico). As SCD de cada atributo serão decididas na etapa dos mapeamentos, mas algumas decisões abaixo têm impacto nelas.
- **Dimensão conformada:** dimensão partilhada por vários processos de negócio (ex.: vendas e compras), com o mesmo significado em todos.

## Proposta base (ponto de partida para as decisões)

| Dimensão | Origem | Atributos principais | Análises que a usam |
|---|---|---|---|
| DimData | Gerada (não vem da fonte) | dia, semana, mês, trimestre, quadrimestre, semestre, ano, estação, fim de semana, último dia do mês | todas |
| DimCliente | `customers` + `zones` | nome, NIF, cidade, código postal, zona, país, tipo, segmento | 1, 2, 4, 6, 7, 8, 9, 10 |
| DimProduto | `products` + `families` + `categories` | designação, família, categoria, taxa de IVA | 1, 2, 3, 5, 6, 8, 9, 10 |
| DimFornecedor | `suplliers` + `zones` | nome, zona | 3, 10 |
| DimEmpregado | `employees` | nome, departamento, chefe | 3, 4 |
| DimMoeda | `invoices.currency` | código ISO, nome | conversão para EUR |
| Nº da fatura | `invoices` | (coluna na tabela de factos) | agrupar linhas da mesma fatura |

Resumo das decisões em aberto:

| # | Decisão | Recomendação |
|---|---|---|
| DD1 | Fornecedor: dimensão própria ou dentro do produto | Dimensão própria |
| DD2 | Zona: dentro de cliente/fornecedor ou dimensão própria | Dentro (desnormalizada) |
| DD3 | Família e categoria: dentro do produto ou dimensões próprias | Dentro do produto |
| DD4 | Fatura: dimensão degenerada ou DimFatura | Degenerada |
| DD5 | Que datas entram no modelo (fatura, pagamento, hora) | Só data da fatura |
| DD6 | Semana do ano: ISO ou padrão do SQL Server | ISO |
| DD7 | Estação do ano: astronómica ou meteorológica | Astronómica |
| DD8 | Hierarquia de chefia dos empregados | Achatada em colunas |
| DD9 | Moeda: dimensão própria ou atributo | Dimensão própria |
| DD10 | Registos incompletos nas dimensões | Membro "Desconhecido" |

---

## DD1 - Fornecedor: dimensão própria ou dentro do produto?

**Contexto.** Na fonte, o fornecedor está ligado ao **produto** (`products.supplyer`) e não à fatura. Ou seja, nas vendas, o fornecedor só se alcança através do produto (`invoices_lines → products → suplliers`). Fora das vendas, o fornecedor está também ligado às compras (`purchases`). O facto de `suplliers` ter tabela própria na fonte não obriga a nada: a BD operacional é normalizada (cada entidade na sua tabela), o modelo dimensional não tem de seguir essa estrutura.

As análises 3 (quantidades por fornecedor) e 10 (drill down zona do fornecedor → fornecedor) funcionam **com qualquer das duas opções**. A diferença está no histórico, no ETL e no reaproveitamento.

### Opção A - DimFornecedor própria, com chave na tabela de factos

Ao carregar cada linha de fatura, o ETL vai buscar o fornecedor do produto e grava a chave da DimFornecedor na linha de factos.

**Prós**
- **Histórico correto sem esforço.** Se o fornecedor mudar de zona, altera-se 1 linha na DimFornecedor; a DimProduto não é afetada. Se um produto mudar de fornecedor, cada linha de factos já guardou o fornecedor da data da venda.
- **Dimensão conformada.** As compras (`purchases`) também têm fornecedor. Num futuro data mart de compras, a DimFornecedor é reaproveitada tal como está. Mostra visão de arquitetura (matriz de barramento de Kimball).
- Hierarquia Zona do fornecedor → Fornecedor (análise 10) fica numa dimensão só dela, simples de usar no Power BI.

**Contras**
- Mais uma tabela, mais um lookup no carregamento da tabela de factos e mais uma chave estrangeira na fato.
- Precisa de um membro "Desconhecido" para produtos sem fornecedor (há 12 na amostra, nenhum vendido).

### Opção B - Atributos do fornecedor dentro da DimProduto

A DimProduto ganha as colunas `NomeFornecedor` e `ZonaFornecedor`.

**Prós**
- Modelo mais simples: uma tabela a menos, ETL com menos um lookup.
- Reflete a fonte: o fornecedor é uma característica do produto.

**Contras**
- **Histórico mais caro.** A zona do fornecedor fica repetida em todos os produtos dele. Se um fornecedor com 8 produtos mudar de zona e quisermos manter o histórico (SCD tipo 2), é preciso criar uma nova versão dos 8 produtos, apesar de nada nos produtos ter mudado. Com SCD tipo 1 (sobrescrever), as vendas antigas passam a aparecer na zona nova, o que distorce a análise 10.
- Não é reaproveitável num futuro data mart de compras.

**Recomendação:** Opção A, pelo histórico e pela dimensão conformada. A Opção B é defensável se se assumir no relatório que as mudanças no fornecedor são tratadas como SCD tipo 1 (ou que são raras).
**Raphael:** Aqui eu escolheria o opção B. Seria uma tabela a menos para se trabalhar com e o unico problema acontece caso um fornecedor mude de localidade, por exemplo, o que acaba por ser raro, como a propria recomendação diz acima.
**Ellah:** Iria pela A. Testei quantos produtos tem cada fornecedor: o fornecedor 8 tem 20 produtos e o 9 e o 12 têm 10 cada. Com a B, se o fornecedor 8 mudar de zona e quisermos manter o histórico, são criadas 20 novas versões de produto sem que nada no produto tenha mudado. Além disso, a A permite reaproveitar a DimFornecedor num futuro data mart de compras (dimensão conformada) e deixa a hierarquia da análise 10 numa dimensão própria. Se ficarmos com a B, a justificação no relatório tem de ser que assumimos as mudanças de fornecedor como raras e as tratamos como SCD tipo 1.
---

## DD2 - Zona: dentro de cliente/fornecedor ou dimensão própria?

**Contexto.** A tabela `zones` é usada tanto por clientes como por fornecedores. Tem 5 zonas que misturam regiões portuguesas (Norte, Centro, Sul, Ilhas) com um país (Espanha). Há análises por zona do cliente (6, 9, 10) e por zona do fornecedor (10).

### Opção A - Desnormalizar: colunas `Zona` e `País` dentro da DimCliente e da DimFornecedor

**Prós**
- Abordagem recomendada por Kimball (sem snowflake).
- Consultas e Power BI mais simples: a hierarquia Cliente → Cidade → Zona fica toda numa dimensão.
- Permite acrescentar o atributo `País` (Portugal/Espanha, futuramente Reino Unido), que resolve a mistura de regiões e países em `zones` e prepara a expansão pedida no enunciado.

**Contras**
- O nome da zona fica repetido em vários clientes. Se uma zona mudar de nome, é preciso atualizar várias linhas (raro e barato com estes volumes).

### Opção B - DimZona própria

Pode ser ligada à fato (duas vezes: zona do cliente e zona do fornecedor) ou às dimensões cliente/fornecedor (snowflake).

**Prós**
- Zona definida num só sítio.

**Contras**
- Ligada às dimensões é snowflake, que Kimball desaconselha.
- Ligada à fato exige duas chaves (role-playing) e separa a zona do cliente do resto da hierarquia geográfica do cliente.
- Mais tabelas sem ganho real para as análises pedidas.

**Recomendação:** Opção A, com o atributo `País` acrescentado.
**Raphael:** Não tenho muito uma ideia geral pois essa depende muito da escolha 1. Vou tentar colocar abaixo os problemas que um ponto gera no outro mas acho que é meio claro que querendo manter fornecedor dentro de produto na 1 a escolha b acaba por ficar mais complicada. A opção A é a opção que corrobora com Kimball, iria por ela apenas por isso.
**Ellah:** Opção A, com o atributo `País`. Além de seguir o Kimball, resolve o problema de `zones` misturar regiões portuguesas com Espanha e prepara o modelo para a expansão para o Reino Unido.

> **Nota - relação com a DD1.** As duas decisões são quase independentes: a DD1 decide *em que tabela* ficam as colunas de zona do fornecedor; a DD2 decide se a zona é *coluna ou tabela própria*. A recomendação (Opção A) mantém-se nos dois cenários da DD1:
>
> - **DD1 = A (DimFornecedor):** `Zona`/`País` na DimCliente e na DimFornecedor, como descrito acima.
> - **DD1 = B (fornecedor dentro do produto):** a zona do cliente fica na DimCliente; a zona do fornecedor passa a colunas da DimProduto (`ZonaFornecedor`, `PaisFornecedor`). A análise 10 continua a funcionar com a hierarquia Zona do fornecedor → Fornecedor → Produto, toda dentro da DimProduto.
>
> Com a DD1 = B, a Opção B desta decisão (DimZona) fica ainda pior: ou a DimZona é ligada à DimProduto (snowflake Produto → Zona), ou a fato ganha uma chave de zona do fornecedor sem ter chave de fornecedor, o que não faz sentido.
>
> Efeito colateral: com a DD1 = B, a zona do fornecedor fica repetida em todos os produtos desse fornecedor. Uma mudança de zona do fornecedor obriga a alterar todos esses produtos (é o contra já descrito na DD1, a DD2 não acrescenta nenhum problema novo).
---

## DD3 - Família e categoria: dentro do produto ou dimensões próprias?

**Contexto.** Na fonte, `families` e `categories` são tabelas separadas, ambas ligadas ao produto. As análises usam família (2, 6, 8, 10) e categoria (1, 5, 9), sempre com drill down até ao produto.

Há uma pergunta prévia: **família e categoria são independentes, ou uma está dentro da outra?** As análises tratam-nas como classificações paralelas (Produto → Família e Produto → Categoria), mas convém confirmar nos dados:

```sql
-- Se devolver linhas, a mesma família tem produtos de várias categorias => são independentes.
SELECT family, COUNT(DISTINCT category) n_categorias
FROM products
WHERE family IS NOT NULL AND category IS NOT NULL
GROUP BY family
HAVING COUNT(DISTINCT category) > 1;
```

### Opção A - Colunas `Família` e `Categoria` dentro da DimProduto

**Prós**
- Abordagem de Kimball (desnormalização).
- Drill down Família → Produto e Categoria → Produto direto, dentro da mesma dimensão (análises 5 e 6).
- Menos tabelas e menos joins.

**Contras**
- Se uma família mudar de nome, atualizam-se todos os produtos dessa família.

### Opção B - DimFamília e DimCategoria próprias

**Prós**
- Cada classificação definida num só sítio.

**Contras**
- Snowflake (se ligadas ao produto) ou duas chaves a mais na fato (se ligadas à fato).
- O drill down até ao produto atravessa tabelas diferentes.

**Recomendação:** Opção A. Se a query acima mostrar que são independentes, ficam duas hierarquias paralelas na DimProduto; se mostrar que uma está dentro da outra, fica uma hierarquia de 3 níveis.
**Raphael:** O professor mandou usar a metodologia de kimball, logo iria pela A, a desnormalização.
**Ellah:** Opção A. Corri a query acima e o inverso: a família Acessórios tem produtos de 4 categorias, a Rádios de 2, e as categorias 4 e 10 têm produtos de 2 famílias cada. Família e categoria são independentes, por isso ficam duas hierarquias paralelas na DimProduto (Família → Produto e Categoria → Produto), que é o que as análises 5 e 6 pedem.
---

## DD4 - Fatura: dimensão degenerada ou DimFatura?

**Contexto.** O número da fatura é útil para agrupar as linhas da mesma fatura (ex.: valor médio por fatura). Os restantes dados do cabeçalho (`invoices`) já estão representados noutras dimensões (cliente, empregado, data, moeda) ou viram medidas (frete).

### Opção A - Dimensão degenerada: coluna `NumeroFatura` na própria tabela de factos

**Prós**
- Solução clássica de Kimball para números de documentos (faturas, encomendas).
- Sem tabela extra e sem lookup.

**Contras**
- Se no futuro forem precisos outros atributos do cabeçalho (ex.: estado da fatura, forma de pagamento), não há onde os pôr sem alterar a fato.

### Opção B - DimFatura

**Prós**
- Espaço para atributos do cabeçalho.

**Contras**
- Teria praticamente uma linha por fatura com quase nada dentro (o resto já está noutras dimensões). Cresce ao mesmo ritmo da tabela de factos, o que Kimball desaconselha.

**Recomendação:** Opção A.
**Raphael:** Seguiria pelo recomendado a A(dim degenerada, que é propria do conceito do Kimball)
**Ellah:** Opção A. Os restantes dados do cabeçalho já estão nas outras dimensões ou viram medidas, uma DimFatura ficaria praticamente vazia.
---

## DD5 - Que datas entram no modelo?

**Contexto.** As faturas têm data da fatura e data de pagamento (`payment_date`). As tabelas têm também horas em colunas separadas (`*_time`). Todas as análises do enunciado usam a data da venda.

### Opção A - Só a data da fatura

**Prós**
- Cobre todas as análises pedidas.
- Modelo mais simples.

**Contras**
- Não permite análises de prazos de pagamento.

### Opção B - Data da fatura + data de pagamento (DimData usada duas vezes, "role-playing")

**Prós**
- Permite análises de prazos de pagamento e cobranças (podem contar para as 10 análises "à escolha").

**Contras**
- Mais uma chave na fato. Pagamento não é o processo de negócio em análise (vendas).

### Opção C - Acrescentar uma DimHora

**Prós**
- Análises por hora do dia.

**Contras**
- Nenhuma análise pedida usa a hora; é preciso confirmar se a fatura tem hora da venda ou só hora de criação do registo.

**Recomendação:** Opção A. A Opção B só se quisermos usar prazos de pagamento nas análises à escolha.
**Raphael:** Eu acabaria escolhendo a B pois nos abre opções mais a frente como indicado na recomendação.
**Ellah:** Concordo com a B. O custo é só mais uma chave na fato e os dados são fiáveis: `payment_date` nunca é nulo e o profiling (H10) mostrou que nunca é anterior à data da fatura. Dá-nos análises de prazo de pagamento para as 10 à escolha.

---

## DD6 - Semana do ano: ISO ou padrão do SQL Server?

**Contexto.** A análise 6 pede a "6ª semana do ano de 2025". Há duas formas comuns de numerar semanas, e dão **resultados diferentes** em 2025 (o ano começou numa quarta-feira):

| Regra | Semana 1 de 2025 | Semana 6 de 2025 |
|---|---|---|
| ISO 8601 (`DATEPART(ISO_WEEK, ...)`): semana começa à segunda; a semana 1 é a que contém 4 de janeiro | 30/12/2024 a 05/01/2025 | 03/02 a 09/02/2025 |
| SQL Server por omissão (`DATEPART(WEEK, ...)`): semana começa ao domingo; a semana 1 é a que contém 1 de janeiro | 01/01 a 04/01/2025 | 02/02 a 08/02/2025 |

> **O enunciado não define a regra.** Diz apenas "6ª semana do ano de 2025". A escolha é nossa e tem de ser justificada no relatório (ou confirmada com o docente).

### Opção A - ISO 8601

**Prós**
- Norma europeia e portuguesa; semanas sempre completas de 7 dias, de segunda a domingo.
- Não depende de configurações do servidor (`DATEFIRST`).

**Contras**
- Os primeiros dias de janeiro podem pertencer à última semana do ano anterior (e vice-versa). Por isso, a DimData precisa também de um "ano da semana ISO" para agregar corretamente.

### Opção B - Padrão do SQL Server

**Prós**
- Semana 1 começa sempre a 1 de janeiro; não há semanas a atravessar anos.

**Contras**
- A primeira e a última semana podem ter menos de 7 dias.
- Depende da configuração `DATEFIRST` do servidor (o resultado pode mudar entre máquinas).
- Convenção americana, menos adequada para uma empresa portuguesa.

### Opções usadas pelos grupos do ano passado

O enunciado de 2025/26 tinha a mesma pergunta ("semana 6 de 2023") e nenhum dos grupos documentou a regra escolhida. As abordagens deles são alternativas válidas que podemos seguir:

#### Opção C - Sem coluna de semana na DimData; semana calculada no Power BI (grupo 1210990/1211572)

A DimData deles (`ARMDD_25-26-main/Parte_2/SQL Files/Data Mart/Creates/11_script_date.sql`) tem ano, semestre, trimestre, quadrimestre, mês, estação, dia da semana, fim de semana e último dia do mês, mas **não tem semana**. A semana é calculada no relatório Power BI, por exemplo com `WEEKNUM(Data, 21)` (ISO) ou `WEEKNUM(Data)` (domingo a sábado).

**Prós**
- DimData mais pequena; a regra pode ser mudada no Power BI sem recarregar o data mart.

**Contras**
- A semana não fica no data mart: outras ferramentas (SQL, Excel) têm de recalcular, e cada uma pode usar uma regra diferente.
- Vai contra a ideia de Kimball de ter na DimData todos os atributos de calendário já calculados.
- Continua a ser preciso escolher entre ISO e o padrão; só muda o sítio onde se escolhe.

#### Opção D - As duas colunas na DimData (grupo 1221715/1211152)

Geraram a DimData com o assistente do Visual Studio (`Create Date Dimension/DimDate.dim`), que cria `WeekOfYear` (padrão) e `Iso8601WeekOfYear` (ISO).

**Prós**
- Cobre as duas interpretações; quem consulta escolhe a coluna.
- Se o docente esperar a outra regra, a resposta já está no data mart.

**Contras**
- Duas colunas com o mesmo nome conceptual podem confundir; o relatório tem de dizer qual foi usada na análise 6.
- Com a regra ISO é preciso também o "ano da semana ISO" (ver contras da Opção A).

**Recomendação:** Opção A (ISO), justificando no relatório. A Opção D é uma alternativa segura se quisermos cobrir as duas interpretações.
**Raphael:** Iria pela D, pois ficamos abertos a opções e as duas interpretaçõs como a propria recomendação acima
**Ellah:** Concordo com a D. Como o enunciado não define a regra, ter as duas colunas custa pouco e cobre as duas interpretações. Temos de incluir também o ano da semana ISO e dizer no relatório qual das colunas usámos na análise 6.

---

## DD7 - Estação do ano: astronómica ou meteorológica?

**Contexto.** A análise 8 pede "primavera de 2025". As faturas da amostra vão de 31/01/2025 a 01/05/2025, por isso a definição muda o resultado:

| Regra | Primavera 2025 |
|---|---|
| Astronómica (equinócio a solstício) | 20/03 a 20/06/2025 |
| Meteorológica (meses completos) | 01/03 a 31/05/2025 |
| Astronómica com datas fixas (aproximação) | 21/03 a 20/06/2025 |

> **O enunciado não define a regra.** Diz apenas "primavera de 2025". A escolha é nossa e tem de ser justificada no relatório (ou confirmada com o docente).

### Opção A - Astronómica

**Prós**
- É o significado comum de "primavera" em Portugal (calendário civil).

**Contras**
- As datas de início mudam de ano para ano (19, 20 ou 21 de março), é preciso uma tabela ou regra por ano ao gerar a DimData.

### Opção B - Meteorológica

**Prós**
- Simples: cada estação são 3 meses completos. Fácil de gerar.

**Contras**
- Menos intuitiva para quem lê o relatório.

### Opções usadas pelos grupos do ano passado

O enunciado de 2025/26 também tinha uma análise por estação ("primavera e verão") e cada grupo usou uma regra diferente, sem a documentar. As duas abordagens são alternativas válidas que podemos seguir:

#### Opção B usada pelo grupo 1221715/1211152 - Meteorológica

A coluna `Season` da DimData deles (`Files/DimDate.csv`, carregada por `LoadTemporalDimensions.dtsx`) muda sempre no dia 1 do mês: Inverno = dez–fev, Primavera = mar–mai, Verão = jun–ago, Outono = set–nov. É exatamente a Opção B acima, com os mesmos prós e contras.

#### Opção C - Astronómica com datas fixas (grupo 1210990/1211572)

O script deles (`ARMDD_25-26-main/Parte_2/SQL Files/Data Mart/Creates/11_script_date.sql`) usa sempre as mesmas datas em todos os anos: Primavera 21/03–20/06, Verão 21/06–20/09, Outono 21/09–20/12, Inverno 21/12–20/03.

**Prós**
- Próxima do significado comum de "primavera" (Opção A), mas com uma regra simples de gerar (um `CASE` sobre mês e dia, sem tabela por ano).

**Contras**
- É uma aproximação: as datas reais mudam de ano para ano. Em 2025 o equinócio foi a **20/03**, por isso as vendas desse dia ficariam no inverno.
- Tem de ficar explícito no relatório que é uma aproximação.

Antes de escolher esta opção, verificar se há faturas nesse dia (se der 0, a Opção C dá o mesmo resultado que a A na amostra):

```sql
SELECT COUNT(*) FROM invoices WHERE invoice_date = '2025-03-20';
```

**Recomendação:** Opção A, com as datas exatas de cada ano no script que gera a DimData. A escolha tem de ficar explícita no relatório (é o tipo de detalhe que o docente pode perguntar na discussão).
**Raphael:** Eu iria pela opção B. Fica mais facil de definir e aqui não vejo pq ter muito trabalho.
**Ellah:** Concordo com a B. Verifiquei que não há faturas entre 01/03 e 20/03/2025, que é o único período onde as duas regras diferem na amostra, por isso a escolha não altera o resultado da análise 8. Fica a meteorológica por ser a mais simples de gerar, mas temos de referir no relatório que com outros dados o resultado poderia mudar.
---

## DD8 - Hierarquia de chefia dos empregados

**Contexto.** `employees.chief` aponta para outro empregado (auto-relação). O profiling encontrou 2 níveis e 2 raízes (dois empregados sem chefe). As análises 3 e 4 usam o empregado, nenhuma usa o chefe, mas é uma hierarquia natural para as análises à escolha.

### Opção A - Achatar: coluna `Chefe` (nome do chefe) na DimEmpregado

Cada empregado guarda o nome do seu chefe. Os empregados sem chefe ficam com o próprio nome ou com "Sem chefe".

**Prós**
- Simples de consultar e de usar no Power BI (hierarquia Chefe → Empregado normal).
- Adequado porque a hierarquia tem poucos níveis e são fixos.

**Contras**
- Se a hierarquia crescer (mais níveis), é preciso acrescentar colunas.

### Opção B - Pai-filho: guardar a chave do chefe (auto-referência na DimEmpregado)

**Prós**
- Suporta qualquer número de níveis.

**Contras**
- Power BI trata hierarquias pai-filho mal (precisa de funções DAX como `PATH`).
- Complica o SCD: se o chefe tiver uma nova versão, a referência dos subordinados tem de ser atualizada.

**Recomendação:** Opção A.
**Raphael:** Menos trabalho, iria pela A mesmo.
**Ellah:** Opção A. A hierarquia tem só 2 níveis fixos. Os 2 empregados sem chefe ficam com "Sem chefe".

---

## DD9 - Moeda: dimensão própria ou atributo?

**Contexto.** Na amostra só existe euro (gravado como `EURO`), mas o enunciado exige preparar o data mart para outras moedas (expansão para o Reino Unido, GBP), com o euro como moeda de uniformização. A BD não tem taxas de câmbio. **A forma de converter para euro (taxa na fato vs tabela de câmbios) é decidida na etapa dos factos**; aqui decide-se só onde fica a moeda.

### Opção A - DimMoeda (código ISO, nome, símbolo), com chave na fato

**Prós**
- Responde explicitamente ao requisito da expansão, o que fica bem justificado no relatório.
- Mapeia `EURO` para o código ISO `EUR`, normalizando os dados.
- Base natural para uma futura tabela de câmbios (ligada à DimMoeda e à DimData).

**Contras**
- Com uma só moeda, é uma dimensão de uma linha.

### Opção B - Coluna `CodigoMoeda` na fato (degenerada)

**Prós**
- Mais simples.

**Contras**
- Sem sítio para nome e símbolo da moeda, nem ponto de ligação para câmbios.
- Fica menos evidente que o modelo foi pensado para várias moedas.

**Recomendação:** Opção A.
**Raphael:** Opção A tambem pois estamos pensando já na expansão para outras moedas.
**Ellah:** Opção A, pelo requisito da expansão para o Reino Unido. Também serve para mapear o valor `EURO` da fonte para o código ISO `EUR`.

---

## DD10 - Registos incompletos nas dimensões

**Contexto.** O profiling encontrou:
- 12 produtos sem família, categoria, fornecedor, designação e/ou IVA (P5). **Nenhum foi vendido.**
- 4 clientes "técnicos" com NIF inválido (`0`, `00`, `000000000`, vazio), sem zona e/ou sem cidade (P6). **Nenhum tem vendas.**

O enunciado diz que registos com problemas de qualidade que não se possam corrigir automaticamente **não devem ser carregados** e devem ir para tabelas de erro na staging area.

### Opção A - Carregar com "Desconhecido" nos atributos em falta

**Prós**
- Se no futuro houver uma venda destes produtos/clientes, a linha de factos carrega sem problemas.
- Prática comum em Kimball (nunca ter nulos nas dimensões).

**Contras**
- Pode contrariar o enunciado, que manda filtrar registos com problemas.
- Os clientes técnicos (NIF inválido) provavelmente não são clientes reais e poluem a dimensão.

### Opção B - Rejeitar para a tabela de erros

**Prós**
- Cumpre o enunciado à letra.
- Dimensões só com dados limpos.

**Contras**
- Se no futuro houver uma venda de um produto rejeitado, a linha de factos também tem de ser rejeitada (não encontra o produto).

### Opção C - Mista

Distinguir pelo tipo de falha:
- **Atributo descritivo em falta** (ex.: produto sem família): carregar com "Desconhecido", porque o registo é válido e a família é só um nível de agrupamento.
- **Atributo identificador inválido ou registo sem significado** (ex.: cliente com NIF `0` e sem zona): rejeitar para a tabela de erros.

**Prós**
- Equilíbrio entre o enunciado e a prática de Kimball; cada caso justificado.

**Contras**
- É preciso definir e documentar a regra para cada atributo (feito de qualquer forma na etapa dos mapeamentos).

**Recomendação:** Opção C. Independentemente da escolha, cada dimensão tem uma linha "Desconhecido" (chave -1) para não haver nulos nas chaves da tabela de factos.
**Raphael:** Iria pela C e analisamos cada caso individualmente
**Ellah:** Opção C. Concordo em analisar caso a caso: produtos sem família/categoria/fornecedor carregam com "Desconhecido" (o registo é válido), e clientes técnicos com NIF inválido e sem zona vão para a tabela de erros.