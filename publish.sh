#!/bin/bash
# TomSSH 一键发布到 AppCenter
# 用法: ./publish.sh [changelog] [force_update]
#   changelog    - 更新日志，默认自动从最近git提交生成
#   force_update - 1=强制更新，0=非强制（默认）

set -e

SERVER="https://app.tommickey.cn"
FLUTTER="/home/tommy/flutter_3.38.5_stable/bin/flutter"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APK_PATH="$PROJECT_DIR/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"

# 颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 参数
CHANGELOG="${1:-}"
FORCE="${2:-0}"

# 自动生成 changelog
if [ -z "$CHANGELOG" ]; then
    cd "$PROJECT_DIR"
    CHANGELOG=$(git log --oneline -5 --pretty=format:"• %s" 2>/dev/null || echo "自动发布")
    info "自动生成更新日志:"
    echo "$CHANGELOG"
    echo ""
fi

# Step 1: 构建 APK
info "构建 APK..."
cd "$PROJECT_DIR"
$FLUTTER build apk --release --split-per-abi 2>&1 | tail -5

if [ ! -f "$APK_PATH" ]; then
    error "APK 构建失败: $APK_PATH 不存在"
fi

APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
info "APK 构建成功: $APK_SIZE"

# Step 2: 登录获取 Token
info "登录 AppCenter..."
LOGIN_RESP=$(curl -s -X POST "$SERVER/api/admin/login" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"admin123"}')

TOKEN=$(echo "$LOGIN_RESP" | python3 -c "import sys,json; data=json.load(sys.stdin); print(data.get('token',''))" 2>/dev/null || echo "")

if [ -z "$TOKEN" ]; then
    error "登录失败: $LOGIN_RESP"
fi
info "登录成功"

# Step 3: 发布
info "上传 APK 到 AppCenter..."
PUBLISH_RESP=$(curl --progress-bar --http1.1 --max-time 3600 --retry 3 --retry-delay 5 -w "\n%{http_code}" -X POST "$SERVER/api/admin/publish" \
    -H "Authorization: Bearer $TOKEN" \
    -F "file=@$APK_PATH" \
    -F "changelog=$CHANGELOG" \
    -F "forceUpdate=$FORCE" 2>&1)

HTTP_CODE=$(echo "$PUBLISH_RESP" | tail -1)
BODY=$(echo "$PUBLISH_RESP" | sed '$d')

case "$HTTP_CODE" in
    200)
        info "发布成功!"
        echo "$BODY" | python3 -c "
import sys, json
data = json.load(sys.stdin).get('data', {})
app = data.get('app', {})
ver = data.get('version', {})
print(f\"  应用: {app.get('name', 'N/A')} ({app.get('packageName', 'N/A')})\")
print(f\"  版本: {ver.get('versionName', 'N/A')} (code: {ver.get('versionCode', 'N/A')})\")
print(f\"  大小: {ver.get('fileSize', 0) / 1024 / 1024:.1f} MB\")
print(f\"  新应用: {'是' if data.get('isNewApp') else '否'}\")
print(f\"  下载: $SERVER{data.get('downloadUrl', '')}\")
" 2>/dev/null || echo "$BODY"
        ;;
    409)
        warn "该版本号已存在，请先更新 pubspec.yaml 中的 version"
        echo "$BODY"
        ;;
    401)
        error "认证失败，Token 无效或过期"
        ;;
    *)
        error "发布失败 (HTTP $HTTP_CODE): $BODY"
        ;;
esac
