# Conflux

多源平台内容收藏合一。产品说明见 [`docs/PRD-v1.md`](docs/PRD-v1.md)，推广计划见 [`docs/Conflux-推广计划书.md`](docs/Conflux-推广计划书.md)，[`用户协议`](docs/用户协议.md) / [`隐私政策`](docs/隐私政策.md)。

## 目录

```
collection-app/
├── app/          # Flutter 客户端
├── backend/      # Express + MySQL API
├── extension/    # Chrome 扩展（只负责收藏）
└── docs/         # PRD 等文档
```

## 后端

```bash
cd backend
nvm use          # 使用 .nvmrc → Node 23.6.0
pnpm install
cp .env.example .env   # 已有 .env 可跳过
pnpm db:init     # 创建 collection 库
pnpm db:migrate  # 建表（含 users）+ 预置第二层分类
pnpm dev         # http://127.0.0.1:3000
```

健康检查：`GET /api/health`

## App

```bash
cd app
flutter pub get
flutter run
```

Chrome 扩展（浏览器里一键收藏，整理/阅读仍用手机）：见 [`extension/README.md`](extension/README.md)。
