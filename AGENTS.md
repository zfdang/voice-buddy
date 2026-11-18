# AGENTS.md — Voice Buddy Project Directives

> **CRITICAL & INVIOLABLE DIRECTIVES FOR ALL AI AGENTS & AUTOMATION SCRIPTS**
>
> This workspace is the unified repository for **Voice Buddy** (`zfdang/voice-buddy`).
> It contains the complete source code, tests, documentation, GitHub Pages landing site (`pages/`), and Sparkle update distribution configuration (`appcast.xml`).

---

## 1. Repository Architecture & Layout (统一仓库职责与目录规范)

| 目录/文件 | 核心职责 | 说明 |
| :--- | :--- | :--- |
| **`Sources/`** | 核心 Swift 源码 | `VoiceBuddyApp` (主应用与 UI), `VoiceBuddyCore` (文本清洗与 ITN 管道) |
| **`Tests/`** | 单元测试与端到端测试 | 覆盖模型管理、文本清洗、系统弹性、无障碍控制等测试用例 |
| **`scripts/`** | 构建打包与签名脚本 | 本地构建脚本 `build-app.sh`、图标生成脚本与发布辅助工具 |
| **`pages/`** | 官方网站 (`myvoicebuddy.com`) | 静态展示站，由 `.github/workflows/static.yml` 自动部署至 GitHub Pages |
| **`appcast.xml`** | Sparkle 自动更新源 | 维护各版本下载链接、版本号、硬件要求与 EdDSA 签名 |
| **`docs/`** | 内部设计与公共预览资产 | 包含架构文档、依赖约束以及用于 README 的软件界面截图 (`docs/images/`) |

---

## 2. Inviolable Red Lines (不可逾越的绝对红线)

1. **严格禁止开启 CI 自动触发 (Actions 运行额度保护)**：
   - 仓库包含运行时间长达 45 分钟的 macOS 15 虚拟机测试和打包任务。
   - **严禁**为 `.github/workflows/macos.yml` 添加 `push` 或 `pull_request` 自动触发器！该工作流**仅允许保留 `workflow_dispatch` 手动触发**。
   - 严禁任何自作主张恢复 CI 自动触发的行为。发布工作流 `.github/workflows/release.yml` 仅在打版本标签（`v*`）或手动分发时运行。
2. **绝对禁止直接 Push 到 `main` 分支 (严格遵守 PR 流程)**：
   - **严禁任何开发者或 AI 助理向 `main` 分支执行 `git push origin main`**。
   - 所有的新增功能、Bug 修复、工作流调整或文档更改，**必须**首先在独立的特性分支（如 `feat/...`、`fix/...`、`docs/...`、`chore/...`）上进行。
   - 必须通过 GitHub Pull Request 提交变更，由仓库所有者（用户）审查确认后再行合入主分支。
3. **保护 Sparkle 升级描述源 (`appcast.xml`) 完整性**：
   - `appcast.xml` 是用户客户端检查并自动升级的唯一凭证，任何版本更新必须确保 `sparkle:version`、`length` 和 EdDSA 签名的准确性。

---

## 3. Standard Release Flow (规范发布流程)

```mermaid
flowchart TD
    A[日常开发 / 特性分支 / PR] --> B[本地运行测试 swift test]
    B --> C[执行 scripts/build-app.sh 打包签名]
    C --> D[生成 dist/*.dmg, dist/*.zip, 并在 appcast.xml 登记]
    D --> E[提交 PR 合入 main 分支]
    E --> F[发布 GitHub Releases vX.Y.Z 挂载二进制产物]
    E --> G[GitHub Actions 自动部署 pages/ 到 myvoicebuddy.com]
```

详细操作规范与检查清单请参阅：[`docs/repository-governance.md`](file:///Users/zfdang/workspaces/voice-buddy-private/docs/repository-governance.md)。
