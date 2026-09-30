import Foundation

/// A named placeholder (e.g. `{date}`) that can appear in a naming template's format string.
struct TemplateVariable: Identifiable, Codable, Hashable {
    var key: String
    var label: String
    /// Shown as help text for built-ins; sent to the AI verbatim as the field description for custom variables.
    var description: String
    var isBuiltIn: Bool

    var id: String { key }
    var token: String { "{\(key)}" }
}

/// A user-saved naming convention: a display name plus a format string built from variable tokens.
struct NamingTemplate: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var format: String
}

/// Sample values used to render a preview of what a template's format would produce.
let sampleVariableValues: [String: String] = [
    "date": "2025.08.06", "initials": "JW", "amount": "$48.44", "provider": "Quest Diagnostics",
]

/// Renders an example filename for a format string, substituting sample values for built-in
/// variables and a placeholder for any custom variables.
func renderedExample(format: String, customVariables: [TemplateVariable] = []) -> String {
    var result = format
    for (key, value) in sampleVariableValues {
        result = result.replacingOccurrences(of: "{\(key)}", with: value)
    }
    for variable in customVariables {
        result = result.replacingOccurrences(of: variable.token, with: "…")
    }
    return result
}

/// Persists naming templates and custom variables, and tracks which template is active.
final class TemplateStore: ObservableObject {
    @Published var templates: [NamingTemplate] {
        didSet { save() }
    }
    @Published var selectedTemplateID: NamingTemplate.ID {
        didSet { save() }
    }
    @Published var customVariables: [TemplateVariable] {
        didSet { save() }
    }

    static let builtInVariables: [TemplateVariable] = [
        TemplateVariable(
            key: "date", label: "Date",
            description:
                "Date of service, or the payment date if there's no service date. Formatted YYYY.MM.DD.",
            isBuiltIn: true),
        TemplateVariable(
            key: "initials", label: "Initials",
            description:
                "The patient's (or guarantor's) first and last initial, e.g. \"WALDECK, JAN\" \u{2192} JW.",
            isBuiltIn: true),
        TemplateVariable(
            key: "amount", label: "Amount",
            description: "The amount actually paid, formatted like $41.00.",
            isBuiltIn: true),
        TemplateVariable(
            key: "provider", label: "Provider",
            description: "Short name of the doctor, clinic, lab, hospital, or pharmacy.",
            isBuiltIn: true),
    ]

    static let defaultTemplate = NamingTemplate(
        name: "Default", format: "{date} - {initials} - {amount} - {provider}")

    var allVariables: [TemplateVariable] { Self.builtInVariables + customVariables }

    var selectedTemplate: NamingTemplate {
        templates.first { $0.id == selectedTemplateID } ?? Self.defaultTemplate
    }

    private let userDefaults: UserDefaults
    private static let templatesKey = "TemplateStore.templates"
    private static let selectedTemplateIDKey = "TemplateStore.selectedTemplateID"
    private static let customVariablesKey = "TemplateStore.customVariables"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let decoder = JSONDecoder()
        let savedTemplates =
            userDefaults.data(forKey: Self.templatesKey)
            .flatMap { try? decoder.decode([NamingTemplate].self, from: $0) }
        let savedVariables =
            userDefaults.data(forKey: Self.customVariablesKey)
            .flatMap { try? decoder.decode([TemplateVariable].self, from: $0) }

        let templates = (savedTemplates?.isEmpty == false) ? savedTemplates! : [Self.defaultTemplate]
        self.templates = templates
        self.customVariables = savedVariables ?? []

        if let savedIDString = userDefaults.string(forKey: Self.selectedTemplateIDKey),
            let savedID = UUID(uuidString: savedIDString),
            templates.contains(where: { $0.id == savedID })
        {
            self.selectedTemplateID = savedID
        } else {
            self.selectedTemplateID = templates[0].id
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(templates) {
            userDefaults.set(data, forKey: Self.templatesKey)
        }
        if let data = try? encoder.encode(customVariables) {
            userDefaults.set(data, forKey: Self.customVariablesKey)
        }
        userDefaults.set(selectedTemplateID.uuidString, forKey: Self.selectedTemplateIDKey)
    }
}
