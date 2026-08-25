import SwiftUI

struct TermiPadMenuCommands: Commands {
    @AppStorage("TermiPad.language") private var languageRawValue = AppLanguage.simplifiedChinese.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .simplifiedChinese
    }

    var body: some Commands {
        CommandMenu(AppCopy.text("toolsMenu", language: language)) {
            Button(AppCopy.text("openLibrary", language: language)) {
                TermiPadAppAction.openLibrary.send()
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button(AppCopy.text("showFavorites", language: language)) {
                TermiPadAppAction.showFavorites.send()
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button(AppCopy.text("showRecent", language: language)) {
                TermiPadAppAction.showRecent.send()
            }
            .keyboardShortcut("3", modifiers: [.command])

            Divider()

            Button(AppCopy.text("discover", language: language)) {
                TermiPadAppAction.discoverTools.send()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button(AppCopy.text("addTool", language: language)) {
                TermiPadAppAction.addManualTool.send()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }
}

struct TermiPadMenuBarExtra: Scene {
    @AppStorage("TermiPad.language") private var languageRawValue = AppLanguage.simplifiedChinese.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .simplifiedChinese
    }

    var body: some Scene {
        MenuBarExtra("TermiPad", systemImage: "terminal") {
            Button(AppCopy.text("openLibrary", language: language)) {
                TermiPadAppAction.openLibrary.send()
            }
            Button(AppCopy.text("showFavorites", language: language)) {
                TermiPadAppAction.showFavorites.send()
            }
            Button(AppCopy.text("showRecent", language: language)) {
                TermiPadAppAction.showRecent.send()
            }

            Divider()

            Button(AppCopy.text("discover", language: language)) {
                TermiPadAppAction.discoverTools.send()
            }
            Button(AppCopy.text("addTool", language: language)) {
                TermiPadAppAction.addManualTool.send()
            }

            Divider()

            SettingsLink {
                Label(AppCopy.text("settings", language: language), systemImage: "gearshape")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
