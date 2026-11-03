import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private let incomingDrop = IncomingShareDrop()
  private weak var dropView: UIView?

  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    IncomingShareChannel.receive(connectionOptions.urlContexts.map { $0.url })
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    IncomingShareChannel.receive(URLContexts.map { $0.url })
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    if UIDevice.current.userInterfaceIdiom == .pad,
      let view = window?.rootViewController?.view, dropView !== view {
      view.addInteraction(UIDropInteraction(delegate: incomingDrop))
      dropView = view
    }
    IncomingShareChannel.changed()
  }
}
