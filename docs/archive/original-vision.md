Sim. E, no seu formato específico, eu **não usaria uma estratégia rígida do tipo Zero-RB, Robust-RB ou WR-WR**. Você tem informação suficiente para fazer algo melhor: um **draft adaptativo baseado em VBD/VOR + VONA + tiers + probabilidade de o jogador voltar na sua próxima escolha**.

Há ainda duas características da sua liga que mudam bastante a estratégia: são só **2 WR obrigatórios** e apenas **1 FLEX**, o que reduz um pouco a vantagem estrutural do Zero-RB; e são apenas **5 reservas**, o que mantém um waiver relativamente utilizável e aumenta o valor de titulares realmente diferenciados em vez de profundidade “segura”.

O `ffanalytics` é particularmente adequado para isso porque já agrega múltiplas projeções, calcula médias robustas/ponderadas, VOR, tiers, ADP/ECR e incerteza. ([GitHub][1])

## Minha estratégia-base para essa liga

Eu partiria de algo que poderíamos chamar de:

> **Adaptive Hero-RB / Value-Based Drafting**

Ou seja:

**1 RB premium + WRs fortes no começo**, mas sem obrigação de seguir uma sequência predeterminada.

Minha meta aproximada depois de 6 rounds seria:

| Posição | Objetivo típico |
| ------- | --------------: |
| RB      |               2 |
| WR      |             2–3 |
| QB      |             0–1 |
| TE      |             0–1 |
| K       |               0 |
| DST     |               0 |

Não significa "tenho que pegar RB no round 1". Significa que **eu gostaria de sair dos primeiros 4–5 rounds com pelo menos um RB que realmente tenha workload de RB1**, a menos que o board me ofereça valor excepcional em WR.

Isso é ainda mais interessante em 2026: análises atuais de VBD encontram grande valor relativo nos RBs devido à queda rápida de produção depois dos backs com workload relevante; ao mesmo tempo, WRs realmente elite continuam extremamente valiosos, enquanto a faixa intermediária de WR tende a ser mais substituível. ([FantasyPros][2])

---

# 1. Não ranqueie por pontos projetados

Esse é provavelmente o erro mais importante a evitar.

Imagine:

| Jogador | Pos | Proj. |
| ------- | --- | ----: |
| QB A    | QB  |   345 |
| QB B    | QB  |   310 |
| RB A    | RB  |   270 |
| RB B    | RB  |   220 |

O QB A não necessariamente vale mais.

Porque você consegue talvez pegar QB B muito depois.

O que importa é:

$$
VOR = Projeção_{player} - Projeção_{replacement}
$$

O `ffanalytics` já faz exatamente isso através de `points_vor`. Por default ele usa aproximadamente:

* QB13
* RB35
* WR36
* TE13

como referências. ([GitHub][3])

Mas **eu não usaria esses números default na sua liga**.

Eu calcularia seus próprios replacement levels.

---

# 2. Calcule o replacement level da SUA liga

Sua configuração é:

**12 × 14 = 168 jogadores draftados.**

Mas a distribuição obviamente não será uniforme.

Depois de alguns mock drafts provavelmente veremos algo aproximadamente como:

* 16–20 QB
* 45–50 RB
* 50–60 WR
* 15–18 TE
* 12 DST
* 12 K

O replacement player verdadeiro deveria ser:

> o melhor jogador que provavelmente continuará disponível no waiver depois do draft.

E não simplesmente RB24 ou WR24.

### Melhor ainda: calcule isso por Monte Carlo

Você já tem ADP. Então simule, por exemplo, **5.000 drafts**.

Em cada simulação:

1. 11 adversários escolhem aproximadamente por ADP;
2. introduza ruído usando `adp_sd`;
3. imponha restrições razoáveis de roster;
4. simule 14 rounds;
5. veja quem ficou no waiver.

Então obtenha:

$$
Replacement_{RB}
=
median(BestUndraftedRB)
$$

e o mesmo para WR/QB/TE.

Isso faz seu VOR ficar **específico para sua liga**.

Aliás, já existem projetos recentes fazendo justamente esse tipo de Monte Carlo para drafts 2026: um deles simula adversários perturbando ADP, calcula disponibilidade futura e usa VONA para decidir picks. ([GitHub][4])

---

# 3. Mas VOR sozinho ainda não resolve o draft

Aqui entra a métrica que considero **mais importante para snake**:

## VONA — Value Over Next Available

Suponha que você esteja no pick 3.08.

Há dois jogadores:

**RB X**

* 240 pts
* próximo RB comparável: 205

**WR Y**

* 250 pts
* próximo WR comparável: 245

WR Y projeta mais pontos.

Mas se você deixar RB X passar:

$$
240-205 = 35
$$

Você perde potencialmente 35 pontos.

Se deixar WR Y passar:

$$
250-245 = 5
$$

Você perde apenas 5.

Portanto:

**pegue RB X agora e WR depois.**

Essa é a essência do bom snake drafting.

---

# 4. O draft deveria pensar na SUA próxima escolha

Esse é o grande avanço sobre uma cheat sheet convencional.

Se você estiver no pick 1, seus picks são:

**1 → 24 → 25 → 48 → 49...**

Então deixar alguém passar no #25 significa esperar **22 escolhas**.

Já se estiver no #6:

**6 → 19 → 30 → 43...**

Os intervalos são muito menores.

Portanto, o mesmo jogador pode ser:

* um reach absurdo no pick #6;
* uma escolha perfeitamente correta no pick #24.

A pergunta correta não é:

> "Quem é o melhor jogador disponível?"

É:

> **"Quem é o jogador mais valioso que provavelmente NÃO estará disponível quando eu escolher novamente?"**

---

# 5. Portanto eu colocaria uma coluna fundamental no seu modelo

Para cada jogador:

$$
P(AvailableNextPick)
$$

Por exemplo:

| Player | VOR | ADP | Próximo pick | P disponível |
| ------ | --: | --: | -----------: | -----------: |
| RB A   |  72 |  31 |           44 |           8% |
| WR A   |  68 |  38 |           44 |          42% |
| TE A   |  55 |  46 |           44 |          72% |

A decisão praticamente aparece sozinha.

RB A precisa ser considerado agora.

WR A talvez.

TE A provavelmente pode esperar.

Essa coluna é muito mais útil que simplesmente ADP.

---

# 6. Use ADP como preço, não como previsão

Essa distinção é importantíssima.

Sua projeção responde:

> **Quanto acho que ele vale?**

ADP responde:

> **Quanto o mercado está cobrando?**

Você quer jogadores onde:

$$
SeuRank << ADP
$$

Exemplo:

Seu modelo:

**RB18 overall**

ADP:

**34**

Você não deve necessariamente escolhê-lo no pick 18.

Talvez consiga comprá-lo no pick 28.

Esse é o conceito de **capturar surplus de draft capital**.

O `ffanalytics` ajuda bastante aqui porque `add_adp()` adiciona ADP e, dependendo das fontes, também dispersão do ADP; `add_uncertainty()` incorpora dispersão das projeções e dos rankings. ([GitHub][3])

---

# 7. Eu teria cinco números principais no Draft Board

Não 30 estatísticas.

| Métrica     | Significado                               |
| ----------- | ----------------------------------------- |
| **Proj**    | pontos esperados                          |
| **VOR**     | vantagem sobre replacement                |
| **Tier**    | grupo estatisticamente semelhante         |
| **ADP**     | preço de mercado                          |
| **P(next)** | chance de sobreviver até meu próximo pick |

E como auxiliares:

**Ceiling**, **Floor**, **Uncertainty** e **Bye**.

Visualmente poderia ficar:

```text
Player               Pos Proj VOR Tier ADP P(next) Uncert
---------------------------------------------------------
Player A              RB  287  96   1   8    2%     low
Player B              WR  301  91   1  11   12%     low
Player C              RB  266  75   2  17   61%     med
Player D              WR  278  68   2  14   33%     low
Player E              TE  231  63   1  21   78%     med
```

Isso é praticamente um **cockpit de draft**.

---

# 8. Tiers são mais importantes do que ranking absoluto

Imagine:

```text
RB
Tier 1
RB1  295
RB2  291

Tier 2
RB3  267
RB4  263
RB5  260
RB6  258

Tier 3
RB7  225
```

Se ainda existem quatro jogadores no Tier 2 e só um jogador sobrando no Tier 1 de WR:

**pegue o WR.**

Você provavelmente conseguirá um RB Tier 2 depois.

Isso é exatamente o tipo de decisão em que ranking linear falha.

---

# 9. QB: normalmente espere

Sua liga é **1 QB**, e isso muda tudo.

Em 12 times existem só 12 titulares.

Portanto a oferta é grande.

A análise VBD atual para 2026 chega à mesma conclusão: depois dos QBs realmente diferenciados, a curva fica bastante plana; há pouca diferença projetada entre QB1 intermediário e QB2 alto. A exceção são quarterbacks cujo rushing cria um diferencial estrutural. ([FantasyPros][2])

Eu usaria esta regra:

> **QB elite somente quando o VONA justificar. Caso contrário, espere.**

Não pensaria:

> "Round 4 é hora de QB."

Pensaria:

> "O QB4 me dá +42 VOR e o QB8 provavelmente volta até minha próxima escolha?"

Se sim:

**espere.**

### E quase nunca draftaria QB2.

Com 5 reservas, prefiro:

**RB upside > WR upside > QB2.**

---

# 10. TE: elite ou espere

TE possui uma distribuição muito peculiar.

Há frequentemente:

```text
TE1
TE2
--------
TE3
TE4
TE5
TE6
TE7
...
```

com uma enorme diferença no topo e pouca diferença depois.

Isso aparece novamente nas projeções de 2026: McBride/Bowers formam atualmente a faixa realmente diferenciada em muitas análises, enquanto boa parte do restante da posição fica comprimida. ([FantasyPros][2])

Portanto minha política seria:

**Tier elite:** considero se cair.

Caso contrário:

**não entre em pânico quando começar uma corrida de TE.**

Deixe os outros gastarem capital.

Pegue um TE mais tarde.

E não pegue TE2 para reserva salvo algum absurdo de value.

---

# 11. WR: quero estrelas ou upside

Full PPR aumenta obviamente a importância de:

* targets;
* receptions;
* target share;
* route participation;
* WRs que dominam volume.

Mas seu lineup tem apenas:

**WR1 + WR2 + FLEX**

e não três WR obrigatórios.

Isso é importante.

Em muitas ligas Full PPR com **3 WR + 2 FLEX**, Zero-RB fica muito mais atraente.

Na sua:

### é menos interessante.

Você simplesmente não consegue colocar 5 WR simultaneamente no lineup.

Minha tendência seria terminar o draft com aproximadamente:

**4–5 WR**, não 6–7.

Nos primeiros rounds quero **WR verdadeiramente elite**.

Nos rounds médios prefiro WRs com:

* breakout potential;
* WR1 potential no próprio time;
* target upside;
* alta variância positiva.

Não me interessa muito um WR veterano projetado para terminar calmamente como WR35.

---

# 12. RB: aqui eu atacaria upside

RB tem uma característica diferente.

Um reserva de NFL pode mudar instantaneamente de:

```text
4 fantasy pts/game
```

para

```text
17 fantasy pts/game
```

se o titular se machucar ou perder o emprego.

Por isso os últimos RBs do draft devem ser:

> **opções sobre futuros workloads.**

Não necessariamente o RB projetado para fazer mais pontos.

Exemplo:

### RB A

Projeção:
110

Role conhecido:
8 touches/game.

Ceiling:
130.

### RB B

Projeção:
75

Role atual:
backup.

Se titular cair:

240+.

Eu prefiro **RB B** como RB4/RB5.

Isso também explica por que VOR puramente baseado na projeção mediana pode supervalorizar ou subvalorizar certos RBs; a própria análise VBD de 2026 destaca que os backups de RB têm distribuições de resultados extremamente assimétricas. ([FantasyPros][2])

---

# 13. Minha construção provável

Para essa liga eu gosto bastante de terminar assim:

| Position | Quantidade |
| -------- | ---------: |
| QB       |      **1** |
| RB       |    **4–5** |
| WR       |    **4–5** |
| TE       |      **1** |
| K        |      **1** |
| DST      |      **1** |

Uma distribuição excelente seria:

```text
QB   1
RB   5
WR   4
TE   1
DST  1
K    1
---------
13
```

Isso dá 13, então sobra um slot que pode virar:

**WR5 ou TE2/QB2 excepcional**, mas normalmente eu faria:

```text
QB 1
RB 5
WR 5
TE 1
DST 1
K 1
= 14
```

Ou:

```text
QB 1
RB 4
WR 5
TE 2
DST 1
K 1
```

se houver dois TEs realmente interessantes.

Meu default seria o primeiro.

---

# 14. E K/DST?

## Last rounds.

Praticamente sem exceção.

Eu faria:

**Round 13: DST**

**Round 14: K**

ou vice-versa.

Se sua plataforma permitir entrar na Week 1 sem kicker ou DST, pode até haver estratégias mais agressivas de segurar RBs até perto da temporada, mas isso depende das regras.

Não gastaria round 10 porque:

> "é a melhor defesa."

A diferença esperada para DST12 normalmente não compensa perder uma lottery ticket de RB/WR.

---

# 15. Como eu trataria os rounds

Não como regra rígida, mas como **zona de decisão**:

| Round  | Prioridade                           |
| ------ | ------------------------------------ |
| **1**  | WR/RB elite                          |
| **2**  | WR/RB elite; TE excepcional se value |
| **3**  | RB/WR                                |
| **4**  | RB/WR; QB elite se cair              |
| **5**  | RB/WR                                |
| **6**  | RB/WR ou QB/TE value                 |
| **7**  | QB/TE se ainda faltar + RB/WR        |
| **8**  | RB/WR upside                         |
| **9**  | RB/WR upside                         |
| **10** | RB/WR upside                         |
| **11** | RB/WR high ceiling                   |
| **12** | RB/WR high ceiling                   |
| **13** | DST                                  |
| **14** | K                                    |

Uma maneira ainda melhor de pensar:

### R1–R5

**Construir vantagem nos starters.**

### R6–R9

**Capturar value.**

### R10–R12

**Comprar convexidade/upside.**

### R13–R14

**DST/K.**

---

# 16. Sua posição no sorteio muda a estratégia

### Picks 1–4

Eu pegaria o superstar disponível.

Depois teria o problema:

```text
1.03
2.10
3.03
```

Há muitos jogadores entre seus turns.

Consequentemente, seja mais agressivo com VONA.

Pode parecer que você está fazendo um pequeno reach, mas na realidade está evitando esperar ~20 picks.

### Picks 5–8

Para mim é a posição mais confortável analiticamente.

Há menos swings extremos.

Você consegue:

> **deixar o board vir até você.**

Aqui BPA/VBD funciona especialmente bem.

### Picks 9–12

Você precisa pensar em **pares de picks**.

Por exemplo #11:

```text
1.11
2.02

3.11
4.02

5.11
6.02
```

Eu não pensaria:

> "quem pego no 1.11?"

Pensaria:

> **"qual dupla quero construir no 1.11 + 2.02?"**

Exemplo:

```text
elite WR + elite RB
```

ou

```text
elite RB + elite RB
```

ou

```text
elite WR + elite WR
```

dependendo dos tiers.

É um problema de otimização em pares.

---

# 17. Não siga positional runs cegamente

Imagine que aconteceram:

```text
QB
QB
QB
QB
QB
```

cinco picks seguidos.

Reação emocional:

> "Preciso pegar QB!"

Frequentemente a resposta correta é exatamente o contrário.

Os outros 5 times acabaram de **deixar RB/WR cair para você**.

Você só deve entrar na corrida se:

```text
QB remaining tier
```

estiver prestes a sofrer um grande cliff.

Caso contrário:

**explore o run em vez de participar dele.**

---

# 18. O seu Draft Engine poderia tomar a decisão

Aqui é onde acho que seu uso de R fica particularmente interessante.

Em vez de ter apenas uma cheat sheet, faça isso durante o draft.

Quando chegar sua escolha, o sistema recebe:

```text
drafted_players
my_roster
current_pick
next_pick
available_players
```

E para cada candidato simula o resto do draft.

Por exemplo:

```text
Pick Gibbs
  -> 5,000 simulated drafts
  -> expected roster VOR = 683

Pick Chase
  -> 5,000 simulated drafts
  -> expected roster VOR = 701

Pick Jefferson
  -> 5,000 simulated drafts
  -> expected roster VOR = 674
```

Então sua escolha deixa de ser:

> "Chase ou Gibbs?"

e passa a ser:

> **"Qual escolha agora produz o melhor roster esperado dado o que provavelmente estará disponível depois?"**

Isso é muito superior a ranking.

---

# 19. E eu otimizaria STARTERS, não total de pontos do roster

Outro detalhe fundamental.

Se você simplesmente somar:

$$
\sum projectedPoints
$$

o algoritmo pode recomendar profundidade inútil.

Seu objetivo deveria ser aproximadamente:

$$
RosterValue =
StarterVOR
+
FlexVOR
+
BenchOptionValue
$$

Com:

```text
StarterVOR       peso 1.00
Bench RB/WR      peso ~0.25–0.40
QB2              ~0.05
TE2              ~0.05–0.15
```

E o bench deve valorizar principalmente **ceiling**, não median.

Assim você não acaba draftando:

```text
QB8
QB10
TE7
TE9
```

simplesmente porque a soma de projeções parece bonita.

---

# 20. Acrescentaria risco de maneira diferente por round

Outra sofisticação útil:

### Rounds 1–3

Prefira:

**projeção + floor + role certainty.**

Você não quer errar seu first-round pick tentando ser esperto.

### Rounds 4–7

Equilibre:

**median + ceiling.**

### Rounds 8–12

Praticamente maximize:

**ceiling.**

Porque:

```text
WR80 que vira WR45
```

não ajuda muito.

Mas:

```text
WR80 que tem 15% de chance de virar WR15
```

pode ganhar sua liga.

---

# Minha regra resumida para seu draft

Se eu estivesse draftando nessa liga, meu algoritmo mental seria:

1. **Rounds 1–5:** fique quase exclusivamente em RB/WR, salvo valor excepcional de TE/QB.
2. **Tente ter pelo menos 1 RB realmente forte** cedo.
3. **Priorize WR elite; não pague demais por WR intermediário.**
4. **QB: elite com desconto ou espere.**
5. **TE: elite com desconto ou espere.**
6. **Rounds 7–12:** acumule RB/WR com teto alto.
7. **Não draft QB2 por default.**
8. **Não draft TE2 por default.**
9. **DST/K nos dois últimos rounds.**
10. **Ignore bye week até ela virar critério de desempate.**
11. **Não persiga positional runs.**
12. **Use ADP para prever disponibilidade, não para definir valor.**

A principal diferença é que eu **não escolheria previamente Hero RB ou Zero RB**. Eu deixaria sua projeção + VOR + tiers + ADP decidir. A estratégia que emerge provavelmente será algo próximo de **Hero RB/Balanced**, mas isso será uma consequência dos preços do draft, não uma restrição imposta antes.

E isso é particularmente relevante neste momento: rankings PPR publicados em 27 de agosto de 2026 mostram um topo do mercado muito misturado entre RB e WR — não existe hoje uma razão óbvia para forçar uma única posição no primeiro round. ([FantasyPros][5])

## O próximo passo que eu faria

Acho que podemos transformar isso em algo bem mais poderoso do que uma análise teórica.

Usando `ffanalytics`, eu montaria um **Fantasy Draft War Room em R**, com:

```text
ffanalytics
      ↓
projeções consensus
      ↓
uncertainty / floor / ceiling
      ↓
ADP + ADP SD
      ↓
custom replacement level
      ↓
VOR / VOLS
      ↓
tiers
      ↓
Monte Carlo snake simulator
      ↓
P(available at next pick)
      ↓
VONA
      ↓
LIVE PICK RECOMMENDATION
```

A tela do draft poderia literalmente mostrar:

```text
YOUR PICK: 3.07
NEXT PICK: 4.06

RECOMMENDATION

1. Player A RB   89/100  TAKE NOW
   VOR 71 | P(next) 8%

2. Player B WR   85/100  VALUE
   VOR 68 | P(next) 44%

3. Player C QB   79/100  WAIT
   VOR 57 | P(next) 72%
```

**Esse é o sistema que eu construiria para você**, porque aproveita exatamente sua vantagem: você já consegue produzir projeções agregadas em R. A parte que está faltando não é uma projeção melhor; é transformar as projeções em **decisões condicionais dentro de um snake draft**. ([GitHub][1])

Se quiser acompanhar lesões, depth charts e mudanças de ADP até o dia do draft, posso também deixar isso sendo revisitado periodicamente.

[1]: https://github.com/FantasyFootballAnalytics/ffanalytics?utm_source=chatgpt.com "GitHub - FantasyFootballAnalytics/ffanalytics: ffanalytics R package · GitHub"
[2]: https://www.fantasypros.com/2026/06/fantasy-football-draft-strategy-value-based-drafting-2026/ "Fantasy Football Draft Strategy: Value-Based Drafting (2026) - FantasyPros"
[3]: https://github.com/FantasyFootballAnalytics/ffanalytics/blob/master/R/calc_projections.R?utm_source=chatgpt.com "ffanalytics/R/calc_projections.R at master · FantasyFootballAnalytics/ffanalytics · GitHub"
[4]: https://github.com/samipparikh/fantasy-draft-2026?utm_source=chatgpt.com "GitHub - samipparikh/fantasy-draft-2026: Monte-Carlo fantasy football draft model: 12-team half-PPR, slots 5-7, RB-priority · GitHub"
[5]: https://www.fantasypros.com/nfl/rankings/fantasy-br.php?position=ALL&scoring=PPR&type=draft&utm_source=chatgpt.com "Fantasy BR (Fantasy BR) | Fantasy Football PPR Rankings | 2026 Draft | FantasyPros"
