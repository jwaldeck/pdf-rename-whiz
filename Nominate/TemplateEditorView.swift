import SwiftUI

struct TemplateEditorView: View {
    @ObservedObject var store: TemplateStore
    @Environment(\.dismiss) private var dismiss

    @State private var editingTemplateID: NamingTemplate.ID?
    @State private var newVariableKey = ""
    @State private var newVariableDescription = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Naming Templates").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                templateList
                    .frame(width: 190)

                Divider()

                ScrollView {
                    templateEditor
                        .padding(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 520, idealHeight: 560)
        .onAppear { editingTemplateID = store.selectedTemplateID }
    }

    private var templateList: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.templates) { template in
                        Button {
                            editingTemplateID = template.id
                        } label: {
                            Text(template.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    editingTemplateID == template.id ? Color.accentColor : Color.clear
                                )
                                .foregroundColor(editingTemplateID == template.id ? .white : .primary)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }

            Divider()

            HStack(spacing: 12) {
                Button(action: addTemplate) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                }
                Button(action: deleteSelectedTemplate) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18))
                }
                .disabled(store.templates.count <= 1 || editingTemplateID == nil)
                Spacer()
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .padding(12)
        }
    }

    private var selectedTemplateBinding: Binding<NamingTemplate>? {
        guard let id = editingTemplateID, store.templates.contains(where: { $0.id == id }) else {
            return nil
        }
        return Binding(
            get: { store.templates.first(where: { $0.id == id }) ?? TemplateStore.defaultTemplate },
            set: { newValue in
                if let index = store.templates.firstIndex(where: { $0.id == id }) {
                    store.templates[index] = newValue
                }
            }
        )
    }

    @ViewBuilder
    private var templateEditor: some View {
        if let binding = selectedTemplateBinding {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    labeledField("Name", text: binding.name)
                    labeledField("Format", text: binding.format, monospaced: true)
                    Text(
                        "Preview: "
                            + renderedExample(
                                format: binding.wrappedValue.format, customVariables: store.customVariables)
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Available variables").font(.headline)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], alignment: .leading,
                        spacing: 6
                    ) {
                        ForEach(store.allVariables) { variable in
                            Button(variable.token) {
                                binding.wrappedValue.format += variable.token
                            }
                            .buttonStyle(.plain)
                            .font(.system(.callout, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                            .help(variable.description)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Add a custom variable").font(.headline)
                    labeledField("Key", text: $newVariableKey, placeholder: "e.g. insurer")
                    labeledField(
                        "Description for the AI", text: $newVariableDescription,
                        placeholder: "e.g. Name of the insurance company")
                    Button("Add Variable", action: addCustomVariable)
                        .disabled(
                            newVariableKey.trimmingCharacters(in: .whitespaces).isEmpty
                                || newVariableDescription.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if !store.customVariables.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your custom variables").font(.headline)
                        ForEach(store.customVariables) { variable in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(variable.label).bold()
                                    Text(variable.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button {
                                    store.customVariables.removeAll { $0.id == variable.id }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Select a template")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func labeledField(
        _ label: String, text: Binding<String>, placeholder: String = "", monospaced: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundColor(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
        }
    }

    private func addTemplate() {
        let new = NamingTemplate(name: "New Template", format: "{date} - {provider}")
        store.templates.append(new)
        editingTemplateID = new.id
    }

    private func deleteSelectedTemplate() {
        guard let id = editingTemplateID, store.templates.count > 1 else { return }
        store.templates.removeAll { $0.id == id }
        if store.selectedTemplateID == id {
            store.selectedTemplateID = store.templates[0].id
        }
        editingTemplateID = store.templates.first?.id
    }

    private func addCustomVariable() {
        let key =
            newVariableKey
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        let description = newVariableDescription.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !description.isEmpty, !store.allVariables.contains(where: { $0.key == key })
        else { return }

        store.customVariables.append(
            TemplateVariable(key: key, label: key.capitalized, description: description, isBuiltIn: false))
        newVariableKey = ""
        newVariableDescription = ""
    }
}
