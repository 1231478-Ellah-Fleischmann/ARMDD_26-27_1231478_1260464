RELATÓRIO TÉCNICO


Mestrado em Engenharia Informática
Armazéns de Dados (ARMDD)
Ano letivo 2026/2027



Trabalho Prático
Data Mart de Vendas da More Rhythm, SA










Desenvolvido por:
Ellah Fleischmann (1231478)
Raphael Moragas (1260464)




Porto, novembro de 2026
Índice
1. Introdução …………………………………………………………………………….
1.1 Contexto e objetivo ………………………………………………………………….
1.2 Desafio ………………………………………………………………………………
1.3 Fonte dos dados …………………………………………………………………….
1.4 Metodologia e ferramentas ………………………………………………………….
1.5 Estrutura do relatório ……………………………………………………………….
2. Arquitetura do armazém de dados …………………………………………………
2.1 Fontes de dados …………………………………………………………………
2.2 Staging area ……………………………………………………………………
2.3 Data Mart ………………………………………………………………………
2.4 Camada de apresentação …………………………………………………………
2.5 Processo de ETL e carga incremental ……………………………………………
2.6 Parametrização …………………………………………………………………
2.7 Repositório e organização do projeto …………………………………………
3. Fonte de dados e data profiling …………………………………………………
3.1 Caracterização da fonte …………………………………………………………
3.2 Regras de negócio inferidas ……………………………………………………
3.3 Problemas de qualidade e tratamento ……………………………………………
3.4 Casos analisados e não tratados como problemas ………………………………
4. Análise dimensional ………………………………………………………………
4.1 Processo de negócio ……………………………………………………………
4.2 Grão ……………………………………………………………………………
4.3 Dimensões ………………………………………………………………………
4.4 Factos …………………………………………………………………………
4.5 Matriz de barramento ……………………………………………………………
5. Modelo dimensional ………………………………………………………………
5.1 Visão geral ……………………………………………………………………
5.2 FactVendas ………………………………………………………………………
5.3 DimData …………………………………………………………………………
5.4 DimCliente ………………………………………………………………………
5.5 DimProduto ………………………………………………………………………
5.6 DimFornecedor ……………………………………………………………………
5.7 DimEmpregado ……………………………………………………………………
5.8 DimMoeda …………………………………………………………………………
5.9 Tipos de dados …………………………………………………………………

 1. Introdução
Este relatório é referente à primeira parte do trabalho prático da unidade curricular de Armazéns de Dados (ARMDD), do Mestrado em Engenharia Informática, no ano letivo 2026/2027. Neste projeto iremos desenvolver um Data Mart a partir dos dados das vendas (faturação) da More Rhythm, SA, uma empresa de distribuição e comercialização de instrumentos musicais com sede no Porto.
Esta primeira parte do projeto trata da análise e do desenho da solução: a arquitetura do armazém de dados, o modelo dimensional, as estruturas de dados da staging area e os mapeamentos de dados. A implementação, com os processos de extração, transformação, limpeza e carregamento dos dados (Extract, Transform, Load ou ETL), fica para a segunda parte.

1.1 Contexto e objetivos
A More Rhythm, SA, como já introduzida anteriormente, é uma empresa líder, a nível nacional, na distribuição e comercialização de instrumentos musicais, com sede no Porto. As suas vendas abrangem todo o território nacional e, pontualmente, Espanha. O sistema informático da empresa suporta as atividades operacionais, nomeadamente as vendas e a faturação, as compras e a gestão de stocks.
A gestão da empresa pretende implementar um Data Mart que permita realizar análises históricas das vendas efetuadas aos seus clientes. Para dar a maior flexibilidade possível a essas análises, o Data Mart tem de possibilitar consultas ao nível de granularidade mais elementar, assim como indicado no enunciado do projeto. Além disso, o Data Mart tem de acompanhar a evolução prevista da empresa, que pretende expandir as operações para outros países da União Europeia e abrir a primeira sucursal no estrangeiro, no Reino Unido.

1.2 Desafios
Os dados do sistema operacional e os requisitos da empresa colocam os seguintes desafios ao desenvolvimento do Data Mart:
• Registos duplicados. A limpeza dos dados tem de eliminar todas as redundâncias, sejam registos iguais ou aproximadamente iguais. O caso assinalado no enunciado é o dos clientes: o mesmo cliente pode estar registado com identificadores diferentes, e os registos duplicados nem sempre são rigorosamente iguais.
• Qualidade dos dados. Os dados podem ter valores em falta em atributos de preenchimento obrigatório, valores que violam o domínio dos atributos e violações de restrições de integridade. Os registos cuja correção não seja automatizável não serão carregados no Data Mart e devem ficar guardados em tabelas de erros na staging area.
• Custos de expedição. Estão registados ao nível da fatura, e não ao nível de cada linha ou produto.
• Várias moedas. Atualmente, todas as vendas são faturadas em euros. A expansão para o Reino Unido trará vendas em outra moeda, e as análises que envolvam moedas diferentes têm de usar o Euro como moeda de uniformização.
• Carga incremental. O sistema operacional regista a data e a hora em que cada registo é inserido e alterado. A carga das dimensões e dos factos tem de ser incremental: em cada execução, só são carregados os dados novos e atualizados os que sofreram alterações.
• Volume e eficiência. A amostra disponibilizada é pequena, mas é representativa de um volume real de registos bastante elevado. Por isso, todo o processo de ETL tem de ser o mais eficiente possível.
• Parametrização. O projeto de Integration Services não pode ter caminhos absolutos. Os caminhos, os nomes dos servidores e os nomes das bases de dados são definidos num ficheiro de parametrizações.

1.3 Fonte dos dados
A fonte dos dados é a base de dados operacional MoreRhythm, em Microsoft SQL Server 2025, disponibilizada como uma amostra dos dados reais (ficheiros MoreRhythm.mdf e MoreRhythm_log.ldf). As suas 12 tabelas cobrem três processos de negócio: vendas (invoices e invoices_lines), compras (purchases e purchases_lines) e movimentos de stock (stocks_movements). As restantes sete tabelas guardam os dados mestre: clientes, fornecedores, funcionários, produtos, famílias, categorias e zonas. A amostra tem 37 faturas, com 93 linhas, emitidas entre 31 de janeiro e 1 de maio de 2025.
Antes do desenho do Data Mart, foi feito um data profiling sobre a amostra. Este processo permitiu inferir as regras de negócio presentes nos dados e identificar os problemas de qualidade a tratar, que serão apresentados mais à frente, no capítulo 3.

1.4 Metodologia e ferramentas
O desenho do Data Mart, como indicado no enunciado, irá seguir a metodologia de Kimball. A análise dimensional percorre os quatro passos do desenho dimensional: escolher o processo de negócio, declarar o grão, identificar as dimensões e identificar os factos. Todas as opções tomadas na criação do modelo dimensional vão ser justificadas ao longo do relatório.
O trabalho usa as seguintes ferramentas:
•	Microsoft SQL Server, para a base de dados fonte, a staging area e o Data Mart. A staging area e o Data Mart ficam no mesmo servidor.
• SQL Server Integration Services (SSIS), num Integration Services Project do Visual Studio, para os processos de ETL.
• Power BI, para as 20 análises multidimensionais: 10 indicadas pela gestão da empresa e 10 escolhidas pelo grupo, com graus de dificuldade diferentes e incidindo sobre as hierarquias do modelo.
• GitHub, no repositório ARMDD_26-27_1231478_1260464, onde ficam a documentação e o projeto SSIS, desenvolvidos em colaboração pelos dois elementos do grupo.

1.5 Estrutura do relatório
Para além desta introdução, o relatório tem mais sete capítulos:
• No capítulo 2 apresentamos a arquitetura do armazém de dados, desde a fonte até ao Power BI.
• Já no capítulo 3 caracterizamos a base de dados fonte e apresentamos os resultados do data profiling.
• O capítulo 4 descreve a análise dimensional, segundo os quatro passos da metodologia de Kimball.
• O capítulo 5 apresenta o modelo dimensional, com os atributos e os tipos de dados da tabela de factos e de cada dimensão.
• O capítulo 6 define as estruturas de dados da staging area (tabelas e ficheiros).
• O capítulo 7 descreve os mapeamentos de dados da fonte para a staging area e da staging area para o Data Mart, incluindo a estratégia de Slowly Changing Dimension (SCD) e as transformações e limpezas de cada atributo.
• Por fim, o capítulo 8 apresenta as conclusões, as limitações do trabalho e as melhorias possíveis.

 2. Arquitetura do armazém de dados
A arquitetura tem quatro camadas: as fontes de dados, a staging area, o Data Mart e a camada de apresentação. Os dados passam entre elas através de processos de ETL em SQL Server Integration Services (SSIS), e todas as bases de dados ficam em SQL Server 2025 (Figura 1).

**ADICIONAR A FIGURA 1**
Figura 1 – Arquitetura do armazém de dados da More Rhythm

2.1 Fontes de dados
A fonte principal é a base de dados operacional MoreRhythm. Das suas 12 tabelas extraímos apenas as 9 das vendas (invoices, invoices_lines, customers, employees, products, families, categories, suplliers e zones). As compras e os movimentos de stock não nos interessam no momento, sendo outros processos de negócio e ficam fora deste âmbito.
Como a base de dados não tem taxas de câmbio e o Euro tem de ser a moeda de uniformização, as taxas vêm do BCE (retiradas no dia 2 de Novembro de https://data.ecb.europa.eu/data/datasets/EXR/EXR.Q.GBP.EUR.SP00.A). Descarregamos a série diária da libra (EXR.D.GBP.EUR.SP00.A) para o ficheiro ECB Data EUR GBP.csv, que tem a data, a data por extenso e a taxa de conversão. Esta taxa indica quantas libras valem 1 euro, ou seja, o valor em euros é o valor em libras dividido pela taxa da data da fatura. O euro tem taxa 1 e não aparece no ficheiro. Como o BCE só publica taxas nos dias úteis, para os fins de semana e feriados usamos a taxa do último dia útil anterior, e as linhas sem valor (feriados até 2012) são ignoradas.
A terceira fonte é o DimDate.csv, gerado uma única vez como nos exercícios das aulas. Além do dia, mês, trimestre, semestre e ano, tem a semana padrão do SQL Server e a semana ISO 8601 (com o ano ISO), a estação meteorológica, o quadrimestre e os indicadores de último dia do mês e de fim de semana. O intervalo cobre as datas de fatura e de pagamento e os anos futuros. Os ficheiros externos ficam na pasta Files do projeto (secção 2.6).

2.2 Staging area
A staging area é a base de dados MoreRhythm_StagingArea, no mesmo servidor do Data Mart. Assim o sistema operacional é lido uma única vez por execução e todo o tratamento é feito fora dele. A mesma vai ser organizada em duas camadas de dados e dois grupos de tabelas de apoio.
A camada 1 (RAW_) recebe os dados tal como estão na fonte, com os mesmos tipos e as colunas de auditoria. A camada 2 (TR_) recebe os dados já limpos, deduplicados e integrados, prontos para o Data Mart. As duas só têm os registos da carga incremental de cada execução e são esvaziadas no início. Já as tabelas de erros (ERR_) guardam os registos que não podem ser corrigidos automaticamente, com o motivo e a data da execução, e acumulam os erros de todas as execuções. Ter duas camadas permite comparar o dado original com o tratado e perceber em que passo um registo foi alterado ou rejeitado.
As tabelas auxiliares são persistentes. A ETL_Control guarda a marca d'água de cada tabela, ou seja, a data e hora do registo mais recente já extraído com sucesso (secção 2.5). A AUX_CustomerMap guarda a correspondência entre cada cliente e o seu grupo de duplicados, e é necessária porque as camadas 1 e 2 só têm os registos da carga incremental e um cliente novo tem de ser comparado também com os já carregados. A AUX_ExchangeRate tem a taxa de cada moeda para todos os dias do calendário, a AUX_Currency tem as moedas e o mapeamento "EURO" → "EUR", e a LOG_InvoiceDifference regista as faturas em que a soma das linhas difere do cabeçalho. As estruturas detalhadas estão no capítulo 6.


2.3 Data Mart
O Data Mart é a base de dados MoreRhythm_DataMart. Segue a metodologia de Kimball, com dimensões e uma tabela de factos de vendas ao nível da linha de fatura (capítulos 4 e 5). Só o ETL escreve no Data Mart: os utilizadores e o Power BI apenas o leem.

2.4 Camada de apresentação
O Power BI liga-se apenas ao Data Mart e é onde são feitas as 20 análises multidimensionais, com drill down e roll up pelas hierarquias.

2.5 Processo de ETL e carga incremental
A carga é incremental, como pede o enunciado deste projeto. Em cada execução, o ETL lê na ETL_Control a marca d'água de cada tabela e extrai só os registos criados ou alterados depois dela. Como a data e a hora estão em colunas separadas, são juntadas num único valor, e usamos sempre a maior entre a criação e a alteração, porque 8 fornecedores e 8 produtos têm a alteração anterior à criação. As tabelas zones e categories não têm colunas de auditoria e, por isso, são extraídas por inteiro, tal como os ficheiros externos, dos quais só se inserem as datas novas.
Nas faturas, o cliente, o empregado, as datas, a moeda e o frete estão no cabeçalho, mas o grão é a linha. Logo, extraímos as linhas cuja própria alteração ou a do cabeçalho seja posterior à marca d'água, e se o cabeçalho mudar todas as suas linhas são reprocessadas. Isto é o caso normal: 36 das 37 faturas foram alteradas depois de criadas, até 334 dias depois. Também é preciso propagar as alterações dos atributos desnormalizados, ou seja, uma alteração numa família, categoria, zona ou no nome de um chefe obriga a reprocessar os produtos, clientes, fornecedores ou empregados afetados.
As dimensões são carregadas antes dos factos, com a estratégia de SCD de cada atributo. Nos factos, cada chave natural é trocada pela chave substituta da versão válida na data da fatura, e as linhas de cada fatura alterada são apagadas e reinseridas, o que trata também linhas acrescentadas ou apagadas. A fatura é identificada pelo invoice_stamp_id completo, porque o prefixo antes da vírgula não é único. No fim de uma execução bem-sucedida a marca d'água é atualizada, e se a execução falhar a seguinte volta a extrair os mesmos registos. A estrutura da ETL_Control está na Tabela 1, onde o datetime2(7) tem a mesma precisão das colunas time(7) da fonte, para nenhum registo ser ignorado por arredondamento.

Tabela 1 – Estrutura da tabela ETL_Control

| Coluna | Tipo | Descrição |
| --- | --- | --- |
| TableName | varchar(50) | Nome da tabela fonte (chave primária) |
| LastExtractedAt | datetime2(7) | Maior data e hora de criação ou de alteração extraída com sucesso (marca d'água) |
| LastRunAt | datetime2(0) | Data e hora da última execução bem-sucedida |
| RowsExtracted | int | Número de registos extraídos nessa execução |


2.6 Parametrização
Para não existirem caminhos absolutos, a configuração fica nos parâmetros do projeto SSIS (Project.params), como no exercício das aulas (Tabela 2). As ligações e os caminhos dos ficheiros são expressões sobre estes parâmetros, por exemplo @[$Project::PackagePath] + "\\Files\\ECB Data EUR GBP.csv". Para instalar o projeto noutro computador basta mudar os valores. Acrescentámos o servidor e a base de dados da fonte, que o enunciado também pede.

Tabela 2 – Parâmetros do projeto SSIS

| Parâmetro | Tipo | Valor de exemplo | Utilização |
| --- | --- | --- | --- |
| SourceServerName | String | (local) | Servidor da base de dados operacional |
| SourceDBName | String | MoreRhythm | Nome da base de dados operacional |
| ServerName | String | (local) | Servidor do Data Mart e da staging area (o mesmo para ambos) |
| StagingAreaDBName | String | MoreRhythm_StagingArea | Nome da base de dados da staging area |
| DataMartDBName | String | MoreRhythm_DataMart | Nome da base de dados do Data Mart |
| PackagePath | String | C:\ARMDD\MoreRhythm | Pasta do projeto, onde estão as pastas Files e SQL Scripts |


2.7 Repositório e organização do projeto
Tudo fica no repositório GitHub ARMDD_26-27_1231478_1260464. A pasta do projeto (PackagePath) tem as pastas Files (ficheiros externos), SQL Scripts (criação das tabelas), MoreRhythm ETL (projeto SSIS) e Docs (relatórios, profiling e registo de decisões).

Projeto realizado tendo em vista os trabalhos do ano passado e retrasado