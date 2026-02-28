//
//  ContentView.swift
//  BrainCopy
//
//  Created by 酒井雄太 on 2026/02/28.
//

import SwiftUI
import RealityKit

struct ContentView: View {

    @State var enlarge = false

    var body: some View {
        RealityView { content in
            // 球体のメッシュを生成
            let sphereMesh = MeshResource.generateSphere(radius: 0.1)

            // 物理ベースマテリアルを作成
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .blue)
            material.roughness = .init(floatLiteral: 0.2)
            material.metallic = .init(floatLiteral: 0.5)

            // 球体の ModelEntity を作成
            let sphereEntity = ModelEntity(mesh: sphereMesh, materials: [material])

            // 球体を RealityView に追加
            content.add(sphereEntity)
        }
    }
}

#Preview(windowStyle: .volumetric) {
    ContentView()
}
