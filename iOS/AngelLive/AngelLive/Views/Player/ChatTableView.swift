//
//  ChatTableView.swift
//  AngelLive
//
//  UIKit-based chat list for smoother scrolling
//

import SwiftUI
import UIKit
import AngelLiveCore

struct ChatTableView: UIViewRepresentable {
    let messages: [ChatMessage]
    @Binding var showJumpToLatest: Bool
    @Binding var scrollToBottomRequest: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITableView {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.keyboardDismissMode = .interactive
        tableView.estimatedRowHeight = 44
        tableView.rowHeight = UITableView.automaticDimension
        tableView.contentInset = UIEdgeInsets(top: 12, left: 0, bottom: 72, right: 0)
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.register(ChatBubbleCapsuleCell.self, forCellReuseIdentifier: ChatBubbleCapsuleCell.reuseIdentifier)
        tableView.register(ChatBubbleRoundedCell.self, forCellReuseIdentifier: ChatBubbleRoundedCell.reuseIdentifier)
        return tableView
    }

    func updateUIView(_ uiView: UITableView, context: Context) {
        context.coordinator.setShowJumpToLatest = { [self] value in
            if showJumpToLatest != value {
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showJumpToLatest = value
                    }
                }
            }
        }
        context.coordinator.update(messages: messages, tableView: uiView)
        if scrollToBottomRequest {
            context.coordinator.scrollToBottom(in: uiView, animated: true)
            DispatchQueue.main.async {
                scrollToBottomRequest = false
                showJumpToLatest = false
            }
        }
    }

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        private var messages: [ChatMessage] = []
        private var messageIDs: [UUID] = []
        private var isUserAtBottom = true
        private var cachedCellTypes: [UUID: Bool] = [:] // true = capsule, false = rounded
        private var lastTableWidth: CGFloat = 0
        var setShowJumpToLatest: ((Bool) -> Void)?

        func update(messages: [ChatMessage], tableView: UITableView) {
            let newIDs = messages.map { $0.id }
            let tableWidth = tableView.bounds.width
            
            // 宽度变化时，清除缓存并刷新
            if tableWidth != lastTableWidth && lastTableWidth > 0 {
                cachedCellTypes.removeAll()
                self.messages = messages
                messageIDs = newIDs
                lastTableWidth = tableWidth
                tableView.reloadData()
                if isUserAtBottom {
                    scrollToBottom(in: tableView, animated: false)
                }
                return
            }
            lastTableWidth = tableWidth
            
            if newIDs == messageIDs {
                return
            }

            if messageIDs.isEmpty {
                self.messages = messages
                messageIDs = newIDs
                tableView.reloadData()
                scrollToBottom(in: tableView, animated: false)
                return
            }

            let canInsert = newIDs.count >= messageIDs.count && isPrefix(messageIDs, of: newIDs)
            if canInsert {
                let insertedRange = messageIDs.count..<newIDs.count
                if !insertedRange.isEmpty {
                    self.messages = messages
                    let indexPaths = insertedRange.map { IndexPath(row: $0, section: 0) }
                    UIView.performWithoutAnimation {
                        tableView.performBatchUpdates {
                            tableView.insertRows(at: indexPaths, with: .none)
                        }
                        tableView.layoutIfNeeded()
                    }
                    messageIDs = newIDs
                    if isUserAtBottom {
                        scrollToBottom(in: tableView, animated: false)
                        setShowJumpToLatest?(false)
                    } else {
                        setShowJumpToLatest?(true)
                    }
                    return
                }
            }

            self.messages = messages
            messageIDs = newIDs
            tableView.reloadData()
            if isUserAtBottom {
                scrollToBottom(in: tableView, animated: false)
                setShowJumpToLatest?(false)
            } else {
                setShowJumpToLatest?(true)
            }
        }

        private func isPrefix(_ prefix: [UUID], of array: [UUID]) -> Bool {
            guard array.count >= prefix.count else { return false }
            for index in prefix.indices {
                if prefix[index] != array[index] {
                    return false
                }
            }
            return true
        }

        func scrollToBottom(in tableView: UITableView, animated: Bool) {
            let row = max(0, messages.count - 1)
            guard messages.indices.contains(row) else { return }
            tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .bottom, animated: animated)
        }
        
        /// 判断消息是否为单行（使用胶囊样式）
        private func isSingleLine(message: ChatMessage, tableWidth: CGFloat) -> Bool {
            if let cached = cachedCellTypes[message.id] {
                return cached
            }
            
            let horizontalPadding: CGFloat = 16 * 2  // cell 左右边距
            let bubblePadding: CGFloat = 12 * 2      // bubble 内边距
            let spacing: CGFloat = 8                  // userName 和 message 之间的间距
            
            let availableWidth = tableWidth - horizontalPadding - bubblePadding
            
            let font = UIFont.preferredFont(forTextStyle: .caption1)
            let userNameFont = font.withWeight(.semibold)
            
            if message.isSystemMessage {
                let iconWidth: CGFloat = 14 + spacing
                let textWidth = availableWidth - iconWidth
                let messageSize = (message.message as NSString).boundingRect(
                    with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: UIFont.preferredFont(forTextStyle: .caption2)],
                    context: nil
                )
                let isSingle = messageSize.height <= font.lineHeight + 2
                cachedCellTypes[message.id] = isSingle
                return isSingle
            } else {
                let userNameSize = (message.userName as NSString).boundingRect(
                    with: CGSize(width: .greatestFiniteMagnitude, height: font.lineHeight),
                    options: [.usesLineFragmentOrigin],
                    attributes: [.font: userNameFont],
                    context: nil
                )
                let textWidth = availableWidth - userNameSize.width - spacing
                let messageSize = (message.message as NSString).boundingRect(
                    with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: font],
                    context: nil
                )
                let isSingle = messageSize.height <= font.lineHeight + 2
                cachedCellTypes[message.id] = isSingle
                return isSingle
            }
        }

        // MARK: - UITableViewDataSource

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            messages.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let message = messages[indexPath.row]
            let useCapsule = isSingleLine(message: message, tableWidth: tableView.bounds.width)
            
            if useCapsule {
                guard let cell = tableView.dequeueReusableCell(withIdentifier: ChatBubbleCapsuleCell.reuseIdentifier, for: indexPath) as? ChatBubbleCapsuleCell else {
                    return UITableViewCell()
                }
                cell.configure(with: message)
                return cell
            } else {
                guard let cell = tableView.dequeueReusableCell(withIdentifier: ChatBubbleRoundedCell.reuseIdentifier, for: indexPath) as? ChatBubbleRoundedCell else {
                    return UITableViewCell()
                }
                cell.configure(with: message)
                return cell
            }
        }

        // MARK: - UITableViewDelegate

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let threshold: CGFloat = 60
            let offsetY = scrollView.contentOffset.y
            let visibleHeight = scrollView.bounds.height
            let contentHeight = scrollView.contentSize.height
            let isAtBottom = offsetY + visibleHeight >= contentHeight - threshold

            if isAtBottom != isUserAtBottom {
                isUserAtBottom = isAtBottom
                if isAtBottom {
                    setShowJumpToLatest?(false)
                }
            }
        }
    }
}

// MARK: - Base Cell Class

class ChatBubbleBaseCell: UITableViewCell {
    let bubbleView = UIView()
    let stackView = UIStackView()
    let iconView = UIImageView()
    let userNameLabel = UILabel()
    let messageLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        let horizontalPadding: CGFloat = 16
        let verticalPadding = AppConstants.Spacing.xs

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.layer.masksToBounds = true
        bubbleView.layer.cornerCurve = .continuous
        contentView.addSubview(bubbleView)

        stackView.axis = .horizontal
        stackView.alignment = .top
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(stackView)

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIColor.systemYellow.withAlphaComponent(0.8)
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        userNameLabel.numberOfLines = 1
        userNameLabel.setContentHuggingPriority(.required, for: .horizontal)
        userNameLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        userNameLabel.adjustsFontForContentSizeCategory = true
        userNameLabel.font = UIFont.preferredFont(forTextStyle: .caption1).withWeight(.semibold)

        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: verticalPadding),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -verticalPadding),
            bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalPadding),
            bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -horizontalPadding),

            stackView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8),
            stackView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),

            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14)
        ])
    }
    
    func configure(with message: ChatMessage) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if message.isSystemMessage {
            iconView.image = UIImage(systemName: "info.circle.fill")
            messageLabel.text = message.message
            messageLabel.textColor = UIColor.systemYellow.withAlphaComponent(0.9)
            messageLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
            stackView.addArrangedSubview(iconView)
            stackView.addArrangedSubview(messageLabel)

            bubbleView.backgroundColor = UIColor.black.withAlphaComponent(AppConstants.PlayerUI.Opacity.overlayMedium)
            bubbleView.layer.borderColor = UIColor.systemYellow.withAlphaComponent(0.3).cgColor
            bubbleView.layer.borderWidth = 0.5
        } else {
            userNameLabel.text = message.userName
            userNameLabel.textColor = chatUserColor(for: message.userName)
            messageLabel.text = message.message
            messageLabel.textColor = UIColor(white: 0.9, alpha: 1.0)
            messageLabel.font = UIFont.preferredFont(forTextStyle: .caption1)

            stackView.addArrangedSubview(userNameLabel)
            stackView.addArrangedSubview(messageLabel)

            bubbleView.backgroundColor = UIColor.black.withAlphaComponent(AppConstants.PlayerUI.Opacity.overlayMedium)
            bubbleView.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
            bubbleView.layer.borderWidth = 0.5
        }
    }
    
    private func chatUserColor(for userName: String) -> UIColor {
        let colors: [UIColor] = [
            .systemBlue, .systemGreen, .systemOrange, .systemPurple,
            .systemPink, .systemCyan, .systemMint, .systemIndigo
        ]
        let index = abs(userName.hashValue) % colors.count
        return colors[index]
    }
}

// MARK: - Capsule Cell (单行，胶囊圆角)

final class ChatBubbleCapsuleCell: ChatBubbleBaseCell {
    static let reuseIdentifier = "ChatBubbleCapsuleCell"
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // 胶囊样式：圆角 = 高度/2
        bubbleView.layer.cornerRadius = bubbleView.bounds.height / 2
    }
}

// MARK: - Rounded Cell (多行，固定圆角)

final class ChatBubbleRoundedCell: ChatBubbleBaseCell {
    static let reuseIdentifier = "ChatBubbleRoundedCell"
    
    override func setupUI() {
        super.setupUI()
        // 固定圆角 12
        bubbleView.layer.cornerRadius = 12
    }
}

// MARK: - UIFont Extension

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
