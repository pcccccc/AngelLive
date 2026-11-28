//
//  OpenSourceListView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/3/6.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct OpenSourceListView: View {
    var usesFullUI = false

    @State var acknowList: AcknowList = {
        let url = Bundle.main.url(forResource: "Package", withExtension: "resolved")
        let data = try? Data(contentsOf: url!)
        let acknowList = try? AcknowPackageDecoder().decode(from: data!)
        return acknowList!
    }()
    
    var body: some View {
        if usesFullUI {
            List(acknowList.acknowledgements) { acknowledgement in
                NavigationLink {
                    TVLicenseDetail(acknowledgement: acknowledgement)
                } label: {
                    Text(verbatim: acknowledgement.title)
                }
            }
            .navigationTitle("开源许可")
        } else {
            VStack {
                AcknowListSwiftUIView(acknowList: acknowList)
            }
        }
    }
}

private struct TVLicenseDetail: View {
    let acknowledgement: Acknow
    @Environment(\.dismiss) private var dismiss
    @State private var licenseText: String?
    @State private var loadFailed = false
    @State private var request: URLSessionDataTask?
    @State private var generation = UUID()

    private var repository: URL? {
        acknowledgement.repository.flatMap { GitHubAPI.isGitHubRepository($0) ? $0 : nil }
    }

    var body: some View {
        Group {
            if let text = acknowledgement.text ?? licenseText {
                TVLicenseTextView(text: text)
            } else if repository == nil {
                Text("此组件未提供许可正文。")
            } else if loadFailed {
                VStack {
                    Text("许可正文加载失败")
                    Button("重试", action: loadLicense)
                }
            } else {
                ProgressView("正在加载许可正文…")
            }
        }
        .navigationTitle(acknowledgement.title)
        .onAppear(perform: loadLicense)
        .onDisappear {
            generation = UUID()
            request?.cancel()
            request = nil
        }
        .tvFullUIBackCommand { dismiss() }
    }

    private func loadLicense() {
        guard acknowledgement.text == nil, licenseText == nil, request == nil, let repository else { return }
        loadFailed = false
        let currentGeneration = generation
        request = GitHubAPI.getLicense(for: repository) { result in
            // AcknowList delivers this completion on the main queue.
            MainActor.assumeIsolated {
                guard generation == currentGeneration else { return }
                request = nil
                switch result {
                case .success(let text): licenseText = text
                case .failure: loadFailed = true
                }
            }
        }
    }
}

private struct TVLicenseTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.isSelectable = true
        view.isUserInteractionEnabled = true
        view.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
    }
}

#Preview {
    OpenSourceListView()
}
