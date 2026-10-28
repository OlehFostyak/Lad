import SwiftUI

/// The settings popover under the menu bar icon.
struct PanelView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            problem
            PanelSection(title: "Виправлення") { fixes }
            PanelSection(title: "Розкладка") { layout }
            PanelSection(title: "Інше") { other }
            PanelSection(title: "Хоткеї") { hotkeys }
            lists
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("Lad").font(.headline)
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var problem: some View {
        switch model.health {
        case .needsAccess:
            Callout(
                text: "Lad потрібен «Універсальний доступ» (Accessibility), щоб бачити набір і виправляти слова. Увімкни Lad у списку — він підхопить дозвіл сам.",
                button: "Відкрити налаштування", action: model.grantAccess
            )
        case .needsLayouts:
            Callout(
                text: "Увімкни дві розкладки: латинську (U.S. чи ABC) і кириличну.",
                button: "Налаштування клавіатури", action: model.openKeyboardSettings
            )
        case .wordsFailed:
            Callout(text: "Словники не завантажились: працює лише двічі Shift. Перевстанови Lad (make install).", button: nil, action: {})
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var fixes: some View {
        SwitchRow(title: "Автоматичне перемикання", detail: "Виправляти слово на пробілі", isOn: $model.isAutomatic)
        SwitchRow(title: "Виправляти й на Enter", detail: "Перед відправкою повідомлення", isOn: $model.convertsOnReturn)
        SwitchRow(
            title: "Перемикати під час набору", detail: "Щойно початок слова явно з іншої розкладки, не чекаючи пробілу",
            isOn: $model.convertsWhileTyping
        )
        SwitchRow(title: "Виправляти ДВі великі", detail: "«ПРивіт» → «Привіт»", isOn: $model.fixesTwoCapitals)
    }

    @ViewBuilder
    private var layout: some View {
        SwitchRow(
            title: "Розкладка для кожної програми",
            detail: model.systemSwitchesPerDocument
                ? "Вимкни в macOS «Автоматично перемикати джерело вводу документа»"
                : "Програма отримує ту розкладку, що була в ній востаннє",
            isOn: $model.remembersAppLayouts
        )
        if model.rememberedAppCount > 0 {
            Button("Забути розкладки програм (\(model.rememberedAppCount))", action: model.forgetAppLayouts)
                .buttonStyle(.link)
                .font(.caption)
        }
        SwitchRow(title: "Показувати розкладку біля курсора", detail: "UA / EN на мить, коли Lad перемикає", isOn: $model.showsLayoutHint)
        iconPicker
    }

    @ViewBuilder
    private var other: some View {
        SwitchRow(title: "Звук при виправленні", detail: nil, isOn: $model.playsSound)
        SwitchRow(title: "Запускати разом із macOS", detail: nil, isOn: $model.launchesAtLogin)
        if model.loginNeedsApproval {
            Button("Підтвердь автозапуск у Login Items…", action: model.openLoginItems)
                .buttonStyle(.link)
                .font(.caption)
        }
    }

    @ViewBuilder
    private var hotkeys: some View {
        HotkeyRow(keys: "⇧⇧", action: "виправити слово, скасувати, перекласти виділене")
        HotkeyRow(keys: "⌃⌥L", action: "автоперемикання увімк. / вимк.")
        HotkeyRow(keys: "⌃⌥T", action: "виділене латиницею (Олег → Oleh)")
        HotkeyRow(keys: "⌃⌥U", action: "регістр виділеного: малі → ВЕЛИКІ → З Великої")
    }

    private var iconPicker: some View {
        HStack {
            Text("Значок у рядку меню")
            Spacer()
            Picker("Значок у рядку меню", selection: $model.iconStyle) {
                Image(systemName: "keyboard").tag(IconStyle.keyboard)
                Text("Л").tag(IconStyle.glyph)
                Text("EN/UA").tag(IconStyle.layout)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }

    private var lists: some View {
        VStack(alignment: .leading, spacing: 6) {
            WordList(
                title: "Завжди виправляти", words: model.learnedWords, twin: model.twin, isReplaced: true,
                note: "Слова, які ти виправив подвійним Shift, Lad далі виправляє сам.",
                remove: model.removeLearnedWord, clear: model.clearLearnedWords
            )
            WordList(
                title: "Винятки", words: model.exceptions, twin: model.twin, isReplaced: false,
                note: "Слова, які ти скасував подвійним Shift, Lad більше не виправляє.",
                remove: model.removeException, clear: model.clearExceptions
            )
        }
    }

    private var footer: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("За тиждень виправлено \(model.fixesThisWeek) · сьогодні \(model.fixesToday)").font(.caption)
                HStack(spacing: 6) {
                    Text("Lad \(model.version)").foregroundStyle(.secondary)
                    Button("Ліцензії", action: model.openLicenses).buttonStyle(.link)
                }
                .font(.caption2)
                Text("Без мережі. Набраний текст не зберігається, крім твоїх списків слів.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Вийти", action: model.quit)
                .keyboardShortcut("q")
        }
    }

    private var statusText: String {
        switch model.health {
        case let .working(pair): "Працює · \(pair)"
        case .manualOnly: "Лише вручну: двічі Shift"
        case .secureInput: "Чекає: увімкнений захищений ввід (поле пароля)"
        case .loadingWords: "Завантажую словники…"
        case .wordsFailed: "Словники не завантажились"
        case .needsAccess: "Потрібен доступ"
        case .needsLayouts: "Потрібні дві розкладки"
        }
    }

    private var statusColor: Color {
        switch model.health {
        case .working: .green
        case .manualOnly, .secureInput, .loadingWords: .secondary
        case .wordsFailed, .needsAccess, .needsLayouts: .orange
        }
    }
}

private struct SwitchRow: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

/// A titled group of rows.
private struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct HotkeyRow: View {
    let keys: String
    let action: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(keys)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .frame(width: 40, alignment: .leading)
            Text(action)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A collapsible list of words with a remove button each and a "forget all" link. Each word shows
/// its twin in the other layout, and what does not stay on screen is struck through: the typed word
/// of a learned fix (руддщ → hello), the twin of an exception (ghbdsn → привіт).
private struct WordList: View {
    let title: String
    let words: [String]
    let twin: (String) -> String?
    /// Learned words are replaced by their twin; exceptions stay as typed.
    let isReplaced: Bool
    let note: String
    let remove: (String) -> Void
    let clear: () -> Void

    var body: some View {
        DisclosureGroup("\(title) (\(words.count))") {
            if words.isEmpty {
                Note(text: note)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(words, id: \.self) { word in
                            WordPairRow(typed: word, twin: twin(word), isReplaced: isReplaced) { remove(word) }
                        }
                    }
                }
                .frame(maxHeight: 140)
                Button("Забути всі", role: .destructive, action: clear)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }
}

private struct WordPairRow: View {
    let typed: String
    let twin: String?
    let isReplaced: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(typed)
                .strikethrough(isReplaced)
                .foregroundStyle(isReplaced ? HierarchicalShapeStyle.secondary : .primary)
            if let twin {
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(twin)
                    .strikethrough(!isReplaced)
                    .foregroundStyle(isReplaced ? HierarchicalShapeStyle.primary : .secondary)
            }
            Spacer()
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Прибрати")
        }
        .font(.system(.body, design: .monospaced))
        .lineLimit(1)
        .truncationMode(.middle)
    }
}

private struct Note: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Callout: View {
    let text: String
    let button: String?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(text).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .font(.callout)
            if let button {
                Button(button, action: action)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
