import SwiftUI

/// The settings popover under the menu bar icon.
struct PanelView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            problem
            Divider()
            switches
            Divider()
            iconPicker
            Label("Двічі Shift: виправити останнє слово, скасувати виправлення або перекласти виділене.", systemImage: "shift")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

    private var switches: some View {
        VStack(alignment: .leading, spacing: 8) {
            SwitchRow(title: "Автоматичне перемикання", detail: "Виправляти слово на пробілі", isOn: $model.isAutomatic)
            SwitchRow(title: "Виправляти й на Enter", detail: "Перед відправкою повідомлення", isOn: $model.convertsOnReturn)
            SwitchRow(title: "Виправляти ДВі великі", detail: "«ПРивіт» → «Привіт»", isOn: $model.fixesTwoCapitals)
            SwitchRow(
                title: "Розкладка для кожної програми",
                detail: model.systemSwitchesPerDocument
                    ? "Вимкни в macOS «Автоматично перемикати джерело вводу документа»"
                    : "Програма отримує ту розкладку, що була в ній востаннє",
                isOn: $model.remembersAppLayouts
            )
            SwitchRow(title: "Показувати розкладку біля курсора", detail: "UA / EN на мить, коли Lad перемикає", isOn: $model.showsLayoutHint)
            SwitchRow(title: "Звук при виправленні", detail: nil, isOn: $model.playsSound)
            SwitchRow(title: "Запускати разом із macOS", detail: nil, isOn: $model.launchesAtLogin)
            if model.loginNeedsApproval {
                Button("Підтвердь автозапуск у Login Items…", action: model.openLoginItems)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
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
                title: "Завжди виправляти", words: model.learnedWords,
                note: "Слова, які ти виправив подвійним Shift, Lad далі виправляє сам.",
                remove: model.removeLearnedWord, clear: model.clearLearnedWords
            )
            WordList(
                title: "Винятки", words: model.exceptions,
                note: "Слова, які ти скасував подвійним Shift, Lad більше не виправляє.",
                remove: model.removeException, clear: model.clearExceptions
            )
        }
    }

    private var footer: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Lad \(model.version)").font(.caption)
                Text("Без мережі. Набране не зберігається, крім твоїх винятків.")
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

/// A collapsible list of words with a remove button each and a "forget all" link.
private struct WordList: View {
    let title: String
    let words: [String]
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
                            RemovableRow(title: word) { remove(word) }
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

private struct RemovableRow: View {
    let title: String
    let remove: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Прибрати")
        }
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
