import UIKit

// Standalone reference app. It does not access Foliarc's storage or services.
@main
@MainActor
struct NativeSheetReferenceApp {
  static func main() {
    UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
  }
}

@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   configurationForConnecting session: UISceneSession,
                   options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    let config = UISceneConfiguration(name: "Reference", sessionRole: session.role)
    config.delegateClass = SceneDelegate.self
    return config
  }
}

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private let home = ReferenceReader()
  private var fixtureTimer: Timer?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
             options: UIScene.ConnectionOptions) {
    guard let scene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: scene)
    window.rootViewController = UINavigationController(rootViewController: home)
    window.makeKeyAndVisible()
    self.window = window
    // Simulator-only fixture commands, independent of presentation gestures.
    #if targetEnvironment(simulator)
    let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    let command = cache.appendingPathComponent("native-sheet-reference-command.txt")
    let ack = cache.appendingPathComponent("native-sheet-reference-ack.txt")
    fixtureTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let mode = try? String(contentsOf: command, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: command)
        self?.home.show(mode: mode)
        try? mode.write(to: ack, atomically: true, encoding: .utf8)
      }
    }
    #endif
  }


}

@MainActor
final class ReferenceReader: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "原生面板参考"
    view.backgroundColor = .systemBackground
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "添加网页", style: .plain, target: self, action: #selector(openSheet))
    let text = UITextView()
    text.isEditable = false
    text.alwaysBounceVertical = true
    text.backgroundColor = .systemBackground
    text.textColor = .label
    text.font = .preferredFont(forTextStyle: .body)
    text.adjustsFontForContentSizeCategory = true
    text.textContainerInset = UIEdgeInsets(top: 24, left: 20, bottom: 24, right: 20)
    text.text = "学习与记忆\n\n" + String(repeating:
      "阅读之后，试着回忆刚才的重点。把知识与已有经验联系起来，再回到原文核对遗漏。\n\n原生面板可以保留当前阅读场景，提供短暂的操作空间。向上拖动顶部横条，可以展开查看更多内容。\n\n", count: 8)
    text.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(text)
    NSLayoutConstraint.activate([
      text.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      text.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      text.topAnchor.constraint(equalTo: view.topAnchor),
      text.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
  }

  @objc private func openSheet() { show(mode: "medium") }

  func show(mode: String) {
    if mode == "reset" {
      presentedViewController?.dismiss(animated: false)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.show(mode: "medium") }
      return
    }
    if presentedViewController == nil {
      let form = AddressForm()
      let navigation = UINavigationController(rootViewController: form)
      navigation.modalPresentationStyle = .pageSheet
      if let sheet = navigation.sheetPresentationController {
        sheet.detents = [.medium(), .large()]
        sheet.selectedDetentIdentifier = .medium
        sheet.prefersGrabberVisible = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        sheet.prefersEdgeAttachedInCompactHeight = true
      }
      navigation.presentationController?.delegate = form
      present(navigation, animated: true) {
        if mode != "medium" { self.show(mode: mode) }
      }
      return
    }
    guard let navigation = presentedViewController as? UINavigationController,
          let form = navigation.viewControllers.first as? AddressForm,
          let sheet = navigation.sheetPresentationController else { return }
    if mode == "confirm" {
      form.requestClose()
      return
    }
    if mode == "medium" { form.view.endEditing(true) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
      sheet.animateChanges {
        sheet.selectedDetentIdentifier = mode == "medium" ? .medium : .large
      }
      if mode == "keyboard" {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
          form.field.text = "https://example.com/article"
          form.changed()
          form.field.becomeFirstResponder()
        }
      }
    }
  }
}

@MainActor
final class AddressForm: UITableViewController, UIAdaptivePresentationControllerDelegate {
  let field = UITextField()

  init() { super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "添加网页"
    tableView.backgroundColor = .clear
    tableView.keyboardDismissMode = .interactive
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      title: "取消", style: .plain, target: self, action: #selector(requestClose))
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "添加", style: .prominent, target: self, action: #selector(save))
    field.placeholder = "https://"
    field.keyboardType = .URL
    field.autocapitalizationType = .none
    field.autocorrectionType = .no
    field.clearButtonMode = .whileEditing
    field.font = .preferredFont(forTextStyle: .body)
    field.adjustsFontForContentSizeCategory = true
    field.addTarget(self, action: #selector(changed), for: .editingChanged)
    changed()
  }

  override func numberOfSections(in tableView: UITableView) -> Int { 1 }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    "网页地址"
  }
  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    "上下拖动顶部横条，可以切换半屏与展开状态。此样板只演示面板交互。"
  }
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    cell.selectionStyle = .none
    field.translatesAutoresizingMaskIntoConstraints = false
    cell.contentView.addSubview(field)
    NSLayoutConstraint.activate([
      field.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
      field.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
      field.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
      field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
      field.heightAnchor.constraint(greaterThanOrEqualToConstant: 24)
    ])
    return cell
  }

  @objc func changed() {
    let url = URL(string: field.text ?? "")
    navigationItem.rightBarButtonItem?.isEnabled =
      ["http", "https"].contains(url?.scheme?.lowercased() ?? "") && !(url?.host?.isEmpty ?? true)
    navigationController?.isModalInPresentation = !(field.text?.isEmpty ?? true)
  }

  @objc private func save() { dismiss(animated: true) }

  @objc func requestClose() {
    guard !(field.text?.isEmpty ?? true) else { dismiss(animated: true); return }
    view.endEditing(true)
    let confirmation = UIAlertController(title: "放弃填写的地址？", message: "地址不会保存。", preferredStyle: .actionSheet)
    confirmation.addAction(UIAlertAction(title: "放弃更改", style: .destructive) { [weak self] _ in
      self?.dismiss(animated: true)
    })
    confirmation.addAction(UIAlertAction(title: "继续编辑", style: .cancel))
    if traitCollection.userInterfaceIdiom == .pad {
      confirmation.popoverPresentationController?.barButtonItem = navigationItem.leftBarButtonItem
    }
    present(confirmation, animated: true)
  }

  func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
    field.text?.isEmpty ?? true
  }
  func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
    requestClose()
  }
}
