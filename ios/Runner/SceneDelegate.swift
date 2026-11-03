import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func sceneWillResignActive(_ scene: UIScene) {
    (UIApplication.shared.delegate as? AppDelegate)?.prepareBackgroundAudioForSceneTransition()
    super.sceneWillResignActive(scene)
  }
}
