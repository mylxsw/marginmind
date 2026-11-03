import UIKit

/// The extension only stages content. Parsing and library writes stay in Runner.
/// Share extensions cannot reliably launch their containing app through public
/// APIs, so the system sheet explicitly tells the user how to continue.
final class ShareViewController: UIViewController {
  private let status = UILabel()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private var started = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    preferredContentSize = CGSize(width: 480, height: 280)
    let title = UILabel()
    title.text = "Foliarc"
    title.font = .preferredFont(forTextStyle: .title2)
    title.adjustsFontForContentSizeCategory = true
    status.text = NSLocalizedString("saving", comment: "Saving incoming share")
    status.font = .preferredFont(forTextStyle: .body)
    status.adjustsFontForContentSizeCategory = true
    status.numberOfLines = 0
    status.textAlignment = .center
    let done = UIButton(type: .system)
    done.setTitle(NSLocalizedString("done", comment: "Close share sheet"), for: .normal)
    done.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    done.addTarget(self, action: #selector(close), for: .touchUpInside)
    done.isEnabled = false
    done.tag = 1
    let stack = UIStackView(arrangedSubviews: [title, spinner, status, done])
    stack.axis = .vertical
    stack.spacing = 20
    stack.alignment = .center
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
      stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
      done.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
    ])
    spinner.startAnimating()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !started else { return }
    started = true
    let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
    let providers = items.flatMap { $0.attachments ?? [] }
    let title = items.first?.attributedTitle?.string
    Task {
      let outcome = await Task.detached { () -> String in
        do {
          let store = try IncomingShareStore.shared()
          try store.prune()
          try await IncomingShareLoader.receive(providers, title: title, store: store)
          return "saved"
        } catch IncomingShareStore.Failure.limit { return "limit" }
        catch IncomingShareStore.Failure.unsupported { return "unsupported" }
        catch { return "failed" }
      }.value
      spinner.stopAnimating()
      status.text = NSLocalizedString(outcome, comment: "Share result")
      (view.viewWithTag(1) as? UIButton)?.isEnabled = true
    }
  }

  @objc private func close() {
    extensionContext?.completeRequest(returningItems: nil)
  }
}
