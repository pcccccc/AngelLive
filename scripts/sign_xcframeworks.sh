#!/bin/bash

# =============================================================================
# XCFramework 签名脚本
# 用于在 Xcode 编译前检查并签名 SPM 依赖中未签名的 XCFramework
# =============================================================================

set -e

# 加载本地环境配置（如果存在）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env.local" ]; then
    source "$SCRIPT_DIR/.env.local"
fi

# =============================================================================
# 自动获取签名身份
# 优先级：
#   1. 环境变量 SIGNING_IDENTITY（手动指定）
#   2. Xcode 环境变量 EXPANDED_CODE_SIGN_IDENTITY（Build Phase 中自动提供）
#   3. 自动从钥匙串选择第一个有效的开发者证书
#   4. 回退到 Ad-hoc 签名（"-"）
# =============================================================================

auto_select_identity() {
    # 1. 检查是否手动指定了 SIGNING_IDENTITY
    if [ -n "${SIGNING_IDENTITY:-}" ]; then
        echo "$SIGNING_IDENTITY"
        return 0
    fi

    # 2. 检查 Xcode 环境变量（在 Build Phase 中运行时可用）
    if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
        echo "$EXPANDED_CODE_SIGN_IDENTITY"
        return 0
    fi

    # 3. 自动从钥匙串选择证书
    # 优先选择 "Apple Development" 证书
    local identity
    identity=$(security find-identity -v -p codesigning 2>/dev/null | \
               grep -E '"Apple Development' | \
               head -1 | \
               sed -E 's/.*"(.+)".*/\1/')

    if [ -n "$identity" ]; then
        echo "$identity"
        return 0
    fi

    # 4. 尝试选择任意有效的签名身份
    identity=$(security find-identity -v -p codesigning 2>/dev/null | \
               grep -E '^\s+[0-9]+\)' | \
               head -1 | \
               sed -E 's/.*"(.+)".*/\1/')

    if [ -n "$identity" ]; then
        echo "$identity"
        return 0
    fi

    # 5. 回退到 Ad-hoc 签名
    echo "-"
}

SIGNING_IDENTITY=$(auto_select_identity)

# 需要签名的 XCFramework 列表
XCFRAMEWORK_NAMES=(
    "GMObjC.xcframework"
    "openssl.xcframework"
)

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 XCFramework 是否已签名
is_signed() {
    local path="$1"
    codesign -v "$path" 2>/dev/null
    return $?
}

# 签名单个 framework 内的二进制文件
sign_framework() {
    local fw_path="$1"
    local fw_name=$(basename "$fw_path" .framework)

    # iOS/tvOS framework 结构
    local binary_path="$fw_path/$fw_name"

    # macOS framework 结构 (Versions/A/)
    if [ ! -f "$binary_path" ]; then
        binary_path="$fw_path/Versions/A/$fw_name"
    fi

    if [ -f "$binary_path" ]; then
        log_info "  签名二进制: $binary_path"
        codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$binary_path"
    else
        log_warn "  未找到二进制文件: $fw_path"
    fi
}

# 签名整个 XCFramework
sign_xcframework() {
    local xcfw_path="$1"
    local xcfw_name=$(basename "$xcfw_path")

    log_info "处理 $xcfw_name ..."

    # 检查是否已签名
    if is_signed "$xcfw_path"; then
        log_info "  已签名，跳过"
        return 0
    fi

    log_info "  未签名，开始签名..."

    # 确保有写权限
    chmod -R +w "$xcfw_path" 2>/dev/null || true

    # 遍历所有平台目录下的 framework
    find "$xcfw_path" -name "*.framework" -type d | while read fw; do
        sign_framework "$fw"
    done

    # 最后签名整个 xcframework 目录
    log_info "  签名 xcframework 目录..."
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none --deep "$xcfw_path"

    # 验证签名
    if is_signed "$xcfw_path"; then
        log_info "  签名成功"
    else
        log_error "  签名失败"
        return 1
    fi
}

# 查找 SPM 缓存中的 GMObjC 路径
find_gmobjc_path() {
    local search_paths=(
        # Xcode 项目的 DerivedData 路径
        "${BUILD_DIR}/../../SourcePackages/checkouts/GMObjC/Frameworks"
        # 通用 DerivedData 搜索
        ~/Library/Developer/Xcode/DerivedData/*/SourcePackages/checkouts/GMObjC/Frameworks
    )

    for pattern in "${search_paths[@]}"; do
        # 使用 compgen 展开通配符
        for path in $pattern; do
            if [ -d "$path" ]; then
                echo "$path"
                return 0
            fi
        done
    done

    return 1
}

# 主函数
main() {
    log_info "========================================"
    log_info "XCFramework 签名脚本"
    log_info "签名身份: $SIGNING_IDENTITY"
    log_info "========================================"

    # 查找 GMObjC 路径
    local gmobjc_path
    gmobjc_path=$(find_gmobjc_path) || {
        log_error "未找到 GMObjC 库路径"
        log_info "请确保已通过 SPM 下载依赖"
        exit 1
    }

    log_info "找到 GMObjC 路径: $gmobjc_path"

    # 签名每个 XCFramework
    for xcfw_name in "${XCFRAMEWORK_NAMES[@]}"; do
        local xcfw_path="$gmobjc_path/$xcfw_name"
        if [ -d "$xcfw_path" ]; then
            sign_xcframework "$xcfw_path"
        else
            log_warn "未找到 $xcfw_name"
        fi
    done

    log_info "========================================"
    log_info "签名完成"
    log_info "========================================"
}

# 执行主函数
main "$@"
