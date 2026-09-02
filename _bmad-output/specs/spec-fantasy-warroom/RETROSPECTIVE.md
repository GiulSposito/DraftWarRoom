---
spec: spec-fantasy-warroom
date: 2026-09-02
verdict: accepted-with-open-items
criteria: declared
headless: false
---

# Retrospectiva — Épico Fantasy Draft War Room

## Resumo do épico

- **Épico:** `spec-fantasy-warroom` (SPEC.md + 5 companheiros), CAP-1 a CAP-11.
- **Modo:** stories mode (pasta de spec; não há `sprint-status.yaml`).
- **Stories:** 8 de 8 com `status: done`. Nenhuma story pendente.
- **Faixa de diff analisada:** `2e68cc8..HEAD` — 8 commits, um por story
  (`dd5298b` story 1 → `1c8c3db` story 8), histórico linear, sem merges.
  39 arquivos, +12.065 linhas.
- **Baselines por story:** cada `stories/<id>-*.md` grava seu `baseline_commit`;
  as faixas são contíguas e não se sobrepõem. Fim da story 8 inferido como `HEAD`
  (nada registra o fim; consistente com o histórico).

### Inventário de evidências

| Evidência | Situação |
|---|---|
| SPEC.md + companheiros (`rds-contracts`, `recommendation-algorithm`, `functional-core`, `preparation-pipeline`, `operations`) | Presentes e lidos |
| `stories.yaml` + 8 artefatos de story | Presentes; todos `done`, `review_loop_iteration: 0` |
| Diff completo + commits por story | `git_evidence.py` — 8 commits, 0 merges |
| `_bmad-output/implementation-artifacts/deferred-work.md` | Presente — 20 itens, um por achado de review de story |
| `.memlog.md` do spec | Presente (log do `bmad-spec`, não das sessões de dev) |
| Retrospectiva anterior | Não existe (primeiro épico) |
| Logs de sessão das stories | **Ausentes** — a análise de lições de processo se apoia em `deferred-work.md` e nas notas dentro dos artefatos de story, não em transcrições |
| `sprint-status.yaml` | Não existe (stories mode) — o gate de completude rodou sobre o `status` dos artefatos |

### Escopo das análises

- **Aggregate views:** executadas por leitura direta de todo `R/` (2.703 linhas),
  `scripts/` (498), `app.R` (256), `config.R`, `tests/smoke.R` (1.716).
- **Diff-scope review:** executada **inline** sobre o diff, não via subagente
  `bmad-review`. Narrowing registrado: o épico já carrega evidência de review
  por story em `deferred-work.md` (camadas adversarial / edge-case /
  verification-gap citadas explicitamente), e foi feita leitura integral do
  código de implementação e de testes. As lentes adversarial e edge-case foram
  reaplicadas nas fronteiras entre stories.
- **Behavior check:** executado — `make test`, `make simulate`, ensaio reduzido
  de `scripts/draft.R` por pipe, benchmark de `recommend_players()`, subida do
  `app.R` com verificação de que serve a página.

---

## Verificação de comportamento

| Fluxo | Resultado observado |
|---|---|
| `make test` | **Passa.** 8 blocos de story OK; fixture sintética com 228 jogadores (QB24/RB60/WR72/TE24/K24/DST24). |
| `make simulate` | **Passa.** 12 rosters válidos em 2 seeds para as 3 estratégias. **Sinal:** a estratégia `warroom` fica **abaixo** de `adp` em starter_points (1875 vs 1954) e starter_vor (358 vs 406) nos dois seeds; drafta QB só no round 14 e 7 RBs. Ver achado AV-7. |
| `scripts/draft.R` (ensaio por pipe: criar draft, pick, `/status`, pick, `/rec`, `/board qb`, `/undo`, `/team`, `/quit`) | **Funciona.** Resolução de nome, board, undo, roster e save atômico corretos. `/rec` executado durante o pick do Team 03 (fora da vez do usuário) produziu recomendação com `p_next` calculado contra o overall 3 — ver achado LENS-1. |
| `recommend_players()` mid-draft (~60 picks) | **~286 ms/chamada** nesta máquina (média de 20 chamadas), antes de qualquer overhead de reactive/render do Shiny. Ver achado AV-4. |
| `app.R` (`shiny::runApp`) | **Sobe e serve** a página "Draft War Room". Equivalência terminal↔Shiny coberta por `testServer` em `tests/smoke.R` (8c, 8e) com `identical()` no frame completo de recomendação. |

---

## Achados

Cada achado tem referência de fonte. Achados marcados **(deferred)** já constam
em `deferred-work.md`; a retrospectiva os consolida e reavalia a severidade agora
que o épico terminou e nenhum arquivo está mais congelado.

### Aggregate views

**AV-1 — Disciplina "frozen-after-approval" acumulou lógica contornada em arquivos posteriores.** `disposição: fix now (passe de consolidação)`
Fonte: `deferred-work.md` (itens das stories 6 e 7); `R/simulation.R:12-17`;
`R/recommendation.R:295-303`.
Cerca de metade dos 20 itens diferidos são da forma "X duplica/contorna Y porque
o arquivo de Y está congelado nesta story". Quatro peças concretas:
1. `.warroom_following_user_pick()` (`recommendation.R`) reimplementa o padrão de
   `next_user_pick()` (`core.R`), diferindo só por `>` vs `>=`.
2. `.warroom_eligible_sim_candidates()` (`simulation.R:112`) **espelha a regra**
   de strand-guard / grace de K-DST do loop de elegibilidade de
   `recommend_players()` (`recommendation.R:480-487`) — não via função
   compartilhada. Uma mudança futura na regra precisa tocar os dois lugares.
3. `.warroom_sim_starter_ids()` espelha a seleção de `.warroom_best_lineup()`; a
   lógica de pool de FLEX diverge para formatos de liga hipotéticos.
4. `.warroom_sim_metrics()` recomputa o mapeamento pick→slot que
   `derive_draft_view()` monta internamente mas não expõe.
O processo entregou stories limpas e revisáveis ao custo de dívida contornada que
nenhuma story teve permissão de pagar. É o achado estrutural mais importante do
épico. Consolidação natural agora: expor o mapeamento pick→slot e generalizar
`next_user_pick()` a partir de `core.R`; compartilhar o strand-guard entre
`recommendation.R` e `simulation.R`.

**AV-2 — Contrato canônico internamente inconsistente: `BENCH=6` vs 14 rounds.** `disposição: fix now (reconciliação de spec)`
Fonte: `rds-contracts.md:53`, `SPEC.md:80`, `config.R:9`; `deferred-work.md`
(story 1, item 4; re-sinalizado nas stories 5 e 6).
O roster QB1/RB2/WR2/TE1/FLEX1/K1/DST1 + BENCH 6 = 15 slots, mas 12×14 dá 14
picks por time. Sem impacto de runtime — a lógica de viabilidade usa
`league$rounds` e os slots mandatórios, nunca lê `BENCH`; `config.R` `BENCH=6L` é
código morto. Mas o contrato "canônico e validado por preservação" está
inconsistente, e **três stories o contornaram explicitamente** em vez de
corrigi-lo. As stories 5 e 6 nomearam `bmad-spec` como ponto de correção; nunca
aconteceu. Deve virar `BENCH=5` (ou os rounds viram 15) via `bmad-spec`.

**AV-3 — Delta de arquitetura vs `operations.md` "Repository shape".** `disposição: accept`
Fonte: `functional-core.md:32-36`, `operations.md:6-30`; `R/projections.R`,
`R/load_core.R`, `config/score_settings.yml`, `.Rprofile`.
`functional-core.md` lista quatro arquivos em `R/`; o build tem seis
(`projections.R` de 519 linhas para CAP-1/CAP-2, `load_core.R` como loader) mais
`config/score_settings.yml` e `.Rprofile`. Todos justificados e permitidos por
"Minor adjustments... when code evidence requires them". Registrado como delta
as-built, não como defeito.

**AV-4 — CAP-11: alvo de ~300 ms essencialmente na linha, sem guarda de regressão.** `disposição: fix now`
Fonte: `SPEC.md:66` (CAP-11 success); `deferred-work.md` (story 5, item de perf);
benchmark desta sessão.
`recommend_players()` sozinho: ~286 ms/chamada mid-draft nesta máquina, antes de
overhead de Shiny. O item diferido da story 5 mediu 130 ms na máquina de dev e
**nomeou explicitamente um passe focado "antes ou durante a story 8"** para
retirar do loop de candidatos o `.warroom_best_lineup` (roda ~180× por chamada) e
o `.warroom_tier_cliff` (refiltra `available` por candidato). A story 8 não fez.
Não existe teste de perf. Num laptop mais lento de dia de draft, com overhead de
reactive por cima, o alvo "bem abaixo de um segundo" fica em risco — e o próprio
SPEC enquadra o dia do draft como "irrecuperável".

**AV-5 — `tests/smoke.R`: 1.716 linhas, sem framework, helper de caso negativo não verifica a mensagem.** `disposição: fix now`
Fonte: `tests/smoke.R:21-27`; `deferred-work.md` (story 7, item do `expect_error`).
Maior arquivo do repo, cresceu em todas as 8 stories. Script plano com helpers
`fail()`/`expect_error()`/`expect_warning()`, seções por comentário.
`expect_error(expr, label)` só usa `label` no caminho de falha quando **nenhum**
erro foi levantado — nunca compara `conditionMessage()` com um padrão. Todas as
~60 chamadas `expect_error(...)` da suite dão falsa confiança de que uma string
de erro específica está sendo verificada. Fortalecer o helper toca os testes de
todas as stories, por isso precisa de um passe dedicado.

**AV-6 — `validate_projections()` é um gate de schema fino.** `disposição: defer`
Fonte: `R/projections.R:185-248`; `deferred-work.md` (story 1, item 1).
Checa presença de chaves, os 4 campos obrigatórios de `players`, o enum de `pos`
e unicidade de `player_id`. Não type-checa `season`/`method`/`vor_baseline`/
`scoring`, não afirma o conjunto completo de colunas normalizadas, não faz
sanidade numérica (`adp > 0`, `overall_rank` permutação de `1:n`,
`source_low <= points <= source_high`). Um snapshot real da story 2 pode passar
`load_projections()` com campos ausentes/lixo que as stories 5-7 consomem como
`NULL`. Baixa probabilidade com o pipeline atual, mas é o gate de dia de draft.

**AV-7 — A fixture sintética quase não separa mercado de valor; CAP-9/CAP-10 rodam sobre sinal fraco.** `disposição: defer (com nota de calibração)`
Fonte: `R/projections.R:154-158` (`adp = overall_rank + wobble suave`);
`deferred-work.md` (story 1, item 5); saída de `make simulate`.
`p_next`, ADP surplus, reach count e a calibração de pesos só carregam sinal
quando o mercado discorda do valor. A fixture faz ADP≈rank, então a estratégia
`warroom` no simulador fica abaixo da `adp` ingênua e a `calibrate_weights()`
tem pouco a calibrar. CAP-10 é atendida mecanicamente (rosters válidos,
reprodutível, métricas reportadas), mas o valor prático da calibração depende de
uma fixture com divergência mercado-vs-valor deliberada, ou de rodar contra um
snapshot real. Sinalizado na story 1, nunca endereçado, e as stories 6-7 foram
construídas em cima assim mesmo.

### Diff-scope review (lentes inline)

**LENS-1 — `recommend_players()` não checa se o usuário está na vez.** `disposição: fix now (guarda de uma linha)`
Fonte: `R/recommendation.R:453-544`; `deferred-work.md` (story 6);
comportamento observado nesta sessão (`/rec` no overall 3, pick do Team 03).
Chamado fora da vez (via `/rec` durante o pick de um oponente), `adp_value` e o
denominador condicional de `p_next` usam o `current_overall` do oponente enquanto
`following_pick` é o próximo pick real do usuário — recomendação silenciosamente
incoerente. `scripts/draft.R` só auto-exibe na vez do usuário, mas `/rec` é
alcançável a qualquer momento e nada avisa. Uma guarda (ou uma nota "assumindo
seu pick") fecha.

**LENS-2 — Binding draft↔snapshot nunca é enforçado.** `disposição: fix now`
Fonte: `rds-contracts.md:39-40`; `R/core.R:183`, `R/core.R:260`;
`scripts/draft.R:154-181`; `deferred-work.md` (stories 3 e 4).
`rds-contracts.md` diz que o estado é "bound to" um snapshot via
`projection_created_at`, mas o binding é metadata write-only. `record_pick()`,
`derive_draft_view()` e o resume de `run_draft()` nunca afirmam
`snapshot$created_at == state$projection_created_at`. Retomar um draft contra um
snapshot reconstruído é silenciosamente permitido e corrompe todas as views
derivadas. Sinalizado duas vezes; a story 4 foi nomeada como ponto de
enforcement e não incluiu. É uma comparação no topo de `run_draft()` (e no
`server()` do Shiny) depois de carregar os dois arquivos.

**LENS-3 — `scripts/prepare.R` sobrescreve `data/projections.rds` sem guarda.** `disposição: fix now`
Fonte: `scripts/prepare.R:110-111`; `SPEC.md:74` ("imutável durante um draft");
`deferred-work.md` (story 2). Também: `make test` reconstrói a fixture sintética
por cima de um snapshot real (`deferred-work.md` story 1, item 3).
Nenhuma proteção contra um re-prepare no meio do draft substituir o snapshot ao
qual o `state/draft.rds` está atado. Recusar a menos que o arquivo esteja ausente
ou `--force` seja passado.

**LENS-4 — `.warroom_norm01()` colapsa para zeros num range degenerado.** `disposição: defer`
Fonte: `R/recommendation.R:239-247`; `deferred-work.md` (story 6).
Um vetor `wait_cost` com exatamente um valor finito (candidato solitário numa
posição secando, resto `NA` — exatamente quando esperar importa mais) contribui 0
para `decision_score`. O sinal de espera é silenciosamente descartado no cenário
em que ele mais vale.

**LENS-5 — Teto do `decision_score` cai ~100→~70 quando `wait_cost` degrada a `NA`, mas os limiares de label são fixos.** `disposição: defer (calibração)`
Fonte: `R/recommendation.R:549-564`, `:41-46`; `deferred-work.md` (story 6).
Sem `adp`, sem pick seguinte, ou final de draft: o teto alcançável cai mas
`.warroom_take_now_score = 60` e `.warroom_best_value_adp` ficam parados —
`TAKE NOW` / `BEST VALUE` ficam materialmente mais difíceis exatamente no fim do
draft. Mesmo efeito para qualquer `weights` do usuário que não some 1.
Renormalizar os pesos ativos ou derivar os limiares do máximo alcançável.

**LENS-6 — Entrada da ordem de times no terminal comita sem eco nem confirmação.** `disposição: defer`
Fonte: `scripts/draft.R:162-180`; `deferred-work.md` (story 4).
Um nome de time digitado errado não pode ser corrigido de dentro do loop
(`/undo` só toca picks) — o usuário tem que apagar `state/draft.rds` na mão. O
spec congelado dizia "chamar `new_draft` e `save_state` na hora", então um passo
de confirmação é decisão de escopo deliberada a revisitar.

**LENS-7 — Shiny: sem guarda contra duas abas na mesma `state/draft.rds`.** `disposição: defer`
Fonte: `app.R:106-129`; `deferred-work.md` (story 8).
Cada sessão carrega seu `init_state` e `save_state()` é last-write-wins. Duas
abas do **mesmo** usuário durante um draft ao vivo (operador dá refresh e abre
segunda aba) é um deslize plausível que os Non-goals (que descartam
multi-usuário) não cobrem. Checagem de frescor por mtime antes de cada
`commit_state()` fecha.

**LENS-8 — Mensagens de erro do Shiny não distinguem rejeição de validação de falha de I/O.** `disposição: defer`
Fonte: `app.R:157-179`; `deferred-work.md` (story 8).
`draft_btn`/`undo_btn` reportam tanto rejeição de `record_pick()` quanto falha de
`save_state()` sob o mesmo prefixo genérico. Um operador de draft ao vivo não
consegue distinguir "pick inválido" de "o arquivo de estado falhou ao salvar".

---

## Achados que sobreviveram à verificação — o que está limpo

Verificado e correto (não são achados; registrados para o leitor saber o que foi
checado):

- **Determinismo:** `method = "radix"` e tie-break em `player_id` em todo o
  caminho de recomendação/board; a única RNG do core está isolada em um bloco
  save/restore de `.Random.seed` em `R/simulation.R:52-64`. Invariante 9 dos
  contratos: honrada e testada.
- **Constraints do SPEC:** sem SQLite/R6/golem/targets/Docker/API/DI; `ffanalytics`
  e `yaml` só em `scripts/prepare.R`; sem chamada de rede no caminho ao vivo
  (testado estaticamente em `tests/smoke.R` 8h); sem Monte Carlo no caminho de
  recomendação (`pnorm` analítico, testado).
- **Save atômico:** `.tmp` → `.bak` do estado anterior → `file.rename` por cima
  (`R/persistence.R:137-173`); validação de schema antes de escrever e depois de
  ler; toda mutação aceita salva imediatamente nos dois adapters.
- **Persistir fatos, derivar visões:** `state/draft.rds` guarda só
  `overall/player_id/entered_at`; pick atual = `nrow(picks)+1`; roster,
  disponíveis, lineup, na-vez, recomendações todos derivados
  (`R/core.R:260-329`).
- **Equivalência terminal↔Shiny:** `identical()` no frame completo de
  recomendação, mid-draft, em `tests/smoke.R` (8c, 8e). `app.R` não redefine
  função de core nem nomeia símbolo de RNG (8h).
- **`ffanalytics` fixado:** `renv.lock` grava `RemoteSha`
  `42711a074d16caf723291eecd9d0daeb15340cf3` (v3.1.18). `RemoteRef: master` mas o
  SHA é que manda no `restore`.
- **`deferred-work.md`:** exemplar. 20 itens, cada um com story de origem,
  evidência e ponto de correção nomeado. Nada varrido para baixo do tapete.
- **Histórico:** linear, um commit limpo por story, mensagens consistentes,
  atribuição presente. `review_loop_iteration: 0` em todas — cada story passou a
  review na primeira.

---

## Follow-through da retrospectiva anterior

Não aplicável — este é o primeiro épico do projeto. Não há retrospectiva
anterior nem `action_items` prévios para reconciliar.

---

## Itens de ação

Nenhum é aplicado automaticamente. Cada um é remediação proposta aguardando
decisão humana. Owner sugerido: `Giu` (mono-usuário).

| # | Ação | Fonte | Tipo |
|---|---|---|---|
| 1 | **[decidido 2026-09-02 — Giu]** Mover a configuração de liga (times, roster, bench) para `config/league.yml`, lido pelo core no caminho ao vivo; `rounds` deixa de ser valor e passa a ser derivado = `sum(roster)` = **15** (bench 6 mantido, 12×15 = **180 picks**). Reconciliar `SPEC.md` + companheiros via `bmad-spec` (update), atualizar o header de `scripts/prepare.R` e a seção "Where things are" de `AGENTS.md` (agora `yaml` também é lido no caminho ao vivo). AV-2 resolvido por construção. | AV-2 | reconciliação de spec |
| 2 | Passe de consolidação (todos os arquivos descongelados): expor mapeamento pick→slot de `core.R`; generalizar `next_user_pick()` por comparação/overall inicial; extrair o strand-guard de elegibilidade para uma função compartilhada entre `recommendation.R` e `simulation.R`. | AV-1, LENS-1 parcial | dívida técnica |
| 3 | Enforçar o binding draft↔snapshot: comparar `snapshot$created_at == state$projection_created_at` no resume de `run_draft()` e no startup do `server()` do Shiny. | LENS-2 | robustez de dia de draft |
| 4 | Guarda de imutabilidade em `scripts/prepare.R`: recusar sobrescrever `data/projections.rds` a menos que ausente ou `--force`. Considerar caminho de fixture dedicado para `make test` não competir com um snapshot real. | LENS-3 | robustez de dia de draft |
| 5 | Passe de performance em `recommend_players()`: retirar `.warroom_best_lineup` e o agrupamento de `available` por posição do loop de candidatos; adicionar uma asserção de perf (`< ~150 ms` mid-draft) em `tests/smoke.R`. | AV-4 | performance CAP-11 |
| 6 | Guarda de "usuário na vez" em `recommend_players()` (ou nota explícita "assumindo seu pick" na saída) para `/rec` fora de turno. | LENS-1 | correção |
| 7 | Fortalecer `expect_error()` em `tests/smoke.R` para comparar `conditionMessage()` com um padrão; passe dedicado (toca testes de todas as stories). | AV-5 | infra de teste |
| 8 | ~~Injetar divergência mercado-vs-valor na fixture~~ **[decidido 2026-09-02 — Giu: fechado]** A calibração vai rodar contra um snapshot real (`make prepare`), que tem divergência de ADP de verdade. Ação reduzida a: documentar em `operations.md` "Calibration" que a calibração exige snapshot real, não a fixture sintética. | AV-7 | qualidade de calibração |
| 9 | Endereçar em passe focado de normalização/calibração: `.warroom_norm01()` em range degenerado (LENS-4) e teto de score vs limiares fixos de label (LENS-5). | LENS-4, LENS-5 | calibração |
| 10 | Fortalecer `validate_projections()` com type-check de `season/method/vor_baseline/scoring`, conjunto completo de colunas e sanidade numérica — quando o pipeline real de preparação for revisitado. | AV-6 | robustez |

---

## Veredito de aceitação

**accepted-with-open-items.** Critérios: **declarados** (SPEC.md "Success signal"
+ os 11 pares intent/success de CAP e as Constraints).

O sinal de sucesso do SPEC é atendido de ponta a ponta e verificado nesta sessão:
uma pessoa gera/carrega um snapshot, configura a ordem de 12 times, conduz picks
no terminal parando e retomando com segurança, recebe recomendações
determinísticas e explicáveis, roda mocks seedados comparando ADP/VOR/War Room, e
conduz o mesmo draft num Shiny de página única que retorna as mesmas
recomendações na mesma ordem que o core do terminal. Todas as 11 capacidades
estão mecanicamente satisfeitas e cobertas por `tests/smoke.R`. As Constraints do
SPEC foram honradas (verificadas em "o que está limpo"). O histórico e a
disciplina de review são de alta qualidade, e `deferred-work.md` é um registro
honesto e completo da dívida.

Fica em **accepted-with-open-items**, não **accepted**, porque o épico carrega:

1. **Duas lacunas de robustez de dia de draft diferidas para além do ponto de
   correção que elas mesmas nomearam** — binding draft↔snapshot não enforçado
   (LENS-2, nomeado para a story 4) e `prepare.R` sem guarda de imutabilidade
   (LENS-3). O SPEC enquadra o dia do draft como irrecuperável; essas duas falham
   silenciosamente.
2. **Um alvo de performance de CAP-11 essencialmente na linha (~286 ms de núcleo
   antes do Shiny) sem teste de regressão**, apesar de um item diferido ter
   nomeado a story 8 como o momento de corrigir (AV-4).
3. **Uma inconsistência no contrato canônico não reconciliada** (`BENCH=6` vs 14
   rounds, AV-2) que três stories contornaram e nenhuma corrigiu.
4. **Dívida estrutural acumulada pela disciplina de congelamento** (AV-1): a
   regra de elegibilidade strand-guard agora vive em dois arquivos.

Nada disso é falha de story. São itens de fechamento de épico, agora que nenhum
arquivo está congelado.

---

## Perguntas em aberto

- ~~**`BENCH` deve ser 5, ou os rounds devem ser 15?**~~ **Respondido (2026-09-02, Giu):**
  rounds = 15, bench 6, 180 picks; config de liga migra para `config/league.yml`
  com `rounds` derivado de `sum(roster)`. Ver ação 1.
- ~~**A calibração de pesos vai rodar contra um snapshot real antes do draft?**~~
  **Respondido (2026-09-02, Giu): sim.** AV-7 fechado; ação 8 reduzida a documentação.
- **Os logs de sessão das 8 stories existem em algum lugar?** A análise de lições
  de processo se apoiou em `deferred-work.md` e nas notas dos artefatos; com as
  transcrições daria para dizer se algum item foi diferido por pressão de tempo
  vs decisão de escopo.

---

## Assunções

Execução interativa — os fatos confirmados pelo usuário ficam registrados no
"Resumo do épico". Assunções feitas sem o usuário nesta sessão:

- **Seleção do épico:** tomada do argumento da invocação
  (`_bmad-output/specs/spec-fantasy-warroom/`). Sem ambiguidade — é a única pasta
  de spec.
- **Fim da faixa de diff da story 8:** inferido como `HEAD` (`1c8c3db`); nenhum
  artefato registra o fim de uma última story em stories mode.
- **Diff-scope review inline** em vez de subagente `bmad-review` — narrowing
  registrado em "Escopo das análises".
- **Team discussion (Fase 3):** pulada (default; não solicitada).
