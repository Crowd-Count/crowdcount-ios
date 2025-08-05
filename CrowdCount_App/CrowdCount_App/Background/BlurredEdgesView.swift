import UIKit

class BlurredEdgesView: UIView {
    private let edgeColor: UIColor
    private let edgeThickness: CGFloat
    
    init(edgeColor: UIColor, edgeThickness: CGFloat) {
        self.edgeColor = edgeColor
        self.edgeThickness = edgeThickness
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        // Create and add edge views with the specified color
        addEdgeView(position: .top)
        addEdgeView(position: .bottom)
        addEdgeView(position: .left)
        addEdgeView(position: .right)
    }
    
    private func addEdgeView(position: EdgePosition) {
        let edgeView = UIView()
        edgeView.backgroundColor = edgeColor
        edgeView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(edgeView)
        
        switch position {
        case .top:
            NSLayoutConstraint.activate([
                edgeView.topAnchor.constraint(equalTo: topAnchor),
                edgeView.leadingAnchor.constraint(equalTo: leadingAnchor),
                edgeView.trailingAnchor.constraint(equalTo: trailingAnchor),
                edgeView.heightAnchor.constraint(equalToConstant: edgeThickness)
            ])
        case .bottom:
            NSLayoutConstraint.activate([
                edgeView.bottomAnchor.constraint(equalTo: bottomAnchor),
                edgeView.leadingAnchor.constraint(equalTo: leadingAnchor),
                edgeView.trailingAnchor.constraint(equalTo: trailingAnchor),
                edgeView.heightAnchor.constraint(equalToConstant: edgeThickness)
            ])
        case .left:
            NSLayoutConstraint.activate([
                edgeView.topAnchor.constraint(equalTo: topAnchor),
                edgeView.bottomAnchor.constraint(equalTo: bottomAnchor),
                edgeView.leadingAnchor.constraint(equalTo: leadingAnchor),
                edgeView.widthAnchor.constraint(equalToConstant: edgeThickness)
            ])
        case .right:
            NSLayoutConstraint.activate([
                edgeView.topAnchor.constraint(equalTo: topAnchor),
                edgeView.bottomAnchor.constraint(equalTo: bottomAnchor),
                edgeView.trailingAnchor.constraint(equalTo: trailingAnchor),
                edgeView.widthAnchor.constraint(equalToConstant: edgeThickness)
            ])
        }
    }
    
    private enum EdgePosition {
        case top, bottom, left, right
    }
}
