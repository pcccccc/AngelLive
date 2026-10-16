# SharedAssets

共享的资源包，包含在 iOS、macOS 和 tvOS 项目之间共享的颜色、图片等资源。

## 功能特性

- ✅ 跨平台支持（iOS 15+、macOS 12+、tvOS 15+）
- ✅ 自动适配深色模式
- ✅ 类型安全的资源访问
- ✅ SwiftUI 和 UIKit/AppKit 双支持

## 集成方式

本仓库已将 SharedAssets 集成到 `AngelLive.xcworkspace`。从仓库根目录打开 workspace，使用既有本地 Package 引用；不要另开单独工程或重复添加依赖来代替 workspace 构建。

外部项目需要单独复用时，可通过 Xcode 的 Add Local Package 选择本目录，并向使用资源的 target 链接 `SharedAssets` product。包自身最低系统版本以 `Package.swift` 为准，不替代宿主的最低版本。

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
        ├── ArcSpinner.swift           # FullUI 加载样式
        ├── ArcRefreshControlDecoration.swift # iOS 原生刷新装饰
        └── Resources/
            └── Assets.xcassets/         # 资源文件
                ├── AppAccentColor.colorset/
                └── Contents.json
```

## 注意事项

- 资源文件必须放在 `Sources/SharedAssets/Resources/` 下
- 使用 `.module` bundle 来访问 package 中的资源
- 颜色和图片支持自动适配深色模式

## FullUI loading

`ArcSpinner(size:lineWidth:)` is the existing player arc: `Circle.trim(0...0.22)`,
round stroke caps, 0.95 seconds per revolution. It inherits `.tint` at 90% opacity.
Player callers preserve their existing dimensions: iOS 42/1.8, macOS 34/1.5,
tvOS 64/2.5, with `.tint(.white)`. Reduce Motion presents a static arc.

Install `.fullUIArcLoadingStyle(isEnabled: isFullUI)` outside the scene's
presentation modifiers. Keep the modifier present when the mode changes: the
style invokes the native default renderer when disabled, without replacing the
host content. Ordinary indeterminate `ProgressView` uses the environment's
control size; explicit `size` / `lineWidth` parameters are available for player
and other established layouts. Labels and current-value labels are retained.
Determinate progress is rendered by `LinearProgressViewStyle`, not by an arc.
Independent UIKit hosting roots require their own opt-in installation.

Visual acceptance must use new builds for each affected host:

- Compare arc length, round caps, white tint and 42/34/64 player dimensions with
  the original player; retain each page's existing container and label spacing.
- Check mini/small/regular/large loading in buttons, lists, sheets and players;
  no new row height, truncation, clipping or hit target changes.
- Check inherited tint in light/dark appearance, labelled and unlabelled loading,
  VoiceOver labels and current values, and stationary arcs with Reduce Motion.
- Verify determinate bars, numeric progress and labels remain native.
- Toggle the FullUI gate without losing navigation/selection state; disabled
  mode must render the native style. Explicit descendant styles override the
  environment and must be audited at their call sites.

A `ProgressViewStyle` does not restyle `UIRefreshControl`, SwiftUI's platform
refresh indicator, `UIActivityIndicatorView`, or indicators owned by third-party
views. Those surfaces require a separate, scoped integration; this component
alone does not claim to replace every platform-native loading indicator.

### Native iOS refresh integration

`ArcRefreshControlDecoration` (iOS 16+) decorates an existing `UIRefreshControl`:
`attach(to:isRefreshing:)`, `update(isRefreshing:)`, and `detach()`. One retained
`UIHostingConfiguration` content view renders the same 20/1.5 `ArcSpinner`; a
pull reveals a stationary arc and refreshing rotates it, respecting Reduce
Motion. The decoration retains/restores the original tint and leaves actions,
refresh state, insets and accessibility to the native control.

The iOS FullUI `FullUIArcRefreshIndicator` probe is placed inside the three
actual ScrollView/List content trees. It uses only the nearest ancestor
UIScrollView and its public `refreshControl`, rechecks during view updates,
layout and content-offset changes, and makes one deferred attachment attempt.
It never scans a window, uses private class names, replaces native targets, or
polls indefinitely. Disabling the mode gate or unloading the probe detaches the
decoration and restores tint. Existing refresh closures and the home release
gate remain in charge of refresh timing.

UIKit room lists attach the same decoration. Favorites already suppress the
native spinner and present their own synchronization progress; no second
indicator is added there. The plugin-management list's probe uses the dynamic
FullUI gate because that page is also reachable from ShellUI.

Required native-refresh verification: first pull and repeated pulls on home,
category, plugin management, and UIKit room lists; cancelled pull before the
threshold; async completion/error; leaving/reentering while refreshing; light
and dark tint; Reduce Motion; dynamic FullUI-to-ShellUI gate with tint restoration;
and no duplicate indicator or lost refresh action. These are runtime checks,
not established by source inspection.

macOS PlatformDetailView also uses SwiftUI `.refreshable`. Its host-generated
indicator is not an explicit ProgressView call site, and the public
ProgressViewStyle API does not guarantee control of that platform indicator.
The current iOS decoration does not cover it; macOS needs separate new-build
observation before claiming every native refresh spinner is replaced. No macOS
refresh implementation is changed by this integration.
