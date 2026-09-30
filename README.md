# macUtil

Histórico da área de transferência para macOS, no estilo do `Win + V` do
Windows. Fica na barra de menus, guarda o texto que você copia e abre um popup
para escolher um item e colá-lo direto no app que estava em foco.

## Requisitos

- macOS 14 ou mais recente
- Xcode ou Command Line Tools com Swift 6.2+ (`xcode-select --install`)

## Executar

```bash
Scripts/bundle.sh            # build debug
Scripts/bundle.sh release    # build release
open build/macUtil.app
```

O script compila com o SwiftPM e empacota o binário em `build/macUtil.app`. O
bundle é necessário para o app não aparecer no Dock e para o macOS reconhecer a
permissão de Acessibilidade.

O ícone aparece na barra de menus. Para sair, use o menu do ícone ›
"Sair do macUtil".

## Permissão de Acessibilidade

Para colar automaticamente, o app sintetiza um `Cmd+V`, o que exige permissão
de Acessibilidade. Na primeira vez que você escolher um item, o macOS pede a
permissão; libere o macUtil em
**Ajustes do Sistema › Privacidade e Segurança › Acessibilidade** e reabra o
app. Sem a permissão, o texto vai para a área de transferência e você cola com
`Cmd+V`.

### Assinatura

`Scripts/bundle.sh` assina o app com a primeira identidade "Apple Development"
encontrada no Keychain. Assim a permissão continua válida entre builds. Para
usar outra identidade:

```bash
MACUTIL_SIGN_IDENTITY="Nome ou hash SHA-1 da identidade" Scripts/bundle.sh
```

Sem nenhuma identidade disponível, o script cai para assinatura ad-hoc e avisa.
Nesse caso a permissão deixa de valer a cada build: remova o macUtil da lista
de Acessibilidade e adicione de novo.

## Uso

| Atalho | Ação |
|---|---|
| `Control + Option + V` | Abre ou fecha o popup |
| Digitar | Filtra o histórico |
| `↑` / `↓` | Move a seleção |
| `Return` | Cola o item selecionado no app anterior |
| `Delete` | Remove o item do histórico |
| `Esc` | Fecha o popup |

- Só texto é guardado, até 200 itens.
- Conteúdo marcado como sensível por gerenciadores de senha
  (`org.nspasteboard.ConcealedType` e afins) é ignorado.
- O histórico fica em `~/Library/Application Support/macUtil/history.json`.

## Testes

```bash
swift test
```
