# Clipboard History (macUtil) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir um app de menu-bar para macOS que guarda o histórico de textos copiados e, por um atalho global, abre um popup onde o usuário escolhe um item e ele é colado no app em foco — o equivalente de `Win+V` do Windows.

**Architecture:** Um pacote Swift Package Manager com dois alvos. `ClipboardKit` é uma biblioteca com toda a lógica pura (modelo do item, histórico com deduplicação e limite, persistência em JSON, motor de polling do pasteboard) e é 100% coberta por testes. `macUtil` é o executável AppKit/SwiftUI que apenas liga essa lógica ao sistema: `NSStatusItem`, um `Timer` que chama `tick()`, o hot key global via Carbon, um `NSPanel` com a lista SwiftUI, e o envio de `Cmd+V` via `CGEvent`. Um script empacota o binário em um `macUtil.app` com `LSUIElement` para que não apareça no Dock e para que a permissão de Acessibilidade fique associada a um bundle estável.

**Tech Stack:** Swift 6.2 / Xcode 27, SwiftPM, AppKit + SwiftUI (Observation), Carbon `RegisterEventHotKey`, `CGEvent`, `AXIsProcessTrusted`, Swift Testing (`import Testing`). Zero dependências de terceiros.

**Spec:** `.github/docs/Spec.md`

## Global Constraints

- Todos os caminhos deste plano são relativos à raiz do repositório, e todo comando é executado a partir dela.
- Deployment target: macOS 14. `platforms: [.macOS(.v14)]` no `Package.swift`.
- `// swift-tools-version: 6.2`. Concorrência estrita do Swift 6: todo tipo que toca AppKit é `@MainActor`.
- Zero dependências externas. Nada de CocoaPods, SPM remoto, Homebrew.
- Framework de teste: **Swift Testing** (`import Testing`, `@Test`, `#expect`). Não usar XCTest.
- Só o alvo `ClipboardKit` tem testes automatizados. O alvo `macUtil` (AppKit/SwiftUI) é verificado manualmente com passos explícitos em cada tarefa.
- Bundle identifier: `dev.macutil.app`. Nome do executável e do app: `macUtil`.
- Atalho global: **Control + Option + V** (`controlKey | optionKey`, keycode `0x09`). Escolhido por não colidir com `Cmd+Shift+V` ("Paste and Match Style") que muitos apps usam.
- Capacidade do histórico: 200 itens. Intervalo de polling do pasteboard: 0.5 s.
- Persistência: `~/Library/Application Support/macUtil/history.json`, escrita atômica, permissões `0600`.
- Só texto. Imagens, arquivos e RTF ficam fora de escopo.
- Privacidade obrigatória: itens marcados com os tipos de pasteboard `org.nspasteboard.ConcealedType` (gerenciadores de senha) ou `org.nspasteboard.TransientType` nunca entram no histórico.
- Commits em inglês, prefixo convencional (`feat:`, `test:`, `chore:`, `docs:`).

## File Structure

| Arquivo | Responsabilidade |
|---|---|
| `Package.swift` | Manifesto SwiftPM: alvos `ClipboardKit`, `macUtil`, `ClipboardKitTests`. |
| `Sources/ClipboardKit/ClipItem.swift` | Modelo de um item copiado + texto de preview de uma linha. |
| `Sources/ClipboardKit/ClipboardHistory.swift` | Coleção: inserção no topo, deduplicação, limite de capacidade, remoção, busca. |
| `Sources/ClipboardKit/HistoryStore.swift` | Protocolo de persistência + implementação JSON em arquivo. |
| `Sources/ClipboardKit/PasteboardReading.swift` | Protocolo que abstrai o `NSPasteboard` + conformidade real. |
| `Sources/ClipboardKit/ClipboardMonitor.swift` | Motor: compara `changeCount`, grava no histórico, salva, notifica. |
| `Sources/macUtil/main.swift` | Ponto de entrada: cria `NSApplication` em modo accessory. |
| `Sources/macUtil/AppDelegate.swift` | Ciclo de vida, status item, menu, timer de polling, ligação das peças. |
| `Sources/macUtil/HotKey.swift` | Registro do hot key global via Carbon. |
| `Sources/macUtil/PopupController.swift` | Mostra/esconde o `NSPanel`, guarda o app anterior, executa a colagem. |
| `Sources/macUtil/HistoryViewModel.swift` | Estado observável da lista (query, itens filtrados, seleção). |
| `Sources/macUtil/HistoryListView.swift` | View SwiftUI: campo de busca, lista, navegação por teclado. |
| `Sources/macUtil/Paster.swift` | Checagem de permissão de Acessibilidade e envio de `Cmd+V`. |
| `Scripts/Info.plist` | `LSUIElement`, bundle id, versão. |
| `Scripts/bundle.sh` | Compila e monta `build/macUtil.app`, assina ad-hoc. |
| `Tests/ClipboardKitTests/*.swift` | Testes de `ClipboardHistory`, `JSONHistoryStore`, `ClipboardMonitor`. |
| `README.md` | Como compilar, instalar, conceder permissão, atalho. |

---

### Task 1: Bootstrap do pacote + modelo e histórico

**Files:**
- Create: `.gitignore`
- Create: `Package.swift`
- Create: `Sources/ClipboardKit/ClipItem.swift`
- Create: `Sources/ClipboardKit/ClipboardHistory.swift`
- Test: `Tests/ClipboardKitTests/ClipboardHistoryTests.swift`

**Interfaces:**
- Consumes: nada.
- Produces: `struct ClipItem: Codable, Identifiable, Equatable { let id: UUID; let text: String; var copiedAt: Date; var preview: String }` e `struct ClipboardHistory: Codable, Equatable` com `init(items: [ClipItem] = [], capacity: Int = 200)`, `var items: [ClipItem] { get }`, `mutating func record(_ text: String, at date: Date = Date()) -> Bool`, `mutating func remove(id: UUID)`, `mutating func removeAll()`, `func search(_ query: String) -> [ClipItem]`, `static let defaultCapacity = 200`.

- [ ] **Step 1: Aceitar a licença do Xcode**

A licença do Xcode não foi aceita nesta máquina — sem isso `swift build` falha com `You have not agreed to the Xcode license agreements`. Precisa de `sudo`, então peça ao usuário rodar no prompt do Claude Code:

```
! sudo xcodebuild -license accept
```

Confirme com:

```bash
swift --version
```

Esperado: imprime `swift-driver version: ... Swift version 6.x`, sem erro de licença.

- [ ] **Step 2: Inicializar o repositório git**

O diretório ainda não é um repositório git.

```bash
cd "$(git rev-parse --show-toplevel)"
git init
cat > .gitignore <<'EOF'
.DS_Store
.build/
build/
*.xcuserdatad
.swiftpm/
EOF
git add .gitignore .github
git commit -m "chore: init repository with spec and gitignore"
```

- [ ] **Step 3: Criar o manifesto do pacote**

```bash
mkdir -p Sources/ClipboardKit \
         Sources/macUtil \
         Tests/ClipboardKitTests
```

`Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "macUtil",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClipboardKit"),
        // Descomentado na Task 4, quando main.swift existir: SwiftPM falha em
        // um alvo que ainda não tem nenhum arquivo .swift.
        // .executableTarget(name: "macUtil", dependencies: ["ClipboardKit"]),
        .testTarget(name: "ClipboardKitTests", dependencies: ["ClipboardKit"]),
    ]
)
```

- [ ] **Step 4: Escrever o teste que falha para `ClipboardHistory`**

`Tests/ClipboardKitTests/ClipboardHistoryTests.swift`:

```swift
import Foundation
import Testing
@testable import ClipboardKit

@Test func recordPutsNewestItemFirst() {
    var history = ClipboardHistory()
    history.record("primeiro")
    history.record("segundo")
    #expect(history.items.map(\.text) == ["segundo", "primeiro"])
}

@Test func recordMovesDuplicateToFrontWithoutGrowing() {
    var history = ClipboardHistory()
    history.record("a")
    history.record("b")
    history.record("a")
    #expect(history.items.map(\.text) == ["a", "b"])
}

@Test func recordUpdatesTimestampOfDuplicate() {
    let old = Date(timeIntervalSince1970: 0)
    let recent = Date(timeIntervalSince1970: 100)
    var history = ClipboardHistory()
    history.record("a", at: old)
    history.record("a", at: recent)
    #expect(history.items.first?.copiedAt == recent)
}

@Test func recordIgnoresBlankText() {
    var history = ClipboardHistory()
    #expect(history.record("") == false)
    #expect(history.record("   \n\t ") == false)
    #expect(history.items.isEmpty)
}

@Test func recordDropsOldestBeyondCapacity() {
    var history = ClipboardHistory(capacity: 3)
    for text in ["1", "2", "3", "4"] { history.record(text) }
    #expect(history.items.map(\.text) == ["4", "3", "2"])
}

@Test func removeDeletesOnlyTheGivenItem() {
    var history = ClipboardHistory()
    history.record("a")
    history.record("b")
    let target = try! #require(history.items.first)
    history.remove(id: target.id)
    #expect(history.items.map(\.text) == ["a"])
}

@Test func removeAllEmptiesHistory() {
    var history = ClipboardHistory()
    history.record("a")
    history.removeAll()
    #expect(history.items.isEmpty)
}

@Test func searchIsCaseInsensitiveSubstringMatch() {
    var history = ClipboardHistory()
    history.record("Hello World")
    history.record("outra coisa")
    #expect(history.search("hello").map(\.text) == ["Hello World"])
    #expect(history.search("  ").count == 2)
}

@Test func previewCollapsesNewlinesAndTruncates() {
    let item = ClipItem(text: "linha um\n  linha dois  \n\nlinha três")
    #expect(item.preview == "linha um linha dois linha três")

    let long = ClipItem(text: String(repeating: "x", count: 200))
    #expect(long.preview.count == 80)
    #expect(long.preview.hasSuffix("…"))
}

@Test func historySurvivesJSONRoundTrip() throws {
    var history = ClipboardHistory(capacity: 5)
    history.record("a")
    history.record("b")
    let data = try JSONEncoder().encode(history)
    let decoded = try JSONDecoder().decode(ClipboardHistory.self, from: data)
    #expect(decoded == history)
}
```

`try! #require` dentro de um teste não-`throws` funciona, mas prefira marcar o teste como `throws` e usar `try #require`. Ajuste `removeDeletesOnlyTheGivenItem` para:

```swift
@Test func removeDeletesOnlyTheGivenItem() throws {
    var history = ClipboardHistory()
    history.record("a")
    history.record("b")
    let target = try #require(history.items.first)
    history.remove(id: target.id)
    #expect(history.items.map(\.text) == ["a"])
}
```

- [ ] **Step 5: Rodar os testes para ver falhar**

Run: `swift test`
Esperado: FALHA de compilação — `cannot find 'ClipboardHistory' in scope`, `cannot find 'ClipItem' in scope`.

- [ ] **Step 6: Implementar `ClipItem`**

`Sources/ClipboardKit/ClipItem.swift`:

```swift
import Foundation

/// One piece of text captured from the pasteboard.
public struct ClipItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    /// Last time this exact text was copied. Re-copying an existing item bumps it.
    public var copiedAt: Date

    public init(id: UUID = UUID(), text: String, copiedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
    }

    /// Single-line, length-capped label for the popup list.
    public var preview: String {
        let collapsed = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > 80 else { return collapsed }
        return String(collapsed.prefix(79)) + "…"
    }
}
```

- [ ] **Step 7: Implementar `ClipboardHistory`**

`Sources/ClipboardKit/ClipboardHistory.swift`:

```swift
import Foundation

/// Newest-first list of copied texts, deduplicated and capped.
public struct ClipboardHistory: Codable, Equatable, Sendable {
    public static let defaultCapacity = 200

    public private(set) var items: [ClipItem]
    public let capacity: Int

    public init(items: [ClipItem] = [], capacity: Int = ClipboardHistory.defaultCapacity) {
        self.capacity = max(1, capacity)
        self.items = Array(items.prefix(self.capacity))
    }

    /// Inserts `text` at the front, moving an existing copy instead of duplicating it.
    /// Returns false when the text was blank and nothing changed.
    @discardableResult
    public mutating func record(_ text: String, at date: Date = Date()) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        if let index = items.firstIndex(where: { $0.text == text }) {
            var existing = items.remove(at: index)
            existing.copiedAt = date
            items.insert(existing, at: 0)
            return true
        }

        items.insert(ClipItem(text: text, copiedAt: date), at: 0)
        if items.count > capacity {
            items.removeLast(items.count - capacity)
        }
        return true
    }

    public mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    public mutating func removeAll() {
        items.removeAll()
    }

    /// Case-insensitive substring filter. A blank query returns everything.
    public func search(_ query: String) -> [ClipItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
    }
}
```

- [ ] **Step 8: Rodar os testes para ver passar**

Run: `swift test`
Esperado: PASSA, 10 testes, 0 falhas.

- [ ] **Step 9: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add Package.swift Sources/ClipboardKit Tests/ClipboardKitTests
git commit -m "feat: add ClipItem and capped deduplicated ClipboardHistory"
```

---

### Task 2: Persistência em JSON

**Files:**
- Create: `Sources/ClipboardKit/HistoryStore.swift`
- Test: `Tests/ClipboardKitTests/HistoryStoreTests.swift`

**Interfaces:**
- Consumes: `ClipboardHistory` (Task 1).
- Produces: `protocol HistoryStore { func load() -> ClipboardHistory; func save(_ history: ClipboardHistory) }` e `struct JSONHistoryStore: HistoryStore` com `init(url: URL)`, `let url: URL`, `static func defaultURL(fileManager: FileManager = .default) -> URL`.

Decisão de design: `load()` e `save()` **não lançam erro**. Um clipboard manager nunca deve travar por causa de um arquivo corrompido; arquivo ilegível vira histórico vazio, falha de escrita é silenciosa. Isso é intencional, não descuido.

- [ ] **Step 1: Escrever o teste que falha**

`Tests/ClipboardKitTests/HistoryStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import ClipboardKit

/// Fresh empty directory per test, removed at the end.
private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("macUtilTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

@Test func loadReturnsEmptyHistoryWhenFileMissing() throws {
    try withTemporaryDirectory { directory in
        let store = JSONHistoryStore(url: directory.appendingPathComponent("history.json"))
        #expect(store.load().items.isEmpty)
    }
}

@Test func saveThenLoadRoundTripsItems() throws {
    try withTemporaryDirectory { directory in
        let store = JSONHistoryStore(url: directory.appendingPathComponent("history.json"))
        var history = ClipboardHistory()
        history.record("um")
        history.record("dois")

        store.save(history)

        #expect(store.load().items.map(\.text) == ["dois", "um"])
    }
}

@Test func loadReturnsEmptyHistoryWhenFileIsCorrupt() throws {
    try withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("history.json")
        try Data("not json at all".utf8).write(to: url)
        let store = JSONHistoryStore(url: url)
        #expect(store.load().items.isEmpty)
    }
}

@Test func saveCreatesMissingParentDirectory() throws {
    try withTemporaryDirectory { directory in
        let url = directory
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("history.json")
        let store = JSONHistoryStore(url: url)
        var history = ClipboardHistory()
        history.record("um")

        store.save(history)

        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

@Test func savedFileIsReadableOnlyByOwner() throws {
    try withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("history.json")
        let store = JSONHistoryStore(url: url)
        var history = ClipboardHistory()
        history.record("segredo")

        store.save(history)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.int16Value == 0o600)
    }
}

@Test func defaultURLLivesUnderApplicationSupport() {
    let url = JSONHistoryStore.defaultURL()
    #expect(url.lastPathComponent == "history.json")
    #expect(url.deletingLastPathComponent().lastPathComponent == "macUtil")
    #expect(url.path.contains("Application Support"))
}
```

- [ ] **Step 2: Rodar para ver falhar**

Run: `swift test --filter HistoryStore`
Esperado: FALHA de compilação — `cannot find 'JSONHistoryStore' in scope`.

- [ ] **Step 3: Implementar o store**

`Sources/ClipboardKit/HistoryStore.swift`:

```swift
import Foundation

/// Where the history is kept between launches.
public protocol HistoryStore {
    func load() -> ClipboardHistory
    func save(_ history: ClipboardHistory)
}

/// Single pretty-printed JSON file. Failures are swallowed on purpose: losing
/// history is acceptable, crashing a background menu-bar app is not.
public struct JSONHistoryStore: HistoryStore {
    public let url: URL
    private let fileManager: FileManager

    public init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("macUtil", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    public func load() -> ClipboardHistory {
        guard let data = try? Data(contentsOf: url),
              let history = try? JSONDecoder().decode(ClipboardHistory.self, from: data)
        else { return ClipboardHistory() }
        return history
    }

    public func save(_ history: ClipboardHistory) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(history) else { return }

        try? fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        // Clipboard text is sensitive; keep it out of other accounts' reach.
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
```

- [ ] **Step 4: Rodar para ver passar**

Run: `swift test`
Esperado: PASSA, 16 testes.

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add Sources/ClipboardKit/HistoryStore.swift Tests/ClipboardKitTests/HistoryStoreTests.swift
git commit -m "feat: persist clipboard history to an owner-only JSON file"
```

---

### Task 3: Motor de captura (`ClipboardMonitor`)

**Files:**
- Create: `Sources/ClipboardKit/PasteboardReading.swift`
- Create: `Sources/ClipboardKit/ClipboardMonitor.swift`
- Test: `Tests/ClipboardKitTests/ClipboardMonitorTests.swift`

**Interfaces:**
- Consumes: `ClipboardHistory` (Task 1), `HistoryStore` (Task 2).
- Produces:
  - `protocol PasteboardReading: AnyObject { var changeCount: Int { get }; var isConcealed: Bool { get }; func readString() -> String? }`, com `extension NSPasteboard: PasteboardReading`.
  - `@MainActor final class ClipboardMonitor` com `init(pasteboard: PasteboardReading, store: HistoryStore)`, `var history: ClipboardHistory { get }`, `var onChange: (() -> Void)?`, `@discardableResult func tick(now: Date = Date()) -> Bool`, `func remove(id: UUID)`, `func clear()`, `func acknowledgeOwnWrite()`.

Por que polling: o macOS não tem notificação de mudança de pasteboard. Comparar `NSPasteboard.general.changeCount` num timer é o único caminho e é o que todo clipboard manager faz.

`acknowledgeOwnWrite()` existe porque, quando nós mesmos escrevemos no pasteboard para colar (Task 7), o `changeCount` sobe e o próximo `tick()` reinseriria o item. Chamar isso depois de escrever evita o eco.

- [ ] **Step 1: Escrever o teste que falha**

`Tests/ClipboardKitTests/ClipboardMonitorTests.swift`:

```swift
import Foundation
import Testing
@testable import ClipboardKit

/// Hand-driven stand-in for NSPasteboard.
private final class FakePasteboard: PasteboardReading {
    var changeCount: Int = 0
    var isConcealed: Bool = false
    var contents: String?

    func readString() -> String? { contents }

    /// Mimics a real copy: new content plus a bumped change count.
    func copy(_ text: String?, concealed: Bool = false) {
        contents = text
        isConcealed = concealed
        changeCount += 1
    }
}

private final class SpyStore: HistoryStore {
    var saved: [ClipboardHistory] = []
    var stored = ClipboardHistory()

    func load() -> ClipboardHistory { stored }
    func save(_ history: ClipboardHistory) {
        saved.append(history)
        stored = history
    }
}

@Test @MainActor func tickRecordsNewPasteboardText() {
    let pasteboard = FakePasteboard()
    let store = SpyStore()
    let monitor = ClipboardMonitor(pasteboard: pasteboard, store: store)

    pasteboard.copy("olá")

    #expect(monitor.tick() == true)
    #expect(monitor.history.items.map(\.text) == ["olá"])
    #expect(store.saved.count == 1)
}

@Test @MainActor func tickDoesNothingWhenChangeCountIsUnchanged() {
    let pasteboard = FakePasteboard()
    let monitor = ClipboardMonitor(pasteboard: pasteboard, store: SpyStore())

    pasteboard.copy("olá")
    monitor.tick()

    #expect(monitor.tick() == false)
    #expect(monitor.history.items.count == 1)
}

@Test @MainActor func tickSkipsConcealedContent() {
    let pasteboard = FakePasteboard()
    let monitor = ClipboardMonitor(pasteboard: pasteboard, store: SpyStore())

    pasteboard.copy("senha-do-banco", concealed: true)

    #expect(monitor.tick() == false)
    #expect(monitor.history.items.isEmpty)
}

@Test @MainActor func tickSkipsNonTextContent() {
    let pasteboard = FakePasteboard()
    let monitor = ClipboardMonitor(pasteboard: pasteboard, store: SpyStore())

    pasteboard.copy(nil)

    #expect(monitor.tick() == false)
    #expect(monitor.history.items.isEmpty)
}

@Test @MainActor func monitorStartsFromPersistedHistory() {
    let store = SpyStore()
    var persisted = ClipboardHistory()
    persisted.record("antigo")
    store.stored = persisted

    let monitor = ClipboardMonitor(pasteboard: FakePasteboard(), store: store)

    #expect(monitor.history.items.map(\.text) == ["antigo"])
}

@Test @MainActor func monitorIgnoresWhateverWasOnThePasteboardAtLaunch() {
    let pasteboard = FakePasteboard()
    pasteboard.copy("já estava aqui")

    let monitor = ClipboardMonitor(pasteboard: pasteboard, store: SpyStore())

    #expect(monitor.tick() == false)
    #expect(monitor.history.items.isEmpty)
}

@Test @MainActor func acknowledgeOwnWritePreventsEchoingOurOwnPaste() {
    let pasteboard = FakePasteboard()
    let monitor = ClipboardMonitor(pasteboard: pasteboard, store: SpyStore())

    pasteboard.copy("nosso próprio texto")
    monitor.acknowledgeOwnWrite()

    #expect(monitor.tick() == false)
    #expect(monitor.history.items.isEmpty)
}

@Test @MainActor func removeAndClearPersistAndNotify() throws {
    let pasteboard = FakePasteboard()
    let store = SpyStore()
    let monitor = ClipboardMonitor(pasteboard: pasteboard, store: store)
    var notifications = 0
    monitor.onChange = { notifications += 1 }

    pasteboard.copy("a")
    monitor.tick()
    pasteboard.copy("b")
    monitor.tick()
    let target = try #require(monitor.history.items.first)

    monitor.remove(id: target.id)
    #expect(monitor.history.items.map(\.text) == ["a"])

    monitor.clear()
    #expect(monitor.history.items.isEmpty)
    #expect(store.stored.items.isEmpty)
    #expect(notifications == 4) // 2 ticks + remove + clear
}
```

- [ ] **Step 2: Rodar para ver falhar**

Run: `swift test --filter ClipboardMonitor`
Esperado: FALHA de compilação — `cannot find type 'PasteboardReading' in scope`.

- [ ] **Step 3: Implementar o protocolo do pasteboard**

`Sources/ClipboardKit/PasteboardReading.swift`:

```swift
import Foundation

/// The slice of NSPasteboard this app needs, so the monitor can be tested
/// without touching the real system pasteboard.
public protocol PasteboardReading: AnyObject {
    /// Increments on every write by any app. The only change signal macOS gives us.
    var changeCount: Int { get }
    /// True when the owner asked clipboard managers not to store this content.
    var isConcealed: Bool { get }
    func readString() -> String?
}

#if canImport(AppKit)
import AppKit

extension NSPasteboard: PasteboardReading {
    /// Convention published at nspasteboard.org and honoured by password managers.
    public var isConcealed: Bool {
        let optOut: Set<String> = [
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.TransientType",
            "org.nspasteboard.AutoGeneratedType",
        ]
        guard let types else { return false }
        return types.contains { optOut.contains($0.rawValue) }
    }

    public func readString() -> String? {
        string(forType: .string)
    }
}
#endif
```

- [ ] **Step 4: Implementar o monitor**

`Sources/ClipboardKit/ClipboardMonitor.swift`:

```swift
import Foundation

/// Watches the pasteboard and owns the history. Drive it by calling `tick()`
/// from a timer; it does not schedule anything itself.
@MainActor
public final class ClipboardMonitor {
    public private(set) var history: ClipboardHistory
    /// Fired after any change to `history`, so the UI can refresh.
    public var onChange: (() -> Void)?

    private let pasteboard: PasteboardReading
    private let store: HistoryStore
    private var lastChangeCount: Int

    public init(pasteboard: PasteboardReading, store: HistoryStore) {
        self.pasteboard = pasteboard
        self.store = store
        self.history = store.load()
        // Whatever is on the pasteboard at launch predates us; don't claim it.
        self.lastChangeCount = pasteboard.changeCount
    }

    /// Returns true when a new item was recorded.
    @discardableResult
    public func tick(now: Date = Date()) -> Bool {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return false }
        lastChangeCount = current

        guard !pasteboard.isConcealed, let text = pasteboard.readString() else { return false }
        guard history.record(text, at: now) else { return false }

        persistAndNotify()
        return true
    }

    public func remove(id: UUID) {
        history.remove(id: id)
        persistAndNotify()
    }

    public func clear() {
        history.removeAll()
        persistAndNotify()
    }

    /// Call right after writing to the pasteboard ourselves, so the next tick
    /// does not re-record the text we just pasted.
    public func acknowledgeOwnWrite() {
        lastChangeCount = pasteboard.changeCount
    }

    private func persistAndNotify() {
        store.save(history)
        onChange?()
    }
}
```

- [ ] **Step 5: Rodar para ver passar**

Run: `swift test`
Esperado: PASSA, 24 testes.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add Sources/ClipboardKit Tests/ClipboardKitTests/ClipboardMonitorTests.swift
git commit -m "feat: add pasteboard monitor that skips concealed content"
```

---

### Task 4: App de menu-bar que captura de verdade

**Files:**
- Create: `Sources/macUtil/main.swift`
- Create: `Sources/macUtil/AppDelegate.swift`
- Create: `Scripts/Info.plist`
- Create: `Scripts/bundle.sh`
- Modify: `Package.swift` (descomentar o `.executableTarget`)

**Interfaces:**
- Consumes: `ClipboardMonitor`, `JSONHistoryStore` (Tasks 2–3).
- Produces: `@MainActor final class AppDelegate: NSObject, NSApplicationDelegate` com a propriedade interna `private(set) var monitor: ClipboardMonitor!`, usada pelas Tasks 5–8. Script `Scripts/bundle.sh [debug|release]` que gera `build/macUtil.app`.

Entregável desta tarefa: ícone na menu bar, e o `history.json` cresce conforme você copia texto. Sem popup ainda.

- [ ] **Step 1: Habilitar o alvo executável**

Em `Package.swift`, remova o comentário e deixe:

```swift
        .executableTarget(name: "macUtil", dependencies: ["ClipboardKit"]),
```

- [ ] **Step 2: Escrever o ponto de entrada**

`Sources/macUtil/main.swift`:

```swift
import AppKit

// No SwiftUI App lifecycle here: a plain NSApplication in accessory mode keeps
// the app out of the Dock and out of the app switcher.
let delegate = AppDelegate()
let application = NSApplication.shared
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
```

- [ ] **Step 3: Escrever o `AppDelegate`**

`Sources/macUtil/AppDelegate.swift`:

```swift
import AppKit
import ClipboardKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var monitor: ClipboardMonitor!
    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?

    /// macOS gives no pasteboard-change notification; 0.5 s is the usual compromise
    /// between catching every copy and staying idle.
    private let pollInterval: TimeInterval = 0.5

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = ClipboardMonitor(
            pasteboard: NSPasteboard.general,
            store: JSONHistoryStore(url: JSONHistoryStore.defaultURL())
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "list.clipboard",
            accessibilityDescription: "macUtil clipboard history"
        )
        statusItem.menu = makeMenu()

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            // The timer fires on the main run loop, so main-actor state is safe here.
            MainActor.assumeIsolated { self?.monitor.tick() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Sair do macUtil", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }
}
```

- [ ] **Step 4: Escrever o `Info.plist` do bundle**

`Scripts/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>macUtil</string>
    <key>CFBundleDisplayName</key>
    <string>macUtil</string>
    <key>CFBundleIdentifier</key>
    <string>dev.macutil.app</string>
    <key>CFBundleExecutable</key>
    <string>macUtil</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 5: Escrever o script de empacotamento**

`Scripts/bundle.sh`:

```bash
#!/usr/bin/env bash
# Wraps the SwiftPM binary in a .app bundle. The bundle is required for two
# reasons: LSUIElement (no Dock icon) and a stable identity for the
# Accessibility permission granted in System Settings.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIGURATION="${1:-debug}"

swift build -c "$CONFIGURATION"
BINARY="$(swift build -c "$CONFIGURATION" --show-bin-path)/macUtil"
APP="build/macUtil.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/macUtil"
cp Scripts/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature with a fixed identifier so macOS keeps recognising the app
# across rebuilds.
codesign --force --sign - --identifier dev.macutil.app "$APP"

echo "built $APP"
```

```bash
chmod +x Scripts/bundle.sh
```

- [ ] **Step 6: Compilar**

Run: `./Scripts/bundle.sh`
Esperado: termina com `built build/macUtil.app`, sem warnings de concorrência.

- [ ] **Step 7: Verificação manual da captura**

```bash
rm -f ~/Library/Application\ Support/macUtil/history.json
open build/macUtil.app
```

Então: copie três textos diferentes em qualquer app (`Cmd+C`), espere ~1 s e rode:

```bash
cat ~/Library/Application\ Support/macUtil/history.json
```

Esperado: ícone de clipboard visível na menu bar, sem ícone no Dock, e o JSON lista os três textos com o mais recente primeiro. Verifique também `ls -l ~/Library/Application\ Support/macUtil/history.json` → permissões `-rw-------`.

Para encerrar: use "Sair do macUtil" no menu, ou `pkill -f build/macUtil.app`.

- [ ] **Step 8: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add Package.swift Sources/macUtil Scripts
git commit -m "feat: add menu-bar app that records copies to disk"
```

---

### Task 5: Atalho global (Control + Option + V)

**Files:**
- Create: `Sources/macUtil/HotKey.swift`
- Modify: `Sources/macUtil/AppDelegate.swift`

**Interfaces:**
- Consumes: `AppDelegate` (Task 4).
- Produces: `@MainActor final class HotKey` com `init(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void)`. `AppDelegate` ganha `private var hotKey: HotKey?`.

Por que Carbon: `RegisterEventHotKey` é a única API de atalho global que funciona **sem** permissão de Acessibilidade. `NSEvent.addGlobalMonitorForEvents` exigiria essa permissão só para ouvir teclas, o que é pior para o usuário. A API é antiga mas não foi removida.

- [ ] **Step 1: Escrever o `HotKey`**

`Sources/macUtil/HotKey.swift`:

```swift
import AppKit
import Carbon.HIToolbox

/// One system-wide hot key. Carbon is used deliberately: it is the only global
/// hot key API that does not require Accessibility permission.
@MainActor
final class HotKey {
    /// The C callback cannot capture context, so live instances are looked up by id.
    private static var instances: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1
    private static var handler: EventHandlerRef?

    private let id: UInt32
    private let action: @MainActor () -> Void
    private var reference: EventHotKeyRef?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        self.id = HotKey.nextID
        self.action = action
        HotKey.nextID += 1
        HotKey.instances[id] = self

        HotKey.installHandlerIfNeeded()

        // 'mUt1' — an arbitrary but stable signature for this app's hot keys.
        var hotKeyID = EventHotKeyID(signature: OSType(0x6D_55_74_31), id: id)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &reference
        )
        _ = hotKeyID
    }

    deinit {
        if let reference {
            UnregisterEventHotKey(reference)
        }
        MainActor.assumeIsolated { HotKey.instances[id] = nil }
    }

    private static func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                // Carbon hot key events are delivered on the main thread.
                MainActor.assumeIsolated {
                    HotKey.instances[hotKeyID.id]?.action()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handler
        )
    }
}

extension HotKey {
    /// Control + Option + V — the app's default trigger. Chosen over Cmd+Shift+V,
    /// which many apps already use for "Paste and Match Style".
    static func controlOptionV(action: @escaping @MainActor () -> Void) -> HotKey {
        HotKey(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(controlKey | optionKey),
            action: action
        )
    }
}
```

- [ ] **Step 2: Registrar o atalho no `AppDelegate`**

Em `Sources/macUtil/AppDelegate.swift`, adicione a propriedade logo abaixo de `private var pollTimer: Timer?`:

```swift
    private var hotKey: HotKey?
```

E no fim de `applicationDidFinishLaunching`, depois da criação do `pollTimer`:

```swift
        hotKey = HotKey.controlOptionV { [weak self] in
            // Replaced by the popup in Task 6.
            guard let self else { return }
            NSLog("macUtil hot key fired, %d items in history", monitor.history.items.count)
        }
```

- [ ] **Step 3: Compilar**

Run: `./Scripts/bundle.sh`
Esperado: `built build/macUtil.app`, sem erros.

- [ ] **Step 4: Verificação manual do atalho**

```bash
pkill -f build/macUtil.app || true
open build/macUtil.app
log stream --predicate 'eventMessage CONTAINS "macUtil hot key"' --style compact
```

Com o `log stream` rodando, copie algo, então pressione `Control+Option+V` três vezes em apps diferentes (Finder, navegador, terminal).

Esperado: três linhas `macUtil hot key fired, N items in history`, independentemente do app em foco. Se nada aparecer, outro app já registrou esse atalho — troque `optionKey` por `shiftKey` no `controlOptionV` e teste de novo, anotando a mudança no README na Task 8.

`Ctrl+C` encerra o `log stream`.

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add Sources/macUtil/HotKey.swift Sources/macUtil/AppDelegate.swift
git commit -m "feat: register Control+Option+V global hot key"
```

---

### Task 6: Popup com lista, busca e navegação por teclado

**Files:**
- Create: `Sources/macUtil/HistoryViewModel.swift`
- Create: `Sources/macUtil/HistoryListView.swift`
- Create: `Sources/macUtil/PopupController.swift`
- Modify: `Sources/macUtil/AppDelegate.swift`

**Interfaces:**
- Consumes: `ClipboardMonitor` (Task 3), `HotKey` (Task 5).
- Produces:
  - `@MainActor @Observable final class HistoryViewModel` com `init(monitor: ClipboardMonitor)`, `var query: String`, `var items: [ClipItem] { get }`, `var selection: UUID?`, `var selectedItem: ClipItem? { get }`, `func refresh()`, `func moveSelection(by delta: Int)`, `func delete(id: UUID)`.
  - `struct HistoryListView: View` com `init(viewModel: HistoryViewModel, onPick: @escaping (ClipItem) -> Void, onDismiss: @escaping () -> Void)`.
  - `@MainActor final class PopupController` com `init(monitor: ClipboardMonitor, onPick: @escaping (ClipItem) -> Void)`, `func toggle()`, `func show()`, `func hide()`.

Nesta tarefa escolher um item só **copia** para o pasteboard e fecha o popup. A colagem automática entra na Task 7.

- [ ] **Step 1: Escrever o view model**

`Sources/macUtil/HistoryViewModel.swift`:

```swift
import ClipboardKit
import Foundation
import Observation

/// Search text, filtered rows and keyboard selection for the popup.
@MainActor
@Observable
final class HistoryViewModel {
    var query: String = "" {
        didSet { refresh() }
    }
    private(set) var items: [ClipItem] = []
    var selection: UUID?

    private let monitor: ClipboardMonitor

    init(monitor: ClipboardMonitor) {
        self.monitor = monitor
        refresh()
    }

    var selectedItem: ClipItem? {
        items.first { $0.id == selection }
    }

    func refresh() {
        items = monitor.history.search(query)
        if selection == nil || !items.contains(where: { $0.id == selection }) {
            selection = items.first?.id
        }
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selection } ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        selection = items[next].id
    }

    func delete(id: UUID) {
        monitor.remove(id: id)
        refresh()
    }
}
```

- [ ] **Step 2: Escrever a view**

`Sources/macUtil/HistoryListView.swift`:

```swift
import ClipboardKit
import SwiftUI

struct HistoryListView: View {
    @Bindable var viewModel: HistoryViewModel
    let onPick: (ClipItem) -> Void
    let onDismiss: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Buscar no histórico", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(10)
                .focused($searchFocused)
                .onSubmit { pickSelected() }

            Divider()

            if viewModel.items.isEmpty {
                ContentUnavailableView(
                    viewModel.query.isEmpty ? "Histórico vazio" : "Nada encontrado",
                    systemImage: "list.clipboard"
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { scroll in
                    List(viewModel.items, selection: $viewModel.selection) { item in
                        row(for: item)
                            .id(item.id)
                    }
                    .listStyle(.plain)
                    .onChange(of: viewModel.selection) { _, new in
                        guard let new else { return }
                        withAnimation(.none) { scroll.scrollTo(new) }
                    }
                }
            }

            Divider()

            Text("↑↓ navegar · ⏎ usar · ⌫ apagar · esc fechar")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(6)
        }
        .frame(width: 440, height: 420)
        .onAppear { searchFocused = true }
        .onKeyPress(.downArrow) { viewModel.moveSelection(by: 1); return .handled }
        .onKeyPress(.upArrow) { viewModel.moveSelection(by: -1); return .handled }
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .onKeyPress(.return) { pickSelected(); return .handled }
        .onKeyPress(.delete) { deleteSelected(); return .handled }
    }

    private func row(for item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.preview)
                .lineLimit(1)
            Text(item.copiedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { onPick(item) }
    }

    private func pickSelected() {
        guard let item = viewModel.selectedItem else { return }
        onPick(item)
    }

    private func deleteSelected() {
        guard let id = viewModel.selection else { return }
        viewModel.delete(id: id)
    }
}
```

- [ ] **Step 3: Escrever o controlador do painel**

`Sources/macUtil/PopupController.swift`:

```swift
import AppKit
import ClipboardKit
import SwiftUI

/// Owns the floating panel. Remembers which app was in front so the caller can
/// hand focus back after a pick.
@MainActor
final class PopupController {
    /// The app that was frontmost when the popup opened.
    private(set) var previousApplication: NSRunningApplication?

    private let monitor: ClipboardMonitor
    private let onPick: (ClipItem) -> Void
    private var panel: NSPanel?

    init(monitor: ClipboardMonitor, onPick: @escaping (ClipItem) -> Void) {
        self.monitor = monitor
        self.onPick = onPick
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        previousApplication = NSWorkspace.shared.frontmostApplication

        let viewModel = HistoryViewModel(monitor: monitor)
        let view = HistoryListView(
            viewModel: viewModel,
            onPick: { [weak self] item in
                self?.hide()
                self?.onPick(item)
            },
            onDismiss: { [weak self] in self?.hide() }
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: view)
        panel.center()

        // An accessory app must activate for its panel to take keyboard input.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}
```

- [ ] **Step 4: Ligar o popup ao atalho e ao status item**

Em `Sources/macUtil/AppDelegate.swift`, adicione a propriedade:

```swift
    private var popup: PopupController?
```

Substitua o bloco `hotKey = HotKey.controlOptionV { ... NSLog ... }` da Task 5 por:

```swift
        popup = PopupController(monitor: monitor) { [weak self] item in
            self?.use(item)
        }
        hotKey = HotKey.controlOptionV { [weak self] in
            self?.popup?.toggle()
        }
```

Adicione o método (a colagem automática entra na Task 7):

```swift
    /// Puts the chosen text back on the pasteboard.
    private func use(_ item: ClipItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        monitor.acknowledgeOwnWrite()
    }
```

E acrescente o item de abertura no topo de `makeMenu()`, antes do "Sair":

```swift
        let open = NSMenuItem(title: "Abrir histórico", action: #selector(openPopup), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
```

Com o handler:

```swift
    @objc private func openPopup() {
        popup?.show()
    }
```

Por fim, o import de `ClipItem` já vem de `import ClipboardKit`, que o arquivo tem.

- [ ] **Step 5: Compilar**

Run: `./Scripts/bundle.sh`
Esperado: `built build/macUtil.app`.

- [ ] **Step 6: Verificação manual do popup**

```bash
pkill -f build/macUtil.app || true
open build/macUtil.app
```

Copie 4 ou 5 textos distintos, então pressione `Control+Option+V` e confira, um a um:

1. O painel aparece centralizado, com o cursor já no campo de busca.
2. Digitar parte de um texto filtra a lista.
3. `↑`/`↓` movem a seleção e a lista rola acompanhando.
4. `⏎` fecha o painel; colar (`Cmd+V`) em um editor insere o texto escolhido.
5. Clicar em uma linha tem o mesmo efeito de `⏎`.
6. `⌫` remove a linha selecionada e ela não volta depois de reabrir o painel.
7. `esc` fecha sem alterar o pasteboard.
8. `Control+Option+V` com o painel aberto fecha o painel.

Se as setas estiverem sendo consumidas pelo campo de busca em vez de mover a seleção, troque os dois `onKeyPress` de seta para o modificador `.onKeyPress(phases: .down)` na mesma posição e repita o teste.

- [ ] **Step 7: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add Sources/macUtil
git commit -m "feat: add searchable history popup with keyboard navigation"
```

---

### Task 7: Colar direto no app que estava em foco

**Files:**
- Create: `Sources/macUtil/Paster.swift`
- Modify: `Sources/macUtil/AppDelegate.swift`

**Interfaces:**
- Consumes: `PopupController.previousApplication` (Task 6).
- Produces: `enum Paster` com `static var isTrusted: Bool`, `static func requestTrust()`, `static func sendCommandV()`.

Esta é a parte que exige permissão de Acessibilidade: sintetizar `Cmd+V` é controlar outro app. Sem a permissão, o texto ainda vai para o pasteboard e o usuário cola à mão — a degradação é suave, não um erro.

- [ ] **Step 1: Escrever o `Paster`**

`Sources/macUtil/Paster.swift`:

```swift
import AppKit
import ApplicationServices

/// Synthesises Cmd+V into whichever app has focus. Requires the app to be
/// trusted for Accessibility, because it drives another process.
enum Paster {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Opens the system prompt that sends the user to
    /// System Settings › Privacy & Security › Accessibility.
    static func requestTrust() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    /// Returns false when permission is missing; the caller should tell the user
    /// the text is on the pasteboard and they can paste it themselves.
    @discardableResult
    static func sendCommandV() -> Bool {
        guard isTrusted else { return false }

        let source = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(0x09) // kVK_ANSI_V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        else { return false }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }
}
```

- [ ] **Step 2: Colar depois de devolver o foco**

Em `Sources/macUtil/AppDelegate.swift`, substitua o método `use(_:)` da Task 6 por:

```swift
    /// Puts the chosen text on the pasteboard, hands focus back to the app the
    /// user came from, and pastes there.
    private func use(_ item: ClipItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        monitor.acknowledgeOwnWrite()

        guard Paster.isTrusted else {
            Paster.requestTrust()
            notifyPasteboardOnly()
            return
        }

        popup?.previousApplication?.activate()
        // The target app needs a moment to become frontmost before it can
        // receive the synthesised keystroke.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Paster.sendCommandV()
        }
    }

    /// Fallback path when Accessibility permission is missing.
    private func notifyPasteboardOnly() {
        let alert = NSAlert()
        alert.messageText = "Texto copiado para a área de transferência"
        alert.informativeText = """
            Para o macUtil colar automaticamente, permita o acesso em \
            Ajustes do Sistema › Privacidade e Segurança › Acessibilidade. \
            Por enquanto, use Cmd+V para colar.
            """
        alert.alertStyle = .informational
        alert.runModal()
    }
```

- [ ] **Step 3: Compilar e reempacotar**

Run: `./Scripts/bundle.sh`
Esperado: `built build/macUtil.app`.

- [ ] **Step 4: Verificação manual sem permissão**

```bash
pkill -f build/macUtil.app || true
open build/macUtil.app
```

Na primeira escolha de item, esperado: o macOS abre o diálogo pedindo acesso de Acessibilidade e o alerta do app aparece explicando que o texto está no pasteboard. `Cmd+V` manual insere o texto certo.

- [ ] **Step 5: Verificação manual com permissão**

Conceda em **Ajustes do Sistema › Privacidade e Segurança › Acessibilidade**, adicionando `build/macUtil.app` e ligando o botão. Então reinicie o app (a permissão só vale a partir do próximo lançamento):

```bash
pkill -f build/macUtil.app || true
open build/macUtil.app
```

Abra o TextEdit, copie alguns textos, clique no TextEdit, pressione `Control+Option+V`, escolha um item antigo com `↑` e `⏎`.

Esperado: o painel fecha, o TextEdit volta ao foco e o texto aparece no cursor sem nenhum `Cmd+V` manual.

Limitação conhecida a registrar no README: o app é assinado ad-hoc, então **um rebuild pode invalidar a permissão** — nesse caso remova e readicione a entrada na lista de Acessibilidade.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add Sources/macUtil/Paster.swift Sources/macUtil/AppDelegate.swift
git commit -m "feat: paste the picked item into the previously focused app"
```

---

### Task 8: Menu completo e README

**Files:**
- Modify: `Sources/macUtil/AppDelegate.swift`
- Create: `README.md`

**Interfaces:**
- Consumes: tudo das Tasks 1–7.
- Produces: nenhuma API nova.

- [ ] **Step 1: Completar o menu do status item**

Em `Sources/macUtil/AppDelegate.swift`, substitua `makeMenu()` inteiro por:

```swift
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let open = NSMenuItem(
            title: "Abrir histórico  ⌃⌥V",
            action: #selector(openPopup),
            keyEquivalent: ""
        )
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let clear = NSMenuItem(
            title: "Limpar histórico…",
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Sair do macUtil",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Limpar todo o histórico?"
        alert.informativeText = "Os \(monitor.history.items.count) itens guardados serão apagados. Não há como desfazer."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Limpar")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        monitor.clear()
    }
```

- [ ] **Step 2: Escrever o README**

`README.md`:

```markdown
# macUtil

Clipboard history for macOS — the `Win+V` experience, as a menu-bar app.

Every text you copy is remembered. Press **Control + Option + V**, pick an
older entry, and it is pasted straight into the app you were typing in.

## Requirements

- macOS 14 or later
- Xcode 26 or later, for the Swift 6.2 toolchain (accept the license once with
  `sudo xcodebuild -license accept`)

## Build and run

```bash
./Scripts/bundle.sh release
open build/macUtil.app
```

The app has no Dock icon. Look for the clipboard glyph in the menu bar.

To install it permanently:

```bash
cp -R build/macUtil.app /Applications/
open /Applications/macUtil.app
```

## Accessibility permission

Pasting into another app means controlling that app, so macOS asks for
permission. The first time you pick an item, approve the prompt, or grant it
manually in **System Settings › Privacy & Security › Accessibility** by adding
`macUtil.app`. Restart the app afterwards.

Without the permission everything still works, except the final keystroke: the
text lands on the clipboard and you paste it with `Cmd+V` yourself.

Because the app is signed ad-hoc, a rebuild can invalidate the grant. If
auto-paste stops working, remove and re-add `macUtil.app` in that list.

## Shortcuts

| Key | Action |
|---|---|
| `Control+Option+V` | Open or close the history popup |
| type | Filter the list |
| `↑` / `↓` | Move the selection |
| `Return` | Paste the selected item |
| `Delete` | Remove the selected item from history |
| `Escape` | Close the popup |

## What is stored, and where

- Text only. Images, files and rich text are ignored.
- The 200 most recent entries, newest first, duplicates collapsed.
- `~/Library/Application Support/macUtil/history.json`, permissions `0600`.
- Content marked by password managers as concealed
  (`org.nspasteboard.ConcealedType` and friends) is never recorded.

Delete the file, or use **Clear history** in the menu, to wipe everything.

## Tests

```bash
swift test
```

All logic lives in the `ClipboardKit` target and is covered there. The AppKit
shell in `Sources/macUtil` is verified by hand.
```

- [ ] **Step 3: Compilar e conferir o menu**

Run: `./Scripts/bundle.sh && pkill -f build/macUtil.app; open build/macUtil.app`

Clique no ícone da menu bar. Esperado: "Abrir histórico ⌃⌥V", separador, "Limpar histórico…", separador, "Sair do macUtil". "Abrir histórico" abre o painel; "Limpar histórico…" pede confirmação e, ao confirmar, deixa o painel vazio e o `history.json` com lista vazia.

- [ ] **Step 4: Rodar a suíte inteira**

Run: `swift test`
Esperado: PASSA, 24 testes, 0 falhas.

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add Sources/macUtil/AppDelegate.swift README.md
git commit -m "feat: complete status-bar menu and document setup"
```

---

### Task 9 (opcional): Iniciar junto com o login

**Files:**
- Create: `Sources/macUtil/LoginItem.swift`
- Modify: `Sources/macUtil/AppDelegate.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `AppDelegate` (Task 8).
- Produces: `@MainActor enum LoginItem` com `static var isEnabled: Bool`, `static func toggle()`.

Um histórico só acumula se o app estiver rodando, então isso é o que transforma o projeto em algo usável no dia a dia. Fica separado porque não está na spec e depende do app estar em `/Applications`.

- [ ] **Step 1: Escrever o `LoginItem`**

`Sources/macUtil/LoginItem.swift`:

```swift
import AppKit
import ServiceManagement

/// Launch-at-login toggle. SMAppService registers the running bundle itself,
/// so the app should live in /Applications before this is switched on.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Não foi possível alterar a abertura no login"
            alert.informativeText = """
                \(error.localizedDescription)

                Mova o macUtil.app para a pasta Aplicativos e tente de novo.
                """
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
```

- [ ] **Step 2: Adicionar o item de menu com estado**

Em `makeMenu()`, antes do separador que precede "Limpar histórico…":

```swift
        let login = NSMenuItem(
            title: "Abrir no login",
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
```

E o handler, que reconstrói o menu para o check mark refletir o novo estado:

```swift
    @objc private func toggleLoginItem() {
        LoginItem.toggle()
        statusItem.menu = makeMenu()
    }
```

- [ ] **Step 3: Compilar**

Run: `./Scripts/bundle.sh release`
Esperado: `built build/macUtil.app`.

- [ ] **Step 4: Verificação manual**

```bash
pkill -f macUtil.app || true
cp -R build/macUtil.app /Applications/
open /Applications/macUtil.app
```

Marque "Abrir no login" no menu. Confirme:

```bash
sfltool dumpbtm 2>/dev/null | grep -A2 macUtil || open "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
```

Esperado: `macUtil` aparece em Ajustes do Sistema › Geral › Itens de Login. Desmarcar o item de menu o remove da lista.

- [ ] **Step 5: Documentar e commitar**

Adicione ao README, depois da seção "Accessibility permission":

```markdown
## Launch at login

Install the app in `/Applications` first, then tick **Open at login** in the
menu-bar menu. Registration is done through `SMAppService` and shows up in
System Settings › General › Login Items.
```

```bash
cd "$(git rev-parse --show-toplevel)"
git add Sources/macUtil/LoginItem.swift Sources/macUtil/AppDelegate.swift README.md
git commit -m "feat: add launch-at-login toggle"
```

---

## Cobertura da spec

| Pedido na spec | Onde é atendido |
|---|---|
| "gerenciar o que está na área de transferência (após o Ctrl+C)" | Tasks 3–4: polling do `NSPasteboard`, gravação em disco |
| "às vezes perco itens importantes" | Task 2: persistência entre reinícios; Task 1: 200 itens com deduplicação |
| "listar através de um popup o que foi copiado" | Task 6: `NSPanel` + lista SwiftUI com busca |
| "onde vou poder escolher o que será selecionado" | Tasks 6–7: escolha por clique/`⏎`, colagem no app em foco |
| "igualar a funcionalidade do Windows" | Task 5: atalho global, análogo a `Win+V` |
| "algo simples" | Só texto, sem sincronização, sem pin, sem preferências; menos de 600 linhas de Swift |

## Fora de escopo (deliberadamente)

Imagens e arquivos, sincronização entre máquinas, itens fixados, ordenação alternativa, atalho configurável por UI, notarização e distribuição assinada. Cada um desses é um plano próprio, se algum dia fizer falta.
