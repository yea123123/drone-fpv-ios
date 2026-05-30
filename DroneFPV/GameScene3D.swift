import SceneKit
import UIKit

final class GameScene3D: SCNScene {

    // MARK: - Tunables
    private let fieldHalf: Float = 140
    private let droneSpeed: Float = 34
    private let droneHeight: Float = 12
    private let bombReload: Float = 1.1
    private let bombBlast: Float = 13
    private let shellSpeed: Float = 52
    private let neon = UIColor(red: 0.47, green: 0.90, blue: 0.63, alpha: 1)

    // MARK: - State
    enum GState { case menu, playing, over }
    private var state: GState = .menu

    private var droneX: Float = 0, droneZ: Float = 0
    private var vx: Float = 0, vz: Float = 0

    private var score = 0
    private var wave = 0
    private var lives = 4
    private var bombReady = true
    private var bombCooldown: Float = 0
    private var hitFlash: Float = 0
    private var shake: Float = 0
    private var invuln: Float = 0
    private var lastTime: TimeInterval = 0

    // MARK: - Entities
    private final class Tank {
        let node: SCNNode
        var x: Float, z: Float
        var heading: Float = 0
        var turnCd: Float = 0
        var fireCd: Float = 0
        var hp: Int
        let maxHp: Int
        var alive = true
        let barNode: SCNNode
        init(node: SCNNode, x: Float, z: Float, hp: Int, barNode: SCNNode) {
            self.node = node; self.x = x; self.z = z; self.hp = hp; self.maxHp = hp; self.barNode = barNode
        }
    }

    private final class Shell {
        let node: SCNNode
        var x: Float, z: Float, vx: Float, vz: Float
        var life: Float = 2.6
        var alive = true
        init(node: SCNNode, x: Float, z: Float, vx: Float, vz: Float) {
            self.node = node; self.x = x; self.z = z; self.vx = vx; self.vz = vz
        }
    }

    private final class Bomb {
        let x: Float, z: Float
        var timer: Float
        init(x: Float, z: Float, timer: Float) { self.x = x; self.z = z; self.timer = timer }
    }

    private var tanks: [Tank] = []
    private var shells: [Shell] = []
    private var bombs: [Bomb] = []

    // MARK: - Nodes
    private var cameraNode: SCNNode!
    private var worldNode: SCNNode!
    private var impactNode: SCNNode!

    // MARK: - Controls
    var joyVec: CGVector = .zero

    // MARK: - Callbacks
    var onScoreChanged: ((Int) -> Void)?
    var onWaveChanged: ((Int) -> Void)?
    var onTanksChanged: ((Int) -> Void)?
    var onLivesChanged: ((Int) -> Void)?
    var onSpeedChanged: ((Float) -> Void)?
    var onBombStateChanged: ((Bool, Float) -> Void)?
    var onStateChanged: ((GState) -> Void)?

    func getState() -> GState { return state }
    var onFlash: ((Float) -> Void)?
    var onMessage: ((String) -> Void)?

    // MARK: - Init
    override init() {
        super.init()
        buildWorld()
        buildCamera()
        buildLighting()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build
    private func buildWorld() {
        worldNode = SCNNode()
        rootNode.addChildNode(worldNode)

        // Ground
        let groundGeo = SCNPlane(width: CGFloat(fieldHalf * 2 + 40), height: CGFloat(fieldHalf * 2 + 40))
        groundGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.10, green: 0.16, blue: 0.11, alpha: 1)
        groundGeo.firstMaterial?.specular.contents = UIColor.black
        let ground = SCNNode(geometry: groundGeo)
        ground.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        ground.position = SCNVector3(0, 0, 0)
        worldNode.addChildNode(ground)

        // Grid lines
        for i in stride(from: -fieldHalf, through: fieldHalf, by: 12) {
            addGridLine(from: SCNVector3(i, 0.01, -fieldHalf), to: SCNVector3(i, 0.01, fieldHalf))
            addGridLine(from: SCNVector3(-fieldHalf, 0.01, i), to: SCNVector3(fieldHalf, 0.01, i))
        }

        // Border
        let borderColor = UIColor(red: 0.8, green: 0.3, blue: 0.25, alpha: 0.8)
        addBorderLine(from: SCNVector3(-fieldHalf, 0.02, -fieldHalf), to: SCNVector3(fieldHalf, 0.02, -fieldHalf), color: borderColor)
        addBorderLine(from: SCNVector3(fieldHalf, 0.02, -fieldHalf), to: SCNVector3(fieldHalf, 0.02, fieldHalf), color: borderColor)
        addBorderLine(from: SCNVector3(fieldHalf, 0.02, fieldHalf), to: SCNVector3(-fieldHalf, 0.02, fieldHalf), color: borderColor)
        addBorderLine(from: SCNVector3(-fieldHalf, 0.02, fieldHalf), to: SCNVector3(-fieldHalf, 0.02, -fieldHalf), color: borderColor)

        // Impact marker
        let impactGeo = SCNTorus(ringRadius: 2.6, pipeRadius: 0.15)
        impactGeo.firstMaterial?.diffuse.contents = UIColor(red: 1, green: 0.4, blue: 0.35, alpha: 0.9)
        impactGeo.firstMaterial?.emission.contents = UIColor(red: 1, green: 0.4, blue: 0.35, alpha: 0.6)
        impactNode = SCNNode(geometry: impactGeo)
        impactNode.position = SCNVector3(0, 0.05, 0)
        impactNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        impactNode.isHidden = true
        worldNode.addChildNode(impactNode)
    }

    private func addGridLine(from: SCNVector3, to: SCNVector3) {
        let line = lineNode(from: from, to: to, color: UIColor(red: 0.18, green: 0.30, blue: 0.20, alpha: 0.7), width: 0.08)
        worldNode.addChildNode(line)
    }

    private func addBorderLine(from: SCNVector3, to: SCNVector3, color: UIColor) {
        let line = lineNode(from: from, to: to, color: color, width: 0.3)
        worldNode.addChildNode(line)
    }

    private func lineNode(from: SCNVector3, to: SCNVector3, color: UIColor, width: CGFloat) -> SCNNode {
        let vec = SCNVector3(to.x - from.x, to.y - from.y, to.z - from.z)
        let len = sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z)
        let cyl = SCNCylinder(radius: width / 2, height: CGFloat(len))
        cyl.firstMaterial?.diffuse.contents = color
        cyl.firstMaterial?.emission.contents = color.withAlphaComponent(0.3)
        let node = SCNNode(geometry: cyl)
        node.position = SCNVector3((from.x + to.x) / 2, (from.y + to.y) / 2, (from.z + to.z) / 2)
        let dy = to.y - from.y, dxz = sqrt((to.x - from.x) * (to.x - from.x) + (to.z - from.z) * (to.z - from.z))
        node.eulerAngles = SCNVector3(Float.pi / 2 - atan2(dy, dxz), 0, atan2(to.x - from.x, to.z - from.z))
        return node
    }

    private func buildCamera() {
        cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 75
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 300
        cameraNode.position = SCNVector3(0, droneHeight, 0)
        cameraNode.eulerAngles = SCNVector3(-Float.pi / 6, 0, 0)  // tilt down 30°
        rootNode.addChildNode(cameraNode)
    }

    private func buildLighting() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(white: 0.4, alpha: 1)
        rootNode.addChildNode(ambient)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.color = UIColor(white: 0.7, alpha: 1)
        sun.light?.castsShadow = true
        sun.light?.shadowMode = .deferred
        sun.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        rootNode.addChildNode(sun)
    }

    // MARK: - Tank model
    private func makeTankNode(_ hue: CGFloat) -> SCNNode {
        let root = SCNNode()
        let bodyColor = UIColor(hue: hue, saturation: 0.45, brightness: 0.55, alpha: 1)
        let darkColor = UIColor(white: 0.16, alpha: 1)

        // Tracks
        for side in [-1, 1] {
            let track = SCNBox(width: 4.6, height: 0.8, length: 1.2, chamferRadius: 0.3)
            track.firstMaterial?.diffuse.contents = darkColor
            let tn = SCNNode(geometry: track)
            tn.position = SCNVector3(0, 0.4, Float(side) * 1.5)
            root.addChildNode(tn)
        }

        // Body
        let body = SCNBox(width: 4.2, height: 1.5, length: 3.0, chamferRadius: 0.4)
        body.firstMaterial?.diffuse.contents = bodyColor
        body.firstMaterial?.specular.contents = UIColor(white: 0.2, alpha: 1)
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 1.15, 0)
        root.addChildNode(bodyNode)

        // Turret
        let turret = SCNCylinder(radius: 1.1, height: 0.9)
        turret.firstMaterial?.diffuse.contents = bodyColor
        turret.firstMaterial?.specular.contents = UIColor(white: 0.2, alpha: 1)
        let turretNode = SCNNode(geometry: turret)
        turretNode.position = SCNVector3(0, 2.15, 0)
        root.addChildNode(turretNode)

        // Barrel
        let barrel = SCNCylinder(radius: 0.25, height: 2.2)
        barrel.firstMaterial?.diffuse.contents = darkColor
        let barrelNode = SCNNode(geometry: barrel)
        barrelNode.position = SCNVector3(1.6, 2.15, 0)
        barrelNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        root.addChildNode(barrelNode)

        return root
    }

    // MARK: - HP bar
    private func makeHPBar() -> SCNNode {
        let bar = SCNBox(width: 4.0, height: 0.5, length: 0.1, chamferRadius: 0.1)
        bar.firstMaterial?.diffuse.contents = neon
        bar.firstMaterial?.emission.contents = neon.withAlphaComponent(0.5)
        let node = SCNNode(geometry: bar)
        node.position = SCNVector3(0, 3.5, 0)
        return node
    }

    // MARK: - Waves
    private func spawnWave(_ n: Int) {
        wave = n
        let count = 3 + n
        let hp = 1 + n / 3
        let hues: [CGFloat] = [0.28, 0.09, 0.55, 0.0, 0.78]

        for _ in 0..<count {
            var px: Float = 0, pz: Float = 0
            var tries = 0
            repeat {
                px = Float.random(in: (-fieldHalf + 14)...(fieldHalf - 14))
                pz = Float.random(in: (-fieldHalf + 14)...(fieldHalf - 14))
                tries += 1
            } while dist(px, pz, droneX, droneZ) < 38 && tries < 40

            let node = makeTankNode(hues[Int.random(in: 0..<hues.count)])
            node.position = SCNVector3(px, 0, pz)
            worldNode.addChildNode(node)

            let barNode = makeHPBar()
            barNode.isHidden = hp <= 1
            node.addChildNode(barNode)

            let t = Tank(node: node, x: px, z: pz, hp: hp, barNode: barNode)
            t.heading = Float.random(in: 0...(2 * .pi))
            t.fireCd = Float.random(in: 1.5...3.5)
            t.turnCd = Float.random(in: 1...3)
            tanks.append(t)
        }

        onWaveChanged?(wave)
        onTanksChanged?(tanks.count)
        onMessage?("ВОЛНА \(n)")
    }

    // MARK: - Bombs
    func dropBomb() {
        guard state == .playing, bombReady else { return }
        bombReady = false
        bombCooldown = bombReload
        let aim = aimPoint()
        bombs.append(Bomb(x: aim.x, z: aim.z, timer: 0.45))
        onBombStateChanged?(false, bombCooldown)
    }

    private func aimPoint() -> (x: Float, z: Float) {
        let ax = clamp(droneX + vx * 0.35, -fieldHalf, fieldHalf)
        let az = clamp(droneZ + vz * 0.35, -fieldHalf, fieldHalf)
        return (ax, az)
    }

    private func explode(at x: Float, _ z: Float, big: Bool) {
        // Ring
        let ringGeo = SCNTorus(ringRadius: big ? 8 : 3, pipeRadius: 0.3)
        ringGeo.firstMaterial?.diffuse.contents = big ? UIColor.orange : UIColor.yellow
        ringGeo.firstMaterial?.emission.contents = big ? UIColor.orange : UIColor.yellow
        let ring = SCNNode(geometry: ringGeo)
        ring.position = SCNVector3(x, 0.5, z)
        ring.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        worldNode.addChildNode(ring)
        ring.runAction(.sequence([
            .group([.scale(to: big ? 3 : 2, duration: big ? 0.45 : 0.3),
                    .fadeOut(duration: big ? 0.45 : 0.3)]),
            .run { node in node.removeFromParent() }
        ]))

        // Flash sphere
        let flashGeo = SCNSphere(radius: big ? 4.4 : 1.8)
        flashGeo.firstMaterial?.diffuse.contents = UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 0.9)
        flashGeo.firstMaterial?.emission.contents = UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1)
        let flash = SCNNode(geometry: flashGeo)
        flash.position = SCNVector3(x, 1, z)
        worldNode.addChildNode(flash)
        flash.runAction(.sequence([.fadeOut(duration: 0.25), .run { node in node.removeFromParent() }]))

        if big {
            shake = max(shake, 0.45)
            for t in tanks where t.alive {
                let d = dist(t.x, t.z, x, z)
                if d < bombBlast {
                    killTank(t)
                } else if d < bombBlast * 1.6 {
                    damageTank(t)
                }
            }
        }
    }

    private func damageTank(_ t: Tank) {
        t.hp -= 1
        if t.hp <= 0 { killTank(t); return }
        t.barNode.scale = SCNVector3(Float(t.hp) / Float(t.maxHp), 1, 1)
        t.node.runAction(.sequence([
            .customAction(duration: 0.05) { n, _ in
                n.geometry?.firstMaterial?.emission.contents = UIColor.white
            },
            .customAction(duration: 0.15) { n, _ in
                n.geometry?.firstMaterial?.emission.contents = UIColor.black
            }
        ]))
    }

    private func killTank(_ t: Tank) {
        guard t.alive else { return }
        t.alive = false
        explode(at: t.x, t.z, big: false)
        t.node.removeFromParent()
        score += 120
        onScoreChanged?(score)
        onTanksChanged?(tanks.filter { $0.alive }.count)
    }

    // MARK: - Shells
    private func fireShell(from t: Tank) {
        let dx = droneX - t.x, dz = droneZ - t.z
        let len = max(1, sqrt(dx * dx + dz * dz))
        let nx = dx / len, nz = dz / len

        let shellGeo = SCNSphere(radius: 0.4)
        shellGeo.firstMaterial?.diffuse.contents = UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
        shellGeo.firstMaterial?.emission.contents = UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 0.8)
        let node = SCNNode(geometry: shellGeo)
        node.position = SCNVector3(t.x, 2, t.z)
        worldNode.addChildNode(node)

        shells.append(Shell(node: node, x: t.x, z: t.z, vx: nx * shellSpeed, vz: nz * shellSpeed))
    }

    private func playerHit() {
        guard invuln <= 0 else { return }
        lives -= 1
        hitFlash = 0.3
        shake = max(shake, 0.5)
        invuln = 1.4
        onLivesChanged?(lives)
        onFlash?(hitFlash)
        if lives <= 0 { showOver() }
    }

    // MARK: - State
    func showMenu() {
        state = .menu
        clearEntities()
        onStateChanged?(.menu)
    }

    private func showOver() {
        state = .over
        onStateChanged?(.over)
    }

    func startGame() {
        clearEntities()
        score = 0; wave = 0; lives = 4
        droneX = 0; droneZ = 0; vx = 0; vz = 0
        bombReady = true; bombCooldown = 0
        hitFlash = 0; shake = 0; invuln = 1.4
        lastTime = 0
        state = .playing
        onStateChanged?(.playing)
        onScoreChanged?(0)
        onLivesChanged?(4)
        onBombStateChanged?(true, 0)
        spawnWave(1)
    }

    private func clearEntities() {
        for t in tanks { t.node.removeFromParent() }
        for s in shells { s.node.removeFromParent() }
        tanks.removeAll(); shells.removeAll(); bombs.removeAll()
        impactNode.isHidden = true
    }

    // MARK: - Update
    func update(_ currentTime: TimeInterval) {
        if lastTime == 0 { lastTime = currentTime }
        var dt = Float(currentTime - lastTime)
        lastTime = currentTime
        if dt > 1.0 / 20 { dt = 1.0 / 20 }
        if dt < 0 { dt = 0 }

        guard state == .playing else { return }

        let k = min(1, 8 * dt)
        vx += (Float(joyVec.dx) * droneSpeed - vx) * k
        vz += (Float(joyVec.dy) * droneSpeed - vz) * k
        droneX = clamp(droneX + vx * dt, -fieldHalf, fieldHalf)
        droneZ = clamp(droneZ + vz * dt, -fieldHalf, fieldHalf)

        if bombCooldown > 0 {
            bombCooldown -= dt
            if bombCooldown <= 0 {
                bombReady = true
                onBombStateChanged?(true, 0)
            } else {
                onBombStateChanged?(false, bombCooldown)
            }
        }
        if hitFlash > 0 { hitFlash -= dt; onFlash?(hitFlash) }
        if shake > 0 { shake -= dt }
        if invuln > 0 { invuln -= dt }

        updateTanks(dt)
        updateShells(dt)
        updateBombs(dt)

        tanks = tanks.filter { $0.alive }
        if tanks.isEmpty {
            score += 60 * max(1, wave)
            onScoreChanged?(score)
            spawnWave(wave + 1)
        }

        var sx: Float = 0, sz: Float = 0
        if shake > 0 {
            sx = Float.random(in: -1...1) * shake * 1.6
            sz = Float.random(in: -1...1) * shake * 1.6
        }
        cameraNode.position = SCNVector3(droneX + sx, droneHeight, droneZ + sz)

        impactNode.isHidden = !bombReady
        if bombReady {
            let aim = aimPoint()
            impactNode.position = SCNVector3(aim.x, 0.05, aim.z)
        }

        let speed = sqrt(vx * vx + vz * vz)
        onSpeedChanged?(speed)
    }

    private func updateTanks(_ dt: Float) {
        for t in tanks where t.alive {
            t.turnCd -= dt
            if t.turnCd <= 0 {
                t.heading += Float.random(in: -0.8...0.8)
                t.turnCd = Float.random(in: 1.5...4)
            }
            let speed: Float = 5.5
            let fx = -sin(t.heading), fz = cos(t.heading)
            var nx = t.x + fx * speed * dt
            var nz = t.z + fz * speed * dt
            if abs(nx) > fieldHalf - 5 || abs(nz) > fieldHalf - 5 {
                t.heading += .pi
                nx = clamp(nx, -fieldHalf + 5, fieldHalf - 5)
                nz = clamp(nz, -fieldHalf + 5, fieldHalf - 5)
            }
            t.x = nx; t.z = nz
            t.node.position = SCNVector3(nx, 0, nz)
            t.node.eulerAngles = SCNVector3(0, t.heading, 0)

            t.fireCd -= dt
            if t.fireCd <= 0 && dist(t.x, t.z, droneX, droneZ) < 88 {
                fireShell(from: t)
                t.fireCd = Float.random(in: 2.2...3.8)
            }
        }
    }

    private func updateShells(_ dt: Float) {
        for s in shells {
            s.x += s.vx * dt; s.z += s.vz * dt; s.life -= dt
            s.node.position = SCNVector3(s.x, 2, s.z)
            if dist(s.x, s.z, droneX, droneZ) < 3 {
                s.alive = false
                explode(at: s.x, s.z, big: false)
                playerHit()
            } else if s.life <= 0 || abs(s.x) > fieldHalf + 10 || abs(s.z) > fieldHalf + 10 {
                s.alive = false
            }
        }
        for s in shells where !s.alive { s.node.removeFromParent() }
        shells = shells.filter { $0.alive }
    }

    private func updateBombs(_ dt: Float) {
        var remaining: [Bomb] = []
        for b in bombs {
            b.timer -= dt
            if b.timer <= 0 {
                explode(at: b.x, b.z, big: true)
            } else {
                remaining.append(b)
            }
        }
        bombs = remaining
    }

    // MARK: - Helpers
    private func dist(_ ax: Float, _ az: Float, _ bx: Float, _ bz: Float) -> Float {
        sqrt((ax - bx) * (ax - bx) + (az - bz) * (az - bz))
    }

    private func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
        max(lo, min(hi, v))
    }
}
