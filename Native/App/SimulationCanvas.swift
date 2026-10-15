import SwiftUI

struct SimulationCanvas: View {
    let session: PlaygroundSession
    var onInteraction: () -> Void = {}
    @State private var cursor: CGPoint?
    @State private var pan: CGSize = .zero
    @State private var panAnchor: CGSize = .zero
    @GestureState private var drawing = false
    @State private var zoomAnchor: Double?

    var body: some View {
        GeometryReader { geometry in
            let width = CGFloat(session.canvasWidth)
            let height = CGFloat(session.canvasHeight)
            let scale = min(geometry.size.width / width, geometry.size.height / height) * session.canvasZoom
            let size = CGSize(width: width * scale, height: height * scale)
            let limitX = max(0, (size.width - geometry.size.width) / 2)
            let limitY = max(0, (size.height - geometry.size.height) / 2)
            let shift = CGSize(width: max(-limitX, min(limitX, pan.width)), height: max(-limitY, min(limitY, pan.height)))
            let origin = CGPoint(x: (geometry.size.width - size.width) / 2 + shift.width,
                                 y: (geometry.size.height - size.height) / 2 + shift.height)
            ZStack {
                Color(red: 0.028, green: 0.037, blue: 0.056)
                ZStack(alignment: .topLeading) {
                    if session.rendererError == nil {
                        MetalSimulationView(source: session.frameSource, settings: session.renderSettings,
                                            onFailure: session.useFallbackRenderer)
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)
                    } else if let image = session.image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: size.width, height: size.height)
                    }
                    ForEach(session.signs) { sign in
                        Text(sign.text)
                            .font(.system(size: max(6, 10 * scale), design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3 * scale)
                            .padding(.vertical, 2 * scale)
                            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 2 * scale))
                            .position(x: CGFloat(sign.boundsX) * scale + CGFloat(sign.boundsWidth) * scale / 2,
                                      y: CGFloat(sign.boundsY) * scale + CGFloat(sign.boundsHeight) * scale / 2)
                            .allowsHitTesting(false)
                    }
                    if let cursor, session.mode == .build, session.tool != .sample, session.tool != .pan {
                        Circle()
                            .strokeBorder(.white.opacity(0.8), lineWidth: 1)
                            .frame(width: CGFloat(session.brushRadius * 2 + 1) * scale,
                                   height: CGFloat(session.brushRadius * 2 + 1) * scale)
                            .position(cursor)
                            .allowsHitTesting(false)
                    }
                    if session.mode == .inspect, let sample = session.inspection {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                            .frame(width: max(18, scale * 5), height: max(18, scale * 5))
                            .overlay { Circle().fill(Color.accentColor).frame(width: 3, height: 3) }
                            .position(x: (CGFloat(sample.x) + 0.5) * scale, y: (CGFloat(sample.y) + 0.5) * scale)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: size.width, height: size.height)
                .position(x: geometry.size.width / 2 + shift.width, y: geometry.size.height / 2 + shift.height)
                .clipped()
                .overlay { Rectangle().strokeBorder(.white.opacity(0.10), lineWidth: 1) }
            }
            .overlay {
                if session.isBusy {
                    ProgressView("Preparing experiment…")
                        .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let point = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
                    cursor = point.x >= 0 && point.y >= 0 && point.x < size.width && point.y < size.height ? point : nil
                case .ended: cursor = nil
                }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .updating($drawing) { _, state, _ in state = true }
                .onChanged { value in
                    onInteraction()
                    if (session.mode == .build && session.tool == .pan) || session.mode == .run {
                        pan = CGSize(width: max(-limitX, min(limitX, panAnchor.width + value.translation.width)),
                                     height: max(-limitY, min(limitY, panAnchor.height + value.translation.height)))
                        cursor = nil
                        return
                    }
                    let point = CGPoint(x: value.location.x - origin.x, y: value.location.y - origin.y)
                    guard point.x >= 0, point.y >= 0, point.x < size.width, point.y < size.height else {
                        cursor = nil
                        session.finishStroke()
                        return
                    }
                    cursor = point
                    session.paint(x: Int(point.x / scale), y: Int(point.y / scale))
                }
                .onEnded { _ in session.finishStroke(); cursor = nil; panAnchor = pan }
            )
            .simultaneousGesture(MagnifyGesture().onChanged { value in
                if zoomAnchor == nil { zoomAnchor = session.canvasZoom }
                session.canvasZoom = min(4, max(1, (zoomAnchor ?? 1) * value.magnification))
            }.onEnded { _ in zoomAnchor = nil })
            .onChange(of: drawing) { _, active in
                if !active { session.finishStroke(); cursor = nil }
            }
            .onDisappear { session.finishStroke(); cursor = nil }
            .onChange(of: session.canvasZoom) { _, _ in pan = .zero; panAnchor = .zero; cursor = nil }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Simulation canvas")
            .accessibilityValue("\(session.particleCount) particles. \(session.isPaused ? "Paused" : "Running").")
            .accessibilityHint("Build: drag to paint. Inspect: select a particle. Run: drag to pan when zoomed. Pinch to zoom.")
        }
    }
}
