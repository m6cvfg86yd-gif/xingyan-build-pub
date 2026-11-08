import SwiftUI
import SceneKit
import UIKit

struct StarWorld3DEntryCard: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(hex: 0x071B2A),
                    Color(hex: 0x0D4D4A),
                    Color(hex: 0xAD9C5A)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(hex: 0x59E3C0).opacity(0.30))
                .frame(width: 180, height: 180)
                .blur(radius: 34)
                .offset(x: 210, y: -34)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("XINGYAN WORLD")
                        .font(pfStyled(size: 9, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.62))
                    Text(Tr("星言房间"))
                        .font(pfStyled(size: 23, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(Tr("一个房间，一个玩家"))
                        .font(pfStyled(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer(minLength: 12)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                    .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 0.7))
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 148)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 18, y: 9)
    }
}

struct World3DEntryPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? -0.035 : 0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct StarWorldExperienceView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var yaw: CGFloat = -0.20
    @State private var pitch: CGFloat = 0.10
    @State private var startYaw: CGFloat = -0.20
    @State private var startPitch: CGFloat = 0.10
    @State private var entered = false
    @State private var avatarProfile = StarAvatarProfile.fallback
    @State private var showAvatarStudio = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x02070F),
                    Color(hex: 0x08243A),
                    Color(hex: 0x0E3A38)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color(hex: 0x57D8C0).opacity(0.18),
                    Color.clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 330
            )
            .ignoresSafeArea()

            StarWorldSceneView(yaw: $yaw, pitch: $pitch, profile: avatarProfile)
                .id(avatarProfile)
                .ignoresSafeArea()
                .opacity(entered ? 1 : 0)
                .scaleEffect(entered ? 1 : 0.92)
                .animation(.easeOut(duration: 0.8), value: entered)

            VStack(spacing: 0) {
                HStack {
                    worldGlassButton("chevron.left") { dismiss() }
                    Spacer()
                    VStack(spacing: 1) {
                        Text(Tr("星言房间"))
                            .font(pfStyled(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(Tr("我的房间 · 1位玩家"))
                            .font(pfStyled(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.60))
                    }
                    Spacer()
                    worldGlassButton("info.circle") { }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)

                Spacer()

                HStack(spacing: 28) {
                    worldAction("person.crop.circle", Tr("形象")) {
                        showAvatarStudio = true
                    }
                    worldAction("sofa.fill", Tr("房间")) { }
                    worldAction("tshirt.fill", Tr("换装")) { }
                    worldAction("globe.asia.australia.fill", Tr("世界")) { }
                }
                .padding(.horizontal, 22)
                .frame(height: 70)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.7))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, max(18, L.safeBottom))
            }
        }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    yaw = startYaw + value.translation.width / 260
                    pitch = min(0.48, max(-0.34, startPitch - value.translation.height / 520))
                }
                .onEnded { _ in
                    startYaw = yaw
                    startPitch = pitch
                }
        )
        .onAppear {
            entered = true
            avatarProfile = StarAvatarProfileStore.load(userID: app.me?.id ?? "local")
        }
        .sheet(isPresented: $showAvatarStudio) {
            StarAvatarPhotoStudioView(
                profile: $avatarProfile,
                userID: app.me?.id ?? "local"
            )
            .environmentObject(app)
        }
        .statusBarHidden(true)
    }

    private func worldGlassButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    private func worldAction(_ symbol: String,
                             _ title: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(pfStyled(size: 10.5, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.92))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct StarWorldSceneView: UIViewRepresentable {
    @Binding var yaw: CGFloat
    @Binding var pitch: CGFloat
    let profile: StarAvatarProfile

    final class Coordinator {
        let root = SCNNode()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.scene = makeScene(root: context.coordinator.root, profile: profile)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.12
        context.coordinator.root.eulerAngles.x = Float(pitch)
        context.coordinator.root.eulerAngles.y = Float(yaw)
        SCNTransaction.commit()
    }

    private func makeScene(root: SCNNode, profile: StarAvatarProfile) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scene.rootNode.addChildNode(root)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 52
        camera.camera?.wantsHDR = true
        camera.camera?.wantsExposureAdaptation = true
        camera.position = SCNVector3(0, 0.25, 6.1)
        camera.look(at: SCNVector3(0, 0.05, -1.1))
        scene.rootNode.addChildNode(camera)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(red: 0.32, green: 0.43, blue: 0.55, alpha: 1)
        ambient.intensity = 430
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        func material(_ color: UIColor,
                      roughness: CGFloat = 0.65,
                      metalness: CGFloat = 0.05) -> SCNMaterial {
            let value = SCNMaterial()
            value.lightingModel = .physicallyBased
            value.diffuse.contents = color
            value.roughness.contents = roughness
            value.metalness.contents = metalness
            return value
        }

        func addSphere(to parent: SCNNode,
                       radius: CGFloat,
                       position: SCNVector3,
                       scale: SCNVector3 = SCNVector3(1, 1, 1),
                       material: SCNMaterial) -> SCNNode {
            let node = SCNNode(geometry: SCNSphere(radius: radius))
            node.position = position
            node.scale = scale
            node.geometry?.materials = [material]
            parent.addChildNode(node)
            return node
        }

        func addCapsule(to parent: SCNNode,
                        radius: CGFloat,
                        height: CGFloat,
                        position: SCNVector3,
                        scale: SCNVector3 = SCNVector3(1, 1, 1),
                        material: SCNMaterial) -> SCNNode {
            let node = SCNNode(geometry: SCNCapsule(capRadius: radius, height: height))
            node.position = position
            node.scale = scale
            node.geometry?.materials = [material]
            parent.addChildNode(node)
            return node
        }

        func addBox(to parent: SCNNode,
                    width: CGFloat,
                    height: CGFloat,
                    length: CGFloat,
                    chamfer: CGFloat,
                    position: SCNVector3,
                    material: SCNMaterial) -> SCNNode {
            let node = SCNNode(geometry: SCNBox(width: width,
                                                height: height,
                                                length: length,
                                                chamferRadius: chamfer))
            node.position = position
            node.geometry?.materials = [material]
            parent.addChildNode(node)
            return node
        }

        let floor = SCNNode(geometry: SCNBox(width: 8.2, height: 0.12, length: 8.2, chamferRadius: 0.02))
        floor.position = SCNVector3(0, -1.28, -0.4)
        floor.geometry?.materials = [material(UIColor(red: 0.055, green: 0.12, blue: 0.13, alpha: 1),
                                             roughness: 0.46)]
        root.addChildNode(floor)

        let backWall = SCNNode(geometry: SCNBox(width: 8.2, height: 4.4, length: 0.08, chamferRadius: 0.02))
        backWall.position = SCNVector3(0, 0.9, -4.05)
        backWall.geometry?.materials = [material(UIColor(red: 0.055, green: 0.10, blue: 0.14, alpha: 1))]
        root.addChildNode(backWall)

        let leftWall = SCNNode(geometry: SCNBox(width: 0.08, height: 4.4, length: 8.2, chamferRadius: 0.02))
        leftWall.position = SCNVector3(-4.05, 0.9, -0.4)
        leftWall.geometry?.materials = [material(UIColor(red: 0.045, green: 0.085, blue: 0.12, alpha: 1))]
        root.addChildNode(leftWall)

        let rug = SCNNode(geometry: SCNBox(width: 3.25, height: 0.025, length: 2.55, chamferRadius: 0.65))
        rug.position = SCNVector3(-0.05, -1.19, -0.25)
        rug.geometry?.materials = [material(UIColor(red: 0.10, green: 0.33, blue: 0.29, alpha: 1),
                                            roughness: 0.90)]
        root.addChildNode(rug)

        let bedBase = SCNNode(geometry: SCNBox(width: 2.15, height: 0.46, length: 3.15, chamferRadius: 0.12))
        bedBase.position = SCNVector3(2.62, -0.91, -1.85)
        bedBase.geometry?.materials = [material(UIColor(red: 0.10, green: 0.17, blue: 0.20, alpha: 1))]
        root.addChildNode(bedBase)

        let mattress = SCNNode(geometry: SCNBox(width: 1.98, height: 0.25, length: 2.92, chamferRadius: 0.18))
        mattress.position = SCNVector3(2.62, -0.55, -1.84)
        mattress.geometry?.materials = [material(UIColor(red: 0.73, green: 0.78, blue: 0.72, alpha: 1),
                                                 roughness: 0.92)]
        root.addChildNode(mattress)

        let pillow = SCNNode(geometry: SCNBox(width: 1.22, height: 0.20, length: 0.58, chamferRadius: 0.25))
        pillow.position = SCNVector3(2.62, -0.36, -2.95)
        pillow.geometry?.materials = [material(UIColor(red: 0.84, green: 0.75, blue: 0.55, alpha: 1),
                                              roughness: 0.95)]
        root.addChildNode(pillow)

        let window = SCNNode(geometry: SCNBox(width: 2.35, height: 1.75, length: 0.025, chamferRadius: 0.10))
        window.position = SCNVector3(-1.10, 0.80, -3.98)
        let windowMat = material(UIColor(red: 0.11, green: 0.30, blue: 0.48, alpha: 1),
                                 roughness: 0.16,
                                 metalness: 0.12)
        windowMat.emission.contents = UIColor(red: 0.05, green: 0.18, blue: 0.30, alpha: 1)
        window.geometry?.materials = [windowMat]
        root.addChildNode(window)

        for x in [-2.25, -1.10, 0.05] {
            let bar = SCNNode(geometry: SCNBox(width: 0.035, height: 1.76, length: 0.035, chamferRadius: 0))
            bar.position = SCNVector3(x, 0.80, -3.95)
            bar.geometry?.materials = [material(UIColor(red: 0.36, green: 0.47, blue: 0.50, alpha: 1),
                                                roughness: 0.28,
                                                metalness: 0.55)]
            root.addChildNode(bar)
        }

        let desk = SCNNode(geometry: SCNBox(width: 1.85, height: 0.10, length: 0.78, chamferRadius: 0.06))
        desk.position = SCNVector3(-2.85, -0.54, -2.55)
        desk.geometry?.materials = [material(UIColor(red: 0.32, green: 0.27, blue: 0.18, alpha: 1),
                                             roughness: 0.70)]
        root.addChildNode(desk)

        for x in [-3.60, -2.10] {
            let leg = SCNNode(geometry: SCNCylinder(radius: 0.055, height: 0.72))
            leg.position = SCNVector3(x, -0.92, -2.55)
            leg.geometry?.materials = [material(UIColor(red: 0.20, green: 0.20, blue: 0.18, alpha: 1),
                                                roughness: 0.42,
                                                metalness: 0.28)]
            root.addChildNode(leg)
        }

        let player = SCNNode()
        player.position = SCNVector3(0, -1.28, -0.25)
        root.addChildNode(player)

        let figure = SCNNode()
        player.addChildNode(figure)

        let skinBase = profile.skinUIColor
        let hairBase = profile.hairUIColor
        let skin = material(skinBase, roughness: 0.68)
        let skinShade = material(avatarColor(skinBase, factor: 0.82), roughness: 0.72)
        let hair = material(hairBase, roughness: 0.62)
        let hairLight = material(avatarColor(hairBase, factor: 1.28), roughness: 0.54)
        let hoodie = material(UIColor(red: 0.075, green: 0.48, blue: 0.42, alpha: 1),
                              roughness: 0.58)
        let hoodieLight = material(UIColor(red: 0.16, green: 0.68, blue: 0.56, alpha: 1),
                                   roughness: 0.50)
        let denim = material(UIColor(red: 0.08, green: 0.13, blue: 0.22, alpha: 1),
                             roughness: 0.82)
        let shoe = material(UIColor(red: 0.84, green: 0.83, blue: 0.76, alpha: 1),
                            roughness: 0.72)
        let sole = material(UIColor(red: 0.24, green: 0.28, blue: 0.28, alpha: 1),
                            roughness: 0.84)
        let accent = material(UIColor(red: 0.91, green: 0.76, blue: 0.38, alpha: 1),
                              roughness: 0.34,
                              metalness: 0.18)
        let eye = material(profile.eyeUIColor, roughness: 0.18)
        let eyeLight = material(UIColor(red: 0.92, green: 0.98, blue: 1.0, alpha: 1),
                                roughness: 0.08)
        let blush = material(UIColor(red: 0.91, green: 0.37, blue: 0.38, alpha: 0.22),
                             roughness: 0.92)
        blush.transparency = 0.40

        // Shoes and tapered legs give the silhouette human proportions instead of a capsule tower.
        for x in [-0.19, 0.19] {
            addBox(to: figure,
                   width: 0.30,
                   height: 0.13,
                   length: 0.46,
                   chamfer: 0.075,
                   position: SCNVector3(x, 0.065, 0.055),
                   material: sole)
            let upper = addBox(to: figure,
                               width: 0.30,
                               height: 0.16,
                               length: 0.44,
                               chamfer: 0.085,
                               position: SCNVector3(x, 0.145, 0.04),
                               material: shoe)
            upper.eulerAngles.y = x < 0 ? -0.035 : 0.035

            addCapsule(to: figure,
                       radius: 0.135,
                       height: 0.62,
                       position: SCNVector3(x * 0.92, 0.49, 0),
                       scale: SCNVector3(0.92, 1, 0.92),
                       material: denim)
            addCapsule(to: figure,
                       radius: 0.158,
                       height: 0.56,
                       position: SCNVector3(x, 0.84, 0),
                       scale: SCNVector3(0.94, 1, 0.94),
                       material: denim)
        }

        addBox(to: figure,
               width: 0.58,
               height: 0.29,
               length: 0.36,
               chamfer: 0.11,
               position: SCNVector3(0, 1.08, 0),
               material: denim)

        let torso = SCNNode(geometry: SCNCone(topRadius: 0.31,
                                              bottomRadius: 0.39,
                                              height: 0.72))
        torso.position = SCNVector3(0, 1.48, 0)
        torso.scale = SCNVector3(1, 1, 0.72)
        torso.geometry?.materials = [hoodie]
        figure.addChildNode(torso)

        addCapsule(to: figure,
                   radius: 0.395,
                   height: 0.12,
                   position: SCNVector3(0, 1.105, 0.01),
                   scale: SCNVector3(1, 1, 0.70),
                   material: hoodie)

        // Rounded shoulders and a soft hood keep the shape friendly rather than robotic.
        addSphere(to: figure,
                  radius: 0.17,
                  position: SCNVector3(-0.28, 1.70, 0),
                  scale: SCNVector3(1.02, 0.86, 0.78),
                  material: hoodie)
        addSphere(to: figure,
                  radius: 0.17,
                  position: SCNVector3(0.28, 1.70, 0),
                  scale: SCNVector3(1.02, 0.86, 0.78),
                  material: hoodie)

        let hood = SCNNode(geometry: SCNTorus(ringRadius: 0.235, pipeRadius: 0.072))
        hood.position = SCNVector3(0, 1.785, -0.055)
        hood.scale = SCNVector3(1.04, 1, 0.78)
        hood.geometry?.materials = [hoodieLight]
        figure.addChildNode(hood)

        for (x, angle) in [(-0.36, CGFloat(0.12)), (0.36, CGFloat(-0.12))] {
            let sleeve = addCapsule(to: figure,
                                    radius: 0.115,
                                    height: 0.57,
                                    position: SCNVector3(x, 1.45, 0.02),
                                    scale: SCNVector3(1, 1, 0.92),
                                    material: hoodie)
            sleeve.eulerAngles.z = Float(angle)
            let hand = addSphere(to: figure,
                                 radius: 0.105,
                                 position: SCNVector3(x < 0 ? -0.245 : 0.245,
                                                      1.18,
                                                      0.255),
                                 scale: SCNVector3(0.92, 1.15, 0.72),
                                 material: skin)
            hand.eulerAngles.z = x < 0 ? -0.18 : 0.18
        }

        // A shallow front pocket and real drawstrings create readable garment detail.
        let pocket = addBox(to: figure,
                            width: 0.43,
                            height: 0.20,
                            length: 0.035,
                            chamfer: 0.07,
                            position: SCNVector3(0, 1.27, 0.274),
                            material: hoodieLight)
        pocket.eulerAngles.x = -0.08

        for x in [-0.075, 0.075] {
            let cord = SCNNode(geometry: SCNCylinder(radius: 0.012, height: 0.28))
            cord.position = SCNVector3(x, 1.57, 0.255)
            cord.geometry?.materials = [accent]
            figure.addChildNode(cord)
            addSphere(to: figure,
                      radius: 0.025,
                      position: SCNVector3(x, 1.425, 0.258),
                      material: accent)
        }

        // A small faceted star reads clearly under the room lighting and can become the brand crest.
        let emblemA = addBox(to: figure,
                             width: 0.035,
                             height: 0.19,
                             length: 0.018,
                             chamfer: 0.01,
                             position: SCNVector3(0, 1.56, 0.294),
                             material: accent)
        emblemA.eulerAngles.z = .pi / 4
        let emblemB = addBox(to: figure,
                             width: 0.19,
                             height: 0.035,
                             length: 0.018,
                             chamfer: 0.01,
                             position: SCNVector3(0, 1.56, 0.295),
                             material: accent)
        emblemB.eulerAngles.z = .pi / 4

        addCapsule(to: figure,
                   radius: 0.095,
                   height: 0.22,
                   position: SCNVector3(0, 1.86, 0),
                   scale: SCNVector3(0.82, 1, 0.84),
                   material: skinShade)

        let headGroup = SCNNode()
        headGroup.position = SCNVector3(0, 2.12, 0)
        headGroup.eulerAngles.z = -0.028
        headGroup.scale = SCNVector3(
            Float(profile.faceWidth),
            Float(profile.faceLength),
            1
        )
        figure.addChildNode(headGroup)

        let head = addSphere(to: headGroup,
                             radius: 0.33,
                             position: .zero,
                             scale: SCNVector3(
                                Float(0.91 * (0.82 + profile.jawWidth * 0.18)),
                                1.08,
                                0.92
                             ),
                             material: skin)
        head.eulerAngles.x = -0.018

        for x in [-0.285, 0.285] {
            addSphere(to: headGroup,
                      radius: 0.065,
                      position: SCNVector3(x, -0.01, 0.015),
                      scale: SCNVector3(0.60, 1.0, 0.68),
                      material: skinShade)
        }

        // Hair sits behind the face and wraps the silhouette, with separate fringe pieces.
        addSphere(to: headGroup,
                  radius: 0.345,
                  position: SCNVector3(0, 0.075, -0.075),
                  scale: SCNVector3(1.02, 0.99, 0.94),
                  material: hair)
        addSphere(to: headGroup,
                  radius: 0.19,
                  position: SCNVector3(-0.25, 0.025, -0.055),
                  scale: SCNVector3(0.65, 1.05, 0.75),
                  material: hair)
        addSphere(to: headGroup,
                  radius: 0.19,
                  position: SCNVector3(0.25, 0.025, -0.055),
                  scale: SCNVector3(0.65, 1.05, 0.75),
                  material: hair)

        let fringeSpecs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (-0.20, 0.245, 0.255, -0.29),
            (-0.075, 0.278, 0.280, -0.12),
            (0.055, 0.285, 0.283, 0.08),
            (0.18, 0.258, 0.262, 0.24)
        ]
        for (x, y, z, angle) in fringeSpecs {
            let fringe = addCapsule(to: headGroup,
                                    radius: 0.052,
                                    height: 0.24,
                                    position: SCNVector3(x, y, z),
                                    scale: SCNVector3(0.82, 1, 0.44),
                                    material: hair)
            fringe.eulerAngles.z = Float(angle)
        }

        switch profile.hairStyle {
        case .shortCrop:
            break
        case .sidePart:
            let sideSweep = addCapsule(to: headGroup,
                                       radius: 0.042,
                                       height: 0.33,
                                       position: SCNVector3(0.275, 0.16, 0.06),
                                       scale: SCNVector3(0.72, 1, 0.48),
                                       material: hairLight)
            sideSweep.eulerAngles.z = 1.02
        case .centerPart:
            for x in [-1.0, 1.0] {
                let part = addCapsule(to: headGroup,
                                      radius: 0.042,
                                      height: 0.30,
                                      position: SCNVector3(0.12 * x, 0.23, 0.255),
                                      scale: SCNVector3(0.68, 1, 0.42),
                                      material: hairLight)
                part.eulerAngles.z = -0.32 * x
            }
        case .bob, .shoulder:
            let length: CGFloat = profile.hairStyle == .bob ? 0.43 : 0.64
            let centerY: CGFloat = profile.hairStyle == .bob ? -0.08 : -0.20
            for x in [-0.29, 0.29] {
                addCapsule(to: headGroup,
                           radius: 0.105,
                           height: length,
                           position: SCNVector3(x, centerY, -0.035),
                           scale: SCNVector3(0.72, 1, 0.68),
                           material: hair)
            }
        case .curly:
            let curls: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (-0.23, 0.27, 0.06, 0.12),
                (-0.10, 0.33, 0.07, 0.13),
                (0.06, 0.34, 0.07, 0.13),
                (0.22, 0.27, 0.06, 0.12),
                (-0.30, 0.12, -0.02, 0.11),
                (0.30, 0.12, -0.02, 0.11),
                (-0.27, -0.02, -0.04, 0.10),
                (0.27, -0.02, -0.04, 0.10)
            ]
            for (x, y, z, r) in curls {
                addSphere(to: headGroup,
                          radius: r,
                          position: SCNVector3(x, y, z),
                          scale: SCNVector3(1.0, 1.0, 0.82),
                          material: hair)
            }
        }

        for x in [-0.105, 0.105] {
            let ex = Float(x * profile.eyeSpacing)
            let eyeRadius = 0.060 * CGFloat(profile.eyeSize)
            addSphere(to: headGroup,
                      radius: eyeRadius,
                      position: SCNVector3(ex, 0.005, 0.292),
                      scale: SCNVector3(0.88, 1.28, 0.28),
                      material: eye)
            addSphere(to: headGroup,
                      radius: 0.018 * CGFloat(profile.eyeSize),
                      position: SCNVector3(
                        ex + 0.018 * Float(profile.eyeSize),
                        0.032,
                        0.314
                      ),
                      scale: SCNVector3(0.82, 0.82, 0.28),
                      material: eyeLight)
            let brow = addBox(to: headGroup,
                              width: 0.105 * CGFloat(profile.eyeSize),
                              height: 0.016,
                              length: 0.014,
                              chamfer: 0.008,
                              position: SCNVector3(ex, 0.115, 0.278),
                              material: hairLight)
            brow.eulerAngles.z = x < 0 ? -0.12 : 0.12
        }

        if profile.hasGlasses {
            let frameMaterial = material(profile.glassesUIColor,
                                         roughness: 0.24,
                                         metalness: 0.42)
            let lensMaterial = SCNMaterial()
            lensMaterial.lightingModel = .physicallyBased
            lensMaterial.diffuse.contents = avatarColor(
                profile.glassesUIColor,
                factor: 1.55
            ).withAlphaComponent(CGFloat(profile.glassesLensOpacity))
            lensMaterial.roughness.contents = 0.08
            lensMaterial.metalness.contents = 0.0
            lensMaterial.transparency = CGFloat(profile.glassesLensOpacity)
            lensMaterial.writesToDepthBuffer = false
            lensMaterial.isDoubleSided = true

            for side in [-1.0, 1.0] {
                let ex = Float(0.105 * profile.eyeSpacing * side)
                switch profile.glassesStyle {
                case .rectangular, .aviator:
                    let width: CGFloat = profile.glassesStyle == .aviator ? 0.17 : 0.16
                    let height: CGFloat = profile.glassesStyle == .aviator ? 0.085 : 0.078
                    addBox(to: headGroup,
                           width: width,
                           height: 0.012,
                           length: 0.012,
                           chamfer: 0.006,
                           position: SCNVector3(ex, 0.043, 0.335),
                           material: frameMaterial)
                    addBox(to: headGroup,
                           width: width,
                           height: 0.012,
                           length: 0.012,
                           chamfer: 0.006,
                           position: SCNVector3(ex, -0.043, 0.335),
                           material: frameMaterial)
                    for edge in [-1.0, 1.0] {
                        addBox(to: headGroup,
                               width: 0.012,
                               height: height,
                               length: 0.012,
                               chamfer: 0.006,
                               position: SCNVector3(
                                 ex + Float(edge) * Float(width / 2),
                                 0,
                                 0.335
                               ),
                               material: frameMaterial)
                    }
                    addBox(to: headGroup,
                           width: width - 0.018,
                           height: height - 0.012,
                           length: 0.003,
                           chamfer: profile.glassesStyle == .aviator ? 0.030 : 0.020,
                           position: SCNVector3(ex, 0, 0.329),
                           material: lensMaterial)
                case .round:
                    let lens = SCNTorus(ringRadius: 0.075, pipeRadius: 0.008)
                    let lensNode = SCNNode(geometry: lens)
                    lensNode.position = SCNVector3(ex, 0.002, 0.335)
                    lensNode.eulerAngles.x = .pi / 2
                    lensNode.scale = SCNVector3(1.0, 0.76, 1.0)
                    lensNode.geometry?.materials = [frameMaterial]
                    headGroup.addChildNode(lensNode)
                    addSphere(to: headGroup,
                              radius: 0.073,
                              position: SCNVector3(ex, 0.002, 0.331),
                              scale: SCNVector3(1.0, 0.76, 0.04),
                              material: lensMaterial)
                }
            }
            addBox(to: headGroup,
                   width: 0.065,
                   height: 0.009,
                   length: 0.009,
                   chamfer: 0.004,
                   position: SCNVector3(0, 0.006, 0.335),
                   material: frameMaterial)
            for side in [-1.0, 1.0] {
                let temple = addBox(to: headGroup,
                                    width: 0.012,
                                    height: 0.012,
                                    length: 0.18,
                                    chamfer: 0.004,
                                    position: SCNVector3(
                                      Float(0.205 * side * profile.faceWidth),
                                      0.003,
                                      0.255
                                    ),
                                    material: frameMaterial)
                temple.eulerAngles.y = Float(side) * 1.10
            }
        }

        addSphere(to: headGroup,
                  radius: 0.037,
                  position: SCNVector3(
                    0,
                    -0.075 - Float(profile.noseLength - 1) * 0.035,
                    0.300
                  ),
                  scale: SCNVector3(
                    0.66,
                    0.80 * Float(profile.noseLength),
                    0.46
                  ),
                  material: skinShade)
        addBox(to: headGroup,
               width: 0.088 * CGFloat(profile.mouthWidth),
               height: 0.014,
               length: 0.012,
               chamfer: 0.007,
               position: SCNVector3(0, -0.155, 0.298),
               material: skinShade)

        for x in [-0.175, 0.175] {
            addSphere(to: headGroup,
                      radius: 0.068,
                      position: SCNVector3(x, -0.085, 0.264),
                      scale: SCNVector3(1.20, 0.60, 0.14),
                      material: blush)
        }

        let halo = SCNNode(geometry: SCNTorus(ringRadius: 0.84, pipeRadius: 0.011))
        halo.position = SCNVector3(0, 0.018, 0)
        halo.eulerAngles.x = .pi / 2
        halo.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.32, green: 0.95, blue: 0.76, alpha: 0.78)
        halo.geometry?.firstMaterial?.emission.contents = UIColor(red: 0.06, green: 0.28, blue: 0.21, alpha: 1)
        player.addChildNode(halo)

        let orbit = SCNNode(geometry: SCNTorus(ringRadius: 0.64, pipeRadius: 0.006))
        orbit.position = SCNVector3(0, 0.025, 0)
        orbit.eulerAngles.x = .pi / 2
        orbit.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.92, green: 0.77, blue: 0.38, alpha: 0.46)
        orbit.geometry?.firstMaterial?.emission.contents = UIColor(red: 0.28, green: 0.18, blue: 0.04, alpha: 1)
        player.addChildNode(orbit)

        let shadowMaterial = SCNMaterial()
        shadowMaterial.lightingModel = .constant
        shadowMaterial.diffuse.contents = starWorldShadowTexture()
        shadowMaterial.transparency = 0.76
        shadowMaterial.writesToDepthBuffer = false
        let contactShadow = SCNNode(geometry: SCNPlane(width: 1.55, height: 1.15))
        contactShadow.position = SCNVector3(0, 0.006, 0.04)
        contactShadow.eulerAngles.x = -.pi / 2
        contactShadow.geometry?.materials = [shadowMaterial]
        player.addChildNode(contactShadow)

        let warm = SCNLight()
        warm.type = .omni
        warm.color = UIColor(red: 1.0, green: 0.76, blue: 0.48, alpha: 1)
        warm.intensity = 960
        let warmNode = SCNNode()
        warmNode.light = warm
        warmNode.position = SCNVector3(2.3, 2.8, 1.6)
        root.addChildNode(warmNode)

        let cool = SCNLight()
        cool.type = .omni
        cool.color = UIColor(red: 0.42, green: 0.82, blue: 1.0, alpha: 1)
        cool.intensity = 780
        let coolNode = SCNNode()
        coolNode.light = cool
        coolNode.position = SCNVector3(-2.4, 2.4, 1.2)
        root.addChildNode(coolNode)

        let idle = SCNAction.sequence([
            .moveBy(x: 0, y: 0.025, z: 0, duration: 1.8),
            .moveBy(x: 0, y: -0.025, z: 0, duration: 1.8)
        ])
        figure.runAction(.repeatForever(idle))
        let look = SCNAction.sequence([
            .rotateBy(x: 0, y: -0.055, z: 0, duration: 2.8),
            .rotateBy(x: 0, y: 0.055, z: 0, duration: 2.8)
        ])
        headGroup.runAction(.repeatForever(look))
        halo.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 10)))
        orbit.runAction(.repeatForever(.rotateBy(x: 0, y: -.pi * 2, z: 0, duration: 15)))
        return scene
    }
}

private func starWorldShadowTexture() -> UIImage {
    let size = CGSize(width: 256, height: 256)
    return UIGraphicsImageRenderer(size: size).image { context in
        let colors = [
            UIColor(red: 0.02, green: 0.10, blue: 0.09, alpha: 0.54).cgColor,
            UIColor(red: 0.02, green: 0.10, blue: 0.09, alpha: 0.18).cgColor,
            UIColor.clear.cgColor
        ] as CFArray
        let locations: [CGFloat] = [0, 0.46, 1]
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: locations
        ) else {
            return
        }
        context.cgContext.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: 128, y: 128),
            startRadius: 4,
            endCenter: CGPoint(x: 128, y: 128),
            endRadius: 126,
            options: []
        )
    }
}

private func avatarColor(_ color: UIColor, factor: CGFloat) -> UIColor {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
        return color
    }
    return UIColor(
        red: min(1, max(0, red * factor)),
        green: min(1, max(0, green * factor)),
        blue: min(1, max(0, blue * factor)),
        alpha: alpha
    )
}
