import SwiftUI

/// Banner shown when an update is available, linking to GitHub releases
struct UpdateBannerView: View {
    let version: String
    @Binding var isPresented: Bool
    var onDownload: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(SynapseTheme.accent)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Update available: v\(version)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                Text("Download the latest version from GitHub")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                onDownload()
            }) {
                Text("Download")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(SynapseTheme.accent)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            
            Button(action: {
                withAnimation {
                    isPresented = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 2)
        )
        .padding()
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

#Preview {
    UpdateBannerView(
        version: "1.1.0",
        isPresented: .constant(true),
        onDownload: {}
    )
    .frame(width: 500)
    .preferredColorScheme(.dark)
}
