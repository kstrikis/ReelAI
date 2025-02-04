import SwiftUI

/// Primary button style
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .shadow(radius: 3)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

/// Secondary button style
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.clear)
            .foregroundColor(.white)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

#if DEBUG
    struct Styles_Previews: PreviewProvider {
        static var previews: some View {
            VStack(spacing: 20) {
                Button("Primary Button") {}
                    .buttonStyle(PrimaryButtonStyle())

                Button("Secondary Button") {}
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding()
            .background(Color.black)
        }
    }
#endif
