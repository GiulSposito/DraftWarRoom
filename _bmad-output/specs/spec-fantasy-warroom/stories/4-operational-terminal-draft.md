---
title: 'Draft de terminal operacional'
type: 'feature'
created: '2026-09-01'
status: 'done'
review_loop_iteration: 0
baseline_commit: '43979a7a25c1d07eb71dda8476f0491dc45c7712'
context:
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/SPEC.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/operations.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/functional-core.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/rds-contracts.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/AGENTS.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** As stories 1–3 entregaram o snapshot de projeção e todo o núcleo de
estado (schedule, `new_draft`, `record_pick`, `undo_pick`, `derive_draft_view`,
`next_user_pick`, `load_state`, `save_state`), mas não existe nenhuma forma de
conduzir um draft: nada lê comandos, resolve um nome digitado para um `player_id`,
mostra board/rosters/status, ou retoma um draft interrompido. O caminho de
terminal é o primeiro produto usável e o fallback operacional do dia do draft
(SPEC "Why", CAP-7).

**Approach:** Implementar `scripts/draft.R` como um adapter fino sobre o núcleo:
um loop interativo que carrega o snapshot e cria ou retoma `state/draft.rds`,
mostra round / pick / time na vez / próximo pick do usuário, aceita o conjunto de
comandos exigido, e na vez do usuário mostra recomendações automaticamente. A
resolução de nome de jogador e a montagem do board são funções puras novas em
`R/core.R` (reusáveis pela Shiny da story 8), não lógica dentro do script. O loop
fica numa função `run_draft()` com conexões de entrada/saída e snapshot/estado
injetáveis, para que `tests/smoke.R` faça um ensaio reduzido completo com pelo
menos uma parada e retomada.

## Boundaries & Constraints

**Always:**
- `scripts/draft.R` é adapter: só I/O, strings de prompt, dispatch de comando e
  renderização da lista numerada. Zero fórmula ou regra de negócio — validação de
  pick, schedule, view, resolução de nome e board vêm de `R/`.
- Nenhuma chamada de rede em `scripts/draft.R` nem em `R/` (AGENTS.md). O snapshot
  vem de `load_projections()`; `data/projections.rds` é imutável durante o draft.
- Todo pick aceito e todo `/undo` chamam `save_state()` imediatamente (AGENTS.md
  "Conventions"). `/quit` salva e sai com status 0.
- Persistir só fatos: o script nunca grava campo derivado. Pick atual continua
  sempre `nrow(picks) + 1`.
- Resolução de nome, em ordem, contra os jogadores **disponíveis** da view: nome
  normalizado exato → prefixo → substring → fallback fuzzy `adist()` → lista
  numerada de desambiguação. O primeiro tier não-vazio vence. Normalização:
  minúsculas, sem acento, sem pontuação, espaços colapsados. Resultado
  determinístico e ordenado (por `points` desc, desempate `player_id`).
- Novo draft: ler a ordem dos 12 times imediatamente antes do draft (uma linha
  separada por vírgula, exatamente `league$teams` nomes, sem duplicados);
  `user_slot` de `config.R` define qual slot é o usuário e portanto `user_team`;
  chamar `new_draft(snapshot, team_order, user_team, seed = cfg$seed)` e
  `save_state()` na hora.
- Retomar: se `state/draft.rds` existe, `load_state()` e continuar do pick
  `nrow(picks) + 1`, sem repetir o prompt de ordem dos times.
- Comandos exatos: `/rec`, `/board`, `/board <pos>`, `/team`, `/teams`, `/undo`,
  `/status`, `/save`, `/quit`. Uma linha sem `/` é um nome de jogador para o time
  na vez. `/help` é permitido (só formatação).
- `run_draft()` aceita `con` (entrada), `out` (saída), `snapshot`, `state_path` e
  `config` — todos com default para o caminho real quando `NULL`. Execução real
  só quando `sys.nframe() == 0L`.

**Ask First:**
- Alterar qualquer contrato de `rds-contracts.md`, as assinaturas existentes do
  catálogo em `functional-core.md`, ou os alvos do `Makefile`.
- Adicionar arquivo em `R/` além de `core.R` (as funções novas vão em `core.R`).
- Adicionar `team_order` ou qualquer chave nova ao contrato de `state/draft.rds`.

**Never:**
- Implementar `recommend_players` ou qualquer parte da story 5–8. `/rec` e o
  auto-show na vez do usuário chamam `recommend_players` **apenas se**
  `exists("recommend_players", mode = "function")`; caso contrário imprimem um
  aviso de uma linha ("recomendações chegam na story 5") e mostram o board por
  valor como stand-in.
- Recomendação, simulação (`R/simulation.R`, `scripts/simulate.R`), Shiny
  (`app.R`).
- SQLite/outro banco, event sourcing, R6, golem, targets, Docker, API,
  autenticação, background workers, injeção de dependência, RNG não-semeado,
  reconciliar com `docs/archive/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Novo draft | sem `state/draft.rds`; linha de 12 nomes | `new_draft` + `save_state`; banner com round 1, pick 1, time na vez, próximo pick do usuário | N/A |
| Ordem inválida | 11 nomes, 13 nomes, ou nome duplicado | mensagem citando o problema; re-prompt | re-prompt, sem crash |
| Retomar | `state/draft.rds` com k picks | `load_state`; banner do pick k+1; nenhum prompt de ordem | N/A |
| Match exato | `"RB Synthetic 01"` e disponível | pick gravado para o time na vez; `save_state`; status reimpresso | N/A |
| Match prefixo | `"te synthe"` casa vários TEs disponíveis | lista numerada estável pelo tier prefixo; usuário digita o número; pick gravado | número fora do range → re-prompt |
| Match substring | `"r synthetic 40"` casa só WR Synthetic 40 (tier prefixo vazio) | pick gravado | N/A |
| Match fuzzy | `"rb synthetc 03"` (typo) dentro do limite | pick gravado (menor `adist`, único; lista se >1 no mínimo) | N/A |
| Ambíguo | `"qb synthetic 1"` casa QB 10–19 | lista numerada estável; usuário digita o número; pick gravado | número fora do range → re-prompt |
| Sem match | `"xyzzy"` | mensagem "nenhum jogador"; nenhum pick; re-prompt | re-prompt |
| Já draftado | nome de jogador já em `picks` | não aparece em `available`, então "nenhum jogador" | re-prompt |
| `/board` | qualquer estado | top disponíveis por `overall_rank` com pos/points/vor/tier/adp | N/A |
| `/board rb` | filtro de posição | mesmo, só `pos == "RB"`; posição desconhecida → aviso | aviso, re-prompt |
| `/team` | roster do usuário | linhas de `view$rosters[[user_team]]` | N/A |
| `/teams` | todos os rosters | um bloco por time em ordem de slot | N/A |
| `/status` | qualquer estado | round, overall pick, time na vez, próximo pick do usuário | N/A |
| `/undo` no início | `picks` vazio | mensagem do `stop()` de `undo_pick` capturada; sem crash | re-prompt |
| `/undo` normal | k>=1 picks | última linha removida, jogador volta a `available`, `save_state` | N/A |
| `/rec` sem story 5 | `recommend_players` ausente | aviso de uma linha + board por valor | N/A |
| Vez do usuário | `derive_draft_view` diz time na vez == `user_team` | recomendações mostradas automaticamente antes do prompt | N/A |
| `/save` | qualquer estado | `save_state`; confirma o path | erro de escrita propagado |
| `/quit` | qualquer estado | `save_state`; sai status 0 | N/A |
| Draft completo | 168 picks gravados | banner "draft completo"; loop encerra | N/A |
| Ensaio reduzido | `run_draft` guiado por `textConnection`, `/quit` no meio, segundo `run_draft` retomando | todos os 168 picks completados; `load_state` final + `derive_draft_view` com `is_complete == TRUE` | N/A |

</frozen-after-approval>

## Code Map

- `scripts/draft.R` -- **novo**. Bootstrap idêntico ao de `scripts/prepare.R:33-47`
  (`source("R/load_core.R"); load_core()`; `config.R` via `sys.source` em env
  isolado). `run_draft(con = NULL, out = stdout(), snapshot = NULL,
  state_path = NULL, config = NULL)`: `con = NULL` abre `file("stdin")`; resolve
  defaults, cria/retoma estado, roda o
  loop de comando. Helpers de renderização locais (`.warroom_print_banner`,
  `.warroom_print_board`, `.warroom_print_roster`, `.warroom_show_recommendations`,
  `.warroom_fmt_player`, `.warroom_read_line`, `.warroom_print_help`). Guarda de
  execução: `if (sys.nframe() == 0L) run_draft()`.
- `R/core.R` -- **estender** (não alterar o existente). Adicionar:
  `.warroom_normalize_name(x)` (minúsculas, `iconv` para ASCII//TRANSLIT, remove
  não-alfanumérico, colapsa espaço); `resolve_player(query, available,
  all_players = available)` → `list(status = "unique"|"ambiguous"|"none",
  players = <df de linhas de available>, query)` seguindo a ordem
  exato→prefixo→substring→`adist` (primeiro tier não-vazio vence); um nome exato
  de alguém que está em `all_players` mas não em `available` → `"none"` (já
  draftado, sem fuzzy). Ordenação determinística. `available_board(view,
  pos = NULL, n = NULL)` → `view$available` filtrado por `pos` (validando contra
  `c("QB","RB","WR","TE","K","DST")`) e ordenado por `overall_rank` (fallback
  `points` desc). Puras, offline, sem `shiny`. Catálogo/invariantes:
  `functional-core.md:9-48`.
- `R/core.R` existente -- `derive_draft_view():260` dá `available`, `rosters`,
  `team_on_clock`, `round_on_clock`, `is_complete`; `next_user_pick():318`;
  `record_pick():183`; `undo_pick():238`. Não modificar.
- `R/persistence.R` -- `load_state():179`, `save_state():137`. Usar como está.
- `R/projections.R` -- `load_projections():253` devolve o snapshot. Não modificar.
- `config.R` -- `user_slot` (`config.R:29`), `seed` (`config.R:34`), `paths`
  (`config.R:37-44`: `projections`, `draft_state`). `user_team` (`config.R:28`) é
  placeholder — o `user_team` real vem de `team_order[user_slot]`.
- `R/load_core.R` -- `load_core()` faz `source()` só de `R/*.R` (`load_core.R:26`);
  `scripts/draft.R` não é auto-carregado. `tests/smoke.R` fará
  `source("scripts/draft.R")` para obter `run_draft` sem executá-lo (a guarda
  `sys.nframe()` protege).
- `tests/smoke.R` -- **estender**. Bloco offline de story 4 antes do Summary
  (`smoke.R:713`). Helpers `fail()`, `expect_error()` já existem
  (`smoke.R:15-25`); `cfg` já disponível (`smoke.R:13`). `Makefile` alvo `test`
  inalterado.
- `Makefile` -- alvo `draft` já é `Rscript scripts/draft.R` (`Makefile:16-17`).

## Tasks & Acceptance

**Execution:**
- [x] `R/core.R` -- adicionar `.warroom_normalize_name`, `resolve_player`,
  `available_board` (puras, offline). `resolve_player` só considera as linhas de
  `available`; ordem exato→prefixo→substring→`adist` com limite
  `max(1L, floor(nchar(query_normalizado) / 3))`; retorna 0/1/N candidatos com
  `status` correspondente, candidatos ordenados por `points` desc / `player_id`.
  `available_board` valida `pos`, ordena por `overall_rank`, aplica `head(n)`.
- [x] `scripts/draft.R` -- criar o adapter. Bootstrap + `run_draft()` + guarda
  `sys.nframe()`. Startup: `load_projections`; se `state_path` existe →
  `load_state`, senão ler a linha de ordem dos times, derivar `user_team` de
  `config$user_slot`, `new_draft`, `save_state`. Loop: imprime banner/recs quando
  for a vez do usuário, lê uma linha, faz dispatch. Comandos e nome-de-jogador
  conforme a matriz. `record_pick`/`undo_pick` seguidos de `save_state`. Erros de
  `record_pick`/`undo_pick`/`resolve_player` capturados com `tryCatch` e
  reportados sem encerrar o loop. `/quit` e fim de draft encerram; `run_draft`
  retorna `invisible(state_path)`.
- [x] `tests/smoke.R` -- bloco offline de story 4. `source("scripts/draft.R")`;
  chamar `run_draft(con, out, snapshot = snap, state_path = <tempdir>)` (o
  `config` real é carregado: `user_slot = 1`, `seed = 1`, liga 12×14). (1) Um
  `run_draft` guiado por `textConnection` que: cria o draft (linha de 12 nomes),
  exercita match exato, prefixo, substring, fuzzy e ambíguo+número, `/board`,
  `/board rb`, `/board xx` (inválido), `/team`, `/teams`, `/status`, `/rec` (sem
  story 5), `/undo`, `/undo` em excesso, `/save`, e `/quit` no meio. (2) Segundo
  `run_draft` com o mesmo `state_path` que retoma e completa até 168 picks
  (nomes exatos gerados a partir de `available`). Asserts: `save_state` gravou
  após cada pick; `.bak` existe; estado final `load_state` + `derive_draft_view`
  com `is_complete == TRUE` e `nrow(picks) == 168`; nenhuma chave derivada em
  `state/draft.rds`. Só `tempdir()`, sem rede.
- [x] Testar cada linha da I/O & Edge-Case Matrix no bloco de story 4.

**Acceptance Criteria:**
- Given `make test` sem rede, when executado, then status 0 e o bloco de story 4
  passa junto com os de stories 1–3.
- Given `grep -nE "recommend_players|simulate_draft|shiny|scrape|http" scripts/draft.R`,
  when inspecionado, then a única ocorrência de `recommend_players` está sob uma
  guarda `exists(...)` e não há nenhuma das outras.
- Given `grep -nE "adist|substr|normalize|make_snake_schedule|derive_draft_view" scripts/draft.R`,
  when inspecionado, then não há algoritmo de matching nem de schedule no
  script — só chamadas às funções de `R/`.
- Given um novo draft criado pelo terminal, when o processo é encerrado com
  `/quit` e reiniciado, then o banner mostra o pick `nrow(picks) + 1` e todos os
  picks anteriores estão preservados em ordem.
- Given a vez do usuário (time na vez == `user_team`), when o prompt aparece,
  then as recomendações (ou o stand-in por valor) já foram impressas.

## Spec Change Log

- **2026-09-01 — Ordem de matching (renegociação do bloco frozen, autorizada pelo
  humano em sessão, opção 1 de 3 apresentadas).** Achado: "exato → substring →
  prefixo → fuzzy" torna o tier prefixo código morto, porque todo prefixo também
  é substring; a linha da matriz "Match prefixo" ficava insatisfazível com os
  nomes sintéticos. Emenda: ordem passou a "exato → prefixo → substring → fuzzy"
  (primeiro tier não-vazio vence), e as linhas Match prefixo / Match substring /
  Ambíguo da matriz ganharam exemplos coerentes com o fixture. Evita: um tier de
  resolução que nunca executa e um critério de aceitação impossível. KEEP: a
  ordem determinística (`points` desc, desempate `player_id`) e o fato de só
  linhas de `available` poderem voltar.
- **2026-09-01 — Patches da revisão adversarial (iteração 1, sem loopback).**
  Findings tratados como patch, código ajustado no lugar: (a) o curto-circuito
  "nome exato de drafted → none" passou a rodar só depois de exato/prefixo/
  substring vazios, para não engolir um prefixo válido de outro jogador
  disponível; (b) `.warroom_normalize_name` cai para a string minúscula pré-`iconv`
  quando `iconv(., "ASCII//TRANSLIT")` devolve `NA`; (c) nomes normalizados vazios
  nunca casam; (d) `available_board` valida coluna `pos`/ordenável e desempata por
  `player_id`; (e) o loop de comando embrulha cada iteração — um erro de
  render/derive vira mensagem, o draft não morre; (f) `save_state` no `/quit`
  também é protegido; (g) lista de desambiguação > 25 vira "seja mais especifico".

## Design Notes

- Guarda de execução: `if (sys.nframe() == 0L) run_draft()` roda sob
  `Rscript scripts/draft.R` (frame 0 no topo) mas não sob `source("scripts/draft.R")`
  a partir de `tests/smoke.R` (frame > 0 dentro de `source`). Mesmo idioma usado
  por scripts R de linha de comando; evita um segundo sentinel.
- `resolve_player` só devolve linhas de `view$available`; recebe também
  `snapshot$players` como `all_players`. Quando exato/prefixo/substring dão vazio
  e o query é o nome exato de alguém que está no snapshot mas fora do board, o
  resultado é `"none"` (drafted) em vez de o fuzzy sugerir vizinhos a distância 1.
  A checagem roda **depois** dos três tiers determinísticos, para não engolir um
  prefixo legítimo de outro jogador disponível (ex.: "Mike Williams" draftado,
  "Mike Williams Jr" livre). A mesma função serve a busca da Shiny (story 8).
- `.warroom_normalize_name` cai para a string minúscula pré-`iconv` por elemento
  quando `iconv(., "ASCII//TRANSLIT")` devolve `NA` (acontece por elemento e, em
  alguns locales, para todos) — sem isso todo query resolveria `"none"` em
  silêncio. Nomes que normalizam para `""` nunca casam em nenhum tier.
- O loop de comando embrulha cada iteração inteira em `tryCatch`: um erro
  inesperado em `derive_draft_view`, num renderer ou no dispatch vira uma linha
  "erro inesperado: ..." e o loop continua — um draft ao vivo não pode morrer por
  bug de exibição (SPEC "Why"). Só `/quit` e o draft completo encerram. `/quit` e
  todo save passam por `safe_save`, que reporta falha sem abortar.
- Lista de desambiguação limitada: acima de 25 candidatos o adapter imprime
  "N jogadores casam ... seja mais especifico" e não prompta número, para uma
  tecla solta não despejar 100+ linhas no dia do draft.
- Fuzzy com hit único grava o pick sem confirmação (matriz "Match fuzzy"): o
  limite `adist` de `floor(nchar/3)` é conservador; um `"did you mean?"` no tier
  fuzzy é candidato a melhoria futura mas está fora do escopo desta story.
- Ordem prefixo → substring: um match de prefixo é sempre também um match de
  substring, então "substring antes de prefixo" tornaria o tier prefixo
  inalcançável (defeito herdado de `operations.md`, renegociado com o humano). Com
  prefixo antes, um `"cee"` casa "CeeDee ..." pelo começo antes de cair no
  `contains`.
- `adist()` fuzzy: computar a distância do `query` normalizado a cada nome
  normalizado disponível, pegar o mínimo; se `min <= max(1, floor(nchar/3))`,
  candidatos são todos os empates nesse mínimo. Determinístico.
- `/rec` degradado: a guarda `exists("recommend_players", mode = "function")`
  deixa o comando cabeado e a story 5 o acende sem tocar em `scripts/draft.R`.
- Entrada de linha via `.warroom_read_line(con)` = `readLines(con, n = 1L)`. EOF
  (`character(0)` → `NA`) no meio do loop vira `/quit` para o `textConnection` do
  teste terminar limpo; uma linha em branco só re-prompta.
- `con = NULL` abre `file("stdin", open = "r")`, não `stdin()`: sob
  `Rscript scripts/draft.R` com um pipe, `readLines(stdin(), n = 1L)` retorna
  `character(0)` de imediato; `file("stdin")` lê tanto pipe quanto terminal.
  `run_draft` fecha essa conexão via `on.exit`.

## Verification

**Commands:**
- `make test` -- expected: status 0, sem rede; bloco de story 4 + stories 1–3.
- `Rscript -e 'source("R/load_core.R"); load_core(); snap <- build_synthetic_projections(); v <- derive_draft_view(new_draft(snap, sprintf("Team %02d", 1:12), "Team 01"), snap); r <- resolve_player("wr synthetic 05", v$available); stopifnot(r$status == "unique", nrow(r$players) == 1L)'`
  -- expected: sem erro.
- `grep -nE "recommend_players|simulate_draft|shiny|scrape_data|http[s]?://" scripts/draft.R`
  -- expected: só linhas de `recommend_players` sob `exists(...)`.
- `printf 'Team 01,Team 02,Team 03,Team 04,Team 05,Team 06,Team 07,Team 08,Team 09,Team 10,Team 11,Team 12\n/status\n/quit\n' | Rscript scripts/draft.R` com `state/` limpo
  -- expected: cria `state/draft.rds`, imprime status do pick 1, sai 0.

## Suggested Review Order

**O adapter e seu contorno (comece aqui)**

- Ponto de entrada: `run_draft()` — resolve defaults, cria/retoma, roda o loop; nenhuma regra de negócio.
  [`draft.R:122`](../../../../scripts/draft.R#L122)
- O loop embrulha cada iteração inteira — erro de render/derive vira mensagem, o draft não morre.
  [`draft.R:181`](../../../../scripts/draft.R#L181)
- `safe_save`: todo pick, `/undo`, `/save` e `/quit` salvam pelo mesmo helper que reporta falha sem abortar.
  [`draft.R:143`](../../../../scripts/draft.R#L143)
- Guarda de execução: roda sob `Rscript`, fica inerte quando `source()`-d pelo smoke.
  [`draft.R:285`](../../../../scripts/draft.R#L285)

**Resolução de nome de jogador (a mecânica central da story)**

- `resolve_player`: ordem exato → prefixo → substring → fuzzy `adist`, primeiro tier não-vazio vence.
  [`core.R:373`](../../../../R/core.R#L373)
- Curto-circuito "nome exato de drafted → none" roda só depois dos três tiers, para não engolir prefixo válido.
  [`core.R:402`](../../../../R/core.R#L402)
- `.warroom_normalize_name` com fallback quando `iconv` devolve `NA`; nomes vazios nunca casam.
  [`core.R:343`](../../../../R/core.R#L343)
- Filtro `ok` de nomes não-vazios aplicado a todos os tiers, inclusive o fuzzy.
  [`core.R:393`](../../../../R/core.R#L393)

**Board e desambiguação**

- `available_board`: valida coluna ordenável/`pos`, filtro NA-safe, desempate determinístico por `player_id`.
  [`core.R:438`](../../../../R/core.R#L438)
- Lista de desambiguação acima de 25 candidatos não prompta número — "seja mais especifico".
  [`draft.R:234`](../../../../scripts/draft.R#L234)
- `.warroom_fmt_player`: guarda cada campo contra ausência e `NA` antes de formatar.
  [`draft.R:39`](../../../../scripts/draft.R#L39)
- `/rec` degradado atrás de `exists("recommend_players")`; colunas alinhadas a `recommendation-algorithm.md`.
  [`draft.R:86`](../../../../scripts/draft.R#L86)

**Periféricos**

- Bloco offline de story 4: cada linha da matriz I/O, `tempdir()` apenas, sem rede.
  [`smoke.R:713`](../../../../tests/smoke.R#L713)
- Ensaio reduzido: 8 picks + `/quit`, depois retomada até os 168 picks.
  [`smoke.R:753`](../../../../tests/smoke.R#L753)
- Edge do loop: `/help`, linha em branco, número fora do range, EOF sem `/quit` → save limpo.
  [`smoke.R:802`](../../../../tests/smoke.R#L802)
- Auto-recomendação na vez do usuário aparece antes do prompt (checagem de ordem).
  [`smoke.R:822`](../../../../tests/smoke.R#L822)
- Regressão da ordem de matching: nome exato de drafted que é prefixo de um disponível.
  [`smoke.R:875`](../../../../tests/smoke.R#L875)
