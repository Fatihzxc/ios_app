import SwiftUI

struct BootstrapView: View {
    var body: some View {
        VStack {
            Text("bootstrap.ready")
                .font(.title2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .accessibilityIdentifier("bootstrap.root")
    }
}
