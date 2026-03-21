import UIKit

/// Simple demo app with navigation, input, and data store.
class HomeViewController: UIViewController {
    private let store = AppStore.shared

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 20, weight: .medium)
        label.textAlignment = .center
        return label
    }()

    private lazy var nameField: UITextField = {
        let field = UITextField()
        field.borderStyle = .roundedRect
        field.placeholder = "Enter name"
        return field
    }()

    private lazy var updateButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Update Name", for: .normal)
        button.addTarget(self, action: #selector(updateName), for: .touchUpInside)
        return button
    }()

    private lazy var settingsButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Go to Settings", for: .normal)
        button.addTarget(self, action: #selector(goToSettings), for: .touchUpInside)
        return button
    }()

    private lazy var detailButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Go to Detail", for: .normal)
        button.addTarget(self, action: #selector(goToDetail), for: .touchUpInside)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Home"
        view.backgroundColor = .systemBackground
        setupUI()
        refreshLabel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshLabel()
    }

    private func setupUI() {
        let stack = UIStackView(arrangedSubviews: [
            nameLabel, nameField, updateButton, settingsButton, detailButton
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
        ])
    }

    private func refreshLabel() {
        let name = store.get("user_name") as? String ?? "Unknown"
        nameLabel.text = "Hello, \(name)!"
    }

    @objc private func updateName() {
        guard let text = nameField.text, !text.isEmpty else { return }
        store.set("user_name", value: text)
        refreshLabel()
        nameField.text = ""
    }

    @objc private func goToSettings() {
        navigationController?.pushViewController(SettingsViewController(), animated: true)
    }

    @objc private func goToDetail() {
        navigationController?.pushViewController(DetailViewController(), animated: true)
    }
}

// MARK: - Settings

class SettingsViewController: UIViewController {
    private let store = AppStore.shared

    private lazy var themeSwitch: UISwitch = {
        let s = UISwitch()
        s.isOn = (store.get("theme") as? String) == "dark"
        s.addTarget(self, action: #selector(toggleTheme), for: .valueChanged)
        return s
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "Dark Mode"

        let stack = UIStackView(arrangedSubviews: [label, themeSwitch])
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    @objc private func toggleTheme() {
        store.set("theme", value: themeSwitch.isOn ? "dark" : "light")
    }
}

// MARK: - Detail

class DetailViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Detail"
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "Detail Page"
        label.font = .systemFont(ofSize: 24)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}

// MARK: - App Store (shared state)

class AppStore {
    static let shared = AppStore()
    private var data: [String: Any] = [
        "user_name": "Alice",
        "theme": "light",
        "notifications_enabled": true,
        "item_count": 3,
    ]

    func get(_ key: String) -> Any? { data[key] }
    func set(_ key: String, value: Any) { data[key] = value }
    func all() -> [String: Any] { data }
}
