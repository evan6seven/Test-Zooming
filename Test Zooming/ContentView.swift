//
//  ContentView.swift
//  Test Zooming
//
//  Created by mainuser on 2/16/26.
//

import SwiftUI

struct TwoFingerDragModifier: ViewModifier {
    @Binding var offset: CGFloat
    @Binding var lastOffset: CGFloat
    var isEnabled: Bool
    var maxOffset: CGFloat

    func body(content: Content) -> some View {
        content.overlay(
            TwoFingerDragView(offset: $offset, lastOffset: $lastOffset, isEnabled: isEnabled, maxOffset: maxOffset)
        )
    }
}

struct TwoFingerDragView: UIViewRepresentable {
    @Binding var offset: CGFloat
    @Binding var lastOffset: CGFloat
    var isEnabled: Bool
    var maxOffset: CGFloat

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.offset = $offset
        context.coordinator.lastOffset = $lastOffset
        context.coordinator.maxOffset = maxOffset
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(offset: $offset, lastOffset: $lastOffset, isEnabled: isEnabled, maxOffset: maxOffset)
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var offset: Binding<CGFloat>
        var lastOffset: Binding<CGFloat>
        var isEnabled: Bool
        var maxOffset: CGFloat

        init(offset: Binding<CGFloat>, lastOffset: Binding<CGFloat>, isEnabled: Bool, maxOffset: CGFloat) {
            self.offset = offset
            self.lastOffset = lastOffset
            self.isEnabled = isEnabled
            self.maxOffset = maxOffset
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard isEnabled else { return }
            let translation = gesture.translation(in: gesture.view)
            switch gesture.state {
            case .changed:
                offset.wrappedValue = lastOffset.wrappedValue + translation.x
            case .ended, .cancelled:
                let clamped = min(max(offset.wrappedValue, -maxOffset), maxOffset)
                offset.wrappedValue = clamped
                lastOffset.wrappedValue = clamped
            default:
                break
            }
        }
    }
}

struct ContentView: View {
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGFloat = 0
    @State private var lastOffset: CGFloat = 0

    private let baseHeight: CGFloat = 150
    private var stackWidth: CGFloat { UIScreen.main.bounds.width - 32 }
    private var maxOffset: CGFloat { stackWidth * (scale - 1) / 2 }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Top block
                RoundedRectangle(cornerRadius: 16)
                    .fill(.blue)
                    .frame(height: baseHeight)
                    .overlay(Text("Top Block").foregroundStyle(.white).font(.title2))

                // Middle block — pinch to zoom
                // Color.clear reserves layout height; overlay draws the scaled block on top
                Color.clear
                    .frame(height: baseHeight * scale)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.green)
                            .frame(
                                width: stackWidth * scale,
                                height: baseHeight * scale
                            )
                            .overlay(
                                Text("Pinch to Zoom")
                                    .foregroundStyle(.white)
                                    .font(.system(size: 22 * scale))
                            )
                            .offset(x: offset)
                    )
                    .modifier(TwoFingerDragModifier(offset: $offset, lastOffset: $lastOffset, isEnabled: scale > 1, maxOffset: maxOffset))
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = max(1, lastScale * value.magnification)
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale <= 1 {
                                    offset = 0
                                    lastOffset = 0
                                } else {
                                    let clamped = min(max(offset, -maxOffset), maxOffset)
                                    offset = clamped
                                    lastOffset = clamped
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.interactiveSpring()) {
                            scale = 1.0
                            lastScale = 1.0
                            offset = 0
                            lastOffset = 0
                        }
                    }

                // Bottom block
                RoundedRectangle(cornerRadius: 16)
                    .fill(.orange)
                    .frame(height: baseHeight)
                    .overlay(Text("Bottom Block").foregroundStyle(.white).font(.title2))
            }
            .padding()
            .animation(.interactiveSpring(), value: scale)
            .animation(.interactiveSpring(), value: offset)
        }
    }
}

#Preview {
    ContentView()
}
