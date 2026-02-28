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

            // マテリアルを作成
            var material = SimpleMaterial()
            material.color = .init(tint: .blue)

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
