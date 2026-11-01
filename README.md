# ARMDD 2026/2027 — Data Mart de Vendas More Rhythm, SA

Trabalho prático de Armazéns de Dados (Mestrado em Engenharia Informática, ISEP).

**Grupo:** 1231478 - Ellah Fleischmann | 1260464 - Raphael Moragas
**Docente PL:** Paulo Oliveira (pjo@isep.ipp.pt)

## Objetivo
Data mart para análise histórica das vendas (faturação) a clientes, ao nível da linha de fatura, com processo ETL incremental em SSIS e análises em Power BI.

## Estrutura do repositório
| Pasta | Conteúdo |
|---|---|
| `docs/` | Relatórios, modelo dimensional, mapeamentos, SCD, data profiling, registo de decisões |
| `sql/01_staging` | Criação da staging area (tabelas de staging, erro e controlo) |
| `sql/02_datamart` | Criação das dimensões e tabela de factos |
| `sql/03_profiling` | Queries de análise de qualidade dos dados |
| `sql/04_analises` | Queries das 20 análises multidimensionais |
| `ssis/` | Integration Services Project |
| `config/` | Ficheiro de parametrizações (servidores e bases de dados) |
| `powerbi/` | Relatório Power BI (formato .pbip) |

## Como executar
1. Restaurar a BD operacional (não incluída no repositório).
2. Executar os scripts de `sql/01_staging` e `sql/02_datamart`, por ordem.
3. Ajustar `config/MoreRhythm.dtsConfig` (servidor/BD de origem, servidor do DM e staging, nomes das BDs).
4. Executar `ssis/MoreRhythm_ETL/00_Master.dtsx`.

## Entregas
- **1ª parte** (relatório PDF): 15/11/2026, 23h59
- **2ª parte** (relatório final + projeto SSIS, ZIP): 13/12/2026, 23h59

## Convenções
- Branches: `feat/<tarefa>`, `docs/<tarefa>`, `fix/<tarefa>`; integração na `main` por pull request.
- Packages e scripts com prefixo numérico indicando a ordem de execução.