# Runbook — dados reais no pipe e simulação de draft

Como sair da fixture sintética, gerar projeções reais e rodar simulações antes do
draft ao vivo. Rode tudo a partir da raiz do repositório.

## O pipe em uma frase

Dados reais entram em **um único ponto**: `data/projections.rds`, gerado por
`scripts/prepare.R`. O simulador (`scripts/simulate.R`), o terminal
(`scripts/draft.R`) e o Shiny (`app.R`) todos leem esse mesmo arquivo.

```
config/score_settings.yml ─┐
ffanalytics (scrape)  ─────┼─> scripts/prepare.R ─> data/projections.rds ─┬─> make simulate
config/league.yml     ─────┘                        (imutável no draft)   ├─> make draft
                                                                          └─> make app
```

Estado atual: `data/projections.rds` é a **fixture sintética** (228 jogadores
sintéticos). O scrape real de 2026-09-01 já está em `data/raw_scrape.rds`
(season 2026, week 0, 6 posições).

---

## 0. Dependências (uma vez)

```bash
Rscript -e 'renv::restore()'
```

- Instala o `ffanalytics` no commit pinado (`42711a0…`) e ~70 dependências do
  `renv.lock`.
- **Precisa de rede.** Pode levar alguns minutos na primeira vez.
- Se perguntar `Do you want to proceed? [Y/n]`, responda `y`.
- Verificar: `Rscript -e 'packageVersion("ffanalytics")'` deve imprimir
  `3.1.18.0000`.

---

## 1. Gerar o snapshot real de projeções

O guard de imutabilidade recusa sobrescrever um `data/projections.rds` existente
— é preciso passar `--force`.

**Opção A — reusa o scrape de 2026-09-01 (offline, rápido ~1 min):**

```bash
Rscript scripts/prepare.R --force
```

**Opção B — scrape fresco (rede, ADP e projeções atuais — recomendado perto do
dia do draft):**

```bash
Rscript scripts/prepare.R --rescrape --force
```

O que acontece dentro do script:

1. Lê `config/score_settings.yml` (Full-PPR) e mescla sobre `ffanalytics::scoring`.
2. `scrape_data(pos = QB/RB/WR/TE/K/DST, season = 2026, week = 0)` — ou reusa
   `data/raw_scrape.rds` quando não há `--rescrape`.
3. Grava `data/raw_scrape.rds` (somente no `--rescrape`).
4. `projections_table(avg_type = "robust")` com VOR baseline
   `QB13 / RB35 / WR36 / TE13 / K13 / DST13`.
5. `add_player_info()` + `add_adp()`.
6. `normalize_projections()` → valida o schema de `rds-contracts.md`.
7. Grava `data/projections.rds` de forma **atômica** (`.tmp` → rename), com um
   `.bak` do snapshot anterior tirado **antes** de qualquer scrape.

**Saída esperada** (últimas linhas):

```
--force: backed up the current snapshot to data/projections.rds.bak
prepared data/projections.rds -- NNN players (season 2026, method robust)
  QB   XX
  RB   XX
  ...
adp columns: yes
ffanalytics: 3.1.18.0000 @ 42711a0...
raw scrape:  data/raw_scrape.rds
```

**Se falhar:**

| Sintoma | Causa / ação |
|---|---|
| `adp columns: no (unavailable)` | `add_adp()` falhou; o mercado dos oponentes fica sem sinal. Tente `--rescrape`, ou rode mais perto da data. |
| Erro de rede em `scrape_data` | Sem internet, ou uma fonte fora do ar. Use a Opção A (reusa o raw). |
| `could not find function` / pacote ausente | Volte ao passo 0. |
| `refusing to overwrite ... immutable` | Faltou `--force`. |

---

## 2. Verificar o snapshot

```bash
make test
```

Roda `tests/smoke.R` contra o gate de schema (`validate_projections`). ~2 min.
Espera `smoke OK -- NNN players in data/projections.rds` e a tabela de posições.

Inspeção manual:

```bash
Rscript -e '
x <- readRDS("data/projections.rds")
cat("criado:", format(x$created_at), "\n")
cat("jogadores:", nrow(x$players), "\n")
cat("tem adp?:", all(c("adp","adp_sd") %in% names(x$players)), "\n")
print(head(x$players[order(x$players$adp),
      c("player","pos","points","vor","adp")], 15))
'
```

Confira: `criado` é recente, `tem adp?: TRUE`, o topo de ADP faz sentido
(RBs/WRs de elite primeiro).

---

## 3. Simulação reduzida

```bash
make simulate
```

- Roda `compare_strategies()` para `adp` / `vor` / `warroom`, em 2 seeds
  (`config.R$seed` e `seed + 1`), com o usuário = `config.R$user_team`.
- Por estratégia imprime: `starter_points`, `starter_vor`, `bench_vor`,
  contagem por posição (`n_QB`…`n_DST`, soma 15), `adp_surplus`, `reach_count`,
  `roster_valid`, `qb_round`, `te_round`, `all_rosters_valid`.
- Sai `0` se todos os 12 rosters de todas as estratégias forem válidos.

Espera terminar com:

```
todas as estrategias completaram com os 12 rosters validos.
```

Com ADP real, a estratégia `warroom` deve ficar competitiva com `adp` (com a
fixture sintética ela perdia — o mercado quase não divergia do valor).

---

## 4. Simular de um slot / seed específico (opcional)

Sem editar `config.R`, numa sessão R:

```bash
Rscript -e '
source("R/load_core.R"); load_core()
snap <- load_projections("data/projections.rds")
to   <- sprintf("Team %02d", 1:12)
print(compare_strategies(snap, to, "Team 07", seed = 42L), row.names = FALSE)
'
```

Ou fixe no `config.R` (linhas ~24–30): `user_team <- "Team 07"`,
`user_slot <- 7L`, `seed <- 42L` — aí `make simulate` já usa esses valores.

O formato da liga (12 times, 15 rounds) vem de `config/league.yml`; `rounds` é
derivado da soma das vagas de roster, não se configura.

---

## 5. Calibrar os pesos de recomendação (lento)

```bash
Rscript scripts/simulate.R --calibrate
```

- Grade `expand.grid` de `roster_value × wait_cost × tier_cliff` (~20 linhas
  válidas), cada uma rodada em `seeds = 1:3 × slots = c(1, 6, 12)` com a
  estratégia `warroom`.
- Fitness = `starter_vor + 0.5·bench_vor + 0.1·adp_surplus − 1000·(roster
  inválido)`; ordena por `risk_score = média − desvio`.
- **Demora** vários minutos (≈ 20 × 9 drafts de 15 rounds, cada um chamando
  `recommend_players` 15 vezes).

Saída: tabela ordenada + `melhor configuracao (maior risk_score)`.

Para adotar os pesos vencedores, edite `R/recommendation.R` (função
`default_decision_weights()`):

```r
default_decision_weights <- function() {
  c(roster_value = 0.50, wait_cost = 0.30, tier_cliff = 0.15, adp_value = 0.05)
}
```

Depois `make test && make simulate` para confirmar.

> A calibração só é significativa contra um snapshot **real** — a fixture
> sintética tem ADP quase monótona e não separa mercado de valor.

---

## 6. No dia do draft

```bash
make draft      # terminal
# ou
make app        # Shiny (http://127.0.0.1:PORT)
```

- Ambos carregam `data/projections.rds` e ligam o `state/draft.rds` a ele pelo
  `created_at`.
- **Não rode `prepare` depois de começar o draft.** O assert de binding recusa
  retomar o draft se o `created_at` do snapshot mudar — é a proteção contra
  operar com projeções diferentes das que o draft começou.
- Parar e retomar: `/quit` no terminal salva o estado; rodar `make draft` de
  novo retoma do mesmo ponto. O Shiny salva a cada pick aceito.
- Recomendação fora da vez (`/rec` durante o pick de um oponente) ainda
  aparece, mas com aviso — os números assumem que você pica agora.
