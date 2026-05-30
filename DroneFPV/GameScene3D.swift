import SceneKit
import UIKit

final class GameScene3D: SCNScene {

    // MARK: - Tunables
    private let fieldHalf: Float = 140
    private let droneSpeed: Float = 34
    private let droneHeight: Float = 12
    private let bombReload: Float = 1.1
    private let bombFuse: Float = 0.48
    private let bombBlast: Float = 13
    private let shellSpeed: Float = 52
    private let neon = UIColor(red: 0.47, green: 0.90, blue: 0.63, alpha: 1)

    // MARK: - State
    enum GState { case menu, playing, paused, over }
    private var state: GState = .menu

    private var droneX: Float = 0
    private var droneZ: Float = 0
    private var vx: Float = 0
    private var vz: Float = 0

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
        let barNode: SCNNode
        var x: Float
        var z: Float
        var heading: Float = 0
        var turnCd: Float = 0
        var fireCd: Float = 0
        var hp: Int
        let maxHp: Int
        let speed: Float
        var alive = true

        init(node: SCNNode, barNode: SCNNode, x: Float, z: Float, hp: Int, speed: Float) {
            self.node = node
            self.barNode = barNode
            self.x = x
            self.z = z
            self.hp = hp
            self.maxHp = hp
            self.speed = speed
        }
    }

    private final class Shell {
        let node: SCNNode
        var x: Float
        var z: Float
        var vx: Float
        var vz: Float
        var life: Float = 2.6
        var alive = true

        init(node: SCNNode, x: Float, z: Float, vx: Float, vz: Float) {
            self.node = node
            self.x = x
            self.z = z
            self.vx = vx
            self.vz = vz
        }
    }

    private final class Bomb {
        let node: SCNNode
        let x: Float
        let z: Float
        var timer: Float

        init(node: SCNNode, x: Float, z: Float, timer: Float) {
            self.node = node
            self.x = x
            self.z = z
            self.timer = timer
        }
    }

    private var tanks: [Tank] = []
    private var shells: [Shell] = []
    private var bombs: [Bomb] = []

    // MARK: - Nodes
    private var cameraNode: SCNNode!
    private var worldNode: SCNNode!
    private var impactNode: SCNNode!
    private var droneShadowNode: SCNNode!

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
    var onFlash: ((Float) -> Void)?
    var onMessage: ((String) -> Void)?
    var onPlayerHit: (() -> Void)?

    func getState() -> GState { state }

    // MARK: - Init
    override init() {
        super.init()
        buildWorld()
        buildCamera()
        buildLighting()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Build
    private func buildWorld() {
        background.contents = UIColor(red: 0.06, green: 0.08, blue: 0.09, alpha: 1)
        fogColor = UIColor(red: 0.06, green: 0.09, blue: 0.08, alpha: 1)
        fogStartDistance = 90
        fogEndDistance = 250

        worldNode = SCNNode()
        rootNode.addChildNode(worldNode)

        let groundGeo = SCNPlane(width: CGFloat(fieldHalf * 2 + 40), height: CGFloat(fieldHalf * 2 + 40))
        groundGeo.materials = [material(diffuse: UIColor(red: 0.10, green: 0.16, blue: 0.11, alpha: 1), specular: .black)]
        let ground = SCNNode(geometry: groundGeo)
        ground.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        worldNode.addChildNode(ground)

        for i in stride(from: -fieldHalf, through: fieldHalf, by: 12) {
            addGridLine(from: SCNVector3(i, 0.01, -fieldHalf), to: SCNVector3(i, 0.01, fieldHalf))
            addGridLine(from: SCNVector3(-fieldHalf, 0.01, i), to: SCNVector3(fieldHalf, 0.01, i))
        }

        let borderColor = UIColor(red: 0.8, green: 0.3, blue: 0.25, alpha: 0.8)
        addBorderLine(from: SCNVector3(-fieldHalf, 0.02, -fieldHalf), to: SCNVector3(fieldHalf, 0.02, -fieldHalf), color: borderColor)
        addBorderLine(from: SCNVector3(fieldHalf, 0.02, -fieldHalf), to: SCNVector3(fieldHalf, 0.02, fieldHalf), color: borderColor)
        addBorderLine(from: SCNVector3(fieldHalf, 0.02, fieldHalf), to: SCNVector3(-fieldHalf, 0.02, fieldHalf), color: borderColor)
        addBorderLine(from: SCNVector3(-fieldHalf, 0.02, fieldHalf), to: SCNVector3(-fieldHalf, 0.02, -fieldHalf), color: borderColor)

        buildScenery()
        buildTargetingNodes()
    }

    private func buildTargetingNodes() {
        let shadowGeo = SCNTorus(ringRadius: 2.3, pipeRadius: 0.08)
        shadowGeo.materials = [material(diffuse: UIColor.black.withAlphaComponent(0.38))]
        droneShadowNode = SCNNode(geometry: shadowGeo)
        droneShadowNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        droneShadowNode.isHidden = true
        worldNode.addChildNode(droneShadowNode)

        let impactGeo = SCNTorus(ringRadius: 2.6, pipeRadius: 0.15)
        impactGeo.materials = [material(
            diffuse: UIColor(red: 1, green: 0.4, blue: 0.35, alpha: 0.9),
            emission: UIColor(red: 1, green: 0.4, blue: 0.35, alpha: 0.6)
        )]
        impactNode = SCNNode(geometry: impactGeo)
        impactNode.position = SCNVector3(0, 0.05, 0)
        impactNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        impactNode.isHidden = true
        impactNode.runAction(.repeatForever(.rotateBy(x: 0, y: 0, z: CGFloat.pi * 2, duration: 2.2)))
        worldNode.addChildNode(impactNode)
    }

    private func buildScenery() {
        for i in 0..<44 {
            let point = randomFieldPoint(minDistanceFromCenter: 18)
            let node: SCNNode

            switch i % 4 {
            case 0:
                node = makeRockNode()
            case 1:
                node = makeCrateClusterNode()
            case 2:
                node = makeAntennaNode()
            default:
                node = makeBermNode()
            }

            node.position = SCNVector3(point.x, 0, point.z)
            node.eulerAngles.y = Float.random(in: 0...(2 * .pi))
            worldNode.addChildNode(node)
        }
    }

    private func randomFieldPoint(minDistanceFromCenter: Float) -> (x: Float, z: Float) {
        var px: Float = 0
        var pz: Float = 0

        repeat {
            px = Float.random(in: (-fieldHalf + 10)...(fieldHalf - 10))
            pz = Float.random(in: (-fieldHalf + 10)...(fieldHalf - 10))
        } while dist(px, pz, 0, 0) < minDistanceFromCenter

        return (px, pz)
    }

    private func makeRockNode() -> SCNNode {
        let geo = SCNSphere(radius: CGFloat(Float.random(in: 1.1...2.4)))
        geo.segmentCount = 8
        geo.materials = [material(diffuse: UIColor(red: 0.22, green: 0.24, blue: 0.21, alpha: 1), specular: UIColor(white: 0.08, alpha: 1))]

        let node = SCNNode(geometry: geo)
        node.scale = SCNVector3(Float.random(in: 1.1...2.2), Float.random(in: 0.22...0.45), Float.random(in: 0.9...1.8))
        node.position.y = 0.25
        return node
    }

    private func makeCrateClusterNode() -> SCNNode {
        let root = SCNNode()
        let colors = [
            UIColor(red: 0.20, green: 0.25, blue: 0.19, alpha: 1),
            UIColor(red: 0.25, green: 0.22, blue: 0.16, alpha: 1),
            UIColor(red: 0.16, green: 0.23, blue: 0.25, alpha: 1)
        ]

        for i in 0..<3 {
            let box = SCNBox(width: CGFloat(Float.random(in: 2.2...3.6)), height: CGFloat(Float.random(in: 1.2...2.2)), length: CGFloat(Float.random(in: 2.0...3.4)), chamferRadius: 0.12)
            box.materials = [material(diffuse: colors[i % colors.count], specular: UIColor(white: 0.08, alpha: 1))]
            let child = SCNNode(geometry: box)
            child.position = SCNVector3(Float(i - 1) * Float.random(in: 1.8...2.4), Float.random(in: 0.7...1.1), Float.random(in: -1.6...1.6))
            child.eulerAngles.y = Float.random(in: -0.4...0.4)
            root.addChildNode(child)
        }

        return root
    }

    private func makeAntennaNode() -> SCNNode {
        let root = SCNNode()

        let mast = SCNCylinder(radius: 0.18, height: CGFloat(Float.random(in: 7.0...11.0)))
        mast.materials = [material(diffuse: UIColor(red: 0.20, green: 0.24, blue: 0.23, alpha: 1), emission: UIColor(red: 0.05, green: 0.12, blue: 0.09, alpha: 1))]
        let mastNode = SCNNode(geometry: mast)
        mastNode.position.y = Float(mast.height) / 2
        root.addChildNode(mastNode)

        let dish = SCNTorus(ringRadius: 1.2, pipeRadius: 0.08)
        dish.materials = [material(diffuse: neon.withAlphaComponent(0.8), emission: neon.withAlphaComponent(0.35))]
        let dishNode = SCNNode(geometry: dish)
        dishNode.position = SCNVector3(0.4, Float(mast.height) - 1.4, 0)
        dishNode.eulerAngles = SCNVector3(Float.pi / 2, 0.25, 0)
        root.addChildNode(dishNode)

        return root
    }

    private func makeBermNode() -> SCNNode {
        let geo = SCNBox(width: CGFloat(Float.random(in: 5.0...9.0)), height: CGFloat(Float.random(in: 0.7...1.2)), length: CGFloat(Float.random(in: 1.0...1.8)), chamferRadius: 0.35)
        geo.materials = [material(diffuse: UIColor(red: 0.14, green: 0.21, blue: 0.12, alpha: 1), specular: UIColor(white: 0.06, alpha: 1))]
        let node = SCNNode(geometry: geo)
        node.position.y = 0.35
        return node
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
        cyl.materials = [material(diffuse: color, emission: color.withAlphaComponent(0.3))]

        let node = SCNNode(geometry: cyl)
        node.position = SCNVector3((from.x + to.x) / 2, (from.y + to.y) / 2, (from.z + to.z) / 2)
        let dy = to.y - from.y
        let dxz = sqrt((to.x - from.x) * (to.x - from.x) + (to.z - from.z) * (to.z - from.z))
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
        cameraNode.eulerAngles = SCNVector3(-Float.pi / 6, 0, 0)
        rootNode.addChildNode(cameraNode)
    }

    private func buildLighting() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(white: 0.42, alpha: 1)
        rootNode.addChildNode(ambient)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.color = UIColor(white: 0.78, alpha: 1)
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

        for side in [-1, 1] {
            let track = SCNBox(width: 4.6, height: 0.8, length: 1.2, chamferRadius: 0.3)
            track.materials = [material(diffuse: darkColor)]
            let trackNode = SCNNode(geometry: track)
            trackNode.position = SCNVector3(0, 0.4, Float(side) * 1.5)
            root.addChildNode(trackNode)
        }

        let body = SCNBox(width: 4.2, height: 1.5, length: 3.0, chamferRadius: 0.4)
        body.materials = [material(diffuse: bodyColor, specular: UIColor(white: 0.2, alpha: 1))]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 1.15, 0)
        root.addChildNode(bodyNode)

        let turret = SCNCylinder(radius: 1.1, height: 0.9)
        turret.materials = [material(diffuse: bodyColor, specular: UIColor(white: 0.2, alpha: 1))]
        let turretNode = SCNNode(geometry: turret)
        turretNode.position = SCNVector3(0, 2.15, 0)
        root.addChildNode(turretNode)

        let barrel = SCNCylinder(radius: 0.25, height: 2.4)
        barrel.materials = [material(diffuse: darkColor)]
        let barrelNode = SCNNode(geometry: barrel)
        barrelNode.position = SCNVector3(1.7, 2.15, 0)
        barrelNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        root.addChildNode(barrelNode)

        return root
    }

    private func makeHPBar() -> SCNNode {
        let bar = SCNBox(width: 4.0, height: 0.5, length: 0.1, chamferRadius: 0.1)
        bar.materials = [material(diffuse: neon, emission: neon.withAlphaComponent(0.5))]
        let node = SCNNode(geometry: bar)
        node.position = SCNVector3(0, 3.5, 0)
        return node
    }

    // MARK: - Waves
    private func spawnWave(_ n: Int) {
        wave = n
        let count = min(13, 3 + n)
        let hp = min(5, 1 + n / 3)
        let hues: [CGFloat] = [0.28, 0.09, 0.55, 0.0, 0.78]

        for _ in 0..<count {
            var px: Float = 0
            var pz: Float = 0
            var tries = 0

            repeat {
                px = Float.random(in: (-fieldHalf + 14)...(fieldHalf - 14))
                pz = Float.random(in: (-fieldHalf + 14)...(fieldHalf - 14))
                tries += 1
            } while (dist(px, pz, droneX, droneZ) < 42 || tanks.contains { dist(px, pz, $0.x, $0.z) < 15 }) && tries < 60

            let node = makeTankNode(hues[Int.random(in: 0..<hues.count)])
            node.position = SCNVector3(px, 0, pz)
            worldNode.addChildNode(node)

            let barNode = makeHPBar()
            barNode.isHidden = hp <= 1
            node.addChildNode(barNode)

            let speed = Float.random(in: 4.4...6.4) + min(Float(n) * 0.16, 2.2)
            let tank = Tank(node: node, barNode: barNode, x: px, z: pz, hp: hp, speed: speed)
            tank.heading = Float.random(in: 0...(2 * .pi))
            tank.fireCd = Float.random(in: 1.4...3.4)
            tank.turnCd = Float.random(in: 1...3)
            tanks.append(tank)
        }

        onWaveChanged?(wave)
        onTanksChanged?(tanks.count)
        onMessage?("ВОЛНА \(n)")
    }

    // MARK: - Bombs
    @discardableResult
    func dropBomb() -> Bool {
        guard state == .playing, bombReady else { return false }
        bombReady = false
        bombCooldown = bombReload

        let aim = aimPoint()
        let node = makeBombNode()
        node.position = SCNVector3(aim.x, droneHeight - 1.5, aim.z)
        worldNode.addChildNode(node)
        bombs.append(Bomb(node: node, x: aim.x, z: aim.z, timer: bombFuse))

        onBombStateChanged?(false, bombCooldown)
        return true
    }

    private func makeBombNode() -> SCNNode {
        let geo = SCNSphere(radius: 0.65)
        geo.segmentCount = 12
        geo.materials = [material(diffuse: UIColor(red: 0.12, green: 0.13, blue: 0.12, alpha: 1), emission: UIColor(red: 0.55, green: 0.12, blue: 0.08, alpha: 0.35))]

        let node = SCNNode(geometry: geo)
        node.scale = SCNVector3(0.75, 1.35, 0.75)
        return node
    }

    private func aimPoint() -> (x: Float, z: Float) {
        let ax = clamp(droneX + vx * 0.35, -fieldHalf, fieldHalf)
        let az = clamp(droneZ + vz * 0.35, -fieldHalf, fieldHalf)
        return (ax, az)
    }

    private func explode(at x: Float, _ z: Float, big: Bool) {
        let ringGeo = SCNTorus(ringRadius: big ? 8 : 3, pipeRadius: 0.3)
        let ringColor = big ? UIColor.orange : UIColor.yellow
        ringGeo.materials = [material(diffuse: ringColor, emission: ringColor)]
        let ring = SCNNode(geometry: ringGeo)
        ring.position = SCNVector3(x, 0.5, z)
        ring.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        worldNode.addChildNode(ring)
        ring.runAction(.sequence([
            .group([
                .scale(to: big ? 3 : 2, duration: big ? 0.45 : 0.3),
                .fadeOut(duration: big ? 0.45 : 0.3)
            ]),
            .run { node in node.removeFromParentNode() }
        ]))

        let flashGeo = SCNSphere(radius: big ? 4.4 : 1.8)
        flashGeo.segmentCount = 12
        flashGeo.materials = [material(
            diffuse: UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 0.9),
            emission: UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1)
        )]
        let flash = SCNNode(geometry: flashGeo)
        flash.position = SCNVector3(x, 1, z)
        worldNode.addChildNode(flash)
        flash.runAction(.sequence([.fadeOut(duration: 0.25), .run { node in node.removeFromParentNode() }]))

        if big {
            shake = max(shake, 0.45)
            for tank in tanks where tank.alive {
                let d = dist(tank.x, tank.z, x, z)
                if d < bombBlast {
                    killTank(tank)
                } else if d < bombBlast * 1.6 {
                    damageTank(tank)
                }
            }
        }
    }

    private func damageTank(_ tank: Tank) {
        tank.hp -= 1
        if tank.hp <= 0 {
            killTank(tank)
            return
        }

        tank.barNode.scale = SCNVector3(max(0.08, Float(tank.hp) / Float(tank.maxHp)), 1, 1)

        let barNode = tank.barNode
        tank.node.runAction(.sequence([
            .run { [weak self] node in
                self?.setEmission(on: node, color: .white, skipping: barNode)
            },
            .wait(duration: 0.12),
            .run { [weak self] node in
                self?.setEmission(on: node, color: .black, skipping: barNode)
            }
        ]))
    }

    private func killTank(_ tank: Tank) {
        guard tank.alive else { return }
        tank.alive = false
        explode(at: tank.x, tank.z, big: false)
        tank.node.removeFromParentNode()
        score += 120
        onScoreChanged?(score)
        onTanksChanged?(tanks.filter { $0.alive }.count)
    }

    // MARK: - Shells
    private func fireShell(from tank: Tank) {
        let lead = min(0.52, 0.16 + Float(wave) * 0.025)
        let targetX = droneX + vx * lead
        let targetZ = droneZ + vz * lead
        let dx = targetX - tank.x
        let dz = targetZ - tank.z
        let len = max(1, sqrt(dx * dx + dz * dz))
        let nx = dx / len
        let nz = dz / len

        let shellGeo = SCNSphere(radius: 0.4)
        shellGeo.segmentCount = 12
        shellGeo.materials = [material(
            diffuse: UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1),
            emission: UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 0.8)
        )]
        let node = SCNNode(geometry: shellGeo)
        node.position = SCNVector3(tank.x, 2, tank.z)
        worldNode.addChildNode(node)

        shells.append(Shell(node: node, x: tank.x, z: tank.z, vx: nx * shellSpeed, vz: nz * shellSpeed))
    }

    private func playerHit() {
        guard invuln <= 0 else { return }
        lives -= 1
        hitFlash = 0.3
        shake = max(shake, 0.5)
        invuln = 1.4
        onLivesChanged?(lives)
        onFlash?(hitFlash)
        onPlayerHit?()

        if lives <= 0 {
            showOver()
        }
    }

    // MARK: - State
    func showMenu() {
        state = .menu
        joyVec = .zero
        clearEntities()
        droneShadowNode.isHidden = true
        onStateChanged?(.menu)
        onTanksChanged?(0)
        onSpeedChanged?(0)
        onBombStateChanged?(true, 0)
    }

    private func showOver() {
        state = .over
        joyVec = .zero
        shells.forEach { $0.node.removeFromParentNode() }
        shells.removeAll()
        onStateChanged?(.over)
        onSpeedChanged?(0)
    }

    func startGame() {
        clearEntities()
        score = 0
        wave = 0
        lives = 4
        droneX = 0
        droneZ = 0
        vx = 0
        vz = 0
        joyVec = .zero
        bombReady = true
        bombCooldown = 0
        hitFlash = 0
        shake = 0
        invuln = 1.4
        lastTime = 0
        droneShadowNode.isHidden = false
        state = .playing

        onStateChanged?(.playing)
        onScoreChanged?(0)
        onWaveChanged?(0)
        onLivesChanged?(4)
        onSpeedChanged?(0)
        onBombStateChanged?(true, 0)
        spawnWave(1)
    }

    func pauseGame() {
        guard state == .playing else { return }
        state = .paused
        joyVec = .zero
        vx = 0
        vz = 0
        onStateChanged?(.paused)
    }

    func resumeGame() {
        guard state == .paused else { return }
        lastTime = 0
        state = .playing
        onStateChanged?(.playing)
    }

    private func clearEntities() {
        tanks.forEach { $0.node.removeFromParentNode() }
        shells.forEach { $0.node.removeFromParentNode() }
        bombs.forEach { $0.node.removeFromParentNode() }
        tanks.removeAll()
        shells.removeAll()
        bombs.removeAll()
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

        if hitFlash > 0 {
            hitFlash -= dt
            onFlash?(hitFlash)
        }
        if shake > 0 { shake -= dt }
        if invuln > 0 { invuln -= dt }

        updateTanks(dt)
        updateShells(dt)
        guard state == .playing else { return }
        updateBombs(dt)

        tanks = tanks.filter { $0.alive }
        if tanks.isEmpty {
            score += 60 * max(1, wave)
            onScoreChanged?(score)
            spawnWave(wave + 1)
        }

        var sx: Float = 0
        var sz: Float = 0
        if shake > 0 {
            sx = Float.random(in: -1...1) * shake * 1.6
            sz = Float.random(in: -1...1) * shake * 1.6
        }

        let bank = clamp(-vx / droneSpeed * 0.12, -0.12, 0.12)
        let pitch = -Float.pi / 6 + clamp(abs(vz) / droneSpeed * 0.08, 0, 0.08)
        cameraNode.position = SCNVector3(droneX + sx, droneHeight, droneZ + sz)
        cameraNode.eulerAngles = SCNVector3(pitch, 0, bank)
        droneShadowNode.position = SCNVector3(droneX, 0.06, droneZ)

        impactNode.isHidden = !bombReady
        if bombReady {
            let aim = aimPoint()
            impactNode.position = SCNVector3(aim.x, 0.05, aim.z)
        }

        let speed = sqrt(vx * vx + vz * vz)
        onSpeedChanged?(speed)
    }

    private func updateTanks(_ dt: Float) {
        for tank in tanks where tank.alive {
            tank.turnCd -= dt
            if tank.turnCd <= 0 {
                tank.heading += Float.random(in: -0.8...0.8)
                tank.turnCd = Float.random(in: 1.4...3.7)
            }

            let fx = -sin(tank.heading)
            let fz = cos(tank.heading)
            var nx = tank.x + fx * tank.speed * dt
            var nz = tank.z + fz * tank.speed * dt
            if abs(nx) > fieldHalf - 5 || abs(nz) > fieldHalf - 5 {
                tank.heading += .pi
                nx = clamp(nx, -fieldHalf + 5, fieldHalf - 5)
                nz = clamp(nz, -fieldHalf + 5, fieldHalf - 5)
            }

            tank.x = nx
            tank.z = nz
            tank.node.position = SCNVector3(nx, 0, nz)
            tank.node.eulerAngles = SCNVector3(0, tank.heading, 0)

            tank.fireCd -= dt
            if tank.fireCd <= 0 && dist(tank.x, tank.z, droneX, droneZ) < 90 {
                fireShell(from: tank)
                let minCd = max(1.15, 2.25 - Float(wave) * 0.05)
                let maxCd = max(1.8, 3.85 - Float(wave) * 0.06)
                tank.fireCd = Float.random(in: minCd...maxCd)
            }
        }
    }

    private func updateShells(_ dt: Float) {
        for shell in shells {
            shell.x += shell.vx * dt
            shell.z += shell.vz * dt
            shell.life -= dt
            shell.node.position = SCNVector3(shell.x, 2, shell.z)

            if dist(shell.x, shell.z, droneX, droneZ) < 3 {
                shell.alive = false
                explode(at: shell.x, shell.z, big: false)
                playerHit()
            } else if shell.life <= 0 || abs(shell.x) > fieldHalf + 10 || abs(shell.z) > fieldHalf + 10 {
                shell.alive = false
            }
        }

        shells.filter { !$0.alive }.forEach { $0.node.removeFromParentNode() }
        shells = shells.filter { $0.alive }
    }

    private func updateBombs(_ dt: Float) {
        var remaining: [Bomb] = []

        for bomb in bombs {
            bomb.timer -= dt
            let progress = max(0, min(1, bomb.timer / bombFuse))
            bomb.node.position = SCNVector3(bomb.x, 0.7 + (droneHeight - 1.5) * progress, bomb.z)
            bomb.node.eulerAngles.y += dt * 9

            if bomb.timer <= 0 {
                bomb.node.removeFromParentNode()
                explode(at: bomb.x, bomb.z, big: true)
            } else {
                remaining.append(bomb)
            }
        }

        bombs = remaining
    }

    // MARK: - Helpers
    private func material(diffuse: UIColor, emission: UIColor? = nil, specular: UIColor = UIColor.black) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = diffuse
        material.emission.contents = emission ?? UIColor.black
        material.specular.contents = specular
        return material
    }

    private func setEmission(on node: SCNNode, color: UIColor, skipping skipped: SCNNode?) {
        guard node !== skipped else { return }
        node.geometry?.materials.forEach { $0.emission.contents = color }
        node.childNodes.forEach { setEmission(on: $0, color: color, skipping: skipped) }
    }

    private func dist(_ ax: Float, _ az: Float, _ bx: Float, _ bz: Float) -> Float {
        sqrt((ax - bx) * (ax - bx) + (az - bz) * (az - bz))
    }

    private func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
        max(lo, min(hi, v))
    }
}
