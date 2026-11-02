# Rokumio com português brasileiro e melhorias de interface

Código local: `/home/gabriel/rokumio`.
Base: gpratoe/rokumio-client, revisão `1202ca5883e054becd12d8ae826d5b9e2afe61e0`.
Versão do pacote Roku: 0.2.5 (build local). Projeto independente, sem vínculo oficial com o Stremio.

## Cache leve de catálogos e detalhes

O app reutiliza catálogos por 5 minutos, resultados de pesquisa por 1 minuto e detalhes de filmes/séries por 30 minutos. É um cache compartilhado em memória durante a execução do app, com até 64 entradas e orçamento conservador de 2 MiB para textos serializados/chaves. Respostas grandes são ignoradas; ao atingir os limites, os itens menos utilizados saem primeiro. A validade não aumenta a cada leitura, e os dados expirados são removidos nas consultas e por uma limpeza periódica. Essa validade controla novas consultas; não recarrega uma tela já aberta em segundo plano.

O cache guarda somente respostas válidas. Não guarda erros, vídeos, áudio ou arquivos de imagem e não intercepta as consultas de autenticação/biblioteca. A chave distingue provedor, filtros, página, tipo, identificador e configuração do complemento. Trocar de conta, instalar/remover/sincronizar complementos ou importar configurações limpa o cache; consultas que começaram antes da limpeza não podem gravar de volta. A atualização manual da Home pelo botão Replay também ignora a validade. Fechar o app descarta os dados.

A opção Tamanho do cache em Configurações continua sendo a do servidor de streaming. O novo cache da interface é separado e não altera essa configuração. O orçamento de textos não representa um limite para toda a memória do processo; o ganho real e o consumo precisam ser medidos na TV. Para diagnóstico, o nó ResponseCache expõe Stats com contadores de acertos, falhas de consulta ao cache, expirações e descartes, sem listar URLs ou conteúdo.

## Menu lateral recolhível

Na tela inicial, o menu mostra somente os ícones enquanto você navega nos filmes. Pressione esquerda na borda da lista ou `*` para expandir os nomes; direita ou Voltar recolhe o menu e devolve o foco aos filmes. A abertura e o fechamento duram cerca de 0,22 segundo e não recriam os catálogos nem mudam o filme selecionado. Se os catálogos ainda estiverem vazios, o menu fica aberto para manter a navegação disponível. O modo leve aplica a largura final sem animar o painel.

## Controles laterais e tela de pausa (build local 0.2.5)

Durante o vídeo, o botão central **OK** pausa; quando o vídeo está pausado e sem menu, OK retoma. Pressione ↑ ou ↓ para abrir a lateral. Use as setas verticais e OK para escolher **Voltar**, **Áudio e legendas**, **Assistir do início** ou **Pausar/Continuar**. Voltar no controle remoto oculta os controles; o ícone Voltar sai do player e salva o progresso pelo fluxo existente.

Os controles usam ícones em uma lateral estreita sobre o vídeo, sem coluna opaca. O texto aparece apenas na ação em foco; uma vinheta escurece as bordas e a barra inferior mostra tempo atual, duração e progresso.

Após 8 segundos de pausa sem interação, os botões e a barra desaparecem. Essa apresentação separada mostra apenas o logotipo (ou o título, se o logotipo não carregar), identificação do episódio e uma indicação discreta para continuar. A primeira seta ou Voltar só revela os controles, sem avançar o vídeo nem sair. OK ou Play retoma diretamente. Durante reprodução, os controles somem após 6 segundos sem interação.

Assistir do início volta ao segundo zero na reprodução atual e mantém as escolhas de áudio e legenda. Na lateral, ←/→ avança ou recua 10 segundos; avançar/retroceder rápido usa 30 segundos. Fora dela, o transporte nativo da Roku continua disponível.

Áudio e legendas abre o painel direito com abas Legendas e Idioma. Esquerda/direita alterna a aba e somente a lista ativa fica visível. Cada linha usa desenho próprio para alinhar o foco branco, o texto escuro e a marca da seleção; Desativadas é a primeira opção de legendas. O vídeo fica menor à esquerda e volta ao tamanho original ao fechar. As descrições abaixo de versões anteriores documentam os controles antigos.

## Correções da versão 0.2.5

- **Busca sem sobreposição:** teclado e resultados têm áreas de desenho separadas. O tamanho completo do teclado nativo (inclusive campo de texto e opções laterais) é medido após a criação e ajustado à área disponível. A escala fixa anterior podia ultrapassar a coluna esquerda. A medição é repetida brevemente para acomodar o carregamento dos componentes nativos.
- **Histórico acessível:** Ver resultados permite entrar no histórico quando ele está visível; setas dão acesso a remover e limpar. A remoção usa a linha em foco, e um histórico vazio deixa de ocultar a área de resultados.
- **Sem buscas duplicadas:** seleção do histórico e eventos atrasados do teclado não relançam a mesma consulta já ativa.
- **Histórico útil:** prefixos da busca automática não são gravados a cada tecla; a pesquisa é registrada quando o usuário entra nos resultados ou abre um título. Remover/limpar também apaga as entradas antigas do registro local.
- **Legenda e idioma consistentes:** Ligar legendas usa a faixa da lista exibida e salva o idioma daquela mesma faixa, em vez de reutilizar uma faixa antiga de outro idioma.
- **Escolha manual de áudio respeitada:** uma escolha feita no painel não é substituída quando o player informa novas faixas; uma preferência que já corresponde ao áudio atual deixa de ser reaplicada.
- **Filtros com menos falsos positivos:** fragmentos de títulos como Birthday/Avengers e a marca SDR não são tratados como indicação de HD/inglês/SD. Marcadores explícitos como 1080p, [ENG] e UHD continuam reconhecidos.

As funcionalidades da versão 0.2.4 foram preservadas. A compilação, os testes automatizados e a integridade do ZIP são verificados localmente. A correção visual ainda precisa ser conferida na TV; não há confirmação de instalação deste pacote no aparelho.

## Novidades da versão 0.2.4

1. **Preferências persistidas de idioma e legendas**
   - Configurações dedicadas em Configurações → Reprodução para idioma preferido de áudio e legendas, além de opção para manter legendas ligadas ou desligadas por padrão.
   - Diferenciação precisa entre Português e Português (Brasil) quando a fonte ou complemento fornece essa informação (`pt-BR` vs `pt`/`por`).
   - Aplicação automática de faixas compatíveis no início da reprodução, preservando a troca manual e tratando idiomas ausentes sem travar o player nem selecionar opções incorretas.

2. **Próximo episódio e reprodução automática**
   - Card e botão de navegação para avançar diretamente ao próximo episódio ao término da exibição.
   - Reprodução automática opcional (configurável em Configurações → Reprodução), com contagem regressiva de 10 segundos cancelável pelo controle remoto.
   - Preservação do progresso de exibição, respeito estrito à numeração/ordem das temporadas e tratamento adequado para finais de temporada e encerramento de série.

3. **Histórico de buscas recentes**
   - Registro local de até 10 buscas recentes, sem duplicatas e com ordenação pelo termo mais recente.
   - Atalhos no teclado de busca para reutilizar termos recentes com um clique, remover entradas pontuais ou limpar todo o histórico.
   - Preservação da busca enquanto digita com cancelamento de consultas defasadas e proteção de geração contra sobreposição de resultados antigos.

4. **Filtros de fontes e reprodução**
   - Filtros por resolução (4K, 1080p, 720p), idioma e formato a partir dos metadados reais dos complementos.
   - Atalho pelo botão `*` (Options) do controle remoto para alternar filtros diretamente na lista de fontes.
   - Identificação transparente de termos não informados e mensagem explicativa clara quando filtros ativos ocultarem todas as fontes disponíveis, com botão de limpeza rápida.

5. **Modo leve (desempenho) e acessibilidade**
   - Opção de **Modo leve** para televisores Roku com hardware mais modesto, suprimindo animações de pulso, limitando consultas simultâneas a 1 por vez e otimizando o carregamento de cartazes.
   - Modos de **Textos maiores** e **Foco de alto contraste** nas configurações para melhor legibilidade e navegação à distância.
   - Mensagens claras e objetivas de erro em falhas de reprodução, servidor de streaming e complementos, com ações sugeridas (repetir ou verificar configurações) sem alegar causas não comprovadas.

## Alterações das versões anteriores (0.2.0 - 0.2.3)

- Português (Brasil) nos textos da interface: menus, configurações, entrada na conta, biblioteca, episódios, busca e mensagens de reprodução.
- Português brasileiro como padrão em uma instalação sem preferências salvas. Quem já usa outro idioma pode alterá-lo em Settings → General → Language. Inglês e espanhol continuam disponíveis.
- Menu lateral com nomes e ícones, contraste maior e fundo destacado no item selecionado.
- Cabeçalho com instruções curtas e título/tipo do conteúdo selecionado.
- Cartazes das linhas sem foco mais legíveis, preservando os limites de tamanho das imagens.
- Mensagem de catálogo vazio e carregamento. Replay tenta carregar os catálogos novamente quando não há busca em andamento.
- Na tela de fontes, Replay tenta novamente depois que a consulta atual termina; o contador mostra os provedores já consultados.
- Mensagem específica quando uma fonte por infoHash precisa de um servidor ainda não configurado.
- Área maior para mensagens de falha na reprodução e na busca de fontes.

O idioma da interface não muda títulos e sinopses dos complementos nem cria opções de áudio ou legendas que a fonte não ofereça.

## Gerar e verificar

Na pasta do projeto:

```sh
npm ci --ignore-scripts
npm run build
npm test
```

O pacote é gerado em `dist/rokumio-client.zip`.

## Teste no Roku

1. No instalador de desenvolvimento da sua TV, selecione o ZIP, envie com Upload e instale com Install with zip.
2. Verifique português e acentos na tela de entrada e nas configurações.
3. Teste os seis itens do menu, a troca entre menu e catálogo com esquerda/direita e a tecla *.
4. Mova entre cartazes e confira o título/tipo selecionado, a borda de foco e a rolagem.
5. Alterne para inglês ou espanhol e volte à tela inicial; os rótulos devem acompanhar a mudança.
6. Teste Replay após uma falha ou resultado vazio, uma fonte direta válida e uma fonte que exige servidor.

## Limites da validação

A compilação e os testes automatizados locais verificam o código, as traduções e contratos existentes do projeto. Aparência, foco pelo controle remoto e reprodução desta versão ainda precisam ser verificados no aparelho. Este pacote não foi instalado automaticamente no Roku.

A página local de configuração e os mecanismos de conta/rede do projeto original foram mantidos; estas alterações tratam do idioma e da interface.

## Busca enquanto digita e controle de legendas (0.2.2)

- A busca usa um teclado na própria tela, com resultados ao lado. Digite ao menos duas letras e aguarde uma pausa de 0,6 segundo; não é necessário confirmar o texto inteiro.
- No limite inferior do teclado, use ↓ para chegar a **Ver resultados** e OK para navegar nos cartazes. Voltar retorna ao teclado; Voltar novamente sai da busca. Os detalhes dependem dos complementos instalados e da conexão.
- Cada edição descarta resultados antigos e cancela a geração anterior. Cada geração consulta até dois provedores simultaneamente.
- Durante o vídeo, pressione ↓ para focar o botão **Legendas** e OK para abrir as opções. É possível desligar, ligar ou escolher uma das faixas que o player disponibilizou. ↑ ou Voltar fecha o controle e devolve o foco ao vídeo. O menu nativo da Roku em * continua disponível.
- Se não houver legendas, o menu informa isso; ele não cria faixas que a fonte ou os complementos não forneceram. A escolha usa os seletores do player sem reescrever o conteúdo durante a reprodução.

Os novos testes executam os manipuladores reais com objetos simulados: intervalo mínimo de busca, consulta na tela ativa, limite de provedores, resposta atrasada, seleção e cancelamento de legenda e teclas preservadas. O emulador não valida a aparência nem os controles nativos da TV; esses pontos ainda precisam de teste no aparelho.

## Painel por idioma e faixas de áudio (0.2.3)

O botão Legendas (↓, depois OK durante o vídeo) agora abre um painel em setores, inspirado no aplicativo de celular:

- Abas Legendas e Faixas de áudio.
- Coluna de idiomas, com Português (Brasil) separado de Português quando o provedor informa essa diferença.
- Coluna de faixas daquele idioma e indicação da opção selecionada.
- Detalhes com idioma, provedor e formato, quando essas informações estão disponíveis.
- Ações para ligar e desligar as legendas. Use as setas para mudar entre setores, OK para escolher e Voltar ou Fechar para retornar ao vídeo.

A lista usa apenas as faixas disponibilizadas pelo player. Para as legendas externas, o idioma e o nome do provedor são recuperados dos metadados originais. Não é inventada uma faixa dublada, um formato ou uma identificação de português brasileiro quando não há informação suficiente. A seleção de áudio pode exigir uma breve nova preparação pelo player, conforme o formato.

Este painel implementa a organização por idioma e a seleção de faixas. Os ajustes de atraso, tamanho e altura mostrados na referência do celular não foram incluídos neste build.

### Origem e versões

O repositório gpratoe/rokumio-client se descreve como cliente independente para o protocolo de complementos do Stremio, sem vínculo oficial. Seu package.json, na revisão usada, declara Rokumio 0.2.0. Não foi identificada uma versão específica do Stremio Android/desktop usada como base. A versão 0.2.3 é a identificação do nosso pacote local para Roku; não é uma versão do Stremio oficial.

Referências:
- https://github.com/gpratoe/rokumio-client
- https://github.com/gpratoe/rokumio-client/blob/1202ca5883e054becd12d8ae826d5b9e2afe61e0/package.json
- https://developer.roku.com/dev/docs/video

A compilação e os testes locais não validam o desenho ou a troca real de faixas na TV. Esta versão continua pendente de instalação e teste no aparelho.
