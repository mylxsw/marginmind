import Flutter
import UIKit

/// UIKit owns modal mechanics; the existing Dart isolate validates and saves.
/// No additional Flutter engine, repository, or assistant request owner.
final class NativePresentation {
  private let channel: FlutterMethodChannel
  private var activeActions: NativeActionsController?
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

  /// One presentation policy for outline, forms and reader actions.
  fileprivate static func configureSheet(_ navigation: UINavigationController, args: [String: Any]) {
    let dark = args["dark"] as? Bool
    let material = NativeModalStyle(args: args)
    navigation.modalPresentationStyle = .pageSheet
    if let dark {
      let style: UIUserInterfaceStyle = dark ? .dark : .light
      navigation.overrideUserInterfaceStyle = style
      // The sheet's material belongs to the presentation controller, outside
      // the navigation controller's view hierarchy. Keep both traits in sync.
      if #available(iOS 17.0, *) {
        navigation.presentationController?.traitOverrides.userInterfaceStyle = style
      }
    }
    navigation.loadViewIfNeeded()
    navigation.view.backgroundColor = material.background
    navigation.view.layer.borderColor = material.border.resolvedColor(with: navigation.traitCollection).cgColor
    navigation.view.layer.borderWidth = material.borderWidth
    navigation.view.layer.cornerRadius = material.radius
    navigation.view.layer.cornerCurve = .continuous
    navigation.view.clipsToBounds = true
    let bar = UINavigationBarAppearance()
    bar.configureWithOpaqueBackground()
    bar.backgroundColor = material.background
    bar.shadowColor = material.border
    bar.titleTextAttributes = [.foregroundColor: material.label]
    navigation.navigationBar.standardAppearance = bar
    navigation.navigationBar.scrollEdgeAppearance = bar
    navigation.navigationBar.compactAppearance = bar
    navigation.navigationBar.isTranslucent = false
    navigation.navigationBar.tintColor = material.accent
    if let content = navigation.viewControllers.first as? NativeModalTableController {
      content.modalStyle = material
      content.view.backgroundColor = material.background
      content.tableView.backgroundColor = material.background
      content.tableView.tintColor = material.accent
      content.tableView.reloadData()
    }
    if #available(iOS 15.0, *), let sheet = navigation.sheetPresentationController {
      sheet.preferredCornerRadius = material.radius
      sheet.detents = [.medium(), .large()]
      sheet.prefersGrabberVisible = true
      sheet.prefersScrollingExpandsWhenScrolledToEdge = true
      sheet.prefersEdgeAttachedInCompactHeight = true
      sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "available" { result(UIDevice.current.userInterfaceIdiom == .phone); return }
    guard UIDevice.current.userInterfaceIdiom == .phone,
      let args = call.arguments as? [String: Any], let presenter = presenter else {
      result(FlutterError(code: "unavailable", message: "No active iPhone window", details: nil)); return
    }
    switch call.method {
    case "actions":
      guard activeActions == nil && activeList == nil && activeForm == nil else {
        result(FlutterError(code: "busy", message: "A panel is already open", details: nil)); return
      }
      let actions = NativeActionsController(args: args, channel: channel) { [weak self] selected in
        self?.activeActions = nil
        result(selected)
      }
      activeActions = actions
      let navigation = UINavigationController(rootViewController: actions)
      Self.configureSheet(navigation, args: args)
      presenter.present(navigation, animated: true) { navigation.presentationController?.delegate = actions }
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
      guard activeList == nil && activeForm == nil && activeActions == nil else {
        result(FlutterError(code: "busy", message: "A panel is already open", details: nil)); return
      }
      let list = NativeListController(args: args, channel: channel) { [weak self] selected in
        self?.activeList = nil
        result(selected)
      }
      activeList = list
      let navigation = UINavigationController(rootViewController: list)
      Self.configureSheet(navigation, args: args)
      presenter.present(navigation, animated: true) { navigation.presentationController?.delegate = list }
    case "form":
      guard activeForm == nil && activeList == nil && activeActions == nil else {
        result(FlutterError(code: "busy", message: "A form is already open", details: nil)); return
      }
      let form = NativeFormController(args: args, channel: channel) { [weak self] values in
        self?.activeForm = nil
        result(values)
      }
      activeForm = form
      let navigation = UINavigationController(rootViewController: form)
      Self.configureSheet(navigation, args: args)
      presenter.present(navigation, animated: true) {
        navigation.presentationController?.delegate = form
      }
    case "confirm":
      let confirmation = NativeConfirmationController(args: args) { result($0) }
      let navigation = UINavigationController(rootViewController: confirmation)
      Self.configureSheet(navigation, args: args)
      presenter.present(navigation, animated: true) { navigation.presentationController?.delegate = confirmation }
    default: result(FlutterMethodNotImplemented)
    }
  }
}

/// Palette and geometry come from mm_design's MMModalStyle, never a second
/// set of native constants. UIKit still owns scrolling, keyboard and detents.
private struct NativeModalStyle {
  private let light: [String: Any]
  private let dark: [String: Any]
  init(args: [String: Any]) {
    let style = args["modalStyle"] as? [String: Any] ?? [:]
    light = style["light"] as? [String: Any] ?? [:]
    dark = style["dark"] as? [String: Any] ?? [:]
  }
  private func color(_ key: String, fallback: UIColor) -> UIColor {
    let lightValue = light[key] as? NSNumber
    let darkValue = dark[key] as? NSNumber
    return UIColor { traits in
      guard let number = traits.userInterfaceStyle == .dark ? darkValue : lightValue else { return fallback }
      let value = number.uint32Value
      return UIColor(red: CGFloat((value >> 16) & 255) / 255,
        green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255,
        alpha: CGFloat((value >> 24) & 255) / 255)
    }
  }
  var background: UIColor { color("background", fallback: .systemBackground) }
  var border: UIColor { color("border", fallback: .separator) }
  var card: UIColor { color("card", fallback: .secondarySystemGroupedBackground) }
  var label: UIColor { color("label", fallback: .label) }
  var secondaryLabel: UIColor { color("secondaryLabel", fallback: .secondaryLabel) }
  var accent: UIColor { color("accent", fallback: .systemBlue) }
  var critical: UIColor { color("critical", fallback: .systemRed) }
  var radius: CGFloat { (light["radius"] as? NSNumber).map { CGFloat(truncating: $0) } ?? 0 }
  var borderWidth: CGFloat { (light["borderWidth"] as? NSNumber).map { CGFloat(truncating: $0) } ?? 0 }
}

private class NativeModalTableController: UITableViewController {
  var modalStyle = NativeModalStyle(args: [:])

  override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
    // Clear cells hold grouped action tiles; leave their layout transparent
    // over the single opaque panel instead of introducing a second card.
    if cell.backgroundColor != .clear { cell.backgroundColor = modalStyle.card }
    cell.detailTextLabel?.textColor = modalStyle.secondaryLabel
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    flattenNavigationButtons()
  }

  func flattenNavigationButtons() {
    if #available(iOS 26.0, *) {
      for item in (navigationItem.leftBarButtonItems ?? []) + (navigationItem.rightBarButtonItems ?? []) {
        item.hidesSharedBackground = true
        item.setTitleTextAttributes([.foregroundColor: modalStyle.label], for: .normal)
        item.setTitleTextAttributes([.foregroundColor: modalStyle.secondaryLabel], for: .disabled)
      }
    }
  }
}

/// App confirmations use the same opaque sheet as forms and reader panels.
/// No private UIAlertController subviews or global system appearance overrides.
private final class NativeConfirmationController: NativeModalTableController, UIAdaptivePresentationControllerDelegate {
  private let args: [String: Any]
  private var completion: ((String?) -> Void)?
  private var actions: [[String: Any]] { args["actions"] as? [[String: Any]] ?? [] }

  init(args: [String: Any], completion: @escaping (String?) -> Void) {
    self.args = args
    self.completion = completion
    super.init(style: .insetGrouped)
    title = args["title"] as? String
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func viewDidLoad() {
    super.viewDidLoad()
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 52
    navigationItem.leftBarButtonItem = UIBarButtonItem(title: args["cancel"] as? String,
      style: .plain, target: self, action: #selector(cancel))
  }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { actions.count }
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    args["message"] as? String
  }
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let action = actions[indexPath.row]
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    cell.selectionStyle = .none
    cell.isAccessibilityElement = false
    let button = UIButton(type: .system)
    button.setTitle(action["label"] as? String, for: .normal)
    button.setTitleColor(action["destructive"] as? Bool == true ? modalStyle.critical : modalStyle.label, for: .normal)
    button.titleLabel?.font = .preferredFont(forTextStyle: .body)
    button.titleLabel?.adjustsFontForContentSizeCategory = true
    button.titleLabel?.numberOfLines = 0
    button.contentHorizontalAlignment = .leading
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addAction(UIAction { [weak self] _ in self?.finish(action["id"] as? String) }, for: .touchUpInside)
    cell.contentView.addSubview(button)
    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
      button.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
      button.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
      button.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
      button.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
    ])
    return cell
  }
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    finish(actions[indexPath.row]["id"] as? String)
  }
  @objc private func cancel() { finish(nil) }
  private func finish(_ value: String?) {
    guard let done = completion else { return }
    completion = nil
    dismiss(animated: true) { done(value) }
  }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    let done = completion; completion = nil; done?(nil)
  }
}

private final class NativeFormController: NativeModalTableController, UITextFieldDelegate, UIAdaptivePresentationControllerDelegate {
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
        // The system paste control grants access only after the user's tap.
        let paste = UIPasteControl(configuration: UIPasteControl.Configuration())
        paste.target = field
        paste.sizeToFit()
        field.rightView = paste
        field.rightViewMode = .always
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
    submitItem = UIBarButtonItem(title: args["submit"] as? String, style: .done, target: self, action: #selector(submit))
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
    field.textColor = modalStyle.label
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
    var confirmationArgs = args
    confirmationArgs["title"] = args["discardTitle"]
    confirmationArgs["message"] = nil
    confirmationArgs["cancel"] = args["keepEditing"]
    confirmationArgs["actions"] = [["id": "discard", "label": args["discard"] ?? "", "destructive": true]]
    let confirmation = NativeConfirmationController(args: confirmationArgs) { [weak self] selected in
      self?.confirming = false
      if selected == "discard" { self?.finish(nil) }
    }
    let navigation = UINavigationController(rootViewController: confirmation)
    NativePresentation.configureSheet(navigation, args: confirmationArgs)
    present(navigation, animated: true) { navigation.presentationController?.delegate = confirmation }
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


private final class NativeListController: NativeModalTableController, UIAdaptivePresentationControllerDelegate {
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
    navigationItem.leftBarButtonItem = UIBarButtonItem(title: args["close"] as? String,
      style: .plain, target: self, action: #selector(close))
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
    cell.textLabel?.textColor = modalStyle.label
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


/// UIKit renders action data; Dart remains the sole owner of reader settings.
private final class NativeActionsController: NativeModalTableController, UIAdaptivePresentationControllerDelegate {
  private var content: [String: Any]
  private let channel: FlutterMethodChannel
  private let requestID: String
  private var completion: ((String?) -> Void)?
  private var updating = false
  private var appearance: Bool { content["appearance"] as? Bool == true }
  private var groups: [[[String: Any]]] {
    if appearance { return [content["styles"] as? [[String: Any]] ?? []] }
    return [[]] + (content["groups"] as? [[[String: Any]]] ?? [])
  }

  init(args: [String: Any], channel: FlutterMethodChannel, completion: @escaping (String?) -> Void) {
    content = args
    requestID = args["id"] as? String ?? ""
    self.channel = channel
    self.completion = completion
    super.init(style: .insetGrouped)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    tableView.backgroundColor = .clear
    tableView.accessibilityIdentifier = "native-reader-actions"
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 56
    refresh()
  }

  private func refresh() {
    title = content[appearance ? "appearanceTitle" : "title"] as? String
    let close = UIBarButtonItem(title: content["close"] as? String,
      style: .plain, target: self, action: #selector(closePanel))
    close.accessibilityLabel = content["close"] as? String
    close.accessibilityIdentifier = "native-actions-close"
    navigationItem.leftBarButtonItem = close
    if appearance {
      let back = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(back))
      back.accessibilityLabel = content["back"] as? String
      back.accessibilityIdentifier = "native-actions-back"
      navigationItem.rightBarButtonItems = [back]
    } else {
      let undo = UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.backward"), style: .plain, target: self, action: #selector(undo))
      undo.accessibilityLabel = content["undo"] as? String
      undo.accessibilityIdentifier = "native-actions-undo"
      undo.isEnabled = content["canUndo"] as? Bool == true
      navigationItem.rightBarButtonItems = [undo]
    }
    flattenNavigationButtons()
    tableView.reloadData()
  }

  @objc private func closePanel() { finish(nil) }
  @objc private func back() { perform(["id": "back", "inline": true]) }
  @objc private func undo() { finish("undo") }
  private func finish(_ selected: String?) {
    guard let done = completion else { return }
    completion = nil
    dismiss(animated: true) { done(selected) }
  }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    let done = completion
    completion = nil
    done?(nil)
  }

  private func perform(_ item: [String: Any]) {
    guard !updating, item["enabled"] as? Bool != false, let id = item["id"] as? String else { return }
    guard item["inline"] as? Bool == true else { finish(id); return }
    updating = true
    channel.invokeMethod("action", arguments: ["id": requestID, "action": id]) { [weak self] response in
      guard let self else { return }
      self.updating = false
      guard self.completion != nil else { return }
      if let updated = response as? [String: Any], !updated.isEmpty {
        self.content = updated
        self.refresh()
      }
    }
  }

  override func numberOfSections(in tableView: UITableView) -> Int { groups.count }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    !appearance && section == 0 ? 1 : groups[section].count
  }
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
    if !appearance && indexPath.section == 0 {
      cell.backgroundColor = .clear
      cell.selectionStyle = .none
      let stack = UIStackView()
      stack.axis = .horizontal
      stack.spacing = 10
      stack.distribution = .fillEqually
      stack.translatesAutoresizingMaskIntoConstraints = false
      for tile in content["tiles"] as? [[String: Any]] ?? [] {
        var config = UIButton.Configuration.filled()
        let selected = tile["selected"] as? Bool == true
        config.title = tile["title"] as? String
        config.image = UIImage(systemName: tile["icon"] as? String ?? "circle")
        config.imagePlacement = .top
        config.imagePadding = 12
        config.baseBackgroundColor = selected ? .systemBlue : .secondarySystemGroupedBackground
        config.baseForegroundColor = selected ? .white : .label
        config.cornerStyle = .large
        config.titleLineBreakMode = .byWordWrapping
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 4, bottom: 16, trailing: 4)
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.perform(tile) })
        button.isEnabled = tile["enabled"] as? Bool != false
        button.accessibilityIdentifier = "native-actions-" + (tile["id"] as? String ?? "")
        if selected { button.accessibilityTraits.insert(.selected) }
        stack.addArrangedSubview(button)
      }
      cell.contentView.addSubview(stack)
      NSLayoutConstraint.activate([
        stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
        stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
        stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
        stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
      ])
      return cell
    }
    let row = groups[indexPath.section][indexPath.row]
    cell.textLabel?.text = row["title"] as? String
    cell.textLabel?.font = .preferredFont(forTextStyle: .body)
    cell.textLabel?.adjustsFontForContentSizeCategory = true
    cell.textLabel?.numberOfLines = 0
    cell.detailTextLabel?.text = row["value"] as? String
    cell.imageView?.image = UIImage(systemName: row["icon"] as? String ?? "circle")
    cell.imageView?.tintColor = .systemBlue
    let enabled = row["enabled"] as? Bool != false
    cell.textLabel?.textColor = enabled ? modalStyle.label : modalStyle.secondaryLabel
    cell.imageView?.alpha = enabled ? 1 : 0.3
    cell.selectionStyle = enabled ? .default : .none
    cell.accessibilityIdentifier = "native-actions-" + (row["id"] as? String ?? "")
    if !enabled { cell.accessibilityTraits.insert(.notEnabled) }
    if appearance {
      if row["selected"] as? Bool == true { cell.accessibilityTraits.insert(.selected) }
      if let paper = row["paper"] as? Int, let ink = row["ink"] as? Int {
        let color: (Int) -> UIColor = { value in UIColor(red: CGFloat((value >> 16) & 255) / 255,
          green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1) }
        let swatch = UILabel(frame: CGRect(x: 0, y: 0, width: 38, height: 38))
        swatch.text = "Aa"; swatch.textAlignment = .center
        swatch.backgroundColor = color(paper); swatch.textColor = color(ink)
        swatch.layer.cornerRadius = 8; swatch.clipsToBounds = true
        cell.imageView?.image = nil
        let accessory = UIView(frame: CGRect(x: 0, y: 0, width: 70, height: 38))
        accessory.addSubview(swatch)
        let check = UIImageView(image: UIImage(systemName: "checkmark"))
        check.frame = CGRect(x: 48, y: 9, width: 20, height: 20)
        check.tintColor = .systemBlue
        check.alpha = row["selected"] as? Bool == true ? 1 : 0
        accessory.addSubview(check)
        cell.accessoryView = accessory
      }
    } else if enabled { cell.accessoryType = .disclosureIndicator }
    return cell
  }
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard appearance || indexPath.section != 0 else { return }
    perform(groups[indexPath.section][indexPath.row])
  }
}
