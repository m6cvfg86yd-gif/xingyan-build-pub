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
    @Environment(\.dismiss) private var dismiss
    @State private var yaw: CGFloat = -0.20
    @State private var pitch: CGFloat = 0.10
    @State private var startYaw: CGFloat = -0.20
    @State private var startPitch: CGFloat = 0.10
    @State private var entered = false

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

            StarWorldSceneView(yaw: $yaw, pitch: $pitch)
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
                    worldGlassButton("info.circle")
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)

                Spacer()

                HStack(spacing: 28) {
                    worldAction("person.crop.circle", Tr("形象"))
                    worldAction("sofa.fill", Tr("房间"))
                    worldAction("tshirt.fill", Tr("换装"))
                    worldAction("globe.asia.australia.fill", Tr("世界"))
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
        .onAppear { entered = true }
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

    private func worldAction(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
            Text(title)
                .font(pfStyled(size: 10.5, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.92))
        .frame(maxWidth: .infinity)
    }
}

private struct StarWorldSceneView: UIViewRepresentable {
    @Binding var yaw: CGFloat
    @Binding var pitch: CGFloat

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
        view.scene = makeScene(root: context.coordinator.root)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.12
        context.coordinator.root.eulerAngles.x = Float(pitch)
        context.coordinator.root.eulerAngles.y = Float(yaw)
        SCNTransaction.commit()
    }

    private func makeScene(root: SCNNode) -> SCNScene {
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
                                                metalness: 0.55,
                                                roughness: 0.28)]
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
                                                metalness: 0.28,
                                                roughness: 0.42)]
            root.addChildNode(leg)
        }

        let player = SCNNode()
        player.position = SCNVector3(0, -1.15, -0.25)
        root.addChildNode(player)

        let body = SCNNode(geometry: SCNCapsule(capRadius: 0.31, height: 0.98))
        body.position = SCNVector3(0, 1.02, 0)
        body.geometry?.materials = [material(UIColor(red: 0.08, green: 0.55, blue: 0.38, alpha: 1),
                                             roughness: 0.54,
                                             metalness: 0.08)]
        player.addChildNode(body)

        let head = SCNNode(geometry: SCNSphere(radius: 0.34))
        head.position = SCNVector3(0, 1.89, 0)
        head.geometry?.materials = [material(UIColor(red: 0.86, green: 0.68, blue: 0.52, alpha: 1),
                                             roughness: 0.58)]
        player.addChildNode(head)

        let hair = SCNNode(geometry: SCNSphere(radius: 0.35))
        hair.position = SCNVector3(0, 1.98, -0.02)
        hair.scale = SCNVector3(1, 0.58, 1)
        hair.geometry?.materials = [material(UIColor(red: 0.035, green: 0.045, blue: 0.05, alpha: 1),
                                             roughness: 0.72)]
        player.addChildNode(hair)

        for x in [-0.43, 0.43] {
            let arm = SCNNode(geometry: SCNCapsule(capRadius: 0.09, height: 0.68))
            arm.position = SCNVector3(x, 1.08, 0)
            arm.eulerAngles.z = x < 0 ? 0.20 : -0.20
            arm.geometry?.materials = [material(UIColor(red: 0.84, green: 0.66, blue: 0.50, alpha: 1),
                                                roughness: 0.62)]
            player.addChildNode(arm)
        }

        for x in [-0.19, 0.19] {
            let leg = SCNNode(geometry: SCNCapsule(capRadius: 0.12, height: 0.72))
            leg.position = SCNVector3(x, 0.35, 0)
            leg.geometry?.materials = [material(UIColor(red: 0.055, green: 0.10, blue: 0.15, alpha: 1),
                                                roughness: 0.75)]
            player.addChildNode(leg)
        }

        let halo = SCNNode(geometry: SCNTorus(ringRadius: 0.90, pipeRadius: 0.012))
        halo.position = SCNVector3(0, 0.04, 0)
        halo.eulerAngles.x = .pi / 2
        halo.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.31, green: 0.91, blue: 0.72, alpha: 0.80)
        halo.geometry?.firstMaterial?.emission.contents = UIColor(red: 0.08, green: 0.34, blue: 0.25, alpha: 1)
        player.addChildNode(halo)

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
        player.runAction(.repeatForever(idle))
        halo.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 10)))
        return scene
    }
}
