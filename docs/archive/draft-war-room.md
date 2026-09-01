# Reenquadramento: construir um motor de draft, não uma plataforma

A arquitetura anterior estava adequada para um produto multiusuário e evolutivo, mas ficou excessiva para este caso:

* aplicação experimental;
* usada por uma pessoa;
* execução local;
* apenas um draft por vez;
* cerca de 168 escolhas;
* dados previamente preparados;
* necessidade de resposta quase instantânea.

Eu substituiria a solução anterior por este princípio:

> **Um núcleo funcional em R, dois arquivos RDS operacionais, um terminal como primeira interface e um Shiny fino como segunda interface.**

O terminal não seria um protótipo descartável. Ele seria simultaneamente:

1. o primeiro produto utilizável;
2. o ambiente de simulação;
3. a especificação executável do mecanismo;
4. o fallback operacional caso o Shiny apresente algum problema no dia do draft.

---

# 1. Arquitetura simplificada

```text
                       PRÉ-DRAFT
                           │
                           ▼
                scripts/prepare.R
                           │
             ┌─────────────┴─────────────┐
             │                           │
             ▼                           ▼
     ffanalytics::scrape_data()   regras de pontuação
             │                     Full PPR customizadas
             └─────────────┬─────────────┘
                           ▼
              ffanalytics::projections_table()
                           │
                    add_player_info()
                           │
                       add_adp()
                           │
                           ▼
                 data/projections.rds
                     snapshot imutável
                           │
            ┌──────────────┴──────────────┐
            │                             │
            ▼                             ▼
     scripts/simulate.R             scripts/draft.R
      mocks em lote                 terminal interativo
            │                             │
            └──────────────┬──────────────┘
                           ▼
                       R/core.R
                  R/recommendation.R
                    R/simulation.R
                           │
                           ▼
                    state/draft.rds
                           │
                           ▼
                         app.R
                     interface Shiny
```

A aplicação live não chama `ffanalytics`, não acessa internet e não recalcula projeções.

Durante o draft, ela só:

1. lê aproximadamente algumas centenas de jogadores;
2. registra uma escolha;
3. remove esse jogador dos disponíveis;
4. deriva os rosters;
5. calcula o próximo pick do usuário;
6. ordena algumas dezenas de candidatos;
7. salva um pequeno RDS.

Isso é trivialmente pequeno para R.

---

# 2. Como aproveitar corretamente o `ffanalytics`

## 2.1 O pacote já entrega a camada estática

O `projections_table()` recebe o resultado de `scrape_data()` e aceita diretamente:

* regras de pontuação customizadas;
* pesos por fonte;
* baseline de VOR;
* thresholds de tiers;
* método de agregação `average`, `robust` ou `weighted`;
* retorno opcional de estatísticas agregadas em vez dos pontos. ([GitHub][1])

Internamente, o pacote primeiro calcula os pontos de cada fonte conforme as regras da liga e depois agrega os `raw_points` por jogador. A tabela resultante já contém:

```text
id
pos
points
sd_pts
floor
ceiling
dropoff
points_vor
floor_vor
ceiling_vor
rank
floor_rank
ceiling_rank
pos_rank
tier
```

O VOR é calculado em relação a um jogador de referência por posição, e o tier é derivado dos drop-offs de pontos normalizados pela dispersão observada nas fontes. ([GitHub][1])

Portanto, eu eliminaria da solução anterior:

* um Valuation Engine próprio;
* implementação própria de tiers;
* implementação inicial própria de floor/ceiling;
* cálculo próprio de VOR;
* modelo sofisticado de incerteza.

O War Room deve **consumir**, e não recriar, essa camada.

---

## 2.2 Usaria apenas um método de projeção no runtime

Por padrão, o pacote pode gerar `average`, `robust` e `weighted`, produzindo mais de uma linha por jogador. Para o War Room, isso é desnecessário.

Minha escolha inicial seria:

```r
avg_type = "robust"
```

O método robusto reduz a influência de uma fonte muito discrepante e dispensa, no primeiro momento, a discussão sobre os pesos ideais de cada site. O método poderá ser alterado posteriormente para `weighted` sem modificar o motor de draft, pois o contrato do RDS continuará igual. O pacote implementa separadamente média comum, estimador robusto e média ponderada. ([GitHub][1])

Para um jogador existir no snapshot, eu também exigiria pelo menos três projeções válidas. O próprio `projections_table()` avisa que sua finalidade é agregar várias fontes quando encontra menos de três fontes. ([GitHub][1])

---

## 2.3 O que `floor` e `ceiling` realmente representam

No código atual, `floor` e `ceiling` são os quantis de 5% e 95% dos pontos projetados pelas diferentes fontes. `sd_pts` também mede a dispersão entre essas fontes. ([GitHub][1])

Isso significa que eles não são, rigorosamente:

* piso real da temporada;
* teto real da temporada;
* distribuição de lesões;
* distribuição de game scripts;
* intervalo probabilístico completo do jogador.

Eles são melhores interpretados como:

```text
source_low
source_high
source_sd
```

Eu renomearia os campos no snapshot para evitar que o algoritmo trate divergência entre especialistas como uma verdadeira distribuição de resultados esportivos.

Essa informação ainda é útil:

* alta dispersão pode sinalizar incerteza;
* um `source_high` elevado pode desempatar jogadores de banco;
* baixa dispersão pode favorecer uma escolha segura nos primeiros rounds.

Mas o peso deve ser pequeno.

---

# 3. Pontuação customizada: a abordagem mais simples

O pacote permite construir regras com `custom_scoring()` e aceita configurações específicas por posição. Em Full PPR, por exemplo, `rec = 1`; regras para RB, WR e TE também podem ser diferenciadas. Quando uma configuração customizada inclui DST, os brackets de pontos permitidos precisam ser acrescentados separadamente. ([GitHub][2])

Para este projeto, porém, eu faria algo ainda mais simples e menos sujeito a omissões:

```r
scoring_rules <- ffanalytics::scoring

scoring_rules$rec$rec <- 1
scoring_rules$pass$pass_tds <- 4
scoring_rules$pass$pass_int <- -2
scoring_rules$misc$fumbles_lost <- -2

# Ajustar aqui kicker, DST e demais particularidades da liga.
```

Ou seja:

> Copiar as regras completas padrão e sobrescrever somente as diferenças da liga.

Isso preserva automaticamente categorias menos visíveis, como:

* field goals por distância;
* extra points;
* sacks;
* turnovers;
* defensive touchdowns;
* brackets de pontos permitidos.

A configuração exata da liga ficaria em `config.R`, como código R legível e versionado.

---

# 4. Pipeline de preparação

O script `scripts/prepare.R` seria aproximadamente:

```r
library(ffanalytics)
library(dplyr)

cfg <- source("config.R", local = TRUE)$value

scoring_rules <- ffanalytics::scoring
scoring_rules$rec$rec <- 1
scoring_rules$pass$pass_tds <- cfg$scoring$pass_tds
scoring_rules$pass$pass_int <- cfg$scoring$pass_int
scoring_rules$misc$fumbles_lost <- cfg$scoring$fumbles_lost

raw <- ffanalytics::scrape_data(
  src = cfg$projection_sources,
  pos = c("QB", "RB", "WR", "TE", "K", "DST"),
  season = cfg$season,
  week = 0
)

saveRDS(raw, "data/raw_scrape.rds")

projections <- ffanalytics::projections_table(
  data_result = raw,
  scoring_rules = scoring_rules,
  vor_baseline = cfg$vor_baseline,
  avg_type = "robust"
) |>
  ffanalytics::add_player_info() |>
  ffanalytics::add_adp(sources = cfg$adp_sources)

players <- projections |>
  transmute(
    player_id = id,
    player = paste(first_name, last_name),
    nfl_team = team,
    pos,
    points,
    source_sd = sd_pts,
    source_low = floor,
    source_high = ceiling,
    vor = points_vor,
    low_vor = floor_vor,
    high_vor = ceiling_vor,
    overall_rank = rank,
    pos_rank,
    tier,
    adp,
    adp_sd
  )

snapshot <- list(
  schema_version = 1L,
  created_at = Sys.time(),
  season = cfg$season,
  method = "robust",
  scoring = scoring_rules,
  vor_baseline = cfg$vor_baseline,
  players = players
)

saveRDS(snapshot, "data/projections.rds")
```

O `add_adp()` agrega múltiplas fontes e, quando há mais de uma, gera `adp` e `adp_sd`; esse segundo campo é a dispersão entre as fontes de ADP. ([GitHub][1])

## Decisão deliberada: não usar ECR inicialmente

Eu não incluiria no primeiro incremento:

```r
add_ecr()
add_uncertainty()
```

O benefício marginal é pequeno para o MVP, enquanto adiciona:

* mais scraping;
* mais fontes sujeitas a falha;
* mais campos correlacionados;
* mais dificuldade para entender o score.

O próprio `sd_pts` já é suficiente como indicador de divergência entre projeções.

---

# 5. Baseline de VOR

O baseline padrão atual do pacote é:

```r
c(
  QB = 13,
  RB = 35,
  WR = 36,
  TE = 13,
  K = 8,
  DST = 3,
  DL = 10,
  LB = 10,
  DB = 10
)
```

([GitHub][3])

Para a liga descrita, eu manteria inicialmente:

```r
vor_baseline <- c(
  QB = 13,
  RB = 35,
  WR = 36,
  TE = 13,
  K = 13,
  DST = 13
)
```

Os baselines de QB, RB, WR e TE já são plausíveis para uma liga de 12 times com um FLEX e cinco reservas. K e DST não precisam ficar perfeitamente comparáveis porque terão uma regra estratégica explícita: não serão recomendados antes dos rounds finais, salvo necessidade matemática de completar o roster.

O refinamento empírico do baseline deve vir depois dos mocks, não antes da primeira implementação.

---

# 6. Apenas dois RDS operacionais

## 6.1 `data/projections.rds`

Imutável durante o draft:

```r
list(
  schema_version,
  created_at,
  season,
  method,
  scoring,
  vor_baseline,
  players
)
```

O opcional `data/raw_scrape.rds` serve somente para refazer a projeção sem repetir todos os scrapes.

## 6.2 `state/draft.rds`

Única fonte de verdade do draft:

```r
list(
  schema_version = 1L,

  projection_created_at = ...,

  league = list(
    teams = 12L,
    rounds = 14L,
    roster = c(
      QB = 1L,
      RB = 2L,
      WR = 2L,
      TE = 1L,
      FLEX = 1L,
      K = 1L,
      DST = 1L,
      BENCH = 5L
    ),
    flex_positions = c("RB", "WR")
  ),

  team_order = c(
    "Team 1",
    "Team 2",
    "Giuliano",
    ...
  ),

  user_team = "Giuliano",

  seed = 2026L,

  picks = tibble::tibble(
    overall = integer(),
    player_id = character(),
    entered_at = as.POSIXct(character())
  )
)
```

Não armazenaria:

* `current_pick`;
* rosters;
* jogadores disponíveis;
* recomendações;
* posição dentro do round;
* próximo pick do usuário.

Tudo isso é derivado.

Por exemplo:

```r
current_pick <- nrow(state$picks) + 1L
```

Esse princípio evita quase todos os problemas de sincronização:

> **Persistir fatos; derivar visões.**

---

# 7. Persistência simples e segura

Depois de cada escolha:

```r
save_state <- function(state, path = "state/draft.rds") {
  temp_path <- paste0(path, ".tmp")
  backup_path <- paste0(path, ".bak")

  saveRDS(state, temp_path)

  if (file.exists(path)) {
    file.copy(path, backup_path, overwrite = TRUE)
  }

  if (!file.rename(temp_path, path)) {
    stop("Não foi possível salvar o estado do draft.")
  }

  invisible(state)
}
```

Isso entrega:

* recuperação após refresh;
* recuperação após fechar o R;
* backup da versão anterior;
* undo;
* nenhuma infraestrutura adicional.

Não há justificativa para SQLite ou event sourcing neste estágio. A própria tabela `picks` já é o log sequencial do draft.

---

# 8. Núcleo funcional mínimo

Eu concentraria todo o domínio em aproximadamente dez funções.

| Função                  | Responsabilidade                                |
| ----------------------- | ----------------------------------------------- |
| `make_snake_schedule()` | gerar os 168 turns                              |
| `new_draft()`           | criar estado inicial                            |
| `record_pick()`         | validar e registrar jogador                     |
| `undo_pick()`           | retirar último pick                             |
| `derive_draft_view()`   | current pick, time atual, rosters e disponíveis |
| `next_user_pick()`      | encontrar próxima escolha do usuário            |
| `lineup_value()`        | calcular valor do melhor lineup possível        |
| `recommend_players()`   | classificar candidatos                          |
| `opponent_pick()`       | comportamento dos times simulados               |
| `simulate_draft()`      | executar um mock completo                       |

Nenhuma dessas funções importa `shiny`.

Exemplo de contrato:

```r
recommend_players(
  state,
  projection_snapshot,
  weights = default_decision_weights(),
  n = 10L
)
```

Retorno:

```text
player_id
player
pos
points
vor
tier
adp
p_next
marginal_value
wait_cost
tier_cliff
adp_value
decision_score
label
reason
```

Assim, terminal e Shiny sempre mostrarão a mesma recomendação.

---

# 9. Invariantes do draft

O núcleo precisa garantir apenas estas regras:

```text
1. O próximo overall é sempre nrow(picks) + 1.
2. O time da vez vem do snake schedule.
3. Um jogador não pode ser escolhido duas vezes.
4. O player_id precisa existir no snapshot.
5. Undo só remove o último pick.
6. O número de picks não pode ultrapassar teams × rounds.
7. Recomendações só contêm jogadores disponíveis.
8. O algoritmo nunca torna impossível completar o roster obrigatório.
```

Não é necessário modelar regras genéricas para qualquer formato de fantasy no primeiro momento. A liga inicial pode estar parametrizada, mas apenas este formato precisa ser validado:

```text
QB 1
RB 2
WR 2
TE 1
FLEX RB/WR 1
K 1
DST 1
BENCH 5
```

---

# 10. Algoritmo de recomendação enxuto

O algoritmo não precisa ser um grande otimizador de árvore. Ele pode ser dividido em quatro números compreensíveis.

## 10.1 Valor marginal no roster

Primeiro calculamos o melhor lineup possível com o roster atual:

```text
melhor QB
dois melhores RB
dois melhores WR
melhor TE
melhor RB/WR restante como FLEX
```

Não é necessário programação linear. Algumas ordenações resolvem o problema.

Para cada candidato:

$$
MarginalValue_i =
LineupValue(Roster + i)
-
LineupValue(Roster)
$$

Caso o jogador não entre imediatamente no lineup, ele recebe um valor de opção de banco:

$$
BenchOption_i =
0.20 \times \max(VOR_i,0)
$$

Então:

$$
RosterValue_i =
MarginalValue_i + BenchOption_i
$$

O desconto de banco evita que QB2 e TE2 sejam valorizados como titulares, mas mantém algum valor para profundidade de RB e WR.

---

## 10.2 Probabilidade de chegar ao próximo pick

Seja:

* \(c\): pick atual;
* \(n\): próxima escolha do usuário;
* \(\mu_i\): ADP;
* \(\sigma_i\): dispersão assumida do draft.

O campo `adp_sd` fornecido pelo pacote mede divergência entre fontes, e não variabilidade empírica de milhares de drafts. Por isso, ele não deve ser usado sozinho como desvio-padrão de uma distribuição de escolhas. ([GitHub][4])

Eu criaria:

$$
DraftSD_i =
\max(
8,\,
ADP\_SD_i,\,
0.10 \times ADP_i
)
$$

Esses parâmetros devem ficar em `config.R`.

A probabilidade condicional de o jogador ainda existir na próxima escolha, sabendo que ele existe agora, fica:

$$
PNext_i =
\frac{
P(DraftPick_i \ge n)
}{
P(DraftPick_i \ge c)
}
$$

Usando uma aproximação normal:

```r
survival <- function(pick, adp, draft_sd) {
  1 - pnorm(pick - 0.5, mean = adp, sd = draft_sd)
}

p_next <- survival(next_pick, adp, draft_sd) /
          survival(current_pick, adp, draft_sd)
```

O resultado é limitado entre 0 e 1.

Essa aproximação não precisa ser perfeita. Ela precisa responder razoavelmente:

```text
Provavelmente volta?
Talvez volte?
Quase certamente não volta?
```

---

## 10.3 Valor esperado disponível na próxima escolha

Não é preciso rodar Monte Carlo no caminho live.

Para cada posição:

1. ordenar os jogadores disponíveis por valor;
2. obter `p_next` de cada um;
3. calcular a probabilidade de cada jogador ser o melhor sobrevivente.

Para jogadores ordenados \(1,2,\dots,k\), a probabilidade de \(j\) ser o melhor ainda disponível é:

$$
PBest_j =
PNext_j
\times
\prod_{h<j}(1-PNext_h)
$$

Então:

$$
ExpectedBestNext_{pos} =
\sum_j
Value_j \times PBest_j
$$

Isso é:

* determinístico;
* vetorizável;
* rápido;
* fácil de testar;
* mais estável visualmente que uma simulação aleatória live.

O custo de esperar fica:

$$
WaitCost_i =
\max(
0,\,
RosterValue_i -
ExpectedBestNext_{position(i)}
)
$$

Esse é o VONA simplificado do sistema.

---

## 10.4 Tier cliff e preço de mercado

O `ffanalytics` já fornece o tier. O War Room só precisa observar o estado atual:

```text
quantos jogadores ainda restam no tier?
qual a queda até o melhor jogador do tier seguinte?
```

Podemos definir:

$$
TierCliff_i =
Points_i -
Points_{best\ available\ in\ next\ tier}
$$

O valor em relação ao ADP:

$$
ADPValue_i =
CurrentPick - ADP_i
$$

Valores positivos indicam que o jogador caiu além de seu preço médio.

---

## 10.5 Score final

Os componentes são normalizados entre 0 e 1 dentro do shortlist:

$$
Score_i =
100 \times
(
0.50N(RosterValue_i)
+
0.30N(WaitCost_i)
+
0.15N(TierCliff_i)
+
0.05N(ADPValue_i)
)
$$

Pesos iniciais:

```r
decision_weights <- c(
  roster_value = 0.50,
  wait_cost = 0.30,
  tier_cliff = 0.15,
  adp_value = 0.05
)
```

Esses pesos não devem ser tratados como ciência estabelecida. São uma hipótese inicial a ser testada nos mocks.

---

# 11. Regras estratégicas como guardrails

Algumas decisões não precisam surgir de uma fórmula.

## K e DST

```text
Não recomendar antes dos dois últimos rounds,
a menos que os slots restantes obriguem o preenchimento.
```

## Segundo QB

```text
Penalizar fortemente enquanto houver slots titulares ou FLEX vazios.
Permitir somente diante de value excepcional ou nos últimos rounds.
```

## Segundo TE

Mesma política, mas com penalidade um pouco menor que QB2.

## RB e WR de banco

Recebem valor de opção maior porque:

* podem ocupar FLEX;
* substituem múltiplos titulares;
* normalmente concentram mais potencial de crescimento de função.

## Viabilidade do roster

Quando o número de picks restantes for igual ao número de posições obrigatórias ainda vazias, somente essas posições ficam elegíveis.

Esses guardrails impedem resultados matematicamente “ótimos”, mas esportivamente absurdos.

---

# 12. Explicação da recomendação

As explicações devem ser determinísticas.

Exemplo:

```text
1. Player A — RB — TAKE NOW — 91

Valor:
+ maior ganho marginal no lineup
+ VOR 74
+ último jogador do tier 2

Mercado:
+ apenas 11% de chance de chegar ao seu próximo pick
+ custo esperado de esperar: 26 pontos

Roster:
+ preenche RB2
```

Labels simples:

| Condição                             | Label         |
| ------------------------------------ | ------------- |
| `p_next < 0.20` e score alto         | `TAKE NOW`    |
| caiu pelo menos 10 picks vs. ADP     | `BEST VALUE`  |
| `p_next > 0.65`                      | `CAN WAIT`    |
| último jogador relevante do tier     | `TIER CLIFF`  |
| preenche posição obrigatória crítica | `ROSTER NEED` |

Não usaria LLM para gerar explicações durante o draft.

---

# 13. Estrutura mínima do repositório

```text
fantasy-warroom/
├── app.R
├── config.R
├── Makefile
├── renv.lock
│
├── R/
│   ├── core.R
│   ├── recommendation.R
│   ├── simulation.R
│   └── persistence.R
│
├── scripts/
│   ├── prepare.R
│   ├── simulate.R
│   └── draft.R
│
├── data/
│   ├── raw_scrape.rds
│   └── projections.rds
│
├── state/
│   ├── draft.rds
│   └── draft.rds.bak
│
├── tests/
│   └── smoke.R
│
├── SPEC.md
├── TASKS.md
├── AGENTS.md
└── CLAUDE.md
```

## O que não existiria

```text
DESCRIPTION
NAMESPACE
R6 classes
golem
SQLite
event sourcing
API
Docker
targets pipeline
background workers
ExtendedTask
authentication
Shiny modules
generic repository layer
dependency injection
```

Nada disso é proibido no futuro. Apenas não resolve um problema atual.

---

# 14. Makefile operacional

Um Makefile pequeno ajuda tanto você quanto Codex ou Claude Code:

```makefile
prepare:
	Rscript scripts/prepare.R

test:
	Rscript tests/smoke.R

simulate:
	Rscript scripts/simulate.R

draft:
	Rscript scripts/draft.R

app:
	Rscript -e 'shiny::runApp(".")'
```

Fluxo:

```bash
make prepare
make test
make simulate
make draft
make app
```

Eu usaria `renv` para fixar inclusive o commit do `ffanalytics`. Isso evita que uma alteração futura de scraper ou contrato afete o projeto na véspera do draft.

---

# 15. Primeira interface: terminal interativo

O comando:

```bash
make draft
```

abre:

```text
NFL FANTASY WAR ROOM
Draft: 12 teams × 14 rounds
Your team: Giuliano
Your slot: 7

Pick 1/168 — Team: João
player>
```

O usuário digita:

```text
chase
```

O sistema procura entre os disponíveis:

```text
1. Ja'Marr Chase — WR — CIN
2. Chase Brown — RB — CIN

Select [1-2]:
```

Comandos especiais:

```text
/rec             mostrar recomendações
/board           mostrar melhores disponíveis
/board rb        filtrar RB
/team            mostrar meu roster
/teams           mostrar todos os rosters
/undo            desfazer último pick
/status          round, pick e próximo pick
/save            salvar explicitamente
/quit            salvar e sair
```

Na vez do usuário, o sistema mostra automaticamente:

```text
YOUR PICK — 4.07
NEXT PICK — 5.06

1. Player A  RB  TAKE NOW    91
2. Player B  WR  BEST VALUE  87
3. Player C  TE  CAN WAIT    78
4. Player D  WR  TIER CLIFF  76
5. Player E  QB  CAN WAIT    72
```

## Busca de nomes sem nova dependência

A resolução pode usar apenas base R:

1. nome normalizado exato;
2. substring;
3. prefixo;
4. `adist()` para aproximação;
5. lista numerada em caso de ambiguidade.

Não é necessário adicionar Elasticsearch, fuzzy-search package ou banco de dados.

---

# 16. Simulador via terminal

O comando:

```bash
Rscript scripts/simulate.R --slot=7 --n=1000
```

executa mocks completos.

## Modelo dos adversários

No início de cada mock, cada jogador recebe um “market pick” latente:

$$
MarketPick_i \sim Normal(ADP_i, DraftSD_i)
$$

Cada adversário escolhe o jogador disponível de menor `MarketPick`, aplicando apenas:

* posições ainda obrigatórias;
* limites razoáveis por posição;
* necessidade de completar o roster;
* pequena preferência por posições vazias.

Isso produz uma mesa:

* majoritariamente guiada por ADP;
* com variação entre simulações;
* sem precisar modelar onze personalidades complexas.

## Estratégias comparadas

O simulador deve executar pelo menos:

| Estratégia | Comportamento           |
| ---------- | ----------------------- |
| `adp`      | menor ADP disponível    |
| `vor`      | maior VOR disponível    |
| `warroom`  | score completo proposto |

## Métricas

```text
projected starter points
starter VOR
bench discounted VOR
quantidade por posição
ADP surplus
número de reaches
roster completo
momento de escolha de QB
momento de escolha de TE
```

Esse mock não prova qual estratégia vencerá a temporada. Ele serve para:

* encontrar bugs;
* evitar rosters absurdos;
* calibrar pesos;
* avaliar posições de sorteio;
* comparar comportamento relativo dos algoritmos.

---

# 17. Calibração sem algoritmo excessivamente sofisticado

Não usaria algoritmo genético para calibrar quatro pesos.

Uma grade pequena é suficiente:

```r
grid <- expand.grid(
  roster_value = c(0.40, 0.50, 0.60),
  wait_cost    = c(0.20, 0.30, 0.40),
  tier_cliff   = c(0.10, 0.15, 0.20)
)
```

O peso de ADP completa a soma até 1.

Cada configuração roda, por exemplo:

```text
200 mocks × 12 posições do snake
```

Fitness inicial:

$$
Fitness =
StarterVOR
+
0.20 \times BenchVOR
+
0.05 \times ADPSurplus
-
1000 \times InvalidRoster
$$

Depois, escolhemos não apenas a configuração de maior média, mas a que apresenta bom resultado em várias posições do snake e menor instabilidade.

Isso é mais transparente e fácil de depurar que otimização genética.

---

# 18. Testes mínimos

Em vez de começar montando toda a infraestrutura de `testthat`, um `tests/smoke.R` pode validar:

```r
stopifnot(nrow(make_snake_schedule(teams, 14)) == 168)
stopifnot(schedule$team[1] == teams[1])
stopifnot(schedule$team[13] == teams[12])
stopifnot(schedule$team[24] == teams[1])
```

Além disso:

```text
duplicidade de jogador é rejeitada
undo restaura jogador aos disponíveis
reload do RDS preserva o estado
todo mock termina com 14 jogadores por time
todo roster final contém QB, RB, WR, TE, K e DST obrigatórios
recommend_players nunca retorna atleta já escolhido
mesmo estado produz mesma recomendação
```

O teste mais importante da última versão será:

> O terminal e o Shiny retornam os mesmos dez jogadores, na mesma ordem, quando leem o mesmo `draft.rds`.

---

# 19. Shiny como casca fina

O Shiny entra apenas depois que:

```text
168 picks podem ser simulados
um draft pode ser conduzido no terminal
undo funciona
reload funciona
o algoritmo gera recomendações coerentes
```

## Estrutura do `app.R`

Sem módulos inicialmente:

```r
snapshot <- readRDS("data/projections.rds")
initial_state <- load_state("state/draft.rds")

ui <- fluidPage(
  ...
)

server <- function(input, output, session) {
  state <- reactiveVal(initial_state)

  observeEvent(input$record_pick, {
    updated <- record_pick(
      state(),
      input$player_id,
      snapshot
    )

    save_state(updated)
    state(updated)
  })

  recommendations <- reactive({
    recommend_players(state(), snapshot)
  })
}
```

## Tela inicial

```text
┌──────────────────────────────────────────────────────────┐
│ ROUND 5 | PICK 52/168 | TEAM: João | YOUR NEXT: 57      │
├──────────────────────┬───────────────────┬───────────────┤
│ RECOMMENDATIONS      │ REGISTER PICK     │ MY ROSTER     │
│                      │                   │               │
│ 1. Player A          │ [ player search ] │ QB ...        │
│ 2. Player B          │ [ DRAFT ]         │ RB ...        │
│ 3. Player C          │                   │ WR ...        │
│                      │ [ UNDO ]          │ TE ...        │
├──────────────────────┴───────────────────┴───────────────┤
│ DRAFT LOG / AVAILABLE PLAYERS                            │
└──────────────────────────────────────────────────────────┘
```

Componentes suficientes:

* `selectizeInput()` para jogador;
* botão `Draft`;
* botão `Undo`;
* tabela de recomendações;
* meu roster;
* últimos picks;
* filtro por posição;
* tabela de disponíveis.

Não há necessidade inicial de:

* gráficos;
* animações;
* telas administrativas;
* edição de múltiplas ligas;
* responsividade móvel sofisticada;
* simulação assíncrona.

A primeira otimização de UX seria permitir que Enter confirme a escolha.

---

# 20. Roadmap direto em três versões

## Versão 0 — Engine and Terminal Draft

**Objetivo:** conduzir um draft inteiro pelo terminal.

| Entrega              | Conteúdo                                                  |
| -------------------- | --------------------------------------------------------- |
| Preparação           | integração com `ffanalytics`, scoring e `projections.rds` |
| Snake                | schedule para 12 × 14                                     |
| Estado               | `draft.rds`, load, save e backup                          |
| Operação             | record pick, undo, available e rosters                    |
| Recomendação inicial | VOR + tier + roster básico                                |
| Terminal             | REPL operacional                                          |
| Validação            | smoke tests                                               |

Critério de aceite:

```text
É possível conduzir 168 picks,
interromper o processo,
reabrir o programa
e continuar do ponto correto.
```

**Esforço supervisionado estimado:** 8–12 horas.

---

## Versão 1 — Smart Draft Engine and Simulation

**Objetivo:** fazer a recomendação considerar o custo de esperar.

| Entrega          | Conteúdo                                 |
| ---------------- | ---------------------------------------- |
| Lineup optimizer | ganho marginal no roster                 |
| PNext            | probabilidade condicional baseada em ADP |
| Expected next    | cálculo analítico do melhor sobrevivente |
| Wait cost        | VONA simplificado                        |
| Tier cliffs      | último jogador e queda de tier           |
| Guardrails       | K/DST, QB2, TE2 e roster feasibility     |
| Simulador        | adversários baseados em ADP              |
| Calibração       | comparação ADP, VOR e War Room           |

Critério de aceite:

```text
O sistema executa pelo menos 1.000 mocks,
não produz rosters inválidos
e explica por que um jogador deve ser escolhido agora ou pode esperar.
```

**Esforço adicional estimado:** 8–12 horas.

---

## Versão 2 — Shiny War Room

**Objetivo:** tornar o motor confortável para uso ao vivo.

| Entrega        | Conteúdo                             |
| -------------- | ------------------------------------ |
| Interface      | uma página operacional               |
| Entrada rápida | busca, draft e Enter                 |
| Recomendações  | top 10 e justificativas              |
| Roster         | titulares, FLEX e banco              |
| Log            | últimos picks e pick atual           |
| Recuperação    | reload pelo `draft.rds`              |
| Correção       | undo                                 |
| Rehearsal      | draft completo simulado na interface |

Critério de aceite:

```text
O mesmo estado RDS gera a mesma recomendação
no terminal e no Shiny,
e um draft completo pode ser operado sem usar o console.
```

**Esforço adicional estimado:** 6–10 horas.

---

## Estimativa consolidada

| Versão                    |     Esforço |
| ------------------------- | ----------: |
| V0 — terminal operacional |      8–12 h |
| V1 — inteligência e mocks |      8–12 h |
| V2 — Shiny                |      6–10 h |
| **Total**                 | **22–34 h** |

Scrapers quebrados ou fontes incompatíveis com a temporada podem acrescentar algumas horas ao pipeline de preparação. Esse risco fica isolado em `prepare.R` e não afeta o motor live.

---

# 21. Estratégia agêntica: BMAD, mas em dose pequena

Para este projeto, o BMAD completo provavelmente acrescentaria mais documentação e coordenação do que valor.

A documentação atual do BMAD recomenda que mudanças pequenas possam ir diretamente para construção e que a maior parte dos trabalhos bem definidos possa começar por uma especificação curta com `bmad-spec`, em vez de um PRD completo. O Quick Dev também trabalha com um único objetivo por especificação, tarefas ordenadas e critérios Given/When/Then. ([BMAD Method][5])

Minha recomendação seria:

> **BMAD Lite + Walking Skeleton + Functional Core / Imperative Shell.**

## Artefatos

Somente quatro documentos:

```text
SPEC.md
TASKS.md
AGENTS.md
CLAUDE.md
```

### `SPEC.md`

Duas ou três páginas:

```text
Why
Capabilities
Constraints
Non-goals
Success signal
Data contracts
Core function contracts
```

Esse formato é muito próximo do contrato curto que o BMAD atual recomenda para implementação. ([BMAD Method][6])

### `TASKS.md`

Oito slices verticais:

```text
S1 — projection snapshot
S2 — snake schedule and state
S3 — record, undo and persistence
S4 — terminal draft
S5 — roster-aware recommendation
S6 — PNext, wait cost and tiers
S7 — mock simulator and calibration
S8 — Shiny shell
```

### `AGENTS.md` e `CLAUDE.md`

Os dois devem conter as mesmas regras essenciais:

```text
1. Read SPEC.md and TASKS.md before coding.
2. Implement only the requested slice.
3. Business logic belongs under R/, never inside app.R or scripts/.
4. ffanalytics may only be used by scripts/prepare.R.
5. Runtime data uses RDS.
6. Store picks; derive rosters, availability and current pick.
7. Do not add a dependency without a concrete need.
8. Do not introduce classes, databases or frameworks without approval.
9. Run: make test.
10. For algorithm changes also run: make simulate.
11. Keep terminal and Shiny behavior identical.
12. Update TASKS.md acceptance status after successful verification.
```

---

# 22. Ordem exata para Codex ou Claude Code

## Slice 1 — Walking skeleton

```text
Criar o repositório mínimo, config.R, Makefile,
diretórios e um projections.rds sintético.

Implementar tests/smoke.R.

Não integrar ffanalytics ainda.
```

Objetivo: provar que o agente consegue executar o projeto.

## Slice 2 — Adapter `ffanalytics`

```text
Implementar scripts/prepare.R.
Gerar raw_scrape.rds e projections.rds.
Validar o schema e impedir player_id duplicado.
```

## Slice 3 — Snake e estado

```text
Implementar make_snake_schedule(), new_draft(),
derive_draft_view(), save_state() e load_state().
```

## Slice 4 — Draft terminal

```text
Implementar record_pick(), undo_pick(),
resolução de nomes e REPL.
Completar um draft manual reduzido de teste.
```

## Slice 5 — Recomendação básica

```text
Implementar lineup_value(), roster_value
e ranking por VOR/tier.
```

## Slice 6 — Inteligência de espera

```text
Implementar draft_sd, p_next,
expected_best_next, wait_cost e score final.
```

## Slice 7 — Simulador

```text
Implementar opponent_pick(), simulate_draft()
e comparação adp/vor/warroom.
```

## Slice 8 — Shiny

```text
Implementar app.R como adaptador do mesmo core.
Nenhuma fórmula nova dentro do Shiny.
```

---

# 23. Prompt reutilizável para cada slice

```text
Leia SPEC.md, TASKS.md, AGENTS.md e os arquivos atuais do projeto.

Implemente exclusivamente a slice S<N>: <NOME>.

Restrições:
- R é a única linguagem de aplicação.
- Dados operacionais são RDS.
- Não introduza banco de dados.
- Não introduza R6, golem ou arquitetura de pacotes.
- Toda regra de negócio deve ficar sob R/.
- scripts/ e app.R apenas chamam o núcleo.
- Não modifique contratos existentes sem necessidade demonstrada.
- Não implemente tarefas de slices futuras.
- Não faça chamadas de rede no live draft.

Antes de concluir:
1. Execute `make test`.
2. Execute o cenário manual descrito nos critérios de aceite.
3. Mostre os arquivos alterados.
4. Explique qualquer decisão não prevista.
5. Atualize em TASKS.md somente o status desta slice.

Critério principal:
<COLOCAR CRITÉRIOS DA SLICE>
```

No BMAD, isso pode ser processado pelo fluxo de `bmad-build`/Quick Dev. Sem BMAD, o mesmo prompt funciona diretamente em Codex ou Claude Code. O valor está mais na disciplina das slices e dos contratos do que na quantidade de agentes especializados.

---

# 24. Decisões finais

| Solução anterior          | Solução simplificada                   |
| ------------------------- | -------------------------------------- |
| pacote R completo         | scripts + funções compartilhadas       |
| SQLite                    | `draft.rds`                            |
| event sourcing            | tibble sequencial de picks             |
| três engines abstratos    | funções puras                          |
| Monte Carlo live          | probabilidade e expectativa analíticas |
| deep engine assíncrono    | mocks offline                          |
| Shiny primeiro            | terminal primeiro                      |
| múltiplos módulos Shiny   | um `app.R`                             |
| configuração universal    | uma liga parametrizada                 |
| grande framework agêntico | BMAD Lite                              |
| dezenas de documentos     | quatro arquivos de contexto            |

A forma mais eficiente de construir é:

```text
ffanalytics
    ↓
projection snapshot
    ↓
pure draft core
    ↓
terminal simulator
    ↓
terminal live draft
    ↓
Shiny shell
```

O ponto central é não transformar um draft de 168 eventos em um sistema corporativo. O `ffanalytics` já resolve a parte estatística estática; aproximadamente dez funções resolvem o draft; uma fórmula transparente resolve a primeira geração de recomendações; e o Shiny apenas torna esse motor confortável para operar.

[1]: https://github.com/FantasyFootballAnalytics/ffanalytics/blob/master/R/calc_projections.R "ffanalytics/R/calc_projections.R at master · FantasyFootballAnalytics/ffanalytics · GitHub"
[2]: https://github.com/FantasyFootballAnalytics/ffanalytics/blob/master/R/custom_scoring.R "ffanalytics/R/custom_scoring.R at master · FantasyFootballAnalytics/ffanalytics · GitHub"
[3]: https://github.com/FantasyFootballAnalytics/ffanalytics/blob/master/man/default_baseline.Rd "ffanalytics/man/default_baseline.Rd at master · FantasyFootballAnalytics/ffanalytics · GitHub"
[4]: https://github.com/FantasyFootballAnalytics/ffanalytics/blob/master/R/adp_functions.R "ffanalytics/R/adp_functions.R at master · FantasyFootballAnalytics/ffanalytics · GitHub"
[5]: https://docs.bmad-method.org/?utm_source=chatgpt.com "Build Software with BMad | BMAD Method"
[6]: https://docs.bmad-method.org/plan/define-requirements-and-a-specification/?utm_source=chatgpt.com "Define Requirements and a Specification | BMAD Method"
