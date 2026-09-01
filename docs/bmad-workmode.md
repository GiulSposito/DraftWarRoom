# A rota BMAD adequada para este projeto

Não use o fluxo completo:

```text
Product Brief
→ PRD
→ UX
→ Architecture
→ Epics
→ Sprint Planning
→ Development
```

Para o Fantasy War Room isso seria excesso de processo. O projeto é melhor classificado como **um único resultado coerente que exige várias sessões de implementação**. No BMAD atual, isso corresponde ao caminho:

```text
intent rico
    ↓
bmad-spec
    ↓
SPEC.md + companions + stories.yaml
    ↓
bmad-build, uma vez por story
    ↓
bmad-retrospective
```

O próprio BMAD chama isso de **spec-backed epic**: um epic sustentado por uma `SPEC.md`, dividido em stories ordenadas. Esse caminho não usa `sprint-status.yaml`, nem precisa de PRD, arquitetura formal ou sprint planning. ([BMAD Method][1])

---

# 1. Transforme nossa conversa em input, não em `SPEC.md`

Não copie diretamente a resposta anterior para um arquivo chamado `SPEC.md`.

No BMAD atual, `bmad-spec` é o responsável por escrever e atualizar `SPEC.md`; o material fornecido por você funciona como **intent**, fonte ou brain dump. O skill destila isso para um contrato curto com:

* Why;
* Capabilities;
* Constraints;
* Non-goals;
* Success signal;

e coloca detalhes técnicos maiores em companion files ao lado da spec. ([GitHub][2])

Preparei esse input já consolidado, eliminando a arquitetura antiga e preservando a implementação simplificada:

[Baixar `fantasy-warroom-bmad-intent.md`](sandbox:/mnt/data/fantasy-warroom-bmad-intent.md)

Coloque-o no repositório assim:

```bash
mkdir -p docs/intent
cp ~/Downloads/fantasy-warroom-bmad-intent.md \
  docs/intent/fantasy-warroom-intent.md
```

A estrutura inicial pode ser:

```text
fantasy-warroom/
├── docs/
│   └── intent/
│       └── fantasy-warroom-intent.md
├── .gitignore
└── README.md
```

O arquivo que preparei já contém:

* objetivo e escopo;
* configuração da liga;
* restrições técnicas;
* uso de R e RDS;
* papel do `ffanalytics`;
* contratos dos RDS;
* funções centrais;
* terminal;
* algoritmo de recomendação;
* simulador;
* Shiny;
* testes;
* não objetivos;
* ordem obrigatória das oito stories.

Ele também declara explicitamente que substitui a arquitetura anterior com SQLite, event sourcing, package architecture e simulação assíncrona.

---

# 2. Instale ou atualize o BMAD no repositório

Dentro do diretório do projeto:

```bash
cd fantasy-warroom
git init
npx bmad-method install
```

O instalador pergunta quais módulos e ferramentas devem ser configurados. Para ver os IDs atualmente aceitos:

```bash
npx bmad-method install --list-tools
```

O BMAD requer Node.js 20.12 ou posterior. A instalação também verifica `uv`, necessário para skills como Build e Build Auto na distribuição atual. ([GitHub][3])

Para Claude Code, a instalação não interativa documentada é:

```bash
npx bmad-method install \
  --directory . \
  --modules bmm \
  --tools claude-code \
  --yes
```

Para Codex, rode primeiro `--list-tools` e use exatamente o identificador exibido pela sua versão do instalador, evitando assumir um ID que possa ter mudado.

## Mudança de nome importante

Desde o BMAD v6.11.0, publicado em **9 de agosto de 2026**, o fluxo chamado **Quick Dev** passou a se chamar **Build**:

```text
bmad-quick-dev  → bmad-build
bmad-dev-auto   → bmad-build-auto
```

Portanto, em uma instalação atual, use `/bmad-build`. Em uma instalação antiga que ainda mostre `/bmad-quick-dev`, atualize o BMAD ou use temporariamente o nome legado. ([GitHub][4])

---

# 3. Abra o agente no diretório correto

Para Claude Code:

```bash
claude
```

Para Codex, abra-o no mesmo diretório raiz do repositório.

O agente precisa enxergar:

```text
docs/intent/fantasy-warroom-intent.md
.git/
_bmad/
```

Não execute o fluxo a partir de outro diretório, porque o BMAD resolve o project root, os outputs e as instruções do repositório a partir daí.

---

# 4. Crie o contexto permanente do projeto

Antes da spec, rode:

```text
/bmad-project-context
```

Use este prompt:

```text
Set up project context for this repository.

Read docs/intent/fantasy-warroom-intent.md and preserve these
cross-cutting rules:

- R is the only application language.
- Runtime and persistent data use RDS.
- ffanalytics is allowed only in scripts/prepare.R.
- The live draft path performs no network calls.
- Business logic lives in plain functions under R/.
- app.R and scripts/ are adapters over the same functional core.
- Persist ordered picks and derive rosters, availability and current pick.
- Do not introduce SQLite, R6, golem, targets, Docker, APIs,
  background workers or live Monte Carlo.
- Implement terminal and simulation before Shiny.
- Run make test after every implementation story.
- Run make simulate after recommendation or simulation changes.
- Do not implement future stories while working on the current story.
```

O `bmad-project-context` gera um bloco pequeno e verificado em `AGENTS.md`. Para Claude Code, ele pode também propor um `CLAUDE.md` que importe `AGENTS.md`, evitando manter duas cópias divergentes das mesmas instruções. ([BMAD Method][5])

O resultado desejado é aproximadamente:

```text
fantasy-warroom/
├── AGENTS.md
├── CLAUDE.md
├── docs/
│   └── intent/
│       └── fantasy-warroom-intent.md
└── _bmad/
```

Não coloque toda a especificação em `AGENTS.md`. Esse arquivo deve guardar apenas as regras que o código sozinho não consegue demonstrar.

---

# 5. Gere a spec e as stories em uma única operação

Agora execute:

```text
/bmad-spec Create a spec named fantasy-warroom from
docs/intent/fantasy-warroom-intent.md.

Treat it as one spec-backed epic, not as a full BMAD project.

The intent file is authoritative and supersedes earlier designs.
Keep SPEC.md lean and preserve load-bearing technical details as
companion files.

Then perform Story Breakdown using exactly the eight stories,
names and execution order specified in the "Required story order"
section of the intent file.

Do not create a PRD, project architecture, traditional epics,
sprint-status.yaml or sprint-planning artifacts.

Use fantasy-warroom as the spec folder slug.
```

O padrão oficial do BMAD permite pedir a criação da spec e o Story Breakdown na mesma chamada. A saída esperada será semelhante a: ([BMAD Method][6])

```text
_bmad-output/
└── specs/
    └── spec-fantasy-warroom/
        ├── SPEC.md
        ├── stories.yaml
        ├── .memlog.md
        └── implementation-details.md
```

O nome exato dos companions pode variar. O relevante é que:

* `SPEC.md` guarde o contrato conciso;
* os companions guardem contratos RDS, fórmulas e desenho técnico;
* `stories.yaml` guarde a sequência de implementação.

---

# 6. O que revisar antes de começar a programar

Abra:

```bash
cat _bmad-output/specs/spec-fantasy-warroom/SPEC.md
cat _bmad-output/specs/spec-fantasy-warroom/stories.yaml
```

Confirme que `SPEC.md` preservou estes pontos:

```text
R-only
RDS-only
single user
local execution
terminal first
ffanalytics only before draft
no live network
no database
no live Monte Carlo
Shiny as thin shell
```

E confirme que `stories.yaml` está nessa ordem:

```text
1. Walking skeleton and synthetic snapshot
2. ffanalytics projection adapter
3. Snake schedule, draft state, and RDS persistence
4. Operational terminal draft
5. Roster-aware recommendation foundation
6. Market-aware wait intelligence
7. Mock simulator and calibration
8. Thin Shiny War Room
```

No formato atual do BMAD, a ordem física das entradas em `stories.yaml` é a ordem de execução. Os IDs devem ser strings, como `"1"` e `"2"`, e não devem receber um campo `status`; o estado detalhado aparece nos registros gerados para cada story. ([GitHub][7])

Exemplo aceitável:

```yaml
- id: "1"
  title: Walking skeleton and synthetic snapshot
  description: >-
    Create the minimal R repository, synthetic projections fixture,
    Makefile and smoke-test execution path.
  spec_checkpoint: true
  done_checkpoint: true

- id: "2"
  title: ffanalytics projection adapter
  description: >-
    Generate and normalize projections.rds through the pre-draft
    preparation script without changing the runtime contract.
  spec_checkpoint: true
```

Caso o `bmad-spec` invente uma decisão ou perca uma restrição, não edite `SPEC.md` à mão. Reexecute:

```text
/bmad-spec Update the fantasy-warroom spec.

The generated spec incorrectly allows <problema>.
The authoritative intent requires <regra correta>.

Preserve existing capability IDs and regenerate affected companions
and stories.yaml.
```

O BMAD recomenda atualizar a spec pelo próprio skill para preservar IDs e rastreabilidade. ([BMAD Method][8])

---

# 7. Como usar a implementação rápida

## O significado atual de “implementação rápida”

No BMAD atual, a antiga ideia de **Quick Dev** está incorporada em:

```text
/bmad-build
```

O Build recebe:

* uma frase;
* um issue;
* um arquivo de intent;
* uma spec;
* ou uma story planejada;

e executa:

```text
clarificação do objetivo
→ investigação do repositório
→ plano
→ implementação
→ revisão
→ correções
```

Um Build deve receber **um único objetivo coerente**, normalmente limitado a um pequeno conjunto de arquivos e algo próximo de algumas centenas de linhas alteradas. Por isso, não peça para ele implementar as oito stories em uma única chamada. ([BMAD Method][9])

## Story 1

Abra uma conversa nova e execute:

```text
/bmad-build Implement story 1, Walking skeleton and synthetic snapshot,
from _bmad-output/specs/spec-fantasy-warroom/stories.yaml.

Respect the parent SPEC.md and all companion files.
Do not implement any part of story 2 or later stories.
```

Quando ele apresentar o plano, verifique se inclui apenas:

```text
config.R
Makefile
R/core.R
synthetic projections fixture
tests/smoke.R
minimal directory structure
```

Não permita que ele já integre scraping, implemente o terminal completo ou crie Shiny.

Ao final:

```bash
make test
git status
git diff
```

Revise e faça um commit caso o Build não tenha criado um:

```bash
git add .
git commit -m "feat: create fantasy warroom walking skeleton"
```

## Story 2

Comece uma nova conversa:

```text
/bmad-build Implement story 2, ffanalytics projection adapter,
from _bmad-output/specs/spec-fantasy-warroom/stories.yaml.

Preserve the projections.rds runtime contract established by story 1.
The adapter may use ffanalytics only in scripts/prepare.R.
Do not make the runtime depend on live scraping.
```

## Story 3

```text
/bmad-build Implement story 3, Snake schedule, draft state,
and RDS persistence,
from _bmad-output/specs/spec-fantasy-warroom/stories.yaml.

Persist only draft facts and derive current pick, rosters and
availability. Do not implement the terminal loop yet.
```

## Story 4

```text
/bmad-build Implement story 4, Operational terminal draft,
from _bmad-output/specs/spec-fantasy-warroom/stories.yaml.

Use the functional core from prior stories.
Implement the terminal adapter without placing business rules
inside scripts/draft.R.
```

## Story 5

```text
/bmad-build Implement story 5, Roster-aware recommendation foundation,
from _bmad-output/specs/spec-fantasy-warroom/stories.yaml.

Implement deterministic lineup value, marginal roster value,
VOR and tier ranking, guardrails, labels and explanations.
Do not implement p_next or wait-cost logic from story 6.
```

## Story 6

```text
/bmad-build Implement story 6, Market-aware wait intelligence,
from _bmad-output/specs/spec-fantasy-warroom/stories.yaml.

Implement p_next, expected best survivor, wait cost, tier cliff,
ADP value and the configurable final score.
Keep the live calculation deterministic and free of Monte Carlo.
```

## Story 7

```text
/bmad-build Implement story 7, Mock simulator and calibration,
from _bmad-output/specs/spec-fantasy-warroom/stories.yaml.

Implement seeded mock drafts, ADP/VOR/War Room strategy comparison,
roster validation and a small transparent weight grid.
Do not introduce a genetic algorithm.
```

## Story 8

```text
/bmad-build Implement story 8, Thin Shiny War Room,
from _bmad-output/specs/spec-fantasy-warroom/stories.yaml.

Use exactly the same core recommendation and persistence functions
as the terminal. Do not duplicate formulas in Shiny reactives.
Verify that terminal and Shiny produce the same recommendation
order from the same RDS state.
```

Esse formato segue o exemplo oficial de uso:

```text
/bmad-build Implement story 1, <story name>,
from <spec folder>/stories.yaml.
```

Cada execução produz o código e um registro de implementação associado à story e à parent spec. ([BMAD Method][6])

---

# 8. Use uma conversa nova por story

Não continue as oito stories na mesma sessão longa do Claude Code ou Codex.

Use este ciclo:

```text
nova conversa
→ bmad-build story N
→ revisar plano
→ implementar
→ make test
→ revisar diff
→ commit
→ fechar conversa
```

Isso evita que:

* contexto antigo domine decisões novas;
* o agente implemente story futura por antecipação;
* erros de uma story contaminem todas as seguintes;
* o custo de contexto aumente progressivamente.

O contexto comum não se perde porque permanece em:

```text
AGENTS.md
SPEC.md
companions
stories.yaml
código existente
testes existentes
git history
```

---

# 9. Onde usar `bmad-build-auto`

Não comece com automação total.

A recomendação do próprio BMAD é usar Build atendido nas stories iniciais, arquiteturalmente importantes ou arriscadas, e só introduzir Build Auto depois que padrões e decisões estiverem estáveis. ([BMAD Method][10])

Para este projeto:

| Story | Modo sugerido              | Motivo                           |
| ----- | -------------------------- | -------------------------------- |
| 1     | `bmad-build`               | estabelece estrutura             |
| 2     | `bmad-build`               | integração externa e schema      |
| 3     | `bmad-build`               | estado e recuperação             |
| 4     | `bmad-build`               | operação real do draft           |
| 5     | `bmad-build`               | base do algoritmo                |
| 6     | `bmad-build`               | decisão estratégica crítica      |
| 7     | `bmad-build-auto` opcional | padrões já estarão estabilizados |
| 8     | `bmad-build`               | UX operacional do draft          |

Para experimentar automação na story 7:

```text
/bmad-build-auto Implement story 7 from
_bmad-output/specs/spec-fantasy-warroom/stories.yaml.

Follow the parent spec and companions.
Run make test and make simulate.
Stop blocked rather than inventing missing algorithm decisions.
```

O `bmad-build-auto` executa uma unidade sem interação, grava seu resultado no registro da story e pode retomar pelo status persistido. Ele não escolhe sozinho a próxima story e não deve atuar como dono do backlog. ([BMAD Method][11])

---

# 10. A implementação realmente rápida

O ganho de velocidade não vem de mandar um agente construir tudo de uma vez. Vem de reduzir o processo BMAD a:

```text
1 input autoritativo
1 spec-backed epic
8 slices pequenas
1 Build por slice
0 PRDs
0 arquitetura corporativa
0 sprint planning
0 banco de dados
0 duplicação terminal/Shiny
```

A sequência operacional é:

```bash
# Shell
mkdir fantasy-warroom
cd fantasy-warroom
git init

npx bmad-method install
mkdir -p docs/intent

# Copiar o intent preparado para:
# docs/intent/fantasy-warroom-intent.md

claude
```

Dentro do Claude Code:

```text
/bmad-project-context
```

Depois:

```text
/bmad-spec Create a spec named fantasy-warroom from
docs/intent/fantasy-warroom-intent.md and break it into the
eight required stories.
```

Depois, em oito conversas separadas:

```text
/bmad-build Implement story N from
_bmad-output/specs/spec-fantasy-warroom/stories.yaml.
```

---

# 11. O que não fazer

## Não rode full planning

Evite:

```text
bmad-product-brief
bmad-prd
bmad-architecture
bmad-create-epics-and-stories
bmad-sprint-planning
```

Esses artefatos seriam justificados se houvesse vários produtos, equipes, epics ou decisões organizacionais compartilhadas. Para um único desenvolvedor e um único epic coerente, a documentação do BMAD recomenda ir diretamente para `bmad-spec`. ([BMAD Method][12])

## Não entregue o documento antigo e o novo como igualmente autoritativos

Caso queira conservar a especificação anterior:

```text
docs/archive/fantasy-draft-war-room-original-spec.md
```

Mas mantenha no novo intent:

```text
This document supersedes earlier architecture proposals.
```

Caso contrário, o agente poderá tentar conciliar decisões incompatíveis, como RDS e SQLite.

## Não peça “implemente todo o projeto”

Isso transforma oito objetivos revisáveis em uma execução longa e difícil de controlar.

## Não comece pelo Shiny

A interface deve aparecer somente quando:

```text
make test
make simulate
make draft
```

já funcionarem.

## Não use Build Auto para decidir as fórmulas

`p_next`, wait cost, lineup value e guardrails precisam de revisão humana porque definem como o sistema recomendará suas escolhas.

---

# 12. Fechamento do epic

Depois da story 8:

```bash
make test
make simulate
make draft
make app
```

Faça um rehearsal reduzido no terminal e outro no Shiny usando o mesmo estado.

Então execute:

```text
/bmad-retrospective _bmad-output/specs/spec-fantasy-warroom/
```

Para um spec-backed epic, a retrospectiva lê:

* `SPEC.md`;
* `stories.yaml`;
* registros das stories;
* commits;
* diff completo;
* evidências de testes;

e avalia o resultado combinado, não apenas cada story isoladamente. ([BMAD Method][13])

## Fluxo final

```text
docs/intent/fantasy-warroom-intent.md
                  │
                  ▼
              bmad-spec
                  │
        ┌─────────┴──────────┐
        ▼                    ▼
     SPEC.md           companions técnicos
        │
        ▼
   stories.yaml
        │
        ├── story 1 → bmad-build
        ├── story 2 → bmad-build
        ├── story 3 → bmad-build
        ├── story 4 → bmad-build
        ├── story 5 → bmad-build
        ├── story 6 → bmad-build
        ├── story 7 → build ou build-auto
        └── story 8 → bmad-build
                  │
                  ▼
          bmad-retrospective
```

Essa é a forma de usar o BMAD sem deixar o método tornar-se maior que o próprio Fantasy War Room.

[1]: https://docs.bmad-method.org/plan/choose-a-planning-path/?utm_source=chatgpt.com "Choose a Planning Path | BMAD Method"
[2]: https://github.com/bmad-code-org/BMAD-METHOD/blob/main/src/core-skills/bmad-spec/SKILL.md?utm_source=chatgpt.com "BMAD-METHOD/src/core-skills/bmad-spec/SKILL.md at main · bmad-code-org/BMAD-METHOD · GitHub"
[3]: https://github.com/bmad-code-org/BMAD-METHOD/blob/main/docs/start/install-bmad.md?utm_source=chatgpt.com "BMAD-METHOD/docs/start/install-bmad.md at main · bmad-code-org/BMAD-METHOD · GitHub"
[4]: https://github.com/bmad-code-org/BMAD-METHOD/blob/main/CHANGELOG.md?utm_source=chatgpt.com "BMAD-METHOD/CHANGELOG.md at main · bmad-code-org/BMAD-METHOD · GitHub"
[5]: https://docs.bmad-method.org/how-to/project-context/?utm_source=chatgpt.com "Manage Project Context | BMAD Method"
[6]: https://docs.bmad-method.org/existing-codebases/getting-deeper/?utm_source=chatgpt.com "Getting Deeper | BMAD Method"
[7]: https://github.com/bmad-code-org/BMAD-METHOD/blob/main/src/bmm-skills/plan/bmad-spec/assets/stories-schema.md?utm_source=chatgpt.com "BMAD-METHOD/src/bmm-skills/plan/bmad-spec/assets/stories-schema.md at main · bmad-code-org/BMAD-METHOD · GitHub"
[8]: https://docs.bmad-method.org/plan/define-requirements-and-a-specification/?utm_source=chatgpt.com "Define Requirements and a Specification | BMAD Method"
[9]: https://docs.bmad-method.org/build/build-a-change/?utm_source=chatgpt.com "Build a Change | BMAD Method"
[10]: https://docs.bmad-method.org/how-to/choose-a-development-path/?utm_source=chatgpt.com "Choose a Development Path | BMAD Method"
[11]: https://docs.bmad-method.org/cs/reference/dev-auto/?utm_source=chatgpt.com "Autonomous Development Loops | BMAD Method"
[12]: https://docs.bmad-method.org/plan/plan-inside-an-organization/?utm_source=chatgpt.com "Plan Inside an Organization | BMAD Method"
[13]: https://docs.bmad-method.org/build/finish-an-epic/?utm_source=chatgpt.com "Finish an Epic | BMAD Method"
