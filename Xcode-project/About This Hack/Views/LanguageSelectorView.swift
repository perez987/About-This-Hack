//
//  LanguageSelectorView.swift
//  About This Hack
//
//  Language selector view with flag emojis (English, Spanish, French, Italian, Russian).
//

import SwiftUI

struct LanguageItem: Identifiable {
    let id: String
    let code: String
    let name: String
    let flag: String

    init(code: String, name: String, flag: String) {
        id = code
        self.code = code
        self.name = name
        self.flag = flag
    }
}

struct LanguageSelectorView: View {
    var onDismiss: () -> Void
    @State private var selectedLanguage: String
    @State private var showRestartAlert = false
    private let initialLanguage: String

    /// Available languages
    private let languages: [LanguageItem] = [
        LanguageItem(code: "en", name: "English", flag: "🇬🇧"),
        LanguageItem(code: "es", name: "Español", flag: "🇪🇸"),
        LanguageItem(code: "fr", name: "Français", flag: "🇫🇷"),
        LanguageItem(code: "de", name: "Deutsch", flag: "🇩🇪"),
        LanguageItem(code: "it", name: "Italiano", flag: "🇮🇹"),
        LanguageItem(code: "ru", name: "Russian", flag: "🇷🇺"),
    ]

    private var hasLanguageChanged: Bool {
        selectedLanguage != initialLanguage
    }

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        // Load current language preference from UserDefaults
        let currentLang = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?
            .first?.components(separatedBy: "-").first
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"
        _selectedLanguage = State(initialValue: currentLang)
        initialLanguage = currentLang
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(NSLocalizedString("Language selector title", comment: "Language selector title"))
                .font(.title2)
                .padding(.top)

            // Replaced List with ScrollView + ForEach for functional bindings
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(languages) { language in
                        HStack {
                            Text(language.flag)
                                .font(.title2)
                            Text(language.name)
                                .font(.body)
                            Spacer()
                            if selectedLanguage == language.code {
                                Text("◁              ")
                                    .foregroundColor(Color.blue)
                                Capsule()
                                    .frame(width: 5, height: 18)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selectedLanguage == language.code ? Color.accentColor.opacity(0.03) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedLanguage = language.code
                        }
                    }
                }
            }
            .frame(width: 210, height: 192)
            .border(Color.gray.opacity(0.1), width: 0.1)

            HStack(spacing: 11) {
                Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(NSLocalizedString("OK", comment: "OK button")) {
                    if hasLanguageChanged {
                        saveLanguagePreference()
                        showRestartAlert = true
                    } else {
                        onDismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            Spacer()
//            .padding(.bottom)
        }
        .padding()
        .frame(width: 240, height: 320)
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .all)
        .alert(
            NSLocalizedString("Language changed alert title", comment: "Language changed alert title"),
            isPresented: $showRestartAlert
        ) {
            Button(NSLocalizedString("OK", comment: "OK button")) {
                onDismiss()
            }
        } message: {
            Text(NSLocalizedString("Language changed message", comment: "Language changed message"))
        }
    }

    private func saveLanguagePreference() {
        UserDefaults.standard.set([selectedLanguage], forKey: "AppleLanguages")
        switch selectedLanguage {
        case "en-US", "en":
            print("Language changed to English (\(selectedLanguage))")
        case "es-ES", "es":
            print("Language changed to Spanish (\(selectedLanguage))")
        case "fr-FR", "fr":
            print("Language changed to French (\(selectedLanguage))")
        case "de-DE", "de":
            print("Language changed to German (\(selectedLanguage))")
        case "it-IT", "it":
            print("Language changed to Italian (\(selectedLanguage))")
        case "ru-RU", "ru":
            print("Language changed to Russian(\(selectedLanguage))")
        default:
            print("Language changed to code \(selectedLanguage)")
        }
    }
}
