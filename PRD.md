# PRD Escalimetro: Votações

Sistema web com agrupamentos de multiplas votações em um único evento. Usuários criam eventos, convidam participantes cujo votam em diversas pautas.

## Contexto e Problema

- Organizar eventos para amigos com diversos tópicos que precisam de conciliação, como data, local, horario, sabores das pizzas, jogos e filmes. O sistema deixa a experiência mais simples, intuitiva, colaborativa e com relatório claro das melhores opções.
- Planejar escalas de trabalho, onde que o usuário administrativo deve conciliar e permitir votos de acordo com alguma justificativa. Os participantes podem explicitar seu desejo através dos votos e o usuário administrativo pode ao final ver com simplicidade o resultado das intençṍes já conciliadas.

## Glossário

- Evento: Agrupamento de votações de diversos tipos, também possui dados como descrição, local, data e situação. O ciclo inicial tem os status `open` e `closed`.
- Usuário: pessoa com conta (email e senha)
- Convidado: pessoa sem conta
- Participante: Usuário ou convidado que está participando do evento
- Usuário administrativo ou participante administrativo: Usuário com permissões administrativas para editar o evento
- Intensidade de voto: marcação opcional em votos de múltipla escolha para indicar que o participante quer muito aquela opção
- Modo de seleção: configuração de pauta de múltipla escolha que define se o participante pode escolher uma única opção (`single_choice`) ou várias opções (`multi_choice`).

## Publico-Alvo

- Pessoas que precisam administrar pautas que devem ser votadas
- Pessoas que querem simplicidade para expressar seu interesse em alguma pauta que foi convidada

## Jornada do Usuário

- Usuário cria evento, organiza pautas, convida participantes, bloqueia votos, encerra pautas e fecha evento com um relatório facilmente compartilhável.
- Usuário acessa evento via link, vota, acompanha pautas mesmo após evento encerrado.
- Convidado acessa evento via link, identifica-se, vota, acompanha pautas mesmo após evento encerrado.

## Princípios de Design

- Mobile-first: Layout projetado para telas pequenas. Desktop é secundário.
- Zero fricção: Nenhum cadastro para convidados, login ou cookie de identificação. Criar uma conta é opcional para participar de reuniões, porém necessário para adminsitrar eventos.
- Tempo real: Votações são abertas e refletem instantaneamente a todos dispositivos conectados.
- Velocidade: Carregamento rápido mesmo em redes móveis congestionadas.
- Resultado óbvio: Relatório final cristalino de compreensível

## Funcionalidades

### Autenticação e Gestão de Contas (Acesso do Administrador)

- Criação de Conta: Um visitante pode cadastrar-se fornecendo e-mail e confirmando acesso por magic link. Contas precisam estar confirmadas para criar e gerir eventos.
- Login Social: fora do MVP inicial.

### Gestão de Eventos (Fluxo do Administrador)

- Criação de Evento: Usuário confirmado pode criar um novo evento já aberto (`open`) definindo dados básicos: Título, Descrição, Data/Horário previstos (opcional) e Local (opcional).
- Criação de Pautas/Votações: Dentro de um evento, o usuário administrativo pode criar múltiplas pautas. Cada pauta deve aceitar um tipo de votação específico:
  - Opções múltiplas (ex: Sabores de pizza), configuráveis como escolha única ou múltiplas escolhas, com suporte a intensidade de voto para o participante marcar que quer muito uma opção.
  - Sim/Não/Talvez (ex: Presença ou disponibilidade de data).
- Edição de Evento e Pautas: Usuário administrativo pode allterar dados do evento ou das pautas.
- Conciliação de votos: Usuário administrativo pode rejeitar votos, cujo é exibido de maneira transparente nos relatórios.
- Encerramento de Pautas/Votações Individualmente: Usuário administrativo pode bloquear a votação de uma pauta específica (ex: fechar a votação de horários) mantendo as outras pautas abertas.
- Fechamento do Evento: Usuário administrativo pode fechar o evento como `closed`, congelando instantaneamente todas as votações e gerando o relatório final. Um evento fechado pode ser reaberto.
- Gestão de participantes: Usuário administrativo pode invalidar participação invalidando também votos.

### Convites e Acesso (Fluxo de Compartilhamento)

- Geração de Link Único de Convite: O sistema deve gerar/invalidar o link único de acesso por evento. Ao compartilhar este link (via WhatsApp, por exemplo), qualquer participante pode acessar o evento.
- Identificação do Convidado (Sem Cadastro): Ao acessar o link, se o participante for um "Convidado" (sem conta), o sistema deve solicitar apenas um "Nome/Apelido" para identificá-lo na listagem de votos antes de liberar a tela de votação. Nomes duplicados são permitidos e representam participantes distintos.
- QRCode do Evento: Geração de um QRCode na tela do administrador para que pessoas em um mesmo ambiente físico possam escanear e entrar no evento instantaneamente.

### Experiência de Votação e Colaboração (Fluxo do Participante)

Focado na interação em tempo real e na facilidade de uso em dispositivos móveis.

- Votação Multiusuário: O participante pode registrar seu voto nas opções de cada pauta.
- Troca e remoção de voto: Enquanto evento e pauta estiverem abertos, o participante pode trocar seu voto ou remover uma escolha sem precisar selecionar outra.
- Intensidade em votos de múltipla escolha: Ao votar em uma pauta de opções múltiplas, o participante pode marcar um checkbox indicando "quero muito esta opção". Essa marcação deve ser opcional, vinculada ao voto escolhido e não deve existir para votações Sim/Não/Talvez.
- Atualização em Tempo Real: Os votos de todos os participantes devem ser computados e refletidos na tela de todos os usuários conectados instantaneamente, sem necessidade de atualizar a página.
- Opinar e Sugerir em pautas abertas: Permitir que o administrador habilite `allow_suggestion` em uma pauta, onde os participantes podem digitar novas opções (ex: sugerir um sabor de pizza que não estava na lista inicial). Sugestões entram ativas imediatamente e os outros participantes podem votar nas sugestões enviadas por colegas.
- Justificativa de Voto: Atendendo ao cenário de escalas de trabalho, o participante pode adicionar um breve comentário/justificativa ao lado do seu voto (ex: "Não posso na terça pois tenho faculdade"). O administrador configura por pauta se justificativas ficam visíveis para participantes nos detalhes dos resultados.
- Detalhes por opção: Participantes veem a contagem por opção em tempo real e podem abrir os detalhes para consultar votantes, marcações de intensidade e justificativas quando habilitadas.

### Relatórios e Resultados (Resultado Óbvio)

- Visualização Clara de Votos (Visão Geral): Uma tela simples que destaca visualmente a opção mais votada de cada pauta (ex: a data vencedora, o filme escolhido), deixando empates explícitos quando existirem.
- Ordenação inteligente por intensidade: Em pautas de múltipla escolha, relatórios devem exibir a quantidade de votos com intensidade por opção e podem usar essa informação como critério de desempate ou ordenação secundária quando duas opções tiverem totais próximos ou iguais.
- Resultado Público: participantes podem acessar resultados por convite válido.
- Extração de Relatório Consolidado: Um botão para gerar um resumo em formato de texto amigável, copiável para WhatsApp, e exportar uma imagem SVG do relatório (ex: "Resultado do Evento X: Local: Salão, Sabor Vencedor: Calabresa, Horário: 20h").

### Backoffice

- In personate: Usuários que são responsáveis pelo sistema, podem fazer in personate para verificação de bugs
- Dashboard: Quantos usuários ativos, eventos abertos etc, com filtro por período e busca de usuários/eventos.

## O que está fora do escopo

- Login social
- Administradores adicionais por evento no MVP inicial
- Prestação de contas do evento, juntamente com ferramentas estilo "split wise" que simplificam a distribuição dos pagamentos

## Stack Técnica Relevante

- **Phoenix LiveView**: UI reativa sem JS customizado
- **Phoenix Presence**: rastreamento anônimo de usuários conectados por tópico
- **PubSub**: broadcast de atualizações de presença
- **PostgreSQL**: banco de dados
- **Tailwind CSS v4**: estilização mobile-first
