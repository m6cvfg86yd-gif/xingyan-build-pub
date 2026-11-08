import SceneKit
import UIKit

enum StarWorldUSDZScene {
    static func makeRoom(root providedRoot: SCNNode, profile: StarAvatarProfile) -> SCNScene? {
        guard let roomURL = assetURL("StarWorldRoom") else { return nil }
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.025, green: 0.065, blue: 0.085, alpha: 1)
        scene.rootNode.addChildNode(providedRoot)

        do {
            let room = try assetScene(roomURL)
            moveChildren(from: room.rootNode, to: providedRoot)
            providedRoot.childNode(withName: "SM_FloorBase", recursively: true)?.name = "room.floor"
        } catch {
            return nil
        }

        let camera = cameraNode(
            name: "world.camera",
            position: SCNVector3(1.52, 1.58, 3.05),
            target: SCNVector3(0.02, 1.08, -0.15),
            fieldOfView: 54
        )
        scene.rootNode.addChildNode(camera)

        addRoomLighting(to: providedRoot)

        if let avatar = avatarNode(profile: profile) {
            avatar.name = "player.room"
            avatar.position = SCNVector3(0.36, 0.01, -0.28)
            avatar.eulerAngles.y = .pi
            providedRoot.addChildNode(avatar)
        }

        let door = starWorldTravelDoor(
            title: "海边广场",
            nodeName: "travel.plaza",
            width: 1.12,
            height: 2.18
        )
        door.position = SCNVector3(2.04, 1.10, -2.39)
        providedRoot.addChildNode(door)
        return scene
    }

    static func makePlaza(root providedRoot: SCNNode, profile: StarAvatarProfile) -> SCNScene? {
        guard let plazaURL = assetURL("StarWorldPlaza") else { return nil }
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.035, green: 0.105, blue: 0.145, alpha: 1)
        scene.fogStartDistance = 75
        scene.fogEndDistance = 320
        scene.fogColor = UIColor(red: 0.31, green: 0.48, blue: 0.49, alpha: 1)
        scene.rootNode.addChildNode(providedRoot)

        do {
            let plaza = try assetScene(plazaURL)
            let content = SCNNode()
            moveChildren(from: plaza.rootNode, to: content)
            // The authored plaza is centered below its waterline. Raise it once for walking.
            content.position.y = 3.30
            providedRoot.addChildNode(content)
        } catch {
            return nil
        }

        addPlazaLighting(to: providedRoot)

        let hitFloor = SCNNode(geometry: SCNPlane(width: 220, height: 220))
        hitFloor.name = "plaza.ground"
        hitFloor.position.y = 0.02
        hitFloor.eulerAngles.x = -.pi / 2
        let hitMaterial = SCNMaterial()
        hitMaterial.lightingModel = .constant
        hitMaterial.diffuse.contents = UIColor.clear
        hitMaterial.transparency = 0
        hitMaterial.writesToDepthBuffer = false
        hitFloor.geometry?.materials = [hitMaterial]
        providedRoot.addChildNode(hitFloor)

        let player = avatarNode(profile: profile) ?? SCNNode()
        player.name = "world.player"
        player.position = SCNVector3(0, 0.02, -4)
        providedRoot.addChildNode(player)

        let camera = cameraNode(
            name: "world.camera",
            position: SCNVector3(0, 5.2, 11),
            target: SCNVector3(0, 1.2, -0.4),
            fieldOfView: 58
        )
        camera.eulerAngles.x = -0.32
        let cameraRig = SCNNode()
        cameraRig.name = "world.camera.rig"
        cameraRig.addChildNode(camera)
        providedRoot.addChildNode(cameraRig)
        cameraRig.constraints = [
            SCNTransformConstraint(inWorldSpace: true) { _, _ in
                let position = player.presentation.worldPosition
                var matrix = SCNMatrix4Identity
                matrix.m41 = position.x
                matrix.m42 = position.y
                matrix.m43 = position.z
                return matrix
            }
        ]

        let roomDoor = starWorldTravelDoor(
            title: "星言房间",
            nodeName: "travel.room",
            width: 2.0,
            height: 3.2
        )
        roomDoor.position = SCNVector3(0, 0.02, -31)
        providedRoot.addChildNode(roomDoor)
        return scene
    }

    private static func assetURL(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "usdz", subdirectory: "WorldAssets")
            ?? Bundle.main.url(forResource: name, withExtension: "usdz")
    }

    private static func assetScene(_ url: URL) throws -> SCNScene {
        try SCNScene(
            url: url,
            options: [
                .checkConsistency: false,
                .convertUnitsToMeters: true
            ]
        )
    }

    private static func moveChildren(from source: SCNNode, to target: SCNNode) {
        let children = source.childNodes
        for child in children {
            child.removeFromParentNode()
            target.addChildNode(child)
        }
    }

    private static func avatarNode(profile: StarAvatarProfile) -> SCNNode? {
        guard let url = assetURL("StarWorldAvatar"),
              let source = try? assetScene(url) else { return nil }
        let root = SCNNode()
        moveChildren(from: source.rootNode, to: root)
        root.name = "player.room"
        return root
    }

    private static func cameraNode(
        name: String,
        position: SCNVector3,
        target: SCNVector3,
        fieldOfView: CGFloat
    ) -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = fieldOfView
        camera.zNear = 0.04
        camera.zFar = 700
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = true
        camera.bloomIntensity = 0.22
        camera.bloomThreshold = 0.94
        camera.bloomBlurRadius = 12
        let node = SCNNode()
        node.name = name
        node.camera = camera
        node.position = position
        node.look(at: target)
        return node
    }

    private static func addRoomLighting(to root: SCNNode) {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(red: 0.35, green: 0.44, blue: 0.55, alpha: 1)
        ambient.intensity = 240
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        root.addChildNode(ambientNode)
    }

    private static func addPlazaLighting(to root: SCNNode) {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(red: 0.48, green: 0.63, blue: 0.70, alpha: 1)
        ambient.intensity = 680
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        root.addChildNode(ambientNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.color = UIColor(red: 1.0, green: 0.79, blue: 0.57, alpha: 1)
        sun.intensity = 1250
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowRadius = 4
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.orthographicScale = 72
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.90, -0.65, 0)
        root.addChildNode(sunNode)
    }
}
