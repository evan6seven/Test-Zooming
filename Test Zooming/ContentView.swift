//
//  ContentView.swift
//  Test Zooming
//
//  Created by mainuser on 2/16/26.
//

import SwiftUI

struct ContentView: View {
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    private let baseHeight: CGFloat = 150

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
                                width: (UIScreen.main.bounds.width - 32) * scale,
                                height: baseHeight * scale
                            )
                            .overlay(
                                Text("Pinch to Zoom")
                                    .foregroundStyle(.white)
                                    .font(.system(size: 22 * scale))
                            )
                    )
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = max(1, lastScale * value.magnification)
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                    )
                    .animation(.interactiveSpring, value: scale)

                // Bottom block
                RoundedRectangle(cornerRadius: 16)
                    .fill(.orange)
                    .frame(height: baseHeight)
                    .overlay(Text("Bottom Block").foregroundStyle(.white).font(.title2))
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
