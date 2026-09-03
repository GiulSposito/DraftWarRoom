---
name: Fantasy Draft War Room
description: UX experience contract for the local, offline-first fantasy draft operator tool.
status: final
created: 2026-08-29
updated: 2026-08-31
change_log:
  - "2026-08-31: Sprint Change Proposal (app local de uso único). Reduzido para keyboard-first + ARIA básico (roles/labels no combobox + uma região aria-live). Cortados como entregável: aria-controls/aria-activedescendant, roving tabindex, ordem de Tab célula a célula, `?` como referência de atalhos, zoom 200% linear, prefers-reduced-motion, piso de alvo 24x24px. Layout tem dois estados (amplo/estreito) sem painéis alternáveis que preservam foco. Sem `pause`/`resume` como fluxo dedicado. Ver sprint-change-proposal-2026-08-31.md §4.4 e a lista UX-DR anotada em epics.md."
sources:
  - ../../prds/prd-Fantasy Draft War Room-2026-08-28/prd.md
  - ../../prds/prd-Fantasy Draft War Room-2026-08-28/data-contract.md
  - ../../prds/prd-Fantasy Draft War Room-2026-08-28/decisions.md
  - ../../architecture/architecture-Fantasy Draft War Room-2026-08-28/ARCHITECTURE-SPINE.md
  - ../../../../docs/fantasy-draft-war-room-spec.md
---

# Fantasy Draft War Room — Experience Spine

## Foundation

Aplicação Shiny local, offline-first, de operador único. A superfície primária é notebook/desktop, em uma janela ao lado da ESPN NFL Fantasy; ela é a fonte visual paralela, nunca uma integração. O operador é expert, faz entradas manuais e precisa captar o estado e agir sem tirar os olhos do draft.

A Live War Room é uma superfície operacional única, densa e keyboard-first. `DESIGN.md` é a referência visual: `{colors.canvas}`, `{colors.ink}`, `{colors.ink-muted}`, `{colors.action}`, `{typography.data}`, `{spacing.2}`, `{spacing.4}` e `{components.focus-ring.color}` governam a interface. Spine vence sobre qualquer mockup futuro.

## Information Architecture

| Surface | Acesso | Propósito |
|---|---|---|
| Sessões | Abertura/refresh | Escolher explicitamente uma sessão local, pré-selecionando a mais recente. |
| Preparar draft | Nova sessão | Selecionar snapshot, revisar qualidade/avisos, configurar liga, times, ordem e time do operador; só libera início quando válido. |
| Live War Room | Iniciar, retomar ou confirmar sessão | Registrar pick, ver estado global, recomendações, disponíveis e roster sem trocar de página. |
| Busca de jogador | Campo persistente na Live War Room | Encontrar e confirmar rapidamente um jogador disponível. |
| Inspeção de jogador | `Espaço` sobre candidato/resultado | Ver projeção, posição/time NFL, score, fatores, tier e impacto marginal no roster antes de agir. |
| Board e auditoria | Painel da Live War Room | Conferir picks recentes/atuais, navegar para um pick anterior e iniciar correção; evidencia undo e correções. |
| Roster | Painel da Live War Room | Conferir roster do operador, melhor lineup e ocupação dos slots; outros rosters são acessíveis no board. |
| Pausa e exportação | Controles da Live War Room | Pausar/retomar e exportar picks, rosters, configuração e metadados. |
| Conclusão | Último pick | Confirmar draft completo e oferecer exportação. |

A Live War Room mantém simultaneamente visíveis: pick atual e time no relógio, último jogador registrado, próximo pick do operador, busca, candidatos recomendados, board e roster do operador. A tela prioriza a comparação manual com a ESPN: a faixa de estado responde imediatamente “quem foi draftado, onde estamos e quem escolhe agora”.

**[ASSUMPTION]** Em janela estreita lado a lado, painéis secundários colapsam para abas/expansores, mas o cabeçalho de estado, busca e lista de candidatos permanecem visíveis. Não há alvo de celular no V1.

Referência de composição: [Live War Room](mockups/live-war-room.html), que ilustra os padrões de faixa de estado, busca/autocomplete, lista inteligente, painel de inspeção, undo, board, roster e histórico. Os spines vencem em qualquer conflito com o mockup.

## Voice and Tone

Microcopy é curta, factual e orientada à próxima ação. A voz de marca pertence a `DESIGN.md`.

| Use | Evite |
|---|---|
| `Pick 73 — Team Rocket` | `Você está indo muito bem!` |
| `Próximo: seu pick 76` | `Não perca sua chance` |
| `Registrado: Ja'Marr Chase` | `Sucesso! Escolha salva.` |
| `Já escolhido no pick 42. Busque outro jogador.` | `Erro inesperado` |
| `Undo aplicado — pick 73 voltou a aberto.` | celebração, alarmismo ou confiança preditiva |

## Component Patterns

| Componente | Uso | Regras comportamentais |
|---|---|---|
| Seleção de sessão | Sessões | Lista sessões por recência, pré-seleciona a mais nova e só restaura após `Enter`/clique em Confirmar; cada linha anuncia data, status e seleção. |
| Qualidade do snapshot | Preparar draft | Resume metadados, cobertura e avisos; bloqueio identifica campo/compatibilidade e oferece selecionar outro snapshot ou executar `script.R` novamente. |
| Configuração da liga | Preparar draft | Edita times, rounds, slots, FLEX, scoring e time do operador; valida o grupo alterado e bloqueia início até tudo estar viável. |
| Ordem snake | Preparar draft | Cadastra, sorteia ou reordena antes do início; `Validate and Lock` trava a ordem e torna alterações normais indisponíveis. |
| Faixa de estado | Topo da Live War Room | Mostra overall, rodada/pick, time no relógio, último pick e próximo pick do operador. Atualiza como uma unidade após comando aceito. |
| Campo de busca + autocomplete | Sempre disponível na Live War Room | Busca local incremental, tolerante a variações de nome; só retorna disponíveis, com nome, posição e time NFL. Resultado destacado é a ação de `Enter`. |
| Lista inteligente | Abaixo/ao lado da busca | Mostra ao menos cinco candidatos disponíveis, ordenados pela recomendação ativa e filtráveis por posição. Cada linha distingue score, fatores, tier cliff e impacto de roster; não promete disponibilidade futura. |
| Linha de candidato | Busca e lista inteligente | Setas movem o destaque; `Espaço` inspeciona; `Enter` tenta registrar no pick atual. Clique é alternativa, não fluxo principal. |
| Painel de inspeção | Contextual | Mostra explicação determinística: projeção, valor, preço de mercado e urgência quando aplicáveis; declara ausências de dados opcionais. Não é comparação lado a lado V1. |
| Board | Live War Room | Exibe sequência de picks e destaca pick atual, pick do operador e última alteração. Um pick corrigível abre o modo de correção, sem esconder os picks posteriores. |
| Roster do operador | Live War Room | Agrupa titulares, FLEX e banco; torna visíveis melhor lineup, slots vazios e impacto marginal do candidato focado. |
| Histórico de eventos | Board/auditoria | Mostra registros, undos e correções em ordem, com alvo e resultado efetivo. É auditável, não um feed de recomendações históricas. |
| Controle Undo | Persistente na Live War Room | Sempre visível e acionável por `U`; revela quantos picks efetivos consecutivos ainda podem ser desfeitos **[ASSUMPTION]**. |
| Pausa/exportação | Controles secundários | Pausa impede registro normal; exportação não muda o draft. |

## State Patterns

| Estado | Superfície | Tratamento |
|---|---|---|
| Carregando sessões | Sessões | Lista com skeleton; nenhuma restauração silenciosa. |
| Nenhuma sessão recuperável | Sessões | Explica que ainda não há sessão local e oferece iniciar Preparar draft; foco segue para essa ação. |
| Sessão recuperável | Sessões | Mais recente pré-selecionada; Giu confirma ou escolhe outra antes de restaurar. |
| Snapshot carregando ou falhou | Preparar draft | Região de qualidade usa `aria-busy` durante leitura; falha mantém a seleção e oferece executar `script.R` ou escolher outro bundle. |
| Snapshot/configuração inválido | Preparar draft | Início bloqueado; causa concreta e ação: selecionar outro snapshot, revisar configuração ou executar `script.R` novamente. |
| Ordem em preparação | Preparar draft | Grade snake mostra a ordem atual e só habilita `Validate and Lock` após times e configuração válidos; foco permanece na primeira inconsistência. |
| Pronto para iniciar | Preparar draft | Ordem snake e viabilidade visíveis; alterações normais de ordem terminam após início. |
| Live — aguardando pick | Live War Room | Busca recebe foco **[ASSUMPTION]**; pick atual, candidatos e próximo pick do operador são atuais. |
| Consulta sem resultado | Busca | `Nenhum jogador disponível corresponde à busca.` Mantém estado do draft intacto. |
| Inspeção com dado opcional ausente | Painel de inspeção | Exibe `Não disponível neste snapshot` no campo afetado, sem ocultar candidatos nem bloquear o registro. |
| Nome ambíguo, inválido ou já escolhido | Busca/registro | Não persiste nada; explica o motivo e devolve foco à busca/lista. Jogador já escolhido informa o pick efetivo. |
| Registrando | Live War Room | O controle que submeteu permanece focado e `disabled`/`aria-disabled` com o motivo acessível `Registrando pick`; bloqueia repetição da mesma intenção até resposta e mantém o restante do estado legível. |
| Pick confirmado | Live War Room | Atualiza board, disponíveis, rosters e recomendações; anuncia o jogador e avança para o próximo slot. |
| Intenção obsoleta | Live War Room | Nenhuma mudança; recarrega o estado e informa que o pick já mudou antes da ação. |
| Pausado | Live War Room | Estado explícito; bloqueia novos picks normais e oferece retomar. |
| Undo multinível | Live War Room/auditoria | Cada `U` desfaz o último pick **efetivo**, recompõe board, disponíveis, rosters e recomendações, grava um evento e deixa o próximo undo disponível enquanto houver pick efetivo. Não apaga auditoria. |
| Correção válida | Board/auditoria | Reproduz o estado posterior, preserva picks posteriores e adiciona evento de correção; a Live War Room mostra o resultado recomposto. |
| Correção inválida | Board/auditoria | Duplicidade, slot inválido ou outro conflito não persiste; explica qual condição falhou e preserva o estado. |
| Draft completo | Conclusão | Registro final fecha a sessão; registro normal some e exportação permanece disponível. |
| Falha local de persistência | Global | Pick não é apresentado como confirmado; mostra falha acionável e mantém/recarrega o último estado confirmado. |
| Exportando/exportado/falhou | Pausa/exportação | Região de exportação usa `aria-busy`; conclusão anuncia o artefato disponível, falha mantém a sessão e oferece nova tentativa. |
| Encerrado administrativamente | Live War Room | Estado ABORTED usa aviso persistente, bloqueia pick normal e mantém exportação e auditoria acessíveis. |

## Interaction Primitives

- Dentro de entrada editável, atalhos globais não disparam: na busca, ↑/↓, `Enter` e `Esc` pertencem ao autocomplete e espaço insere texto. Fora de entrada editável, setas movem o destaque entre candidatos, `Enter` registra, `Espaço` abre/fecha inspeção, `Esc` fecha a camada superior e `U` aplica um undo por tecla, repetível.
- O foco de teclado é sempre visível por `{components.focus-ring.width}` em `{components.focus-ring.color}`. `Tab` alcança todos os controles; clique não remove a equivalência por teclado.
- O autocomplete é um combobox/listbox: label persistente, `aria-expanded`, `aria-controls` e `aria-activedescendant`; cada candidato é uma opção com nome acessível completo, disponibilidade e estado selecionado. A lista anuncia contagem, ausência de resultados e item ativo sem repetir colunas decorativas.
- O board é uma grade com roving tabindex: setas percorrem picks, `Enter`/`Espaço` abre correção, e cada célula anuncia overall, time, jogador e estado. O painel de correção recebe foco ao abrir e o devolve à mesma célula após cancelar, falhar ou concluir.
- Registro normal não pede modal de confirmação. O feedback confirmado substitui a lista em menos de um ciclo de atenção e devolve o fluxo à busca/lista para o novo pick.
- **[ASSUMPTION]** `/` foca a busca de qualquer painel da Live War Room; `?` abre a referência de atalhos. Esses atalhos não substituem os confirmados acima.
- Correção é iniciada a partir de um pick no board; exige um jogador disponível e valida a sequência recomposta. **[ASSUMPTION]** A escolha do alvo abre um único painel contextual, nunca pilha de modais.
- Não há integração, scraping, sincronização automática ou controle da ESPN. Não há PNext/VONA, simulação, comparação lado a lado nem histórico de recomendações no V1.

## Accessibility Floor

- WCAG 2.2 AA; contraste visual segue os pares e mínimos de `DESIGN.md`, e estado nunca é comunicado só por cor.
- Todo candidato anuncia nome, posição, time NFL, disponibilidade, posição na lista e principais alertas; o pick atual anuncia overall, rodada e time.
- Uma única região `aria-live=polite` e `aria-atomic=true` anuncia comandos aceitos em frase curta: jogador, novo overall e undo disponível. Alertas/bloqueios usam mensagem de erro sem roubar foco. Após registro, undo ou correção, foco retorna à busca/lista; após conclusão, vai para Exportar.
- Ordem de `Tab` acompanha leitura e prioridade operacional: estado, busca, candidatos, inspeção, board, roster, controles.
- Todo atalho possui alternativa por controle acessível, label e dica de teclado. `Esc` fecha somente a camada contextual superior.
- A 200% de zoom ou largura reduzida, estado, busca e lista seguem leitura linear; board, roster e auditoria viram painéis alternáveis com rótulo/estado expandido, preservando foco. Só o grid do board pode rolar horizontalmente e mantém o pick atual identificável. Reduzir movimento elimina transições não essenciais, sem atrasar feedback.
- Controles clicáveis têm alvo mínimo de 24×24 CSS px ou espaçamento equivalente; ao navegar, a tela rola para manter o foco totalmente visível, inclusive abaixo da faixa fixa.

## Responsive & Platform

Web local em notebook/desktop. A prioridade é uma janela dividida com a ESPN, não um layout promocional de tela cheia. **[ASSUMPTION]** Em largura desktop ampla, board e roster permanecem como painéis laterais; em largura de janela reduzida, eles viram painéis alternáveis preservando estado e foco. Celular/tablet está fora do V1.

## Inspiration & Anti-patterns

- **Postura adotada:** terminal/war room denso — informação escaneável, ações próximas do contexto e nenhum espaço dedicado a entretenimento.
- **Rejeitado:** dashboard esportivo editorial, cards hero, highlights decorativos e métricas que ocultam o pick atual.
- **Rejeitado:** qualquer passo dependente de rede ou de automação da ESPN no draft live.
- **Rejeitado:** confirmação modal a cada pick, hover como único caminho e navegação que esconda busca ou estado global.

## Key Flows

### Flow 3 — J-03: Giu registra o pick 73 ao lado da ESPN

1. Giu abre a sessão e confirma a sessão local pré-selecionada.
2. A Live War Room mostra `Pick 73`, o time no relógio, o último jogador escolhido e `Próximo: seu pick 76`.
3. Ele confere a ESPN, digita parte do nome no campo de busca local e usa ↓ para destacar o resultado com posição e time NFL.
4. Se quiser, pressiona `Espaço` e confere fatores, tier e impacto no roster; `Esc` retorna à lista.
5. Pressiona `Enter`.
6. **Clímax:** `Registrado: {jogador}` aparece, o board avança para o pick 74 e o mesmo olhar já mostra o novo time no relógio, o roster atualizado e a lista inteligente recomposta.

Falha: o nome está ambíguo, indisponível ou já escolhido → nada muda; a mensagem identifica o motivo (e pick efetivo quando existir), e Giu segue na busca para registrar o nome correto.

### Flow 0 — J-01: Giu prepara e valida dados

1. Antes do draft, Giu executa `script.R` localmente e abre Preparar draft.
2. Seleciona o snapshot gerado e revisa temporada, geração, fontes, scoring, cobertura e avisos.
3. Confirma que bloqueios não existem e que os campos opcionais ausentes estão explicitamente sinalizados.
4. **Clímax:** a qualidade passa a mostrar snapshot válido e a interface libera a configuração da liga, sem qualquer acesso de rede.

Falha: hash de scoring incompatível ou relatório bloqueante → o draft não pode iniciar; a interface aponta o motivo e oferece executar `script.R` novamente ou selecionar outro snapshot.

### Flow 0.5 — J-02: Giu configura e trava o draft

1. Giu ajusta times, 15 rounds, slots, FLEX, scoring e seu time.
2. Cadastra os times, sorteia ou reordena a primeira rodada e confere a grade snake.
3. A validação mostra qualquer incompatibilidade de roster ao lado do controle correspondente.
4. Pressiona `Validate and Lock`.
5. **Clímax:** a sessão passa a pronta, a ordem inteira fica fixa e o botão de iniciar torna-se a próxima ação inequívoca.

Falha: configuração fora do envelope ou ordem incompleta → `Validate and Lock` não avança; o foco vai à primeira inconsistência e explica a correção necessária.

### Flow 4a — J-04: Giu desfaz uma sequência registrada errada

1. Após perceber que anotou picks 73–75 com um deslocamento, Giu vê o último pick e a ação Undo persistente.
2. Pressiona `U`; o pick 75 deixa de ser efetivo e board, disponíveis, roster e recomendações voltam a refletir o pick 75 aberto.
3. Pressiona `U` novamente para os picks 74 e 73, conferindo a ESPN a cada passo.
4. O histórico mantém os três eventos de undo; nenhum pick é apagado da auditoria.
5. Giu registra a sequência correta pela busca.
6. **Clímax:** o board volta a coincidir visualmente com a ESPN e o estado global passa a indicar o próximo pick real, sem perda da trilha do que foi corrigido.

Falha: não há pick efetivo para desfazer → `U` não altera o draft e anuncia que não há undo disponível.

### Flow 4b — J-04: Giu corrige um pick antigo sem apagar o restante

1. Giu encontra no board o pick antigo divergente e abre a correção.
2. A busca limita-se a jogadores ainda disponíveis e ele escolhe o substituto.
3. O sistema valida a sequência inteira que resulta da correção.
4. **Clímax:** se válida, a Live War Room recompõe todos os painéis com a nova realidade, preserva os picks posteriores e registra a correção na auditoria.

Falha: se o substituto causa duplicidade ou invalida um pick posterior, a correção não é salva; Giu vê o conflito específico e retorna ao board original.

### Flow 4c — J-04: Giu retoma após refresh e encerra o draft

1. Após um refresh, Giu vê sessões ordenadas por atualização, com a mais recente selecionada.
2. Ele confirma a sessão e a Live War Room retorna ao último estado confirmado, com o board e roster consistentes.
3. No último slot, ele registra o jogador normalmente.
4. **Clímax:** a sessão muda para completa, bloqueia novos picks e deixa exportar picks, rosters, configuração e metadados.

Falha: restauração/armazenamento local indisponível → a sessão não é tratada como restaurada; a interface explica a falha e não inventa um estado novo.

### Flow 5 — J-05: Giu encerra e exporta

1. Depois do último pick, a sessão é marcada como completa e o registro normal deixa de estar disponível.
2. Giu exporta picks, rosters, configuração e metadados para auditoria.
3. **Clímax:** o artefato exportado fica disponível sem alterar a sessão concluída.

Falha: em uma situação excepcional, Giu usa Encerrar draft; a sessão fica ABORTED com aviso persistente, auditoria intacta e as mesmas exportações disponíveis.
