import SwiftUI
import SceneKit
import UIKit

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
            SceneView(scene: vm.scene, options: [])
                .ignoresSafeArea()

            FPVOverlay(flash: vm.flashAlpha)

            if vm.state == .playing || vm.state == .paused {
                PlayingHUD(vm: vm)
            }

            if vm.state == .menu || vm.state == .over {
                MenuOverlay(vm: vm)
            }

            if vm.state == .paused {
                PausedOverlay(vm: vm)
            }
        }
        .onAppear { vm.showMenu() }
    }
}

// MARK: - ViewModel
final class GameViewModel: ObservableObject {
    private static let highScoreKey = "DroneFPV.highScore"

    let scene = GameScene3D()

    @Published var state: GameScene3D.GState = .menu
    @Published var score = 0
    @Published var highScore = 0
    @Published var wave = 0
    @Published var tanks = 0
    @Published var lives = 4
    @Published var speed: Float = 0
    @Published var bombReady = true
    @Published var bombCooldown: Float = 0
    @Published var flashAlpha: CGFloat = 0
    @Published var message = ""
    @Published var showMessage = false

    private let bombHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let hitHaptic = UINotificationFeedbackGenerator()
    private var displayLink: CADisplayLink?
    private var messageSerial = 0

    init() {
        highScore = UserDefaults.standard.integer(forKey: Self.highScoreKey)

        scene.onStateChanged = { [weak self] s in
            DispatchQueue.main.async { self?.state = s }
        }
        scene.onScoreChanged = { [weak self] v in
            DispatchQueue.main.async { self?.setScore(v) }
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
                self?.showTransientMessage(msg)
            }
        }
        scene.onPlayerHit = { [weak self] in
            DispatchQueue.main.async {
                self?.hitHaptic.notificationOccurred(.warning)
            }
        }

        bombHaptic.prepare()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink?.add(to: .main, forMode: .common)
    }

    deinit {
        displayLink?.invalidate()
    }

    @objc private func tick(_ link: CADisplayLink) {
        scene.update(link.timestamp)
    }

    func showMenu() { scene.showMenu() }
    func startGame() { scene.startGame() }
    func pauseGame() { scene.pauseGame() }
    func resumeGame() { scene.resumeGame() }

    func dropBomb() {
        guard scene.dropBomb() else { return }
        bombHaptic.impactOccurred()
        bombHaptic.prepare()
    }

    private func setScore(_ value: Int) {
        score = value
        guard value > highScore else { return }
        highScore = value
        UserDefaults.standard.set(value, forKey: Self.highScoreKey)
    }

    private func showTransientMessage(_ text: String) {
        messageSerial += 1
        let serial = messageSerial
        message = text

        withAnimation(.easeOut(duration: 0.18)) {
            showMessage = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, self.messageSerial == serial else { return }
            withAnimation(.easeIn(duration: 0.2)) {
                self.showMessage = false
            }
        }
    }
}

// MARK: - FPV Overlay
struct FPVOverlay: View {
    let flash: CGFloat

    var body: some View {
        ZStack {
            Color(red: 0.4, green: 1, blue: 0.6)
                .opacity(0.06)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)

            ScanlinesView()
                .opacity(0.32)
                .allowsHitTesting(false)

            RadialGradient(
                colors: [.clear, .clear, .black.opacity(0.7)],
                center: .center,
                startRadius: 200,
                endRadius: 520
            )
            .allowsHitTesting(false)

            Color(red: 1, green: 0.2, blue: 0.15)
                .opacity(flash)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

struct ScanlinesView: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let offset = CGFloat(timeline.date.timeIntervalSinceReferenceDate * 8)

            Canvas { ctx, size in
                ctx.opacity = 0.55
                for y in stride(from: offset.truncatingRemainder(dividingBy: 3), to: size.height, by: 3) {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black))
                }

                ctx.opacity = 0.06
                for y in stride(from: offset.truncatingRemainder(dividingBy: 9), to: size.height, by: 9) {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Color(red: 0.5, green: 1, blue: 0.7)))
                }
            }
        }
    }
}

// MARK: - Playing HUD
struct PlayingHUD: View {
    @ObservedObject var vm: GameViewModel
    @State private var joyDrag: CGSize = .zero
    @State private var joyOrigin: CGPoint = .zero
    @State private var joyActive = false

    private let neon = Color(red: 0.47, green: 0.90, blue: 0.63)
    private let amber = Color(red: 1.0, green: 0.76, blue: 0.24)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                joystickGestureArea(in: geo)

                reticle(in: geo)

                topLeftStats
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 18)
                    .padding(.top, 24)

                topRightStats
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 18)
                    .padding(.top, 92)

                pauseButton
                    .position(x: geo.size.width / 2, y: 44)
                    .zIndex(10)

                if vm.showMessage {
                    Text(vm.message)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundColor(amber)
                        .shadow(color: .black, radius: 8)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.66)
                        .transition(.opacity)
                }

                if joyActive {
                    joystickView
                }

                bombButton
                    .position(x: geo.size.width - 74, y: geo.size.height - 88)
                    .zIndex(10)
            }
        }
    }

    private var topLeftStats: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("СЧЁТ \(vm.score)")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(neon)
            Text("РЕКОРД \(vm.highScore)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.30))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(neon.opacity(0.42), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var topRightStats: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(String(format: "СКОР %3.0f", vm.speed / 3))
            Text("ВЫС  120")
            Text(vm.bombReady ? "БОМБА ГОТОВА" : String(format: "БОМБА %.1f", max(0, vm.bombCooldown)))
                .foregroundColor(vm.bombReady ? amber : .white.opacity(0.75))
        }
        .font(.system(size: 14, weight: .bold, design: .monospaced))
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.28))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var pauseButton: some View {
        Button(action: { vm.pauseGame() }) {
            Image(systemName: "pause.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.34))
                .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Пауза")
    }

    private var bombButton: some View {
        Button(action: { vm.dropBomb() }) {
            ZStack {
                Circle()
                    .fill(amber.opacity(vm.bombReady ? 0.18 : 0.08))
                    .overlay(
                        Circle()
                            .strokeBorder(vm.bombReady ? amber : Color.white.opacity(0.55), lineWidth: 3)
                    )
                    .frame(width: 96, height: 96)

                VStack(spacing: 2) {
                    Image(systemName: "scope")
                        .font(.system(size: 18, weight: .bold))
                    Text(vm.bombReady ? "BOMB" : String(format: "%.1f", max(0, vm.bombCooldown)))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
                .foregroundColor(amber)
            }
        }
        .buttonStyle(.plain)
        .disabled(!vm.bombReady)
        .accessibilityLabel("Сброс бомбы")
    }

    private var joystickView: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.05))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 3))
                .frame(width: 128, height: 128)
                .position(joyOrigin)

            Circle()
                .fill(Color.white.opacity(0.25))
                .overlay(Circle().strokeBorder(neon, lineWidth: 2))
                .frame(width: 60, height: 60)
                .position(x: joyOrigin.x + joyDrag.width, y: joyOrigin.y + joyDrag.height)
        }
    }

    private func reticle(in geo: GeometryProxy) -> some View {
        ZStack {
            Circle()
                .strokeBorder(neon, lineWidth: 2)
                .frame(width: 52, height: 52)

            Path { path in
                path.move(to: CGPoint(x: 6, y: 40))
                path.addLine(to: CGPoint(x: 28, y: 40))
                path.move(to: CGPoint(x: 52, y: 40))
                path.addLine(to: CGPoint(x: 74, y: 40))
                path.move(to: CGPoint(x: 40, y: 6))
                path.addLine(to: CGPoint(x: 40, y: 28))
                path.move(to: CGPoint(x: 40, y: 52))
                path.addLine(to: CGPoint(x: 40, y: 74))
            }
            .stroke(neon.opacity(0.85), lineWidth: 2)
            .frame(width: 80, height: 80)

            Circle()
                .foregroundColor(neon)
                .frame(width: 4, height: 4)
        }
        .position(x: geo.size.width / 2, y: geo.size.height / 2)
    }

    private func joystickGestureArea(in geo: GeometryProxy) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: geo.size.width / 2, height: geo.size.height)
            .position(x: geo.size.width / 4, y: geo.size.height / 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
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

                        joyDrag = CGSize(width: dx, height: dy)
                        vm.scene.joyVec = CGVector(dx: dx / maxR, dy: dy / maxR)
                    }
                    .onEnded { _ in
                        joyActive = false
                        joyDrag = .zero
                        vm.scene.joyVec = .zero
                    }
            )
    }
}

// MARK: - Menu Overlay
struct MenuOverlay: View {
    @ObservedObject var vm: GameViewModel
    private let neon = Color(red: 0.47, green: 0.90, blue: 0.63)

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text(vm.state == .menu ? "FPV STRIKE" : "ДРОН СБИТ")
                    .font(.system(size: 42, weight: .bold, design: .monospaced))
                    .foregroundColor(neon)
                    .minimumScaleFactor(0.7)

                if vm.state == .over {
                    VStack(spacing: 6) {
                        Text("СЧЁТ \(vm.score)")
                        Text("РЕКОРД \(vm.highScore)")
                    }
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                } else if vm.highScore > 0 {
                    Text("РЕКОРД \(vm.highScore)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.92))
                }

                Button(action: { vm.startGame() }) {
                    Text(vm.state == .menu ? "НАЧАТЬ" : "ЗАНОВО")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(neon)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
        }
    }
}

struct PausedOverlay: View {
    @ObservedObject var vm: GameViewModel
    private let neon = Color(red: 0.47, green: 0.90, blue: 0.63)

    var body: some View {
        ZStack {
            Color.black.opacity(0.54)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("ПАУЗА")
                    .font(.system(size: 38, weight: .bold, design: .monospaced))
                    .foregroundColor(neon)

                Button(action: { vm.resumeGame() }) {
                    Text("ПРОДОЛЖИТЬ")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 12)
                        .background(neon)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button(action: { vm.startGame() }) {
                    Text("ЗАНОВО")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
