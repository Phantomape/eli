import SpriteKit
import SwiftUI

final class GameSceneHolder: ObservableObject {
    let scene: GameScene

    init() {
        let scene = GameScene()
        scene.scaleMode = .resizeFill
        self.scene = scene
    }
}

struct ContentView: View {
    @StateObject private var holder = GameSceneHolder()

    var body: some View {
        SpriteView(scene: holder.scene, options: [.ignoresSiblingOrder])
            .ignoresSafeArea()
            .background(Color.black)
            .statusBar(hidden: true)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
