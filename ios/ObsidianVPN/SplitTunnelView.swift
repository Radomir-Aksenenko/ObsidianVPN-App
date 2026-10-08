import SwiftUI
import UIKit

/// Экран раздельного туннелирования для одного профиля.
/// Правки сохраняются сразу. Если VPN уже подключен для этого профиля, правила применяются без переподключения.
struct SplitTunnelView: View {
    let profileID: VPNProfile.ID
    var showsDone = false

    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var tunnel: TunnelController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("settings.haptics", store: UserDefaults(suiteName: "group.com.obsidian.vpn")) private var haptics = true

    @State private var draft = ""
    @State private var issues: [SplitRuleIssue] = []

    private var profile: VPNProfile? {
        profiles.profiles.first { $0.id == profileID }
    }

    private var config: SplitTunnelConfig {
        profile?.effectiveSplit ?? SplitTunnelConfig()
    }

    var body: some View {
        ZStack {
            MineralBackground()

            if profile != nil {
                Form {
                    modeSection
                    presetsSection
                    entriesSection
                    limitsSection
                }
                .scrollContentBackground(.hidden)
            } else {
                Text("Сервер не найден")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(ObsidianTheme.secondaryText)
            }
        }
        .navigationTitle("Раздельное туннелирование")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                        .tint(ObsidianTheme.accent)
                }
            }
        }
    }

    // MARK: - Sections

    private var modeSection: some View {
        Section {
            Picker("Режим", selection: modeBinding) {
                Text("Выкл").tag(SplitTunnelMode.off)
                Text("Только список").tag(SplitTunnelMode.include)
                Text("Кроме списка").tag(SplitTunnelMode.exclude)
            }
            .pickerStyle(.segmented)
            .listRowBackground(glassRowBackground)

            VStack(alignment: .leading, spacing: 6) {
                Text(modeDescription(config.mode))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(ObsidianTheme.secondaryText)

                if config.mode == .include && config.rules.isEmpty {
                    Label("Список пуст: через VPN сейчас ничего не идет.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(ObsidianTheme.amber)
                }

                Text(tunnel.state == .connected
                     ? "Подключение активно: изменения применятся сразу."
                     : "Изменения применятся при следующем подключении.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(ObsidianTheme.tertiaryText)
            }
            .listRowBackground(glassRowBackground)
        } header: {
            Text("Режим")
        }
    }

    private var presetsSection: some View {
        Section {
            ForEach(SplitPreset.allCases) { preset in
                Toggle(isOn: presetBinding(preset)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(SplitPresets.title(for: preset))
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundStyle(ObsidianTheme.primaryText)
                        Text(SplitPresets.subtitle(for: preset))
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(ObsidianTheme.secondaryText)
                    }
                }
                .tint(ObsidianTheme.accent)
                .listRowBackground(glassRowBackground)
            }
        } header: {
            Text("Готовые наборы")
        } footer: {
            Text("Наборы добавляют свои адреса к вашему списку. Для режима «Кроме списка» удобны российские сервисы и локальная сеть.")
        }
    }

    private var entriesSection: some View {
        Section {
            ForEach(config.entries.indices, id: \.self) { index in
                Text(config.entries[index])
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(ObsidianTheme.primaryText)
                    .listRowBackground(glassRowBackground)
            }
            .onDelete(perform: deleteEntries)

            if config.entries.isEmpty {
                Text("Список пуст")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(ObsidianTheme.tertiaryText)
                    .listRowBackground(glassRowBackground)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("example.com или 10.0.0.0/8", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .accessibilityLabel("Новое правило")

                Button {
                    addDraft()
                } label: {
                    Label("Добавить", systemImage: "plus.circle.fill")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .tint(ObsidianTheme.accent)

                ForEach(issues.indices, id: \.self) { index in
                    Label(issues[index].reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(ObsidianTheme.danger)
                }
            }
            .listRowBackground(glassRowBackground)
        } header: {
            Text("Свои сайты и адреса")
        } footer: {
            Text("По одной записи в строке. Можно вставить сразу несколько: через пробел или запятую. Смахните строку, чтобы удалить.")
        }
    }

    private var limitsSection: some View {
        Section {
            Label {
                Text("iOS не разрешает делить трафик по приложениям, поэтому правила работают по сайтам и IP-адресам.")
            } icon: {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(ObsidianTheme.accentCyan)
            }
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(ObsidianTheme.secondaryText)
            .listRowBackground(glassRowBackground)

            VStack(alignment: .leading, spacing: 8) {
                Text("Сайты переводятся в адреса при подключении и обновляются каждые 10 минут. CDN может менять адреса чаще, поэтому часть трафика иногда пойдет не тем путем.")
                Text("Зоны вроде *.ru не поддерживаются: добавляйте сайты по одному. Кириллические домены пока не работают, используйте вариант xn--.")
                Text("IPv6 тоже идет через туннель, если не выбран режим «Только список». Пока ядро не поддерживает IPv6, такие соединения сразу переходят на IPv4.")
            }
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(ObsidianTheme.tertiaryText)
            .listRowBackground(glassRowBackground)
        } header: {
            Text("Ограничения")
        }
    }

    private var glassRowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial.opacity(0.65))
    }

    // MARK: - Bindings and edits

    private var modeBinding: Binding<SplitTunnelMode> {
        Binding(
            get: { config.mode },
            set: { newMode in
                triggerHaptic()
                update { $0.mode = newMode }
            }
        )
    }

    private func presetBinding(_ preset: SplitPreset) -> Binding<Bool> {
        Binding(
            get: { config.presets.contains(preset) },
            set: { isOn in
                triggerHaptic()
                update { cfg in
                    if isOn {
                        cfg.presets.insert(preset)
                    } else {
                        cfg.presets.remove(preset)
                    }
                }
            }
        )
    }

    private func deleteEntries(at offsets: IndexSet) {
        update { $0.entries.remove(atOffsets: offsets) }
    }

    private func addDraft() {
        let tokens = draft
            .components(separatedBy: CharacterSet(charactersIn: ",;\n\r\t "))
            .filter { !$0.isEmpty }
        let result = SplitTunnelConfig.canonicalize(tokens)
        let existing = config.entries
        let fresh = result.accepted.filter { !existing.contains($0) }

        if !fresh.isEmpty {
            update { $0.entries.append(contentsOf: fresh) }
            triggerHaptic()
        }

        issues = result.issues
        // Неверные строки остаются в поле, чтобы их можно было поправить.
        draft = result.issues.map { $0.input }.joined(separator: "\n")
    }

    /// Меняет правила профиля, сохраняет и при подключенном туннеле отправляет их в extension.
    private func update(_ change: (inout SplitTunnelConfig) -> Void) {
        guard var updated = profiles.profiles.first(where: { $0.id == profileID }) else { return }
        var cfg = updated.effectiveSplit
        change(&cfg)
        updated.splitTunnel = cfg
        profiles.update(updated)
        tunnel.splitTunnelDidChange(updated)
    }

    private func modeDescription(_ mode: SplitTunnelMode) -> String {
        switch mode {
        case .off:
            return "Раздельное туннелирование выключено: весь трафик идет через VPN."
        case .include:
            return "Через VPN идут только сайты и адреса из списка. Остальной трафик открывается напрямую."
        case .exclude:
            return "Сайты и адреса из списка открываются напрямую. Весь остальной трафик идет через VPN."
        }
    }

    private func triggerHaptic() {
        guard haptics else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
}

/// Цель перехода из настроек и с главного экрана: открывает правила текущего сервера.
/// Условие вынесено в body, чтобы не полагаться на if/else внутри замыканий NavigationLink и sheet.
struct SplitTunnelSettingsDestination: View {
    var showsDone = false

    @EnvironmentObject private var profiles: ProfileStore

    var body: some View {
        if let profileID = profiles.selectedProfile?.id {
            SplitTunnelView(profileID: profileID, showsDone: showsDone)
        } else {
            Text("Сначала добавьте сервер")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(ObsidianTheme.secondaryText)
        }
    }
}

// MARK: - Shared copy for the Settings row and the Home chip

/// Подпись текущих правил: «Выключено» или режим с количеством.
func splitSummaryText(for profile: VPNProfile?) -> String {
    let split = profile?.effectiveSplit ?? SplitTunnelConfig()
    switch split.mode {
    case .off:
        return "Выключено"
    case .include:
        return "Только список: \(splitRulesPhrase(split.itemCount))"
    case .exclude:
        return "Кроме списка: \(splitRulesPhrase(split.itemCount))"
    }
}

/// Короткая подпись для кнопки на главном экране: «Сплит: 3 правила».
func splitChipText(for profile: VPNProfile?) -> String {
    let split = profile?.effectiveSplit ?? SplitTunnelConfig()
    if split.mode == .off {
        return "Сплит: выкл"
    }
    if split.itemCount == 0 {
        return "Сплит: нет правил"
    }
    return "Сплит: \(splitRulesPhrase(split.itemCount))"
}

/// Русское склонение: «1 правило», «2 правила», «5 правил».
func splitRulesPhrase(_ count: Int) -> String {
    let lastDigit = count % 10
    let lastTwo = count % 100
    let word: String
    if lastDigit == 1 && lastTwo != 11 {
        word = "правило"
    } else if (2...4).contains(lastDigit) && !(12...14).contains(lastTwo) {
        word = "правила"
    } else {
        word = "правил"
    }
    return "\(count) \(word)"
}
