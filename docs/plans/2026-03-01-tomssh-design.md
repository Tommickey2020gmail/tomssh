# TomSSH - 移动端 SSH 终端客户端设计文档

## 概述

一款 Android SSH 终端应用，支持分组管理 5-20 台服务器，多会话 Tab 切换，密码和密钥双认证，本地加密存储凭据。

## 技术栈

- Flutter 3.38.5
- dartssh2 — SSH 协议实现
- xterm — 终端模拟器组件
- flutter_secure_storage — 加密存储凭据
- sqflite — 本地数据库存储服务器/分组配置

## 页面结构

```
启动 → [主密码解锁页] → [服务器列表页] → [终端页(多Tab)]
                              │
                         [服务器编辑页]
```

### 1. 主密码解锁页
- APP 启动时输入主密码
- 首次使用时设置主密码
- 主密码用于派生加密密钥，加密所有存储的凭据

### 2. 服务器列表页
- 按分组展示服务器列表
- 分组可折叠/展开
- 点击服务器即发起 SSH 连接
- 长按可编辑/删除
- 右上角添加服务器/分组

### 3. 服务器编辑页
- 字段：名称、主机、端口(默认22)、用户名、认证方式(密码/密钥)、密码/密钥内容、所属分组
- 支持导入本地密钥文件
- 连接测试按钮

### 4. 终端页
- 底部 Tab 栏支持多会话切换
- 每个 Tab 显示服务器名称
- xterm 终端组件渲染
- 支持颜色、vim/top 等全屏程序
- 顶部工具栏：断开/重连按钮
- 断开连接时显示提示，手动点击重连

## 数据模型

### ServerGroup
- id, name, sortOrder

### ServerConfig
- id, name, host, port, username, authType(password/key), groupId, sortOrder

### 凭据(加密存储)
- serverId → password 或 privateKey

## 认证方式
- 密码认证：直接使用存储的密码
- 密钥认证：使用存储的私钥内容

## 安全设计
- 主密码不存储，仅存储其哈希用于验证
- 使用主密码派生 AES 密钥加密所有凭据
- flutter_secure_storage 利用 Android Keystore 系统级安全存储
