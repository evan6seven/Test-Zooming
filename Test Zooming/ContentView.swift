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
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGFloat
    @Binding var lastOffset: CGFloat
    var isDragEnabled: Bool
    var maxOffset: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.scrollView.panGestureRecognizer.isEnabled = false

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.cancelsTouchesInView = false
        pan.delegate = context.coordinator
        pan.isEnabled = isDragEnabled
        webView.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.cancelsTouchesInView = false
        pinch.delegate = context.coordinator
        webView.addGestureRecognizer(pinch)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 1
        doubleTap.cancelsTouchesInView = false
        doubleTap.delegate = context.coordinator
        webView.addGestureRecognizer(doubleTap)

        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        context.coordinator.baseWidth = baseWidth
        context.coordinator.currentScale = max(scale, 1)
        context.coordinator.scale = $scale
        context.coordinator.lastScale = $lastScale
        context.coordinator.offset = $offset
        context.coordinator.lastOffset = $lastOffset
        context.coordinator.isDragEnabled = isDragEnabled
        context.coordinator.maxOffset = maxOffset
        context.coordinator.twoFingerPan = pan
        context.coordinator.pinch = pinch
        context.coordinator.doubleTap = doubleTap
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.baseWidth = baseWidth
        context.coordinator.scale = $scale
        context.coordinator.lastScale = $lastScale
        context.coordinator.offset = $offset
        context.coordinator.lastOffset = $lastOffset
        context.coordinator.isDragEnabled = isDragEnabled
        context.coordinator.maxOffset = maxOffset
        context.coordinator.twoFingerPan?.isEnabled = isDragEnabled
        context.coordinator.updateScale(scale, in: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            baseWidth: baseWidth,
            scale: $scale,
            lastScale: $lastScale,
            offset: $offset,
            lastOffset: $lastOffset,
            isDragEnabled: isDragEnabled,
            maxOffset: maxOffset
        )
    }

    class Coordinator: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate {
        var baseWidth: CGFloat
        var currentScale: CGFloat = 1
        private var hasLoadedPage = false
        var scale: Binding<CGFloat>
        var lastScale: Binding<CGFloat>
        var offset: Binding<CGFloat>
        var lastOffset: Binding<CGFloat>
        var isDragEnabled: Bool
        var maxOffset: CGFloat
        weak var twoFingerPan: UIPanGestureRecognizer?
        weak var pinch: UIPinchGestureRecognizer?
        weak var doubleTap: UITapGestureRecognizer?

        init(
            baseWidth: CGFloat,
            scale: Binding<CGFloat>,
            lastScale: Binding<CGFloat>,
            offset: Binding<CGFloat>,
            lastOffset: Binding<CGFloat>,
            isDragEnabled: Bool,
            maxOffset: CGFloat
        ) {
            self.baseWidth = baseWidth
            self.scale = scale
            self.lastScale = lastScale
            self.offset = offset
            self.lastOffset = lastOffset
            self.isDragEnabled = isDragEnabled
            self.maxOffset = maxOffset
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

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard isDragEnabled else { return }
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

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let webView = gesture.view as? WKWebView else { return }

            let newScale = max(1, lastScale.wrappedValue * gesture.scale)
            scale.wrappedValue = newScale
            currentScale = newScale
            applyTransformScaleCSS(in: webView, scale: newScale)

            if newScale <= 1 {
                isDragEnabled = false
                twoFingerPan?.isEnabled = false
                offset.wrappedValue = 0
                lastOffset.wrappedValue = 0
            } else {
                isDragEnabled = true
                twoFingerPan?.isEnabled = true
                let clamped = min(max(offset.wrappedValue, -maxOffset), maxOffset)
                offset.wrappedValue = clamped
                lastOffset.wrappedValue = clamped
            }

            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                lastScale.wrappedValue = newScale
            }
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .recognized, let webView = gesture.view as? WKWebView else { return }

            withAnimation(.interactiveSpring()) {
                scale.wrappedValue = 1
                lastScale.wrappedValue = 1
                offset.wrappedValue = 0
                lastOffset.wrappedValue = 0
            }

            currentScale = 1
            isDragEnabled = false
            twoFingerPan?.isEnabled = false
            applyTransformScaleCSS(in: webView, scale: 1)
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
                        ScaledWebView(
                            url: URL(string: "https://google.com")!,
                            baseWidth: stackWidth,
                            scale: $scale,
                            lastScale: $lastScale,
                            offset: $offset,
                            lastOffset: $lastOffset,
                            isDragEnabled: scale > 1,
                            maxOffset: maxOffset
                        )
                            .frame(
                                width: stackWidth * scale,
                                height: baseHeight * scale
                            )
                            .border(.green, width: 2) // green = scaled web view frame
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .offset(x: offset)
                    )
                    .border(.purple, width: 2) // purple = middle block after overlay

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
