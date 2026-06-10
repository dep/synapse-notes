import AppKit

// MARK: - Completion popover

class CompletionViewController: NSViewController {
    var onSelect: ((URL) -> Void)?
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var allFiles: [URL] = []
    private var filteredFiles: [URL] = []

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))

        searchField.placeholderString = "Search files..."
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.delegate = self
        searchField.font = .systemFont(ofSize: 12)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        col.isEditable = false
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 26
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(selectItem)
        tableView.target = self
        tableView.allowsEmptySelection = false

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(searchField)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
    }

    @objc private func searchChanged() {
        applyFilter()
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: .newlines).joined()
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scoreFile(_ url: URL, query: String) -> Int? {
        if query.isEmpty { return 1 }
        let name = normalize(url.deletingPathExtension().lastPathComponent)
        let path = normalize(url.path)
        if let range = name.range(of: query) {
            let offset = name.distance(from: name.startIndex, to: range.lowerBound)
            return 400 - min(offset, 300)
        }
        if let range = path.range(of: query) {
            let offset = path.distance(from: path.startIndex, to: range.lowerBound)
            return 200 - min(offset, 180)
        }
        return nil
    }

    private func applyFilter() {
        let query = normalize(searchField.stringValue)
        filteredFiles = allFiles
            .compactMap { url -> (URL, Int)? in
                guard let score = scoreFile(url, query: query) else { return nil }
                return (url, score)
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
        tableView.reloadData()
        if !filteredFiles.isEmpty {
            tableView.selectRowIndexes([0], byExtendingSelection: false)
        }
    }

    @objc func selectItem() {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredFiles.count else { return }
        onSelect?(filteredFiles[row])
    }

    func selectCurrentItem() { selectItem() }

    func moveSelection(by delta: Int) {
        guard !filteredFiles.isEmpty else { return }
        let current = max(0, tableView.selectedRow)
        let next = max(0, min(filteredFiles.count - 1, current + delta))
        tableView.selectRowIndexes([next], byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }
}

extension CompletionViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { filteredFiles.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let name = filteredFiles[row].deletingPathExtension().lastPathComponent
        let cell = NSTextField(labelWithString: name)
        cell.font = .systemFont(ofSize: 13)
        cell.lineBreakMode = .byTruncatingMiddle
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {}
}

extension CompletionViewController: NSSearchFieldDelegate, NSControlTextEditingDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            selectCurrentItem()
            return true
        default:
            return false
        }
    }
}
