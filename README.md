# TomSSH

Android SSH 终端客户端，使用 Flutter 构建。

## 功能

- **多标签终端** — 同时连接多台服务器，标签页切换
- **服务器管理** — 添加、编辑、删除服务器配置，支持分组管理
- **双认证方式** — 密码认证和 SSH 私钥认证
- **主密码锁屏** — 本地加密存储所有凭据（Android Keystore）
- **虚拟键盘工具栏** — Enter、Esc、Tab、Ctrl/Alt/Shift 修饰键、方向键、F1-F12 等
- **快捷命令** — 保存常用命令，一键发送到终端
- **历史记录查看** — 全屏查看当前终端窗口历史内容，支持关键词搜索高亮
- **大段文本输入** — 粘贴或输入多行文本批量发送
- **自动重连** — 断线指数退避重连（2-30 秒，最多 10 次），切换 APP 后自动恢复
- **tmux 会话保持** — 可选自动附加 tmux 会话，断连后进程继续运行
- **会话日志** — SSH 输出自动保存到文件，超过 1MB 自动轮转
- **触摸滚动** — 手指拖动查看终端历史输出
- **屏幕常亮** — 终端界面保持 CPU 唤醒，防止后台挂起

## 技术栈

| 组件 | 库 |
|------|-----|
| SSH 协议 | dartssh2 |
| 终端模拟 | xterm |
| 状态管理 | flutter_riverpod |
| 本地数据库 | sqflite |
| 凭据加密 | flutter_secure_storage |
| 屏幕常亮 | wakelock_plus |

## 构建

```bash
flutter pub get
flutter build apk --debug
```

## 项目结构

```
lib/
├── main.dart                  # 入口，Material 3 暗色主题
├── models/
│   ├── server_config.dart     # 服务器配置模型
│   ├── server_group.dart      # 服务器分组模型
│   └── quick_command.dart     # 快捷命令模型
├── services/
│   ├── ssh_service.dart       # SSH 连接管理（keepalive、PTY）
│   ├── database_service.dart  # SQLite 数据库（v3 迁移）
│   ├── credential_service.dart # 加密凭据存储
│   └── session_log_service.dart # 会话日志轮转
├── screens/
│   ├── lock_screen.dart       # 主密码锁屏
│   ├── server_list_screen.dart # 服务器列表（分组）
│   ├── server_edit_screen.dart # 服务器编辑表单
│   └── terminal_screen.dart   # 多标签终端界面
├── widgets/
│   ├── virtual_keyboard.dart  # 虚拟键盘工具栏
│   └── quick_commands_sheet.dart # 快捷命令面板
└── providers/
    └── providers.dart         # Riverpod 状态管理
```
