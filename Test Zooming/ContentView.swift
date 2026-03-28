//
//  ContentView.swift
//  Test Zooming
//
//  Created by mainuser on 2/16/26.
//

import SwiftUI
import WebKit

struct PlainWebView: UIViewRepresentable {
    let url: URL
    @Binding var zoomScale: CGFloat
    @Binding var frameScale: CGFloat
    @Binding var baseContentHeight: CGFloat
    @Binding var pinchGestureScale: CGFloat
    @Binding var pinchGestureState: String
    private let metricsHandlerName = "webViewportMetrics"

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        config.ignoresViewportScaleLimits = true
        config.userContentController.add(context.coordinator, name: metricsHandlerName)
        config.userContentController.addUserScript(
            WKUserScript(
                source: Self.viewportScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        config.userContentController.addUserScript(
            WKUserScript(
                source: Self.metricsScript(handlerName: metricsHandlerName),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: config)
        context.coordinator.configure(webView)
        webView.navigationDelegate = context.coordinator
        context.coordinator.loadIfNeeded(url, in: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.zoomScale = $zoomScale
        context.coordinator.frameScale = $frameScale
        context.coordinator.baseContentHeight = $baseContentHeight
        context.coordinator.pinchGestureScale = $pinchGestureScale
        context.coordinator.pinchGestureState = $pinchGestureState
        context.coordinator.configure(uiView)
        context.coordinator.loadIfNeeded(url, in: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            zoomScale: $zoomScale,
            frameScale: $frameScale,
            baseContentHeight: $baseContentHeight,
            pinchGestureScale: $pinchGestureScale,
            pinchGestureState: $pinchGestureState
        )
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "webViewportMetrics")
    }

    private static func metricsScript(handlerName: String) -> String {
        """
        (function() {
            if (window.__codexMetricsInstalled) { return; }
            window.__codexMetricsInstalled = true;

            function measure() {
                var viewport = window.visualViewport;
                var scale = viewport && viewport.scale ? viewport.scale : 1;
                var root = document.scrollingElement || document.documentElement || document.body;
                var rawHeight = root ? root.scrollHeight : 0;

                window.webkit.messageHandlers.\(handlerName).postMessage({
                    scale: scale,
                    rawHeight: rawHeight
                });
            }

            var scheduled = false;
            function scheduleMeasure() {
                if (scheduled) { return; }
                scheduled = true;
                requestAnimationFrame(function() {
                    scheduled = false;
                    measure();
                });
            }

            window.addEventListener('load', scheduleMeasure, true);
            document.addEventListener('readystatechange', scheduleMeasure, true);
            if (window.visualViewport) {
                window.visualViewport.addEventListener('resize', scheduleMeasure, true);
            }

            scheduleMeasure();
        })();
        """
    }

    private static let viewportScript = """
    (function() {
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
            meta = document.createElement('meta');
            meta.name = 'viewport';
            document.head.appendChild(meta);
        }

        meta.setAttribute(
            'content',
            'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes'
        );
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, UIGestureRecognizerDelegate {
        var zoomScale: Binding<CGFloat>
        var frameScale: Binding<CGFloat>
        var baseContentHeight: Binding<CGFloat>
        var pinchGestureScale: Binding<CGFloat>
        var pinchGestureState: Binding<String>
        private var loadedURL: URL?
        private var isPinching = false
        private var hasLockedBaseHeight = false
        private weak var webView: WKWebView?
        private weak var observedPinchGesture: UIPinchGestureRecognizer?

        init(
            zoomScale: Binding<CGFloat>,
            frameScale: Binding<CGFloat>,
            baseContentHeight: Binding<CGFloat>,
            pinchGestureScale: Binding<CGFloat>,
            pinchGestureState: Binding<String>
        ) {
            self.zoomScale = zoomScale
            self.frameScale = frameScale
            self.baseContentHeight = baseContentHeight
            self.pinchGestureScale = pinchGestureScale
            self.pinchGestureState = pinchGestureState
        }

        func configure(_ webView: WKWebView) {
            self.webView = webView
            webView.scrollView.isScrollEnabled = false
            webView.scrollView.alwaysBounceVertical = false
            webView.scrollView.bounces = false
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            webView.scrollView.panGestureRecognizer.isEnabled = false
            webView.scrollView.pinchGestureRecognizer?.isEnabled = true

            if observedPinchGesture !== webView.scrollView.pinchGestureRecognizer {
                observedPinchGesture?.removeTarget(self, action: #selector(handlePinchGesture(_:)))
                webView.scrollView.pinchGestureRecognizer?.addTarget(
                    self,
                    action: #selector(handlePinchGesture(_:))
                )
                observedPinchGesture = webView.scrollView.pinchGestureRecognizer
            }
        }

        func loadIfNeeded(_ url: URL, in webView: WKWebView) {
            configure(webView)
            guard loadedURL != url else { return }
            loadedURL = url
            baseContentHeight.wrappedValue = 0
            hasLockedBaseHeight = false
            isPinching = false
            zoomScale.wrappedValue = 1
            frameScale.wrappedValue = 1
            pinchGestureScale.wrappedValue = 1
            pinchGestureState.wrappedValue = "idle"
            webView.load(URLRequest(url: url))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            enableNativePageZoom(in: webView)
            updateMetrics(in: webView)
            refreshMetrics(in: webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard
                let body = message.body as? [String: Any]
            else {
                return
            }

            let scale = max((body["scale"] as? NSNumber).map(CGFloat.init(truncating:)) ?? 1, 1)
            let rawHeight = max((body["rawHeight"] as? NSNumber).map(CGFloat.init(truncating:)) ?? 0, 1)
            applyMeasurement(rawHeight: rawHeight, fallbackHeight: 0, scale: scale)
        }

        private func updateMetrics(in webView: WKWebView) {
            let js = """
            (function() {
                var viewport = window.visualViewport;
                var scale = viewport && viewport.scale ? viewport.scale : 1;
                var root = document.scrollingElement || document.documentElement || document.body;
                var rawHeight = root ? root.scrollHeight : 0;
                return {
                    scale: scale,
                    rawHeight: rawHeight
                };
            })();
            """

            webView.evaluateJavaScript(js) { [weak self, weak webView] result, _ in
                guard let self else { return }
                let payload = result as? [String: Any]
                let scale = max((payload?["scale"] as? NSNumber).map(CGFloat.init(truncating:)) ?? 1, 1)
                let rawHeight = max((payload?["rawHeight"] as? NSNumber).map(CGFloat.init(truncating:)) ?? 0, 0)
                let fallbackHeight = max(webView?.scrollView.contentSize.height ?? 0, 0)
                self.applyMeasurement(rawHeight: rawHeight, fallbackHeight: fallbackHeight, scale: scale)
            }
        }

        private func refreshMetrics(in webView: WKWebView, attemptsRemaining: Int = 20) {
            guard attemptsRemaining > 0 else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak webView] in
                guard let self, let webView else { return }
                guard !self.isPinching else { return }
                self.updateMetrics(in: webView)

                if self.baseContentHeight.wrappedValue <= 1 {
                    self.refreshMetrics(in: webView, attemptsRemaining: attemptsRemaining - 1)
                }
            }
        }

        private func applyMeasurement(rawHeight: CGFloat, fallbackHeight: CGFloat, scale: CGFloat) {
            let measuredHeight = rawHeight > 1 ? rawHeight : fallbackHeight
            guard measuredHeight > 1 || baseContentHeight.wrappedValue > 1 else { return }

            if rawHeight > 1, !hasLockedBaseHeight, !isPinching, scale <= 1.01 {
                DispatchQueue.main.async {
                    if abs(self.baseContentHeight.wrappedValue - rawHeight) > 0.5 {
                        self.baseContentHeight.wrappedValue = rawHeight
                    }
                }
            }

            DispatchQueue.main.async {
                if abs(self.zoomScale.wrappedValue - scale) > 0.001 {
                    self.zoomScale.wrappedValue = scale
                }

                if !self.isPinching, abs(self.frameScale.wrappedValue - scale) > 0.001 {
                    self.frameScale.wrappedValue = scale
                }
            }
        }

        private func enableNativePageZoom(in webView: WKWebView) {
            webView.evaluateJavaScript(PlainWebView.viewportScript)
        }

        @objc
        func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
            DispatchQueue.main.async {
                self.pinchGestureScale.wrappedValue = gesture.scale
                self.pinchGestureState.wrappedValue = switch gesture.state {
                case .possible: "possible"
                case .began: "began"
                case .changed: "changed"
                case .ended: "ended"
                case .cancelled: "cancelled"
                case .failed: "failed"
                @unknown default: "unknown"
                }
            }

            switch gesture.state {
            case .began:
                isPinching = true
                hasLockedBaseHeight = true
            case .changed:
                isPinching = true
            case .ended, .cancelled, .failed:
                isPinching = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak webView] in
                    guard let self, let webView else { return }
                    self.alignContentToTop(in: webView)
                    self.updateMetrics(in: webView)
                    self.refreshMetrics(in: webView, attemptsRemaining: 4)
                }
            default:
                break
            }
        }

        private func alignContentToTop(in webView: WKWebView) {
            let topOffset = -webView.scrollView.adjustedContentInset.top
            let currentOffset = webView.scrollView.contentOffset
            guard abs(currentOffset.y - topOffset) > 0.5 else { return }
            webView.scrollView.setContentOffset(
                CGPoint(x: currentOffset.x, y: topOffset),
                animated: false
            )
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }
    }
}

struct WebZoomView: View {
    @State private var zoomScale: CGFloat = 1
    @State private var frameScale: CGFloat = 1
    @State private var baseContentHeight: CGFloat = 1
    @State private var pinchGestureScale: CGFloat = 1
    @State private var pinchGestureState: String = "idle"

    private let blockHeight: CGFloat = 150
    private let placeholderHeight: CGFloat = 320

    private var resolvedWebHeight: CGFloat {
        let baseHeight = baseContentHeight > 1 ? baseContentHeight : placeholderHeight
        return baseHeight * max(frameScale, 1)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.blue)
                    .frame(height: blockHeight)
                    .overlay {
                        Text("Top Block")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }

                PlainWebView(
                    url: URL(string: "https://evan6seven.github.io/Test-Zooming/")!,
                    zoomScale: $zoomScale,
                    frameScale: $frameScale,
                    baseContentHeight: $baseContentHeight,
                    pinchGestureScale: $pinchGestureScale,
                    pinchGestureState: $pinchGestureState
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: resolvedWebHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.secondary, lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("zoom \(zoomScale, format: .number.precision(.fractionLength(2)))")
                            Text("frame \(frameScale, format: .number.precision(.fractionLength(2)))")
                            Text("base \(baseContentHeight, format: .number.precision(.fractionLength(0)))")
                            Text("height \(resolvedWebHeight, format: .number.precision(.fractionLength(0)))")
                            Text("pinch \(pinchGestureState)")
                            Text("gesture \(pinchGestureScale, format: .number.precision(.fractionLength(2)))")
                        }
                        .font(.caption.monospacedDigit())
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding(12)
                    }

                RoundedRectangle(cornerRadius: 16)
                    .fill(.orange)
                    .frame(height: blockHeight)
                    .overlay {
                        Text("Bottom Block")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(.background)
        .animation(.interactiveSpring(), value: zoomScale)
        .animation(.interactiveSpring(), value: frameScale)
        .animation(.interactiveSpring(), value: baseContentHeight)
    }
}

struct ContentView: View {
    var body: some View {
        WebZoomView()
    }
}

#Preview {
    ContentView()
}
