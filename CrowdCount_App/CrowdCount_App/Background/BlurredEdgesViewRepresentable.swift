import SwiftUI

struct BlurredEdgesViewRepresentable: UIViewRepresentable {
    let edgeColor: UIColor
    let edgeThickness: CGFloat
    
    func makeUIView(context: Context) -> UIView {
        return BlurredEdgesView(edgeColor: edgeColor, edgeThickness: edgeThickness)
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update the view if needed
    }
}
