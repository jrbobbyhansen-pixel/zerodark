import SwiftUI
import Foundation

// MARK: - FormField

enum FieldType: String, Codable {
    case text
    case number
    case date
    case location
}

struct FormField: Identifiable, Codable {
    let id = UUID()
    var label: String
    var type: FieldType
    var value: String = ""
    var isValid: Bool = true
    var validationMessage: String = ""
}

// MARK: - Form

struct Form: Identifiable, Codable {
    let id = UUID()
    var title: String
    var fields: [FormField]
}

// MARK: - FormViewModel

class FormViewModel: ObservableObject {
    @Published var form: Form
    @Published var isFormValid: Bool = false

    init(form: Form) {
        self.form = form
        self.isFormValid = form.fields.allSatisfy { $0.isValid }
    }

    func validateField(_ field: inout FormField) {
        field.isValid = true
        field.validationMessage = ""

        switch field.type {
        case .text:
            if field.value.isEmpty {
                field.isValid = false
                field.validationMessage = "This field is required."
            }
        case .number:
            if let number = Double(field.value), number < 0 {
                field.isValid = false
                field.validationMessage = "Number must be non-negative."
            }
        case .date:
            if field.value.isEmpty {
                field.isValid = false
                field.validationMessage = "This field is required."
            }
        case .location:
            if field.value.isEmpty {
                field.isValid = false
                field.validationMessage = "This field is required."
            }
        }

        isFormValid = form.fields.allSatisfy { $0.isValid }
    }

    func submitForm() {
        // Handle offline submission
        // Export to CSV/JSON
    }
}

// MARK: - FormView

struct FormView: View {
    @StateObject private var viewModel: FormViewModel

    init(form: Form) {
        _viewModel = StateObject(wrappedValue: FormViewModel(form: form))
    }

    var body: some View {
        VStack {
            Text(viewModel.form.title)
                .font(.largeTitle)
                .padding()

            ForEach($viewModel.form.fields) { $field in
                FormFieldView(field: $field, onValueChanged: { viewModel.validateField(&field) })
            }

            Button(action: {
                viewModel.submitForm()
            }) {
                Text("Submit")
                    .padding()
                    .background(viewModel.isFormValid ? Color.green : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(!viewModel.isFormValid)
        }
        .padding()
    }
}

// MARK: - FormFieldView

struct FormFieldView: View {
    @Binding var field: FormField
    let onValueChanged: (inout FormField) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Text(field.label)
                .font(.headline)

            switch field.type {
            case .text, .number, .date, .location:
                TextField("", text: $field.value) { _ in
                    onValueChanged(&field)
                }
                .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            if !field.isValid {
                Text(field.validationMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

struct FormView_Previews: PreviewProvider {
    static var previews: some View {
        FormView(form: Form(title: "Sample Form", fields: [
            FormField(label: "Name", type: .text),
            FormField(label: "Age", type: .number),
            FormField(label: "Date", type: .date),
            FormField(label: "Location", type: .location)
        ]))
    }
}