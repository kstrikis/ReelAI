import SwiftUI

struct CustomTextField: View {
    // MARK: - Properties
    let placeholder: String
    @Binding var text: String
    let isSecure: Bool
    let keyboardType: UIKeyboardType
    let textContentType: UITextContentType?
    let autocapitalization: TextInputAutocapitalization

    // MARK: - Initialization
    init(
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool = false,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        autocapitalizeNone: Bool = false
    ) {
        self.placeholder = placeholder
        self._text = text
        self.isSecure = isSecure
        self.keyboardType = keyboardType
        self.textContentType = textContentType
        self.autocapitalization = autocapitalizeNone ? .never : .sentences
    }

    // MARK: - Body
    var body: some View {
        Group {
            if isSecure {
                SecureField("", text: $text, prompt: Text(placeholder)
                    .foregroundColor(.gray.opacity(0.7)))
            } else {
                TextField("", text: $text, prompt: Text(placeholder)
                    .foregroundColor(.gray.opacity(0.7)))
            }
        }
        .textInputAutocapitalization(autocapitalization)
        .keyboardType(keyboardType)
        .textContentType(textContentType)
        .padding()
        .background(Color.white)
        .cornerRadius(10)
        .foregroundColor(.black)
        .tint(.black)
    }
}

#if DEBUG
struct CustomTextField_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                CustomTextField(
                    placeholder: "Email",
                    text: .constant(""),
                    keyboardType: .emailAddress,
                    autocapitalizeNone: true
                )
                CustomTextField(
                    placeholder: "Password",
                    text: .constant(""),
                    isSecure: true,
                    autocapitalizeNone: true
                )
                CustomTextField(
                    placeholder: "With Text",
                    text: .constant("Hello World")
                )
            }
            .padding()
        }
    }
}
#endif
