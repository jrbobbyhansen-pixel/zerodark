import Foundation
import SwiftUI

// MARK: - Report Template Model

struct ReportTemplate: Identifiable, Codable {
    let id: UUID
    var title: String
    var content: String
    var isStandard: Bool
}

// MARK: - Report Template Manager

class ReportTemplateManager: ObservableObject {
    @Published var templates: [ReportTemplate] = []
    
    init() {
        loadTemplates()
    }
    
    func addTemplate(_ template: ReportTemplate) {
        templates.append(template)
        saveTemplates()
    }
    
    func editTemplate(_ template: ReportTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
            saveTemplates()
        }
    }
    
    func deleteTemplate(_ template: ReportTemplate) {
        templates.removeAll { $0.id == template.id }
        saveTemplates()
    }
    
    private func loadTemplates() {
        if let data = UserDefaults.standard.data(forKey: "ReportTemplates"),
           let decodedTemplates = try? JSONDecoder().decode([ReportTemplate].self, from: data) {
            templates = decodedTemplates
        }
    }
    
    private func saveTemplates() {
        if let encodedTemplates = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(encodedTemplates, forKey: "ReportTemplates")
        }
    }
}

// MARK: - Report Template View Model

class ReportTemplateViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var content: String = ""
    @Published var isStandard: Bool = false
    
    func saveTemplate(_ manager: ReportTemplateManager) {
        let template = ReportTemplate(id: UUID(), title: title, content: content, isStandard: isStandard)
        manager.addTemplate(template)
    }
    
    func updateTemplate(_ template: ReportTemplate, _ manager: ReportTemplateManager) {
        let updatedTemplate = ReportTemplate(id: template.id, title: title, content: content, isStandard: isStandard)
        manager.editTemplate(updatedTemplate)
    }
}

// MARK: - Report Template View

struct ReportTemplateView: View {
    @StateObject private var viewModel = ReportTemplateViewModel()
    @EnvironmentObject private var templateManager: ReportTemplateManager
    @State private var isEditing = false
    @State private var selectedTemplate: ReportTemplate?
    
    var body: some View {
        NavigationView {
            List {
                ForEach(templateManager.templates) { template in
                    VStack(alignment: .leading) {
                        Text(template.title)
                            .font(.headline)
                        Text(template.content)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .onTapGesture {
                        selectedTemplate = template
                        isEditing = true
                        viewModel.title = template.title
                        viewModel.content = template.content
                        viewModel.isStandard = template.isStandard
                    }
                }
                .onDelete { indexSet in
                    if let index = indexSet.first {
                        templateManager.deleteTemplate(templateManager.templates[index])
                    }
                }
            }
            .navigationTitle("Report Templates")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        isEditing = false
                        viewModel.title = ""
                        viewModel.content = ""
                        viewModel.isStandard = false
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isEditing) {
                EditReportTemplateView(viewModel: viewModel, isEditing: $isEditing, selectedTemplate: $selectedTemplate)
            }
        }
    }
}

// MARK: - Edit Report Template View

struct EditReportTemplateView: View {
    @ObservedObject var viewModel: ReportTemplateViewModel
    @Binding var isEditing: Bool
    @Binding var selectedTemplate: ReportTemplate?
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Template Details")) {
                    TextField("Title", text: $viewModel.title)
                    TextEditor(text: $viewModel.content)
                    Toggle("Standard Template", isOn: $viewModel.isStandard)
                }
            }
            .navigationTitle(isEditing ? "Edit Template" : "New Template")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isEditing = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if let template = selectedTemplate {
                            viewModel.updateTemplate(template, Environment(\.managedObjectContext).wrappedValue)
                        } else {
                            viewModel.saveTemplate(Environment(\.managedObjectContext).wrappedValue)
                        }
                        isEditing = false
                    }
                }
            }
        }
    }
}