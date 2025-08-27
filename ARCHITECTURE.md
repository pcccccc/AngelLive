# SimpleLiveTVOS 架构文档

## 概述

SimpleLiveTVOS 是一个基于 SwiftUI 的 Apple TV 直播应用，支持多平台直播内容聚合、收藏管理、弹幕显示等功能。

## 架构模式

采用 **MVVM + Service 层** 架构模式：

```
┌─────────────────┐
│  View (SwiftUI) │ <- 用户界面层
└─────────┬───────┘
          │
┌─────────▼───────┐
│   ViewModel     │ <- 业务逻辑 + UI状态
└─────────┬───────┘
          │
┌─────────▼───────┐
│    Service      │ <- 数据访问层
└─────────┬───────┘
          │
┌─────────▼───────┐
│    AppState     │ <- 全局状态管理
└─────────────────┘
```

## 核心组件

### 1. 全局状态管理 (AppState)

**文件位置**: `SimpleLiveTVOS/Other/AppState.swift`

```swift
@Observable
class AppState {
    var selection = 0
    var favoriteViewModel = AppFavoriteModel()
    var danmuSettingsViewModel = DanmuSettingModel()
    var searchViewModel = SearchViewModel()
    var historyViewModel = HistoryModel()
    var playerSettingsViewModel = PlayerSettingModel()
    var generalSettingsViewModel = GeneralSettingModel()
}
```

**职责**:
- 管理应用的全局状态
- 统一的状态访问入口
- 通过 SwiftUI Environment 注入到各个 View

### 2. Service 层

#### LiveService
**文件位置**: `SimpleLiveTVOS/Source/List/LiveService.swift`

**职责**:
- 直播平台 API 调用
- 房间列表获取
- 搜索功能
- 分享码解析

**主要方法**:
```swift
static func fetchCategoryList(liveType: LiveType) async throws -> [LiveMainListModel]
static func fetchRoomList(liveType: LiveType, category: LiveCategoryModel, parentBiz: String?, page: Int) async throws -> [LiveModel]
static func searchRooms(keyword: String, page: Int) async throws -> [LiveModel]
static func searchRoomWithShareCode(shareCode: String) async throws -> LiveModel?
```

#### FavoriteService  
**文件位置**: `SimpleLiveTVOS/Tools/Common/Utils/FavoriteService.swift`

**职责**:
- CloudKit 数据同步
- 收藏数据的增删改查
- 错误处理和状态管理

**主要方法**:
```swift
static func saveRecord(liveModel: LiveModel) async throws
static func deleteRecord(liveModel: LiveModel) async throws
static func searchRecord() async throws -> [LiveModel]
static func getCloudState() async -> String
```

### 3. ViewModel 层

#### LiveViewModel
**文件位置**: `SimpleLiveTVOS/Source/List/LiveViewModel.swift`

**职责**:
- 房间列表管理 (直播、收藏、历史、搜索)
- UI 状态管理 (菜单、焦点、加载状态)
- 用户交互处理
- Toast 消息管理

**核心属性**:
```swift
var roomListType: LiveRoomListType  // live, favorite, history, search
var liveType: LiveType              // 平台类型
var roomList: [LiveModel]           // 房间列表
var isLoading: Bool                 // 加载状态
var currentRoom: LiveModel?         // 当前选中房间
```

#### 其他 ViewModel
- `RoomInfoViewModel`: 房间详情和播放器控制
- `SearchViewModel`: 搜索功能管理
- `AppFavoriteModel`: 收藏功能管理 
- `DanmuSettingModel`: 弹幕设置管理
- `HistoryModel`: 历史记录管理
- `PlayerSettingModel`: 播放器设置管理
- `GeneralSettingModel`: 通用设置管理

### 4. View 层

**主要 View 组件**:
- `ContentView`: 主界面容器
- `ListMainView`: 房间列表主界面
- `LiveCardView`: 房间卡片组件
- `DetailPlayerView`: 播放器详情页
- `FavoriteMainView`: 收藏列表页面
- `SettingView`: 设置页面

## 数据流向

### 1. 应用启动流程
```
SimpleLiveTVOSApp → AppState → ContentView → Environment 注入
```

### 2. 房间列表加载流程  
```
View 触发 → LiveViewModel.getCategoryList() → LiveService.fetchCategoryList() → 更新 roomList → View 刷新
```

### 3. 收藏操作流程
```
View 操作 → AppState.favoriteViewModel.addFavorite() → FavoriteService.saveRecord() → CloudKit 同步 → UI 更新
```

### 4. 搜索流程
```
SearchRoomView → AppState.searchViewModel → LiveViewModel.searchRoomWithText() → LiveService.searchRooms() → 结果展示
```

## 支持的平台

- **哔哩哔哩** (Bilibili)
- **斗鱼** (Douyu) 
- **虎牙** (Huya)
- **抖音** (Douyin)
- **快手** (KuaiShou)
- **YY直播** (YY)
- **网易CC** (NeteaseCC)
- **YouTube**

## 核心功能模块

### 1. 直播聚合
- 多平台内容聚合
- 分类浏览
- 实时状态更新

### 2. 收藏系统
- CloudKit 云同步
- 跨设备数据同步
- 离线收藏管理

### 3. 搜索功能
- 关键词搜索
- 分享码/链接解析
- YouTube 链接支持

### 4. 播放器
- 集成 KSPlayer
- 弹幕显示 (DanmakuKit)
- 播放控制

### 5. 历史记录
- 观看历史管理
- 快速访问

## 第三方依赖

### 核心依赖
- **LiveParse**: 直播平台解析库
- **KSPlayer**: 视频播放器
- **DanmakuKit**: 弹幕显示

### UI 组件
- **SimpleToast**: 消息提示
- **Kingfisher**: 图片加载
- **ColorfulX**: 动态背景效果

### 网络和数据
- **Alamofire**: 网络请求
- **Cache**: 数据缓存
- **SwiftyJSON**: JSON 解析
- **CloudKit**: 云数据同步

## 架构优势

### 1. 清晰的职责分离
- Service 层专注数据访问
- ViewModel 层处理业务逻辑
- View 层只负责 UI 展示

### 2. 统一的状态管理
- 全局状态通过 AppState 统一管理
- 避免了状态散乱和数据不一致

### 3. 良好的扩展性
- 新平台接入只需实现 Service 接口
- 新功能可独立开发和测试

### 4. 现代 SwiftUI 特性
- @Observable 响应式状态管理
- Environment 依赖注入
- Async/Await 异步编程

## 后续优化方向

### 1. 进一步的职责分离
- 将 LiveViewModel 拆分为更细粒度的组件
- 提取通用的 UI 状态管理逻辑

### 2. 错误处理优化
- 统一的错误处理机制
- 更友好的错误提示

### 3. 性能优化
- 懒加载和虚拟化
- 更智能的缓存策略

### 4. 测试覆盖
- 单元测试
- UI 测试
- 集成测试

---

*最后更新: 2025-08-27*
*架构版本: v2.0 (重构后)*