# Diagramas das bases de dados

Diagramas em Mermaid (o GitHub e o VS Code mostram-nos como figuras). Há três BDs:

| BD | Papel | Tabelas |
|---|---|---|
| `MoreRhythm` | Fonte (sistema operacional) | 12 tabelas, ligadas por chaves estrangeiras |
| `MoreRhythm_SA` | Staging area (capítulo 6) | 22 tabelas, sem chaves estrangeiras: as ligações são feitas pelo ETL |
| `MoreRhythm_DM` | Data mart (capítulo 5) | 6 dimensões + 1 tabela de factos, em estrela |

## 1. Visão geral do fluxo

Igual à Figura 1 do relatório.

```mermaid
---
config:
  layout: elk
---
flowchart LR
    subgraph FONTE["1 - Fontes de dados"]
        MR[("BD operacional<br/>MoreRhythm<br/>SQL Server 2025")]
        ECB["Taxas de câmbio do BCE<br/>ficheiro CSV"]
    end

    subgraph STG["2 - Staging area (MoreRhythm_SA)"]
        CTRL["ETL_Control<br/>data da última extração<br/>de cada tabela"]
        RAW["Extração: E_*<br/>dados como na fonte"]
        TR["Transformação: T_*<br/>limpos, deduplicados<br/>e integrados"]
        ERR["ERR_Clientes<br/>ERR_Fornecedores<br/>registos rejeitados"]
        LOG["LOG_DiferencasFatura"]
        MAP["MAP_Cliente<br/>MAP_Moeda"]
    end

    subgraph DM["3 - Data Mart (MoreRhythm_DM)"]
        SCR["Script SQL<br/>(DimData)"]
        DIM["Dimensões<br/>DimData, DimCliente,<br/>DimProduto, DimFornecedor,<br/>DimEmpregado, DimMoeda"]
        FACT["FactVendas<br/>grão: linha de fatura"]
    end

    subgraph APR["4 - Apresentação"]
        PBI["Power BI<br/>20 análises"]
    end

    MR -- "carga incremental" --> RAW
    ECB -- "ficheiro completo" --> RAW
    CTRL <-. "lê / atualiza" .-> RAW

    RAW -- "limpeza e transformação" --> TR
    RAW -. "não corrigíveis" .-> ERR
    RAW -. "correções P1, P2 e P3" .-> LOG
    MAP <-. "duplicados e moedas" .-> TR

    SCR -. "gerada uma vez" .-> DIM
    TR -- "1.º carga das dimensões<br/>(SCD e criação das SK)" --> DIM
    TR -- "2.º carga dos factos" --> FACT
    DIM -. "lookup das SK" .-> FACT

    FACT -- "só leitura" --> PBI
```

## 2. Fonte: MoreRhythm

Chaves estrangeiras definidas na BD da fonte. As tabelas de compras e de stocks não são usadas no data mart de vendas. Só aparecem as colunas usadas, mais as chaves.

```mermaid
erDiagram
    zones ||--o{ customers : "zone"
    zones ||--o{ suplliers : "zone"
    customers ||--o{ invoices : "customer"
    employees ||--o{ invoices : "employee"
    employees |o--o{ employees : "chief"
    invoices ||--|{ invoices_lines : "invoice_stamp_id"
    products ||--o{ invoices_lines : "product"
    families |o--o{ products : "family"
    categories |o--o{ products : "category"
    suplliers |o--o{ products : "supplyer"
    suplliers ||--o{ purchases : "supplier"
    employees ||--o{ purchases : "employee"
    zones ||--o{ purchases : "zone"
    purchases ||--|{ purchases_lines : "purchase_stamp"
    products |o--o{ purchases_lines : "product"
    products ||--o{ stocks_movements : "product"

    zones {
        numeric code PK
        varchar zone
    }
    customers {
        numeric number PK
        varchar name
        varchar taxpayer_number
        varchar clity "bairro ou lugar"
        varchar zip_code "codigo + localidade postal"
        numeric zone FK
        varchar type
        varchar segment
    }
    suplliers {
        numeric number PK
        varchar name
        varchar taxpayer_number
        varchar city
        varchar zip_code
        numeric zone FK
        varchar type
        varchar nationality
    }
    employees {
        numeric number PK
        varchar name
        varchar departament
        numeric chief FK
    }
    families {
        varchar reference PK
        varchar name
        varchar classification
    }
    categories {
        int Code PK
        varchar Category "sem auditoria"
    }
    products {
        char reference PK
        char designation
        varchar family FK
        int category FK
        numeric supplyer FK
        numeric vat_rate
        numeric current_sell_price
        numeric last_cost_price
    }
    invoices {
        char invoice_stamp_id PK
        date invoice_date
        date payment_date
        numeric customer FK
        numeric employee FK
        varchar currency
        numeric products_total
        numeric total_for_vat
    }
    invoices_lines {
        char invoice_line_stamp_id PK
        char invoice_stamp_id FK
        char product FK
        numeric quantity
        numeric unit_price
        numeric line_total
        numeric line_vat
    }
    purchases {
        char purchase_stamp PK "nao usada"
    }
    purchases_lines {
        char purchase_line_stamp PK "nao usada"
    }
    stocks_movements {
        char stock_movement_stamp PK "nao usada"
    }
```

Todas as tabelas, exceto `zones` e `categories`, têm as colunas de auditoria `create_date`, `create_time`, `last_update_date` e `last_update_time`.

## 3. Staging area: MoreRhythm_SA

A staging não tem chaves estrangeiras. O diagrama mostra que tabelas alimentam cada tabela de transformação e de que forma.

```mermaid
flowchart LR
    subgraph EXT["Extração - esvaziadas em cada execução"]
        rc["E_customers"]
        rs["E_suplliers"]
        re["E_employees"]
        rp["E_products"]
        rf["E_families"]
        rcat["E_categories"]
        rz["E_zones"]
        ri["E_invoices"]
        rl["E_invoices_lines"]
        recb["E_ECB"]
    end

    subgraph TRF["Transformação - esvaziadas em cada execução"]
        tc["T_Cliente"]
        tf["T_Fornecedor"]
        te["T_Empregado"]
        tp["T_Produto"]
        tcam["T_Cambio"]
        tfv["T_FactVendas"]
    end

    subgraph PERS["Persistentes"]
        ctl["ETL_Control"]
        mc["MAP_Cliente"]
        mm["MAP_Moeda"]
        ec["ERR_Clientes"]
        ef["ERR_Fornecedores"]
        lg["LOG_DiferencasFatura"]
    end

    rc --> tc
    rz -- "zona" --> tc
    rc -. "técnicos" .-> ec
    rc <-. "duplicados" .-> mc
    mc --> tc

    rs --> tf
    rz -- "zona" --> tf
    rs -. "técnicos" .-> ef

    re --> te

    rp --> tp
    rf -- "família" --> tp
    rcat -- "categoria" --> tp

    recb -- "todos os dias" --> tcam
    mm -- "euro = 1" --> tcam

    ri --> tfv
    rl --> tfv
    mc -- "cliente do grupo" --> tfv
    mm -- "código ISO" --> tfv
    tcam -- "taxa da data da fatura" --> tfv
    ri -. "correções P1, P2 e P3" .-> lg
    rl -.-> lg

    ctl -. "marca d'água de cada tabela" .-> EXT
```

## 4. Data mart: MoreRhythm_DM

Estrela com a FactVendas ao centro. A DimData é usada duas vezes (role-playing). Todas as dimensões têm a linha -1 "Desconhecido".

```mermaid
erDiagram
    DimData ||--o{ FactVendas : "DataFaturaKey"
    DimData ||--o{ FactVendas : "DataPagamentoKey"
    DimCliente ||--o{ FactVendas : "ClienteKey"
    DimProduto ||--o{ FactVendas : "ProdutoKey"
    DimFornecedor ||--o{ FactVendas : "FornecedorKey"
    DimEmpregado ||--o{ FactVendas : "EmpregadoKey"
    DimMoeda ||--o{ FactVendas : "MoedaKey"

    FactVendas {
        bigint VendaKey PK
        int DataFaturaKey FK
        int DataPagamentoKey FK
        int ClienteKey FK
        int ProdutoKey FK
        int FornecedorKey FK
        int EmpregadoKey FK
        int MoedaKey FK
        varchar NumeroFatura "dimensao degenerada"
        numeric Quantidade
        numeric PrecoUnitario
        numeric ValorProdutos
        numeric ValorIVA
        numeric ValorFrete
        numeric ValorSemIVA
        numeric ValorComIVA
        numeric PrecoUnitarioEUR
        numeric ValorProdutosEUR
        numeric ValorIVAEUR
        numeric ValorFreteEUR
        numeric ValorSemIVAEUR
        numeric ValorComIVAEUR
        numeric TaxaCambio
    }
    DimData {
        int DataKey PK "AAAAMMDD"
        date Data
        tinyint Dia
        tinyint DiaSemana
        varchar NomeDiaSemana
        bit FimDeSemana
        bit UltimoDiaMes
        tinyint SemanaAno
        tinyint SemanaISO
        smallint AnoSemanaISO
        tinyint Mes
        varchar NomeMes
        tinyint Trimestre
        tinyint Quadrimestre
        tinyint Semestre
        smallint Ano
        varchar Estacao
        smallint AnoEstacao
    }
    DimCliente {
        int ClienteKey PK
        bigint ClienteID "chave natural"
        varchar Nome
        varchar NIF
        varchar CodigoPostal
        varchar Cidade
        varchar Localidade
        varchar Zona
        varchar Pais
        varchar TipoCliente
        varchar Segmento
        date DataInicio "SCD 2"
        date DataFim "SCD 2"
        bit Atual "SCD 2"
    }
    DimProduto {
        int ProdutoKey PK
        varchar ProdutoID "chave natural"
        varchar Designacao
        varchar Familia
        varchar DescricaoFamilia
        varchar ClassificacaoFamilia
        varchar Categoria
        numeric TaxaIVA
        numeric PrecoVendaTabela
        numeric CustoTabela
        date DataInicio "SCD 2"
        date DataFim "SCD 2"
        bit Atual "SCD 2"
    }
    DimFornecedor {
        int FornecedorKey PK
        bigint FornecedorID "chave natural"
        varchar Nome
        varchar NIF
        varchar CodigoPostal
        varchar Cidade
        varchar Localidade
        varchar Zona
        varchar Pais
        varchar TipoFornecedor
        date DataInicio "SCD 2"
        date DataFim "SCD 2"
        bit Atual "SCD 2"
    }
    DimEmpregado {
        int EmpregadoKey PK
        int EmpregadoID "chave natural"
        varchar Nome
        varchar Grupo
        varchar Departamento
        varchar Chefe
        date DataInicio "SCD 2"
        date DataFim "SCD 2"
        bit Atual "SCD 2"
    }
    DimMoeda {
        int MoedaKey PK
        char CodigoISO "chave natural"
        varchar Nome
        varchar Simbolo
    }
```

## 5. Da fonte ao data mart, por tabela

| Data mart | Staging (transformação) | Fonte |
|---|---|---|
| DimData | (gerada por script) | - |
| DimCliente | `T_Cliente` + `MAP_Cliente` | `customers` + `zones` |
| DimProduto | `T_Produto` | `products` + `families` + `categories` |
| DimFornecedor | `T_Fornecedor` | `suplliers` + `zones` |
| DimEmpregado | `T_Empregado` | `employees` (chefe: a própria `employees`) |
| DimMoeda | `MAP_Moeda` | `invoices.currency` |
| FactVendas | `T_FactVendas` + `T_Cambio` | `invoices` + `invoices_lines` (+ `products.supplyer`) + CSV do BCE |