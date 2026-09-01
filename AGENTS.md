<!-- bmad:context -->
<!-- Verificado em 2026-09-01 contra 42935f6 (greenfield, sem código ainda). Gerenciado por bmad-project-context; edições dentro deste bloco são substituídas no refresh. Mantenha fora dos marcadores o que quiser preservar. -->

## DraftWarRoom

War Room de draft de fantasy NFL: local, mono-usuário, em R, para um único draft snake de
12 times, Full PPR, 14 rounds. Prepara projeções antes do draft, simula drafts no terminal,
opera o draft ao vivo e gera recomendações de pick determinísticas e explicáveis. Intent
autoritativo: `docs/fantasy-warroom-bmad-intent.md`. Fluxo BMAD: `docs/bmad-workmode.md`.
Spec e stories (após `bmad-spec`): `_bmad-output/specs/spec-fantasy-warroom/`.

## Policy

- `docs/fantasy-warroom-bmad-intent.md` é a única fonte autoritativa. `docs/archive/` contém
  design antigo (SQLite, event sourcing, package architecture, Monte Carlo assíncrono) —
  histórico apenas, nunca reconciliar com ele.
- Nunca introduzir SQLite ou outro banco, event sourcing, R6, golem, targets, Docker, API,
  autenticação, background workers ou injeção de dependência. Persistência é RDS.
- Nunca fazer chamada de rede no caminho do draft ao vivo (`scripts/draft.R`, `app.R`, `R/`).
  `ffanalytics` e qualquer scraping só em `scripts/prepare.R`.
- Nunca rodar Monte Carlo no caminho de recomendação; o cálculo de custo de espera é
  analítico e determinístico.
- `data/projections.rds` é imutável durante um draft.
- Não implementar partes de stories futuras enquanto trabalha na story atual (ordem em
  `docs/fantasy-warroom-bmad-intent.md`, seção "Required story order").
- Terminal (`scripts/draft.R`) e simulador (`scripts/simulate.R`) funcionam antes de
  qualquer trabalho em Shiny (`app.R`).

## Where things are

- Regras de negócio: funções puras em `R/` (`core.R`, `recommendation.R`, `simulation.R`,
  `persistence.R`) — nunca dependem de `shiny`.
- Adapters sobre o mesmo core: `scripts/prepare.R`, `scripts/simulate.R`, `scripts/draft.R`,
  `app.R`. Sem fórmula ou regra de negócio duplicada neles.
- Contratos RDS (`data/projections.rds`, `state/draft.rds`) e contratos das funções core:
  `docs/fantasy-warroom-bmad-intent.md`.
- Ainda não existe código — repositório greenfield. Estrutura alvo no intent doc, seção
  "Repository shape".

## Running and verifying

Comandos ainda não existem (greenfield). Ao criar o `Makefile` (story 1), usar exatamente
estes alvos, todos via `Rscript`:

- `make test` -> `Rscript tests/smoke.R`. Rodar após toda story de implementação.
- `make simulate` -> `Rscript scripts/simulate.R`. Rodar também após qualquer mudança em
  recomendação ou simulação.
- `make prepare` -> `Rscript scripts/prepare.R` (único caminho que chama `ffanalytics`).
- `make draft` -> `Rscript scripts/draft.R`.
- `make app` -> `Rscript -e 'shiny::runApp(".")'`.

## Conventions that differ from defaults

- Persistir fatos, derivar visões: `state/draft.rds` guarda só os picks ordenados
  (`overall`, `player_id`, `entered_at`). Pick atual, time na vez, rosters, disponíveis,
  lineup e recomendações são sempre derivados, nunca persistidos.
- Pick atual é sempre `nrow(picks) + 1`.
- Save de estado é atômico: escrever `.tmp`, copiar estado anterior para `.bak`, renomear
  por cima. Todo pick aceito salva imediatamente.
- Recomendação é determinística: mesmo snapshot + config + picks produz a mesma ordem.
  Nada de RNG não-semeado no caminho de recomendação.
- Dependências fixadas com `renv`, incluindo uma versão/commit conhecido de `ffanalytics`.
- Runtime também tem que funcionar com um fixture de projeção sintético, sem depender de
  scrapers ao vivo.

<!-- /bmad:context -->
