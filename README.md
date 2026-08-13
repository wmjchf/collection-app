# 超级收藏夹

多源平台内容收藏合一。产品说明见 [`docs/PRD-v1.md`](docs/PRD-v1.md)。

## 目录

```
collection-app/
├── app/          # Flutter 客户端
├── backend/      # Express + MySQL API
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

当前 App 仅搭好「主页 / 我的收藏」导航壳，业务功能按 PRD 逐步实现。
