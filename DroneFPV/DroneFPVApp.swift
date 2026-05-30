import SwiftUI
import SceneKit

@main
struct DroneFPVApp: App {
    var body: some Scene {
        WindowGroup {
            GameView3D()
                .ignoresSafeArea()
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}

struct GameView3D: View {
    @StateObject private var vm = GameViewModel()

    var body: some View {
        ZStack {
            // 3D Scene
            SceneView(
                scene: vm.scene,
                options: [.allowsCameraControl, .autoenablesDefaultLighting]
            )
            .ignoresSafeArea()

            // FPV Overlays
            FPVOverlay(flash: vm.flashAlpha)

            // HUD
            if vm.scene.getState() == .playing {
                PlayingHUD(vm: vm)
            }

            // Menu/Game Over
            if vm.scene.getState() == .menu || vm.scene.getState() == .over {
                MenuOverlay(vm: vm)
            }
        }
        .onAppear { vm.showMenu() }
    }
}

// MARK: - ViewModel
final class GameViewModel: ObservableObject {
    let scene = GameScene3D()

    @Published var state: GameScene3D.GState = .menu
    @Published var score = 0
    @Published var wave = 0
    @Published var tanks = 0
    @Published var lives = 4
    @Published var speed: Float = 0
    @Published var bombReady = true
    @Published var bombCooldown: Float = 0
    @Published var flashAlpha: CGFloat = 0
    @Published var message: String = ""
    @Published var showMessage = false

    private var displayLink: CADisplayLink?

    init() {
        scene.onStateChanged = { [weak self] s in
            DispatchQueue.main.async { self?.state = s }
        }
        scene.onScoreChanged = { [weak self] v in
            DispatchQueue.main.async { self?.score = v }
        }
        scene.onWaveChanged = { [weak self] v in
            DispatchQueue.main.async { self?.wave = v }
        }
        scene.onTanksChanged = { [weak self] v in
            DispatchQueue.main.async { self?.tanks = v }
        }
        scene.onLivesChanged = { [weak self] v in
            DispatchQueue.main.async { self?.lives = v }
        }
        scene.onSpeedChanged = { [weak self] v in
            DispatchQueue.main.async { self?.speed = v }
        }
        scene.onBombStateChanged = { [weak self] ready, cd in
            DispatchQueue.main.async {
                self?.bombReady = ready
                self?.bombCooldown = cd
            }
        }
        scene.onFlash = { [weak self] v in
            DispatchQueue.main.async {
                self?.flashAlpha = CGFloat(max(0, v / 0.3)) * 0.5
            }
        }
        scene.onMessage = { [weak self] msg in
            DispatchQueue.main.async {
                self?.message = msg
                self?.showMessage = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    self?.showMessage = false
                }
            }
        }

        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func tick(_ link: CADisplayLink) {
        scene.update(link.timestamp)
    }

    func showMenu() { scene.showMenu() }
    func startGame() { scene.startGame() }
    func dropBomb() { scene.dropBomb() }
}

// MARK: - FPV Overlay
struct FPVOverlay: View {
    let flash: CGFloat

    var body: some View {
        ZStack {
            // Tint
            Color(red: 0.4, green: 1, blue: 0.6)
                .opacity(0.06)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)

            // Scanlines
            ScanlinesView()
                .opacity(0.32)
                .allowsHitTesting(false)

            // Vignette
            RadialGradient(
                colors: [.clear, .clear, .black.opacity(0.7)],
                center: .center,
                startRadius: 200,
                endRadius: 500
            )
            .allowsHitTesting(false)

            // Flash
            Color(red: 1, green: 0.2, blue: 0.15)
                .opacity(flash)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

struct ScanlinesView: View {
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                ctx.opacity = 0.55
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.01)))
                for y in stride(from: offset.truncatingRemainder(dividingBy: 3), to: size.height, by: 3) {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black))
                }
                ctx.opacity = 0.06
                for y in stride(from: offset.truncatingRemainder(dividingBy: 9), to: size.height, by: 9) {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Color(red: 0.5, green: 1, blue: 0.7)))
                }
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
                offset += 0.13
            }
        }
    }
}

// MARK: - Playing HUD
struct PlayingHUD: View {
    @ObservedObject var vm: GameViewModel
    @GestureState private var joyDrag: CGSize = .zero
    @State private var joyOrigin: CGPoint = .zero
    @State private var joyActive = false

    let neon = Color(red: 0.47, green: 0.90, blue: 0.63)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Reticle
                Circle()
                    .stroke(neon, lineWidth: 2)
                    .frame(width: 52, height: 52)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                Circle()
                    .fill(neon)
                    .frame(width: 4, height: 4)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                // Stats (top left)
                VStack(alignment: .leading, spacing: 4) {
                    Text("СЧЁТ \(vm.score)")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(neon)
                    Text("ВОЛНА \(vm.wave)")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("ТАНКИ \(vm.tanks)")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 1, green: 0.66, blue: 0.35))
                    Text("ЖИЗНИ \(String(repeating: "▮", count: max(0, vm.lives)))")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.5, green: 0.9, blue: 1))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 18)
                .padding(.top, 34)

                // Speed/Alt (top right)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "СКОР %3.0f", vm.speed / 3))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("ВЫС  120")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, 18)
                .padding(.top, 112)

                // Message
                if vm.showMessage {
                    Text(vm.message)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 1, green: 0.85, blue: 0.4))
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.66)
                        .transition(.opacity)
                }

                // Joystick
                if joyActive {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.35), lineWidth: 3)
                            .fill(Color.white.opacity(0.05))
                            .frame(width: 128, height: 128)
                            .position(joyOrigin)

                        Circle()
                            .fill(Color.white.opacity(0.25))
                            .stroke(neon, lineWidth: 2)
                            .frame(width: 60, height: 60)
                            .position(x: joyOrigin.x + joyDrag.width, y: joyOrigin.y + joyDrag.height)
                    }
                }

                // Bomb button
                Button(action: { vm.dropBomb() }) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 1, green: 0.8, blue: 0.2).opacity(0.15))
                            .stroke(vm.bombReady ? Color(red: 1, green: 0.8, blue: 0.2) : Color.white.opacity(0.6), lineWidth: 3)
                            .frame(width: 96, height: 96)

                        Text(vm.bombReady ? "BOMB" : String(format: "%.1f", max(0, vm.bombCooldown)))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 1, green: 0.85, blue: 0.3))
                    }
                }
                .position(x: geo.size.width - 74, y: geo.size.height - 96)

                // Joystick gesture area (left half)
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: geo.size.width / 2, height: geo.size.height)
                    .position(x: geo.size.width / 4, y: geo.size.height / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating($joyDrag) { value, state, _ in
                                if !joyActive {
                                    joyOrigin = value.startLocation
                                    joyActive = true
                                }
                                var dx = value.translation.width
                                var dy = value.translation.height
                                let len = sqrt(dx * dx + dy * dy)
                                let maxR: CGFloat = 64
                                if len > maxR {
                                    dx = dx / len * maxR
                                    dy = dy / len * maxR
                                }
                                state = CGSize(width: dx, height: dy)
                                vm.scene.joyVec = CGVector(dx: dx / maxR, dy: dy / maxR)
                            }
                            .onEnded { _ in
                                joyActive = false
                                vm.scene.joyVec = .zero
                            }
                    )
            }
        }
    }
}

// MARK: - Menu Overlay
struct MenuOverlay: View {
    @ObservedObject var vm: GameViewModel
    let neon = Color(red: 0.47, green: 0.90, blue: 0.63)

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(vm.scene.getState() == .menu ? "FPV STRIKE" : "ДРОН СБИТ")
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .foregroundColor(neon)

                Text(vm.scene.getState() == .menu ? "ТАП — СТАРТ" : "ТАП — ЗАНОВО   ·   СЧЁТ \(vm.score)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
        .onTapGesture {
            if vm.scene.getState() == .menu || vm.scene.getState() == .over {
                vm.startGame()
            }
        }
    }
}
