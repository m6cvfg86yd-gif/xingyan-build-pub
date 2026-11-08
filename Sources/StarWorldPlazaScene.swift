import UIKit
import SceneKit

enum StarWorldMap: String, Hashable {
    case room
    case plaza

    var title: String {
        switch self {
        case .room: return Tr("星言房间")
        case .plaza: return Tr("海边广场")
        }
    }

    var subtitle: String {
        switch self {
        case .room: return Tr("我的房间 · 点击房门前往广场")
        case .plaza: return Tr("星言世界 · 300 米公共广场")
        }
    }
}

enum StarWorldPlazaScene {
    static func make(root: SCNNode, profile: StarAvatarProfile) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.035, green: 0.105, blue: 0.145, alpha: 1)
        scene.fogStartDistance = 170
        scene.fogEndDistance = 720
        scene.fogColor = UIColor(red: 0.29, green: 0.46, blue: 0.49, alpha: 1)
        scene.rootNode.addChildNode(root)

        let camera = SCNNode()
        camera.name = "world.camera"
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 58
        camera.camera?.zNear = 0.08
        camera.camera?.zFar = 1500
        camera.camera?.wantsHDR = true
        camera.camera?.wantsExposureAdaptation = true
        camera.camera?.bloomIntensity = 0.32
        camera.camera?.bloomThreshold = 0.92
        camera.camera?.bloomBlurRadius = 18
        camera.position = SCNVector3(0, 5.2, 11.0)
        camera.eulerAngles.x = -0.32

        let cameraRig = SCNNode()
        cameraRig.name = "world.camera.rig"
        cameraRig.addChildNode(camera)
        root.addChildNode(cameraRig)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(red: 0.38, green: 0.52, blue: 0.65, alpha: 1)
        ambient.intensity = 520
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        root.addChildNode(ambientNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.color = UIColor(red: 1.0, green: 0.79, blue: 0.56, alpha: 1)
        sun.intensity = 1320
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowRadius = 5
        sun.shadowColor = UIColor.black.withAlphaComponent(0.28)
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.zFar = 650
        sun.orthographicScale = 160
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.95, -0.72, 0)
        root.addChildNode(sunNode)

        let rim = SCNLight()
        rim.type = .omni
        rim.color = UIColor(red: 0.32, green: 0.90, blue: 0.84, alpha: 1)
        rim.intensity = 760
        rim.attenuationStartDistance = 18
        rim.attenuationEndDistance = 86
        let rimLightNode = SCNNode()
        rimLightNode.light = rim
        rimLightNode.position = SCNVector3(-34, 12, -12)
        root.addChildNode(rimLightNode)

        func physicalMaterial(
            _ color: UIColor,
            roughness: CGFloat,
            metalness: CGFloat = 0,
            emission: UIColor? = nil
        ) -> SCNMaterial {
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = color
            material.roughness.contents = roughness
            material.metalness.contents = metalness
            if let emission {
                material.emission.contents = emission
                material.emission.intensity = 0.8
            }
            return material
        }

        let basalt = physicalMaterial(
            UIColor(red: 0.045, green: 0.13, blue: 0.16, alpha: 1),
            roughness: 0.30,
            metalness: 0.16
        )
        let pearl = physicalMaterial(
            UIColor(red: 0.83, green: 0.84, blue: 0.79, alpha: 1),
            roughness: 0.24,
            metalness: 0.04
        )
        let bronze = physicalMaterial(
            UIColor(red: 0.76, green: 0.57, blue: 0.28, alpha: 1),
            roughness: 0.20,
            metalness: 0.90
        )
        let mint = physicalMaterial(
            UIColor(red: 0.22, green: 0.85, blue: 0.73, alpha: 1),
            roughness: 0.18,
            metalness: 0.20,
            emission: UIColor(red: 0.04, green: 0.36, blue: 0.30, alpha: 1)
        )
        let sail = physicalMaterial(
            UIColor(red: 0.91, green: 0.89, blue: 0.82, alpha: 1),
            roughness: 0.82
        )
        let water = physicalMaterial(
            UIColor(red: 0.12, green: 0.48, blue: 0.55, alpha: 0.86),
            roughness: 0.06,
            metalness: 0.10
        )
        water.transparency = 0.82
        water.isDoubleSided = true

        let floor = SCNCylinder(radius: 150, height: 1.0)
        floor.radialSegmentCount = 192
        let floorNode = SCNNode(geometry: floor)
        floorNode.name = "plaza.ground"
        floorNode.position = SCNVector3(0, -0.50, 0)
        floorNode.geometry?.materials = [basalt]
        root.addChildNode(floorNode)

        let rimRing = SCNTorus(ringRadius: 149.2, pipeRadius: 0.34)
        rimRing.ringSegmentCount = 192
        rimRing.pipeSegmentCount = 12
        let plazaRimNode = SCNNode(geometry: rimRing)
        plazaRimNode.position.y = 0.12
        plazaRimNode.eulerAngles.x = .pi / 2
        plazaRimNode.geometry?.materials = [bronze]
        root.addChildNode(plazaRimNode)

        let innerRing = SCNTorus(ringRadius: 92, pipeRadius: 0.18)
        innerRing.ringSegmentCount = 160
        innerRing.pipeSegmentCount = 10
        let innerRingNode = SCNNode(geometry: innerRing)
        innerRingNode.position.y = 0.12
        innerRingNode.eulerAngles.x = .pi / 2
        innerRingNode.geometry?.materials = [mint]
        root.addChildNode(innerRingNode)

        let center = SCNodeFactory.cylinder(radius: 18, height: 0.20, material: pearl)
        center.position.y = 0.11
        root.addChildNode(center)

        let star = SCNNode(geometry: SCNShape(path: starPath(outer: 10.8, inner: 2.8, points: 8),
                                              extrusionDepth: 0.10))
        star.position.y = 0.22
        star.eulerAngles.x = -.pi / 2
        star.geometry?.materials = [bronze]
        star.name = "plaza.star"
        root.addChildNode(star)
        star.runAction(.repeatForever(.sequence([
            .moveBy(x: 0, y: 0.07, z: 0, duration: 2.4),
            .moveBy(x: 0, y: -0.07, z: 0, duration: 2.4)
        ])))

        let poolBase = SCNodeFactory.cylinder(radius: 8.4, height: 0.34, material: basalt)
        poolBase.position = SCNVector3(0, 0.18, 8)
        root.addChildNode(poolBase)
        let pool = SCNodeFactory.cylinder(radius: 7.7, height: 0.12, material: water)
        pool.position = SCNVector3(0, 0.39, 8)
        pool.name = "plaza.pool"
        root.addChildNode(pool)
        let poolRim = SCNTorus(ringRadius: 8.1, pipeRadius: 0.23)
        poolRim.ringSegmentCount = 96
        poolRim.pipeSegmentCount = 12
        let poolRimNode = SCNNode(geometry: poolRim)
        poolRimNode.position = SCNVector3(0, 0.40, 8)
        poolRimNode.eulerAngles.x = .pi / 2
        poolRimNode.geometry?.materials = [pearl]
        root.addChildNode(poolRimNode)

        makeArch(parent: root, material: pearl)
        makeStage(parent: root, wood: basalt, canvas: sail, accent: mint, bronze: bronze)
        makeMarket(parent: root, wood: basalt, canvas: sail, pearl: pearl, accent: bronze)
        makeWaterSlide(parent: root, shell: pearl, water: water, bronze: bronze)
        makeLandscape(parent: root, pearl: pearl, mint: mint, bronze: bronze)

        let roomDoor = starWorldTravelDoor(
            title: "星言房间",
            nodeName: "travel.room",
            width: 2.0,
            height: 3.2
        )
        roomDoor.position = SCNVector3(0, 0.02, -112)
        root.addChildNode(roomDoor)

        let player = makeAvatar(profile: profile)
        player.name = "world.player"
        player.position = SCNVector3(0, 0.02, -98)
        player.eulerAngles.y = 0
        root.addChildNode(player)

        let follow = SCNTransformConstraint(inWorldSpace: true) { _, _ in
            let target = player.presentation.worldPosition
            var transform = SCNMatrix4Identity
            transform.m41 = target.x
            transform.m42 = target.y
            transform.m43 = target.z
            return transform
        }
        cameraRig.constraints = [follow]
        return scene
    }

    private static func makeArch(parent: SCNNode, material: SCNMaterial) {
        let arch = UIBezierPath()
        arch.move(to: CGPoint(x: -12, y: 0))
        arch.addCurve(
            to: CGPoint(x: 12, y: 0),
            controlPoint1: CGPoint(x: -10, y: 22),
            controlPoint2: CGPoint(x: 10, y: 22)
        )
        let shape = SCNShape(path: arch, extrusionDepth: 0.32)
        shape.chamferRadius = 0.14
        let node = SCNNode(geometry: shape)
        node.position = SCNVector3(0, 0.58, 8)
        node.geometry?.materials = [material]
        parent.addChildNode(node)
    }

    private static func makeStage(
        parent: SCNNode,
        wood: SCNMaterial,
        canvas: SCNMaterial,
        accent: SCNMaterial,
        bronze: SCNMaterial
    ) {
        let stage = SCNNode()
        stage.position = SCNVector3(-76, 0, -26)
        parent.addChildNode(stage)

        let platform = SCNodeFactory.cylinder(radius: 10.5, height: 0.55, material: wood)
        platform.position.y = 0.28
        stage.addChildNode(platform)

        let ring = SCNTorus(ringRadius: 9.5, pipeRadius: 0.11)
        ring.ringSegmentCount = 96
        let ringNode = SCNNode(geometry: ring)
        ringNode.position.y = 0.58
        ringNode.eulerAngles.x = .pi / 2
        ringNode.geometry?.materials = [accent]
        stage.addChildNode(ringNode)

        for x in [-7.0, 0.0, 7.0] {
            let post = SCNodeFactory.cylinder(radius: 0.085, height: 7.8, material: bronze)
            post.position = SCNVector3(Float(x), 4.1, -1.8)
            stage.addChildNode(post)
        }

        let canopy = SCNNode(geometry: SCNSphere(radius: 10.8))
        canopy.position = SCNVector3(0, 8.2, -1.8)
        canopy.scale = SCNVector3(1.0, 0.18, 0.72)
        canopy.geometry?.materials = [canvas]
        canvas.isDoubleSided = true
        stage.addChildNode(canopy)

        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(red: 1.0, green: 0.72, blue: 0.38, alpha: 1)
        light.intensity = 1200
        light.attenuationStartDistance = 6
        light.attenuationEndDistance = 38
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.position = SCNVector3(0, 5.0, 1.2)
        stage.addChildNode(lightNode)
    }

    private static func makeMarket(
        parent: SCNNode,
        wood: SCNMaterial,
        canvas: SCNMaterial,
        pearl: SCNMaterial,
        accent: SCNMaterial
    ) {
        let market = SCNNode()
        market.position = SCNVector3(67, 0, -18)
        parent.addChildNode(market)

        for offset in [SCNVector3(0, 0, 0), SCNVector3(-18, 0, 28)] {
            let pavilion = SCNNode()
            pavilion.position = offset
            market.addChildNode(pavilion)

            let counter = SCNodeFactory.box(width: 7.2, height: 1.1, length: 2.4, material: pearl)
            counter.position.y = 0.58
            pavilion.addChildNode(counter)

            for x in [-3.0, 3.0] {
                let pole = SCNodeFactory.cylinder(radius: 0.075, height: 7.0, material: wood)
                pole.position = SCNVector3(Float(x), 3.5, 0)
                pavilion.addChildNode(pole)
            }

            let roof = SCNPyramid(width: 8.4, height: 4.5, length: 8.4)
            let roofNode = SCNNode(geometry: roof)
            roofNode.position.y = 7.7
            roofNode.eulerAngles.y = .pi / 4
            roofNode.scale = SCNVector3(1, 0.55, 1)
            roofNode.geometry?.materials = [canvas]
            pavilion.addChildNode(roofNode)
        }

        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(red: 1.0, green: 0.76, blue: 0.42, alpha: 1)
        light.intensity = 980
        light.attenuationEndDistance = 38
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.position = SCNVector3(0, 6.0, 0)
        market.addChildNode(lightNode)
    }

    private static func makeWaterSlide(
        parent: SCNNode,
        shell: SCNMaterial,
        water: SCNMaterial,
        bronze: SCNMaterial
    ) {
        let slide = SCNNode()
        slide.position = SCNVector3(-62, 0, 72)
        parent.addChildNode(slide)

        for x in [-4.5, 4.5] {
            for z in [-4.5, 4.5] {
                let leg = SCNodeFactory.cylinder(radius: 0.34, height: 21, material: bronze)
                leg.position = SCNVector3(Float(x), 10.5, Float(z))
                slide.addChildNode(leg)
            }
        }

        let deck = SCNodeFactory.box(width: 10.4, height: 0.55, length: 10.4, material: shell)
        deck.position.y = 21.1
        slide.addChildNode(deck)

        func curvePoint(_ t: Float) -> SCNVector3 {
            let angle = t * .pi * 1.75
            let radius = 10.0 + t * 12.0
            return SCNVector3(
                cos(angle) * radius,
                20.0 - t * 18.0,
                sin(angle) * radius - t * 18.0
            )
        }

        let segments = 44
        for index in 0..<segments {
            let t = Float(index) / Float(segments)
            let point = curvePoint(t)
            let next = curvePoint(min(1, t + 0.03))
            let chute = SCNodeFactory.box(width: 2.8, height: 0.32, length: 1.45, material: shell)
            chute.position = point
            chute.look(at: next, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            slide.addChildNode(chute)

            let stream = SCNodeFactory.box(width: 2.15, height: 0.035, length: 1.2, material: water)
            stream.position = SCNVector3(point.x, point.y + 0.20, point.z)
            stream.eulerAngles = chute.eulerAngles
            slide.addChildNode(stream)
        }

        let landing = SCNodeFactory.cylinder(radius: 13, height: 0.42, material: shell)
        landing.position = SCNVector3(-12, 0.22, -18)
        slide.addChildNode(landing)
        let landingWater = SCNodeFactory.cylinder(radius: 12.2, height: 0.10, material: water)
        landingWater.position = SCNVector3(-12, 0.45, -18)
        slide.addChildNode(landingWater)
    }

    private static func makeLandscape(
        parent: SCNNode,
        pearl: SCNMaterial,
        mint: SCNMaterial,
        bronze: SCNMaterial
    ) {
        for index in 0..<20 {
            let angle = Float(index) / 20 * .pi * 2
            let radius: Float = index % 2 == 0 ? 118 : 134
            let lamp = SCNNode()
            lamp.position = SCNVector3(sin(angle) * radius, 0, cos(angle) * radius)

            let pole = SCNodeFactory.cylinder(radius: 0.13, height: 7.4, material: bronze)
            pole.position.y = 3.7
            lamp.addChildNode(pole)

            let bulb = SCNNode(geometry: SCNSphere(radius: 0.34))
            bulb.position.y = 7.5
            bulb.geometry?.materials = [mint]
            lamp.addChildNode(bulb)
            parent.addChildNode(lamp)
        }

        for index in 0..<16 {
            let angle = Float(index) / 16 * .pi * 2
            let bench = SCNodeFactory.box(width: 4.2, height: 0.34, length: 1.2, material: pearl)
            bench.position = SCNVector3(sin(angle) * 58, 0.20, cos(angle) * 58)
            bench.eulerAngles.y = angle + .pi / 2
            parent.addChildNode(bench)
        }
    }

    private static func makeAvatar(profile: StarAvatarProfile) -> SCNNode {
        let avatar = SCNNode()
        let skin = SCNodeFactory.material(profile.skinUIColor, roughness: 0.62)
        let hair = SCNodeFactory.material(profile.hairUIColor, roughness: 0.52)
        let eye = SCNodeFactory.material(profile.eyeUIColor, roughness: 0.18)
        let hoodie = SCNodeFactory.material(
            UIColor(red: 0.08, green: 0.48, blue: 0.42, alpha: 1),
            roughness: 0.58
        )
        let denim = SCNodeFactory.material(
            UIColor(red: 0.07, green: 0.12, blue: 0.20, alpha: 1),
            roughness: 0.82
        )
        let shoe = SCNodeFactory.material(
            UIColor(red: 0.88, green: 0.86, blue: 0.78, alpha: 1),
            roughness: 0.68
        )
        let accent = SCNodeFactory.material(
            UIColor(red: 0.91, green: 0.75, blue: 0.40, alpha: 1),
            roughness: 0.22,
            metalness: 0.52
        )

        for x in [-0.20, 0.20] {
            let leg = SCNCapsule(capRadius: 0.14, height: 0.86)
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(Float(x), 0.55, 0)
            legNode.geometry?.materials = [denim]
            avatar.addChildNode(legNode)

            let foot = SCNCapsule(capRadius: 0.12, height: 0.33)
            let footNode = SCNNode(geometry: foot)
            footNode.position = SCNVector3(Float(x), 0.12, 0.08)
            footNode.eulerAngles.x = .pi / 2
            footNode.geometry?.materials = [shoe]
            avatar.addChildNode(footNode)
        }

        let torso = SCNCone(topRadius: 0.34, bottomRadius: 0.48, height: 0.82)
        let torsoNode = SCNNode(geometry: torso)
        torsoNode.position.y = 1.30
        torsoNode.geometry?.materials = [hoodie]
        avatar.addChildNode(torsoNode)

        for x in [-0.43, 0.43] {
            let arm = SCNCapsule(capRadius: 0.105, height: 0.66)
            let armNode = SCNNode(geometry: arm)
            armNode.position = SCNVector3(Float(x), 1.28, 0)
            armNode.eulerAngles.z = Float(x < 0 ? 0.14 : -0.14)
            armNode.geometry?.materials = [hoodie]
            avatar.addChildNode(armNode)
        }

        let head = SCNNode(geometry: SCNSphere(radius: 0.31))
        head.position.y = 1.96
        head.scale = SCNVector3(0.91, 1.03, 0.92)
        head.geometry?.materials = [skin]
        avatar.addChildNode(head)

        let hairCap = SCNNode(geometry: SCNSphere(radius: 0.323))
        hairCap.position = SCNVector3(0, 2.02, -0.06)
        hairCap.scale = SCNVector3(0.96, 0.98, 0.92)
        hairCap.geometry?.materials = [hair]
        avatar.addChildNode(hairCap)

        for x in [-0.105, 0.105] {
            let eyeNode = SCNNode(geometry: SCNSphere(radius: 0.026))
            eyeNode.position = SCNVector3(Float(x), 1.97, 0.285)
            eyeNode.scale = SCNVector3(0.9, 1.1, 0.35)
            eyeNode.geometry?.materials = [eye]
            avatar.addChildNode(eyeNode)
        }

        if profile.hasGlasses {
            let frame = SCNodeFactory.material(profile.glassesUIColor, roughness: 0.22, metalness: 0.34)
            for x in [-0.105, 0.105] {
                let lens = SCNTorus(ringRadius: 0.075, pipeRadius: 0.009)
                let lensNode = SCNNode(geometry: lens)
                lensNode.position = SCNVector3(Float(x), 1.97, 0.304)
                lensNode.scale.y = 0.80
                lensNode.geometry?.materials = [frame]
                avatar.addChildNode(lensNode)
            }
        }

        let starA = SCNodeFactory.box(width: 0.04, height: 0.21, length: 0.02, material: accent)
        starA.position = SCNVector3(0, 1.42, 0.37)
        starA.eulerAngles.z = .pi / 4
        avatar.addChildNode(starA)
        let starB = SCNodeFactory.box(width: 0.21, height: 0.04, length: 0.02, material: accent)
        starB.position = SCNVector3(0, 1.42, 0.37)
        starB.eulerAngles.z = .pi / 4
        avatar.addChildNode(starB)

        let shadow = SCNNode(geometry: SCNPlane(width: 1.45, height: 1.05))
        shadow.position.y = 0.015
        shadow.eulerAngles.x = -.pi / 2
        let shadowMaterial = SCNMaterial()
        shadowMaterial.lightingModel = .constant
        shadowMaterial.diffuse.contents = UIColor.black.withAlphaComponent(0.22)
        shadowMaterial.writesToDepthBuffer = false
        shadow.geometry?.materials = [shadowMaterial]
        avatar.addChildNode(shadow)
        return avatar
    }

    private static func starPath(outer: CGFloat, inner: CGFloat, points: Int) -> UIBezierPath {
        let path = UIBezierPath()
        for index in 0..<(points * 2) {
            let angle = CGFloat.pi / 2 + CGFloat(index) * .pi / CGFloat(points)
            let radius = index.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.close()
        return path
    }
}

enum SCNodeFactory {
    static func material(
        _ color: UIColor,
        roughness: CGFloat,
        metalness: CGFloat = 0
    ) -> SCNMaterial {
        let value = SCNMaterial()
        value.lightingModel = .physicallyBased
        value.diffuse.contents = color
        value.roughness.contents = roughness
        value.metalness.contents = metalness
        return value
    }

    static func cylinder(radius: CGFloat, height: CGFloat, material: SCNMaterial) -> SCNNode {
        let geometry = SCNCylinder(radius: radius, height: height)
        geometry.radialSegmentCount = 64
        let node = SCNNode(geometry: geometry)
        geometry.materials = [material]
        return node
    }

    static func box(
        width: CGFloat,
        height: CGFloat,
        length: CGFloat,
        material: SCNMaterial,
        chamfer: CGFloat = 0
    ) -> SCNNode {
        let geometry = SCNBox(
            width: width,
            height: height,
            length: length,
            chamferRadius: chamfer
        )
        let node = SCNNode(geometry: geometry)
        geometry.materials = [material]
        return node
    }
}

func starWorldTravelDoor(
    title: String,
    nodeName: String,
    width: CGFloat = 1.45,
    height: CGFloat = 2.45
) -> SCNNode {
    let root = SCNNode()
    root.name = nodeName

    let frame = SCNodeFactory.box(
        width: width + 0.20,
        height: height + 0.20,
        length: 0.11,
        material: SCNodeFactory.material(
            UIColor(red: 0.78, green: 0.58, blue: 0.29, alpha: 1),
            roughness: 0.18,
            metalness: 0.82
        ),
        chamfer: 0.08
    )
    root.addChildNode(frame)

    let panelMaterial = SCNodeFactory.material(
        UIColor(red: 0.035, green: 0.19, blue: 0.20, alpha: 1),
        roughness: 0.12,
        metalness: 0.24
    )
    panelMaterial.emission.contents = UIColor(
        red: 0.03,
        green: 0.22,
        blue: 0.19,
        alpha: 1
    )
    let panel = SCNodeFactory.box(
        width: width,
        height: height,
        length: 0.035,
        material: panelMaterial,
        chamfer: 0.045
    )
    panel.position.z = 0.075
    root.addChildNode(panel)

    let handle = SCNNode(geometry: SCNSphere(radius: 0.055))
    handle.position = SCNVector3(Float(width * 0.34), 0, 0.13)
    handle.geometry?.materials = [
        SCNodeFactory.material(
            UIColor(red: 0.95, green: 0.77, blue: 0.40, alpha: 1),
            roughness: 0.16,
            metalness: 0.88
        )
    ]
    root.addChildNode(handle)

    let text = SCNText(string: Tr(title), extrusionDepth: 0.008)
    text.font = UIFont.systemFont(ofSize: 26, weight: .semibold)
    text.flatness = 0.18
    text.firstMaterial = SCNodeFactory.material(
        UIColor(red: 0.76, green: 0.96, blue: 0.90, alpha: 1),
        roughness: 0.20
    )
    text.firstMaterial?.emission.contents = UIColor(
        red: 0.04,
        green: 0.28,
        blue: 0.23,
        alpha: 1
    )
    let label = SCNNode(geometry: text)
    label.scale = SCNVector3(0.007, 0.007, 0.007)
    label.position = SCNVector3(-Float(width * 0.42), Float(height * 0.68), 0.145)
    label.constraints = [SCNBillboardConstraint()]
    root.addChildNode(label)
    return root
}
