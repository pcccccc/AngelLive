# SharedAssets

共享的资源包，包含在 iOS、macOS 和 tvOS 项目之间共享的颜色、图片等资源。

## 功能特性

- ✅ 跨平台支持（iOS 15+、macOS 12+、tvOS 15+）
- ✅ 自动适配深色模式
- ✅ 类型安全的资源访问
- ✅ SwiftUI 和 UIKit/AppKit 双支持

## 集成方式

### 方法 1: 通过 Xcode 添加本地 Package

1. 打开你的 `.xcodeproj` 文件
2. 选择项目 -> Package Dependencies 标签
3. 点击 "+" 按钮
4. 选择 "Add Local..."
5. 导航到 `Shared/SharedAssets` 文件夹并选择
6. 在你的 target 中添加 `SharedAssets` 依赖

### 方法 2: 通过 Workspace 添加

如果你使用 `.xcworkspace`：

1. 将 `SharedAssets/Package.swift` 拖入 Xcode workspace
2. 在各个项目的 target 设置中，添加 `SharedAssets` 到 Frameworks and Libraries

## 使用方式

### SwiftUI

```swift
import SwiftUI
import SharedAssets

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Hello")
                .foregroundColor(SharedAssets.Colors.appAccent)

            // 或使用便捷方法
            Text("World")
                .foregroundColor(.shared("AppAccentColor"))
        }
    }
}
```

### UIKit (iOS/tvOS)

```swift
import UIKit
import SharedAssets

class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = SharedAssets.Colors.appAccentUIColor
    }
}
```

### AppKit (macOS)

```swift
import AppKit
import SharedAssets

class ViewController: NSViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.layer?.backgroundColor = SharedAssets.Colors.appAccentNSColor.cgColor
    }
}
```

## 添加新资源

### 添加颜色

1. 在 Xcode 中打开 `Sources/SharedAssets/Resources/Assets.xcassets`
2. 右键 -> New Color Set
3. 配置颜色（支持 Light/Dark mode）
4. 在 `SharedAssets.swift` 中添加访问器：

```swift
public struct Colors {
    public static var yourNewColor: Color {
        Color("YourColorName", bundle: .module)
    }
}
```

### 添加图片

1. 在 `Assets.xcassets` 中添加图片资源
2. 在 `SharedAssets.swift` 中添加访问器：

```swift
public struct Images {
    public static var yourImage: Image {
        Image("YourImageName", bundle: .module)
    }
}
```

## 文件结构

```
SharedAssets/
├── Package.swift
└── Sources/
    └── SharedAssets/
        ├── SharedAssets.swift          # 资源访问器
        └── Resources/
            └── Assets.xcassets/         # 资源文件
                ├── AppAccentColor.colorset/
                └── Contents.json
```

## 注意事项

- 资源文件必须放在 `Sources/SharedAssets/Resources/` 下
- 使用 `.module` bundle 来访问 package 中的资源
- 颜色和图片支持自动适配深色模式
