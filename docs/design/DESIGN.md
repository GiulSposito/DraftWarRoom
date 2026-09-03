---
name: Fantasy Draft War Room
description: UX visual identity for the local, offline-first fantasy draft operator tool.
status: final
created: 2026-08-29
updated: 2026-08-31
change_log:
  - "2026-08-31: Sprint Change Proposal (app local de uso único). Os design tokens abaixo permanecem a fonte visual. UX-DR3 (auditoria de contraste WCAG como entregável) deixa de ser uma story — os pares de token abaixo são aceitos como estão. Ver _bmad-output/planning-artifacts/sprint-change-proposal-2026-08-31.md §4.4."
sources:
  - ../../prds/prd-Fantasy Draft War Room-2026-08-28/prd.md
  - ../../prds/prd-Fantasy Draft War Room-2026-08-28/data-contract.md
  - ../../prds/prd-Fantasy Draft War Room-2026-08-28/decisions.md
  - ../../architecture/architecture-Fantasy Draft War Room-2026-08-28/ARCHITECTURE-SPINE.md
  - ../../../../docs/fantasy-draft-war-room-spec.md
colors:
  canvas: '#0B0F14'
  surface: '#121922'
  surface-raised: '#18222E'
  border: '#293746'
  ink: '#E7EDF3'
  ink-muted: '#91A0AF'
  action: '#57D68D'
  action-ink: '#06120B'
  focus: '#67B7FF'
  warning: '#F2C14E'
  danger: '#FF6B6B'
typography:
  display:
    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace'
    fontSize: 18px
    fontWeight: '700'
    lineHeight: '1.2'
  data:
    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace'
    fontSize: 14px
    fontWeight: '500'
    lineHeight: '1.3'
  label:
    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace'
    fontSize: 11px
    fontWeight: '700'
    lineHeight: '1.2'
    letterSpacing: '0.06em'
rounded:
  sm: 2px
  md: 4px
  full: 9999px
spacing:
  '1': 4px
  '2': 8px
  '3': 12px
  '4': 16px
  '5': 24px
  gutter: 12px
components:
  focus-ring:
    color: '{colors.focus}'
    width: 2px
    offset: 2px
  status-strip:
    background: '{colors.surface}'
    foreground: '{colors.ink}'
    current-pick: '{colors.action}'
    current-pick-foreground: '{colors.action-ink}'
    radius: '{rounded.sm}'
  panel:
    background: '{colors.surface}'
    border: '{colors.border}'
    radius: '{rounded.sm}'
  candidate-active:
    background: '{colors.surface-raised}'
    outline: '{components.focus-ring.color}'
  undo:
    foreground: '{colors.warning}'
    border: '{colors.border}'
    radius: '{rounded.sm}'
  search-autocomplete:
    background: '{colors.surface-raised}'
    foreground: '{colors.ink}'
    focus: '{colors.focus}'
  smart-list:
    background: '{colors.surface}'
    foreground: '{colors.ink}'
    active: '{components.candidate-active.background}'
  draft-board:
    background: '{colors.surface}'
    current-pick: '{colors.action}'
  operator-roster:
    background: '{colors.surface}'
    foreground: '{colors.ink}'
  inspection-panel:
    background: '{colors.surface-raised}'
    border: '{colors.border}'
  event-history:
    foreground: '{colors.ink-muted}'
  pause-export:
    foreground: '{colors.ink}'
    border: '{colors.border}'
  feedback-error:
    success: '{colors.action}'
    error: '{colors.danger}'
  session-picker:
    background: '{colors.surface}'
    selected: '{colors.surface-raised}'
    focus: '{colors.focus}'
  snapshot-quality:
    background: '{colors.surface}'
    warning: '{colors.warning}'
    error: '{colors.danger}'
  league-setup:
    background: '{colors.surface}'
    border: '{colors.border}'
  snake-order:
    background: '{colors.surface-raised}'
    locked: '{colors.ink-muted}'
  candidate-row:
    background: '{colors.surface}'
    active: '{components.candidate-active.background}'
---

## Brand & Style

Fantasy Draft War Room é um instrumento operacional local: um posto de comando para acompanhar a ESPN e agir antes que o próximo pick passe. A tela privilegia leitura em varredura, dados compactos e ação por teclado; não parece um produto esportivo editorial nem uma dashboard promocional.

[ASSUMPTION] Tema escuro único, com estética de terminal sóbria: sem textura, brilho neon, mascotes ou cromos de atletas. A identidade vem da precisão e da cadência dos dados, não de decoração.

## Colors

- **Canvas** `{colors.canvas}` é o fundo contínuo, para a janela permanecer discreta ao lado da ESPN.
- **Surfaces** `{colors.surface}` e `{colors.surface-raised}` separam painéis e a linha em foco sem usar sombras pesadas.
- **Ink** `{colors.ink}` e `{colors.ink-muted}` criam a hierarquia de leitura: nome/pick primeiro; contexto e metadados depois.
- **Action** `{colors.action}` só marca o pick vivo, a confirmação e a ação que será executada. Não é cor decorativa.
- **Focus** `{colors.focus}` identifica foco de teclado e resultado selecionado; nunca depende só da cor, devendo manter contorno visível.
- **Warning** `{colors.warning}` identifica undo e estado que pede conferência. **Danger** `{colors.danger}` fica reservado para falha, conflito ou ação inválida.

[ASSUMPTION] Os valores são escolhas iniciais de alto contraste e devem ser validados em uso real no notebook; não há modo claro no V1.

Combinações permitidas: `{colors.ink}` sobre `{colors.canvas}`, `{colors.surface}` ou `{colors.surface-raised}` deve atingir 4.5:1; `{colors.ink-muted}` só identifica metadados não críticos e também deve atingir 4.5:1; `{colors.focus}` contra `{colors.canvas}` e `{colors.surface-raised}`, e `{colors.action}`, `{colors.warning}` ou `{colors.danger}` quando usados como indicador não textual, devem atingir 3:1. Todo estado usa texto, ícone ou rótulo além da cor.

## Typography

[ASSUMPTION] A pilha de monoespaçada do sistema evita dependência de fonte e sustenta a leitura tabular e de atalhos. `{typography.display}` é para o jogador e pick atual; `{typography.data}` para nomes, ranks e colunas; `{typography.label}` para rótulos curtos em caixa alta. Não usar texto decorativo ou títulos grandes: durante o draft, informação vence personalidade.

## Layout & Spacing

A Live War Room usa toda a largura disponível, em painéis com bordas finas e `{spacing.gutter}` entre eles. O cabeçalho operacional fica fixo: pick atual, time no relógio, próximo pick do operador e estado da sessão sempre aparecem antes de qualquer ranking.

[ASSUMPTION] Em uma janela estreita lado a lado com a ESPN, o layout preserva nesta ordem: estado/pick, busca e candidato ativo, recomendações, roster do operador e board. Painéis secundários podem compactar ou alternar por abas, mas o cabeçalho e a busca nunca saem da vista. Linhas densas usam `{spacing.2}`; só superfícies principais usam `{spacing.4}`.

Referência de composição: [Live War Room](mockups/live-war-room.html) — estado, busca, candidatos, inspeção, undo, board, roster e auditoria em janela estreita. Os spines vencem em qualquer conflito com o mockup.

## Elevation & Depth

Profundidade vem de tom, borda e foco, não de cartões flutuantes. `{colors.surface-raised}` indica a linha ou painel ativo; foco de teclado recebe `{components.focus-ring.width}` em `{components.focus-ring.color}`. [ASSUMPTION] Sombras são omitidas, exceto uma sombra discreta sob popovers de busca e diálogos de confirmação.

## Shapes

[ASSUMPTION] Cantos quase retos ({rounded.sm}) deixam board, tabelas, campos e ações com aspecto de ferramenta. `{rounded.md}` vale apenas para popovers e diálogos. Pílulas ({rounded.full}) ficam restritas a pequenos badges de posição, nunca em ações primárias ou painéis.

## Components

- **Faixa de estado** — faixa fixa, com o overall pick em `{typography.display}`, time no relógio e próximo pick do operador; o pick vivo usa `{components.status-strip.current-pick}`. Estado pausado, alerta ou concluído usa texto e ícone além de cor.
- **Campo de busca + autocomplete** — campo de largura dominante com resultados imediatamente abaixo; cada linha traz nome, posição e time NFL. O resultado que `Enter` registrará usa `{components.candidate-active.background}` e contorno de foco, sem ambiguidade visual.
- **Lista inteligente** — tabela curta, ordenada, com posição, nome, tier, score e motivo resumido. A recomendação nº 1 é destacada por ordem e peso tipográfico, não por um card grande; filtros de posição são badges discretos.
- **Board de draft** — grade compacta por round/time com coluna ou linha do pick atual claramente marcada; jogador recém-registrado recebe realce transitório de `{colors.action}`, sem animação prolongada. Picks do operador são distinguíveis também por rótulo, não apenas cor.
- **Roster do operador** — matriz enxuta de slots: titulares, FLEX e banco têm grupos visuais estáveis; nomes ocupam uma linha e posição/time NFL ficam em `{typography.label}` ou `{colors.ink-muted}`.
- **Undo** — controle sempre visível, com atalho `U`, borda e texto `{components.undo.foreground}`. Enquanto houver picks efetivos para reverter, ele mostra de forma compacta o próximo pick que será desfeito (overall, jogador e time); [ASSUMPTION] o contador de reversões disponíveis aparece junto ao atalho para tornar o undo multinível óbvio, sem parecer uma ação destrutiva.
- **Painel de inspeção** — superfície contextual de `{components.inspection-panel.background}`; mostra dados e fatores sem cobrir estado ou busca.
- **Histórico de eventos** — lista compacta em `{components.event-history.foreground}` para registros, undos e correções; não compete com o board atual.
- **Pausa/exportação** — controles secundários de borda fina; pausa é sempre textual, exportação não aparece como ação destrutiva.
- **Feedback e erro** — confirmação de registro é breve, textual e próxima à barra de estado; erros persistem até o operador poder agir. Toasts não podem encobrir busca, pick atual ou foco de teclado.
- **Seleção de sessão** — lista curta de sessões com linha pré-selecionada em `{components.session-picker.selected}` e confirmação explícita; data e status são metadados compactos.
- **Qualidade do snapshot** — resumo com cobertura, metadados e avisos; bloqueios usam `{components.snapshot-quality.error}` e sempre incluem a ação de recuperação.
- **Configuração da liga** — formulário compacto em grupos previsíveis: times/rounds, slots/FLEX, scoring e time do operador; validade aparece junto ao grupo afetado.
- **Ordem snake** — grade compacta, com o estado travado visível em `{components.snake-order.locked}` e `Validate and Lock` como a única ação de transição.
- **Linha de candidato** — linha tabular de busca/recomendação; seu destaque ativo usa `{components.candidate-row.active}`, além de contorno e rótulo de foco.

## Do's and Don'ts

| Do | Don't |
|---|---|
| Manter pick atual, busca e foco de teclado imediatamente reconhecíveis | Exigir leitura de um dashboard para descobrir a próxima ação |
| Usar tabelas densas, alinhamento consistente e números monoespaçados | Trocar dados por cards grandes, imagens ou gráficos decorativos |
| Reservar verde para ação/pick vivo e azul para foco | Usar cor como único sinal de seleção, urgência ou erro |
| Exibir `U` e o próximo pick a desfazer de modo persistente | Esconder undo em menu, confirmação distante ou histórico |
| Fazer cada painel parecer parte do mesmo instrumento | Replicar a estética promocional ou a navegação da ESPN |
