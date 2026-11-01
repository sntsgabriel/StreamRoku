# Rokumio com português brasileiro e melhorias de interface

Código local: `/home/gabriel/rokumio`.
Base: gpratoe/rokumio-client, revisão `1202ca5883e054becd12d8ae826d5b9e2afe61e0`.
Versão do pacote Roku: 0.2.3 (build local). Projeto independente, sem vínculo oficial com o Stremio.

## Alterações

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
