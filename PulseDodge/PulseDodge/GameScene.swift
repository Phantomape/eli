import SpriteKit
import UIKit

final class GameScene: SKScene, SKPhysicsContactDelegate {
    private enum PlayState {
        case ready
        case running
        case gameOver
    }

    private enum Category {
        static let player: UInt32 = 1 << 0
        static let obstacle: UInt32 = 1 << 1
        static let spark: UInt32 = 1 << 2
    }

    private enum Palette {
        static let background = UIColor(red: 0.02, green: 0.035, blue: 0.055, alpha: 1)
        static let cyan = UIColor(red: 0.10, green: 0.90, blue: 0.95, alpha: 1)
        static let yellow = UIColor(red: 1.00, green: 0.82, blue: 0.24, alpha: 1)
        static let orange = UIColor(red: 1.00, green: 0.35, blue: 0.18, alpha: 1)
        static let red = UIColor(red: 0.94, green: 0.12, blue: 0.22, alpha: 1)
        static let text = UIColor(white: 0.96, alpha: 1)
        static let mutedText = UIColor(white: 0.80, alpha: 1)
    }

    private let backgroundNode = SKNode()
    private let worldNode = SKNode()
    private let hudNode = SKNode()
    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let highScoreLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let messageLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let subMessageLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")

    private var player: SKShapeNode?
    private var playState: PlayState = .ready
    private var hasConfiguredScene = false
    private var lastUpdateTime: TimeInterval = 0
    private var nextObstacleTime: TimeInterval = 0
    private var nextSparkTime: TimeInterval = 0
    private var score: Double = 0
    private var displayedScore = -1
    private var highScore = UserDefaults.standard.integer(forKey: "PulseDodgeHighScore")

    override func didMove(to view: SKView) {
        guard !hasConfiguredScene else { return }
        hasConfiguredScene = true

        backgroundColor = Palette.background
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        addChild(backgroundNode)
        addChild(worldNode)
        addChild(hudNode)

        configureHUD()
        resetToReady()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard size.width > 0, size.height > 0 else { return }

        if backgroundNode.children.isEmpty {
            seedBackground()
        }

        layoutHUD()

        if let player {
            player.position = clampedPlayerPoint(player.position)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        guard playState == .running else {
            lastUpdateTime = currentTime
            return
        }

        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }

        let delta = min(currentTime - lastUpdateTime, 1.0 / 20.0)
        lastUpdateTime = currentTime

        score += delta * 9.0
        updateScoreLabels()

        if currentTime >= nextObstacleTime {
            spawnObstacle()
            let difficulty = min(score / 550.0, 1.0)
            nextObstacleTime = currentTime + Double(CGFloat.random(in: 0.58...0.92) - CGFloat(difficulty) * 0.24)
        }

        if currentTime >= nextSparkTime {
            spawnSpark()
            nextSparkTime = currentTime + Double(CGFloat.random(in: 1.15...1.85))
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        switch playState {
        case .ready:
            startGame()
            movePlayer(to: location)
        case .running:
            movePlayer(to: location)
        case .gameOver:
            resetToReady()
            startGame()
            movePlayer(to: location)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard playState == .running, let touch = touches.first else { return }
        movePlayer(to: touch.location(in: self))
    }

    func didBegin(_ contact: SKPhysicsContact) {
        guard playState == .running else { return }

        let mask = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if mask == (Category.player | Category.obstacle) {
            endGame()
            return
        }

        if mask == (Category.player | Category.spark) {
            let sparkNode = contact.bodyA.categoryBitMask == Category.spark ? contact.bodyA.node : contact.bodyB.node
            collectSpark(sparkNode)
        }
    }

    private func configureHUD() {
        hudNode.zPosition = 100

        scoreLabel.fontSize = 34
        scoreLabel.fontColor = Palette.text
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.verticalAlignmentMode = .center
        hudNode.addChild(scoreLabel)

        highScoreLabel.fontSize = 14
        highScoreLabel.fontColor = Palette.mutedText
        highScoreLabel.horizontalAlignmentMode = .center
        highScoreLabel.verticalAlignmentMode = .center
        hudNode.addChild(highScoreLabel)

        messageLabel.fontSize = 42
        messageLabel.fontColor = Palette.text
        messageLabel.horizontalAlignmentMode = .center
        messageLabel.verticalAlignmentMode = .center
        hudNode.addChild(messageLabel)

        subMessageLabel.fontSize = 17
        subMessageLabel.fontColor = Palette.mutedText
        subMessageLabel.horizontalAlignmentMode = .center
        subMessageLabel.verticalAlignmentMode = .center
        hudNode.addChild(subMessageLabel)
    }

    private func layoutHUD() {
        let topInset = view?.safeAreaInsets.top ?? 0
        let scoreY = size.height - max(54, topInset + 34)

        scoreLabel.position = CGPoint(x: size.width / 2, y: scoreY)
        highScoreLabel.position = CGPoint(x: size.width / 2, y: scoreY - 32)
        messageLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.57)
        subMessageLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.57 - 48)

        let compactWidth = size.width < 360
        messageLabel.fontSize = compactWidth ? 34 : 42
        subMessageLabel.fontSize = compactWidth ? 15 : 17
    }

    private func seedBackground() {
        backgroundNode.removeAllChildren()

        let starCount = max(44, Int(size.height / 12))
        for _ in 0..<starCount {
            let radius = CGFloat.random(in: 0.8...2.2)
            let star = SKShapeNode(circleOfRadius: radius)
            star.fillColor = UIColor(white: 1, alpha: CGFloat.random(in: 0.22...0.55))
            star.strokeColor = .clear
            star.position = CGPoint(
                x: CGFloat.random(in: 0...max(size.width, 1)),
                y: CGFloat.random(in: 0...max(size.height, 1))
            )
            star.zPosition = -10
            backgroundNode.addChild(star)

            let duration = TimeInterval(CGFloat.random(in: 8.0...18.0))
            let reset = SKAction.run { [weak self, weak star] in
                guard let self, let star else { return }
                star.position = CGPoint(
                    x: CGFloat.random(in: 0...max(self.size.width, 1)),
                    y: self.size.height + 12
                )
            }
            star.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: -size.height - 24, duration: duration),
                reset
            ])))
        }
    }

    private func resetToReady() {
        worldNode.isPaused = false
        worldNode.removeAllChildren()

        playState = .ready
        lastUpdateTime = 0
        nextObstacleTime = 0
        nextSparkTime = 0
        score = 0
        displayedScore = -1

        addPlayer()
        updateScoreLabels(force: true)
        showMessage(title: "PULSE DODGE", subtitle: "TOUCH TO START")
    }

    private func startGame() {
        playState = .running
        lastUpdateTime = 0
        nextObstacleTime = 0
        nextSparkTime = 0.75
        hideMessage()
    }

    private func endGame() {
        playState = .gameOver
        worldNode.children.forEach { $0.removeAllActions() }

        let finalScore = Int(score)
        if finalScore > highScore {
            highScore = finalScore
            UserDefaults.standard.set(highScore, forKey: "PulseDodgeHighScore")
        }

        updateScoreLabels(force: true)
        showMessage(title: "GAME OVER", subtitle: "TOUCH TO RETRY")
        UINotificationFeedbackGenerator().notificationOccurred(.error)

        player?.run(.sequence([
            .group([
                .scale(to: 1.6, duration: 0.12),
                .fadeAlpha(to: 0.45, duration: 0.12)
            ]),
            .group([
                .scale(to: 1.0, duration: 0.18),
                .fadeAlpha(to: 1.0, duration: 0.18)
            ])
        ]))
    }

    private func addPlayer() {
        let radius: CGFloat = size.width < 360 ? 17 : 20
        let node = SKShapeNode(circleOfRadius: radius)
        node.name = "player"
        node.fillColor = Palette.cyan
        node.strokeColor = UIColor.white.withAlphaComponent(0.9)
        node.lineWidth = 3
        node.glowWidth = 9
        node.zPosition = 20

        let body = SKPhysicsBody(circleOfRadius: radius)
        body.categoryBitMask = Category.player
        body.contactTestBitMask = Category.obstacle | Category.spark
        body.collisionBitMask = 0
        body.affectedByGravity = false
        body.allowsRotation = false
        node.physicsBody = body

        node.position = CGPoint(x: max(size.width, 1) / 2, y: max(size.height * 0.18, 90))
        player = node
        worldNode.addChild(node)

        let pulse = SKAction.sequence([
            .scale(to: 1.08, duration: 0.55),
            .scale(to: 1.0, duration: 0.55)
        ])
        node.run(.repeatForever(pulse))
    }

    private func movePlayer(to point: CGPoint) {
        guard let player else { return }
        let target = clampedPlayerPoint(point)
        player.removeAction(forKey: "move")
        player.run(.move(to: target, duration: 0.07), withKey: "move")
    }

    private func clampedPlayerPoint(_ point: CGPoint) -> CGPoint {
        let bottomInset = view?.safeAreaInsets.bottom ?? 0
        let radius = max(player?.frame.width ?? 40, 40) / 2
        let minX = radius + 12
        let maxX = max(minX, size.width - radius - 12)
        let minY = max(radius + 16 + bottomInset, 70)
        let maxY = max(minY, size.height * 0.62)

        return CGPoint(
            x: clamped(point.x, lower: minX, upper: maxX),
            y: clamped(point.y, lower: minY, upper: maxY)
        )
    }

    private func spawnObstacle() {
        guard size.width > 0, size.height > 0 else { return }

        let difficulty = CGFloat(min(score / 600.0, 1.0))
        let side = CGFloat.random(in: 30...62)
        let node = SKShapeNode(rectOf: CGSize(width: side, height: side), cornerRadius: side * 0.22)
        node.name = "obstacle"
        node.fillColor = Bool.random() ? Palette.red : Palette.orange
        node.strokeColor = UIColor.white.withAlphaComponent(0.18)
        node.lineWidth = 2
        node.glowWidth = 4
        node.zPosition = 12

        let minX = side / 2 + 12
        let maxX = max(minX, size.width - side / 2 - 12)
        node.position = CGPoint(x: CGFloat.random(in: minX...maxX), y: size.height + side)

        let body = SKPhysicsBody(rectangleOf: CGSize(width: side * 0.82, height: side * 0.82))
        body.categoryBitMask = Category.obstacle
        body.contactTestBitMask = Category.player
        body.collisionBitMask = 0
        body.affectedByGravity = false
        node.physicsBody = body

        worldNode.addChild(node)

        let drift = CGFloat.random(in: -38...38)
        let duration = TimeInterval(CGFloat.random(in: 2.65...3.45) - difficulty * 0.85)
        let fallDistance = size.height + side + 96
        node.run(.sequence([
            .group([
                .moveBy(x: drift, y: -fallDistance, duration: max(1.65, duration)),
                .rotate(byAngle: CGFloat.random(in: -3.6...3.6), duration: max(1.65, duration))
            ]),
            .removeFromParent()
        ]))
    }

    private func spawnSpark() {
        guard size.width > 0, size.height > 0 else { return }

        let radius: CGFloat = 15
        let node = SKShapeNode(path: diamondPath(radius: radius))
        node.name = "spark"
        node.fillColor = Palette.yellow
        node.strokeColor = UIColor.white.withAlphaComponent(0.9)
        node.lineWidth = 2
        node.glowWidth = 7
        node.zPosition = 14

        let minX = radius + 16
        let maxX = max(minX, size.width - radius - 16)
        node.position = CGPoint(x: CGFloat.random(in: minX...maxX), y: size.height + radius)

        let body = SKPhysicsBody(circleOfRadius: radius)
        body.categoryBitMask = Category.spark
        body.contactTestBitMask = Category.player
        body.collisionBitMask = 0
        body.affectedByGravity = false
        node.physicsBody = body

        worldNode.addChild(node)

        let duration = TimeInterval(CGFloat.random(in: 3.35...4.6))
        node.run(.repeatForever(.rotate(byAngle: .pi, duration: 0.9)))
        node.run(.sequence([
            .moveBy(x: CGFloat.random(in: -24...24), y: -size.height - 80, duration: duration),
            .removeFromParent()
        ]), withKey: "fall")
    }

    private func collectSpark(_ node: SKNode?) {
        guard let node, node.name == "spark" else { return }
        node.name = "spark-collected"
        node.physicsBody = nil
        node.removeAllActions()
        score += 28
        updateScoreLabels(force: true)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        showPoints(at: node.position)
        node.run(.sequence([
            .group([
                .scale(to: 2.2, duration: 0.16),
                .fadeOut(withDuration: 0.16)
            ]),
            .removeFromParent()
        ]))
    }

    private func showPoints(at point: CGPoint) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = "+28"
        label.fontSize = 20
        label.fontColor = Palette.yellow
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = point
        label.zPosition = 60
        worldNode.addChild(label)

        label.run(.sequence([
            .group([
                .moveBy(x: 0, y: 34, duration: 0.35),
                .fadeOut(withDuration: 0.35)
            ]),
            .removeFromParent()
        ]))
    }

    private func updateScoreLabels(force: Bool = false) {
        let rounded = Int(score)
        guard force || rounded != displayedScore else { return }
        displayedScore = rounded
        scoreLabel.text = "\(rounded)"
        highScoreLabel.text = "BEST \(max(highScore, rounded))"
    }

    private func showMessage(title: String, subtitle: String) {
        messageLabel.text = title
        subMessageLabel.text = subtitle
        messageLabel.isHidden = false
        subMessageLabel.isHidden = false
        messageLabel.alpha = 0
        subMessageLabel.alpha = 0
        messageLabel.run(.fadeIn(withDuration: 0.18))
        subMessageLabel.run(.fadeIn(withDuration: 0.18))
        layoutHUD()
    }

    private func hideMessage() {
        messageLabel.removeAllActions()
        subMessageLabel.removeAllActions()
        messageLabel.isHidden = true
        subMessageLabel.isHidden = true
    }

    private func diamondPath(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: radius))
        path.addLine(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -radius))
        path.addLine(to: CGPoint(x: -radius, y: 0))
        path.closeSubpath()
        return path
    }

    private func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
