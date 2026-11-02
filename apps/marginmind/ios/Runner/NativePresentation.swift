import Flutter
import UIKit

/// UIKit owns modal mechanics; the existing Dart isolate validates and saves.
/// No additional Flutter engine, repository, or assistant request owner.
final class NativePresentation {
  private let channel: FlutterMethodChannel
  private var activeColor: NativeColorDelegate?
  private var activeList: NativeListController?
  private var activeForm: NativeFormController?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "marginmind/presentation", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
  }

  private var presenter: UIViewController? {
    var root = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }.flatMap { $0.windows }
      .first { $0.isKeyWindow }?.rootViewController
    while let presented = root?.presentedViewController { root = presented }
    return root
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "available" { result(UIDevice.current.userInterfaceIdiom == .phone); return }
    guard UIDevice.current.userInterfaceIdiom == .phone,
      let args = call.arguments as? [String: Any], let presenter = presenter else {
      result(FlutterError(code: "unavailable", message: "No active iPhone window", details: nil)); return
    }
    switch call.method {
    case "color":
      guard activeColor == nil else { result(FlutterError(code: "busy", message: nil, details: nil)); return }
      let picker = UIColorPickerViewController()
      picker.view.accessibilityIdentifier = "native-color-picker"
      picker.supportsAlpha = false
      let raw = args["value"] as? Int ?? 0xFFFFFFFF
      picker.selectedColor = UIColor(red: CGFloat((raw >> 16) & 255) / 255,
        green: CGFloat((raw >> 8) & 255) / 255, blue: CGFloat(raw & 255) / 255, alpha: 1)
      if let dark = args["dark"] as? Bool { picker.overrideUserInterfaceStyle = dark ? .dark : .light }
      let delegate = NativeColorDelegate { [weak self] value in self?.activeColor = nil; result(value) }
      activeColor = delegate
      picker.delegate = delegate
      presenter.present(picker, animated: true) { picker.presentationController?.delegate = delegate }
    case "list":
      guard activeList == nil && activeForm == nil else {
        result(FlutterError(code: "busy", message: "A panel is already open", details: nil)); return
      }
      let list = NativeListController(args: args, channel: channel) { [weak self] selected in
        self?.activeList = nil
        result(selected)
      }
      activeList = list
      let navigation = UINavigationController(rootViewController: list)
      navigation.modalPresentationStyle = .pageSheet
      if let dark = args["dark"] as? Bool { navigation.overrideUserInterfaceStyle = dark ? .dark : .light }
      if #available(iOS 15.0, *), let sheet = navigation.sheetPresentationController {
        sheet.detents = [.medium(), .large()]
        sheet.prefersGrabberVisible = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        sheet.prefersEdgeAttachedInCompactHeight = true
      }
      presenter.present(navigation, animated: true) { navigation.presentationController?.delegate = list }
    case "form":
      guard activeForm == nil && activeList == nil else {
        result(FlutterError(code: "busy", message: "A form is already open", details: nil)); return
      }
      let form = NativeFormController(args: args, channel: channel) { [weak self] values in
        self?.activeForm = nil
        result(values)
      }
      activeForm = form
      let navigation = UINavigationController(rootViewController: form)
      navigation.modalPresentationStyle = .pageSheet
      if let dark = args["dark"] as? Bool { navigation.overrideUserInterfaceStyle = dark ? .dark : .light }
      if #available(iOS 15.0, *), let sheet = navigation.sheetPresentationController {
        sheet.detents = [.medium(), .large()]
        sheet.prefersGrabberVisible = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        sheet.prefersEdgeAttachedInCompactHeight = true
        sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
      }
      presenter.present(navigation, animated: true) {
        navigation.presentationController?.delegate = form
      }
    case "confirm":
      let alert = UIAlertController(title: args["title"] as? String,
        message: args["message"] as? String, preferredStyle: .actionSheet)
      if let dark = args["dark"] as? Bool { alert.overrideUserInterfaceStyle = dark ? .dark : .light }
      for item in args["actions"] as? [[String: Any]] ?? [] {
        guard let id = item["id"] as? String, let label = item["label"] as? String else { continue }
        alert.addAction(UIAlertAction(title: label,
          style: item["destructive"] as? Bool == true ? .destructive : .default) { [weak alert] _ in
            alert?.dismiss(animated: true) { result(id) }
          })
      }
      alert.addAction(UIAlertAction(title: args["cancel"] as? String, style: .cancel) { [weak alert] _ in alert?.dismiss(animated: true) { result(nil) } })
      presenter.present(alert, animated: true)
    default: result(FlutterMethodNotImplemented)
    }
  }
}

private final class NativeFormController: UITableViewController, UITextFieldDelegate, UIAdaptivePresentationControllerDelegate {
  private let args: [String: Any]
  private let channel: FlutterMethodChannel
  private var completion: (([String: String]?) -> Void)?
  private var fields: [UITextField] = []
  private var labels: [String] = []
  private var keys: [String] = []
  private var initial: [String: String] = [:]
  private var error: String?
  private var submitting = false
  private var confirming = false
  private var submitItem: UIBarButtonItem!

  init(args: [String: Any], channel: FlutterMethodChannel, completion: @escaping ([String: String]?) -> Void) {
    self.args = args
    self.channel = channel
    self.completion = completion
    super.init(style: .insetGrouped)
    title = args["title"] as? String
    for item in args["fields"] as? [[String: Any]] ?? [] {
      guard let key = item["id"] as? String else { continue }
      let field = UITextField()
      field.text = item["value"] as? String ?? ""
      field.placeholder = item["placeholder"] as? String
      field.font = .preferredFont(forTextStyle: .body)
      field.adjustsFontForContentSizeCategory = true
      field.clearButtonMode = .whileEditing
      field.accessibilityIdentifier = "native-field-" + key
      field.accessibilityLabel = item["label"] as? String
      field.keyboardType = item["keyboard"] as? String == "url" ? .URL : item["keyboard"] as? String == "number" ? .numberPad : .default
      if field.keyboardType == .URL {
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.textContentType = .URL
      }
      field.returnKeyType = .done
      field.delegate = self
      field.addTarget(self, action: #selector(changed), for: .editingChanged)
      fields.append(field)
      keys.append(key)
      labels.append(item["label"] as? String ?? "")
      initial[key] = field.text ?? ""
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  private var values: [String: String] { Dictionary(uniqueKeysWithValues: zip(keys, fields.map { $0.text ?? "" })) }
  private var dirty: Bool { values != initial }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    tableView.backgroundColor = .clear
    tableView.keyboardDismissMode = .interactive
    tableView.cellLayoutMarginsFollowReadableWidth = true
    navigationItem.leftBarButtonItem = UIBarButtonItem(title: args["cancel"] as? String,
      style: .plain, target: self, action: #selector(cancel))
    if #available(iOS 26.0, *) {
      submitItem = UIBarButtonItem(title: args["submit"] as? String, style: .prominent, target: self, action: #selector(submit))
    } else {
      submitItem = UIBarButtonItem(title: args["submit"] as? String, style: .done, target: self, action: #selector(submit))
    }
    submitItem.accessibilityIdentifier = "native-form-submit"
    navigationItem.rightBarButtonItem = submitItem
    changed()
  }

  override func numberOfSections(in tableView: UITableView) -> Int { fields.count }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { labels[section] }
  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    section == fields.count - 1 ? (error ?? args["message"] as? String) : nil
  }
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    cell.selectionStyle = .none
    let field = fields[indexPath.section]
    field.translatesAutoresizingMaskIntoConstraints = false
    cell.contentView.addSubview(field)
    NSLayoutConstraint.activate([
      field.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
      field.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
      field.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
      field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
      field.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
    ])
    return cell
  }

  @objc private func changed() { navigationController?.isModalInPresentation = dirty || submitting }
  func textFieldShouldReturn(_ textField: UITextField) -> Bool { submit(); return false }
  @objc private func submit() {
    guard !submitting else { return }
    submitting = true
    submitItem.isEnabled = false
    changed()
    channel.invokeMethod("validate", arguments: ["id": args["id"] ?? "", "values": values]) { [weak self] reply in
      guard let self = self, self.completion != nil else { return }
      self.submitting = false
      self.submitItem.isEnabled = true
      self.changed()
      if let failure = reply as? FlutterError { self.showError(failure.message ?? failure.code) }
      else if let message = reply as? String, !message.isEmpty { self.showError(message) }
      else { self.finish(self.values) }
    }
  }
  private func showError(_ message: String) {
    error = message
    // Update the footer without recreating fields or interrupting the keyboard.
    tableView.beginUpdates()
    if let footer = tableView.footerView(forSection: fields.count - 1) {
      footer.textLabel?.text = message
      footer.textLabel?.textColor = .systemRed
    }
    tableView.endUpdates()
    UIAccessibility.post(notification: .announcement, argument: message)
  }
  @objc private func cancel() {
    guard !submitting else { return }
    guard dirty else { finish(nil); return }
    guard !confirming else { return }
    confirming = true
    let alert = UIAlertController(title: args["discardTitle"] as? String, message: nil, preferredStyle: .actionSheet)
    alert.addAction(UIAlertAction(title: args["keepEditing"] as? String, style: .cancel) { [weak self] _ in self?.confirming = false })
    alert.addAction(UIAlertAction(title: args["discard"] as? String, style: .destructive) { [weak self] _ in
      self?.confirming = false
      self?.finish(nil)
    })
    present(alert, animated: true)
  }
  private func finish(_ result: [String: String]?) {
    guard let complete = completion else { return }
    completion = nil
    submitting = true
    submitItem.isEnabled = false
    view.endEditing(true)
    dismiss(animated: true) { complete(result) }
  }
  func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) { cancel() }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    let complete = completion
    completion = nil
    complete?(nil)
  }
}

/// Real system material for phone chrome. Flutter paints only the controls.
final class NativeGlassFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    NativeGlass(frame: frame, args: args as? [String: Any] ?? [:])
  }
}
private final class NativeGlass: NSObject, FlutterPlatformView {
  private let material: UIVisualEffectView
  init(frame: CGRect, args: [String: Any]) {
    let effect: UIVisualEffect
    if #available(iOS 26.0, *) { effect = UIGlassEffect(style: .regular) }
    else { effect = UIBlurEffect(style: .systemMaterial) }
    material = UIVisualEffectView(effect: effect)
    super.init()
    material.frame = frame
    material.isUserInteractionEnabled = false
    material.overrideUserInterfaceStyle = args["dark"] as? Bool == true ? .dark : .light
    let radius = CGFloat(args["radius"] as? Double ?? 22)
    if #available(iOS 26.0, *) {
      material.cornerConfiguration = .capsule(maximumRadius: radius)
    } else {
      material.layer.cornerRadius = radius
      material.layer.cornerCurve = .continuous
      material.clipsToBounds = true
    }
    material.accessibilityElementsHidden = true
  }
  func view() -> UIView { material }
}


private final class NativeListController: UITableViewController, UIAdaptivePresentationControllerDelegate {
  private let args: [String: Any]
  private let channel: FlutterMethodChannel
  private let sections: [[String: Any]]
  private var section = 0
  private var completion: (([String: String]?) -> Void)?
  private let images = NSCache<NSString, UIImage>()
  private var requested = Set<String>()
  private let sectionButton = UIButton(type: .system)
  private var rows: [[String: Any]] { sections.indices.contains(section) ? sections[section]["rows"] as? [[String: Any]] ?? [] : [] }

  init(args: [String: Any], channel: FlutterMethodChannel, completion: @escaping ([String: String]?) -> Void) {
    self.args = args
    self.channel = channel
    self.sections = args["sections"] as? [[String: Any]] ?? []
    self.completion = completion
    super.init(style: .insetGrouped)
    self.section = sections.firstIndex { ($0["id"] as? String) == args["selectedSection"] as? String } ?? 0
    title = args["title"] as? String
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    tableView.backgroundColor = .clear
    tableView.keyboardDismissMode = .interactive
    tableView.estimatedRowHeight = 60
    tableView.rowHeight = UITableView.automaticDimension
    images.countLimit = 48
    navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: args["manage"] as? String, style: .plain, target: self, action: #selector(manage))
    sectionButton.showsMenuAsPrimaryAction = true
    sectionButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    sectionButton.accessibilityIdentifier = "native-reader-section"
    navigationItem.titleView = sectionButton
    updateSection()
  }
  private func updateSection() {
    guard !sections.isEmpty else { return }
    var configuration = UIButton.Configuration.plain()
    configuration.title = sections[section]["title"] as? String ?? ""
    configuration.image = UIImage(systemName: "chevron.down")
    configuration.imagePlacement = .trailing
    configuration.imagePadding = 5
    sectionButton.configuration = configuration
    sectionButton.menu = UIMenu(children: sections.enumerated().map { index, item in
      UIAction(title: item["title"] as? String ?? "", state: index == section ? .on : .off) { [weak self] _ in
        self?.section = index
        self?.updateSection()
      }
    })
    tableView.reloadData()
    if let current = rows.firstIndex(where: { $0["selected"] as? Bool == true }) {
      tableView.scrollToRow(at: IndexPath(row: current, section: 0), at: .middle, animated: false)
    }
    let label = UILabel()
    label.font = .preferredFont(forTextStyle: .body)
    label.adjustsFontForContentSizeCategory = true
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.text = sections[section]["empty"] as? String ?? args["empty"] as? String
    tableView.backgroundView = rows.isEmpty ? label : nil
  }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let item = rows[indexPath.row]
    let id = item["id"] as? String ?? ""
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    cell.accessibilityIdentifier = "native-reader-row-" + id
    cell.textLabel?.text = item["title"] as? String
    cell.textLabel?.font = .preferredFont(forTextStyle: .body)
    cell.textLabel?.adjustsFontForContentSizeCategory = true
    cell.textLabel?.numberOfLines = 2
    cell.detailTextLabel?.text = item["subtitle"] as? String
    cell.detailTextLabel?.font = .preferredFont(forTextStyle: .caption1)
    cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
    cell.indentationLevel = min(item["depth"] as? Int ?? 0, 6)
    cell.indentationWidth = 14
    cell.accessoryType = item["selected"] as? Bool == true ? .checkmark : .none
    cell.isUserInteractionEnabled = item["enabled"] as? Bool != false
    if !cell.isUserInteractionEnabled { cell.textLabel?.textColor = .secondaryLabel }
    if item["preview"] as? Bool == true {
      cell.imageView?.image = images.object(forKey: id as NSString) ?? UIImage(systemName: "doc")
      cell.imageView?.contentMode = .scaleAspectFit
      if images.object(forKey: id as NSString) == nil && requested.insert(id).inserted {
        channel.invokeMethod("preview", arguments: ["id": args["id"] ?? "", "row": id]) { [weak self] reply in
          guard let self = self, self.completion != nil, let data = reply as? FlutterStandardTypedData,
            let image = UIImage(data: data.data) else { return }
          self.requested.remove(id)
          let size = CGSize(width: 72, height: 100)
          let scaled = UIGraphicsImageRenderer(size: size).image { _ in
            let scale = min(size.width / image.size.width, size.height / image.size.height)
            let rect = CGRect(x: (size.width - image.size.width * scale) / 2,
              y: (size.height - image.size.height * scale) / 2,
              width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: rect)
          }
          self.images.setObject(scaled, forKey: id as NSString)
          // A response can arrive after switching categories. Find by stable id.
          if let row = self.rows.firstIndex(where: { $0["id"] as? String == id }) {
            self.tableView.reloadRows(at: [IndexPath(row: row, section: 0)], with: .none)
          }
        }
      }
    }
    return cell
  }
  override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    rows[indexPath.row]["preview"] as? Bool == true ? 128 : UITableView.automaticDimension
  }
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    finish(rows[indexPath.row]["id"] as? String)
  }
  @objc private func close() { finish(nil) }
  @objc private func manage() { finish("__manage__") }
  private func finish(_ selected: String?) {
    guard let complete = completion else { return }
    completion = nil
    dismiss(animated: true) { complete(["section": self.sections[self.section]["id"] as? String ?? "", "id": selected ?? "__close__"]) }
  }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    let complete = completion
    completion = nil
    complete?(["section": sections[section]["id"] as? String ?? "", "id": "__close__"])
  }
}

private final class NativeColorDelegate: NSObject, UIColorPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
  private var completion: ((Int?) -> Void)?
  private var selected: Int?
  init(completion: @escaping (Int?) -> Void) { self.completion = completion }
  func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    guard viewController.selectedColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
    selected = 0xFF000000 | (Int((r * 255).rounded()) << 16) | (Int((g * 255).rounded()) << 8) | Int((b * 255).rounded())
  }
  func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) { finish() }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish() }
  private func finish() { let complete = completion; completion = nil; complete?(selected) }
}
