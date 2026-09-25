# Spec — Clipboard history for macOS

Quero criar uma feature/util para meu mac para igualar a funcionalidade do
windows de gerenciar oq esta em minha area de transferencia (apos o ctrl c),
sinto que isso é uma dor no ambiente pois as vezes perco itens importantes e
preciso copiar novamente.

Meu planejamento é algo simples, apenas quero listar atraves de um popup oq foi
copiado onde vou poder escolher oq sera selecionado.

## Decisões tomadas a partir desta spec

| Pergunta | Decisão |
|---|---|
| Stack | Swift + SwiftUI nativo, app de menu-bar, sem dependências externas |
| Tipos de conteúdo | Só texto |
| Persistência | Em disco, sobrevive a reiniciar o app e a máquina |
| Ação ao escolher um item | Cola direto no app que estava em foco (requer permissão de Acessibilidade) |

O plano de implementação derivado desta spec está em
`.github/docs/superpowers/plans/2026-09-25-clipboard-history.md`.
