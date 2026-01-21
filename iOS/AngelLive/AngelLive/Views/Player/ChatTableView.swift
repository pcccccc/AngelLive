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
        tableView.register(ChatBubbleTableViewCell.self, forCellReuseIdentifier: ChatBubbleTableViewCell.reuseIdentifier)
        return tableView
    }

    func updateUIView(_ uiView: UITableView, context: Context) {
        context.coordinator.setShowJumpToLatest = { value in
            if showJumpToLatest != value {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showJumpToLatest = value
                }
            }
        }
        context.coordinator.update(messages: messages, in: uiView)
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
        var setShowJumpToLatest: ((Bool) -> Void)?

        func update(messages: [ChatMessage], in tableView: UITableView) {
            let newIDs = messages.map { $0.id }
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

        // MARK: - UITableViewDataSource

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            messages.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: ChatBubbleTableViewCell.reuseIdentifier, for: indexPath) as? ChatBubbleTableViewCell else {
                return UITableViewCell()
            }
            cell.configure(with: messages[indexPath.row])
            return cell
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

final class ChatBubbleTableViewCell: UITableViewCell {
    static let reuseIdentifier = "ChatBubbleTableViewCell"

    private let bubbleView = UIView()
    private let stackView = UIStackView()
    private let iconView = UIImageView()
    private let userNameLabel = UILabel()
    private let messageLabel = UILabel()

    private var usesCapsule = true
    private var isSystemMessage = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let baseLineHeight = max(messageLabel.font.lineHeight, userNameLabel.font.lineHeight, iconView.bounds.height)
        if stackView.bounds.height > 0 {
            usesCapsule = stackView.bounds.height <= (baseLineHeight + 1)
        }
        let targetRadius = usesCapsule ? bubbleView.bounds.height / 2 : 12
        if bubbleView.layer.cornerRadius != targetRadius {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bubbleView.layer.cornerRadius = targetRadius
            CATransaction.commit()
        }
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        let horizontalPadding: CGFloat = 16
        let verticalPadding = AppConstants.Spacing.sm

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.layer.masksToBounds = true
        bubbleView.layer.cornerCurve = .continuous
        bubbleView.layer.actions = ["cornerRadius": NSNull()]
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
        isSystemMessage = message.isSystemMessage

        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if isSystemMessage {
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

        setNeedsLayout()
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

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
