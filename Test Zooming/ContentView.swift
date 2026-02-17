//
//  ContentView.swift
//  Test Zooming
//
//  Created by mainuser on 2/16/26.
//

import SwiftUI
import WebKit

struct ScaledWebView: UIViewRepresentable {
    let url: URL
    let baseWidth: CGFloat
    var scale: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.scrollView.panGestureRecognizer.isEnabled = false
        for gesture in webView.gestureRecognizers ?? [] {
            gesture.isEnabled = false
        }
        webView.isUserInteractionEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        context.coordinator.baseWidth = baseWidth
        context.coordinator.currentScale = max(scale, 1)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.baseWidth = baseWidth
        context.coordinator.updateScale(scale, in: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(baseWidth: baseWidth)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var baseWidth: CGFloat
        var currentScale: CGFloat = 1
        private var hasLoadedPage = false

        init(baseWidth: CGFloat) {
            self.baseWidth = baseWidth
        }

        func updateScale(_ scale: CGFloat, in webView: WKWebView) {
            currentScale = max(scale, 1)
            guard hasLoadedPage else { return }
            applyTransformScaleCSS(in: webView, scale: currentScale)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            hasLoadedPage = true
            let width = Int(baseWidth)
            let js = """
            (function() {
                var meta = document.querySelector('meta[name=viewport]');
                if (!meta) {
                    meta = document.createElement('meta');
                    meta.name = 'viewport';
                    document.head.appendChild(meta);
                }
                meta.content = 'width=\(width), initial-scale=1.0, maximum-scale=1.0, user-scalable=no';

                var style = document.getElementById('codex-transform-scale-style');
                if (!style) {
                    style = document.createElement('style');
                    style.id = 'codex-transform-scale-style';
                    style.textContent = `
                    :root { --codex-scale: 1; }
                    html, body {
                        overflow: hidden !important;
                    }
                    body {
                        transform-origin: top left !important;
                        transform: scale(var(--codex-scale)) !important;
                        width: calc(100% / var(--codex-scale)) !important;
                        min-height: calc(100% / var(--codex-scale)) !important;
                    }
                    `;
                    document.head.appendChild(style);
                }
            })();
            """
            webView.evaluateJavaScript(js)
            applyTransformScaleCSS(in: webView, scale: currentScale)
        }

        private func applyTransformScaleCSS(in webView: WKWebView, scale: CGFloat) {
            let clampedScale = max(scale, 1)
            let js = "document.documentElement.style.setProperty('--codex-scale', '\(clampedScale)');"
            webView.evaluateJavaScript(js)
        }
    }
}

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
                    .border(.red, width: 2) // red = top block

                // Middle block — pinch to zoom web view
                // Color.clear reserves layout height; overlay draws the scaled block on top
                Color.clear
                    .frame(height: baseHeight * scale)
                    .border(.yellow, width: 2) // yellow = Color.clear layout spacer
                    .overlay(
                        ScaledWebView(url: URL(string: "https://google.com")!, baseWidth: stackWidth, scale: scale)
                            .frame(
                                width: stackWidth * scale,
                                height: baseHeight * scale
                            )
                            .border(.green, width: 2) // green = scaled web view frame
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .offset(x: offset)
                    )
                    .border(.purple, width: 2) // purple = middle block after overlay
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
                    .border(.cyan, width: 2) // cyan = bottom block
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
