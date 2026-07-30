# 在线音乐创作网站实施计划

> **供自动化开发人员使用：** 必须使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐项执行本计划。所有步骤用复选框记录。

**目标：** 构建独立的暗色唱片室风格音乐网站，提供合规音乐搜索、点数付费的 AI 完整歌曲生成和试听。

**架构：** Next.js 提供自适应界面与 API 路由；PostgreSQL 使用 Prisma 保存用户、点数账本、订单、生成任务和作品。仅服务端运行的服务商适配器创建并轮询任务，任务以原子操作结算预留点数。

**技术栈：** Next.js（App Router）、TypeScript、Tailwind CSS、Prisma、PostgreSQL、Auth.js、Zod、Vitest、React Testing Library、Playwright、Docker Compose。

## 全局约束

- 这是独立网站，不修改或替换 Windows/iOS 本地播放器计划。
- 视觉复用 Windows 播放器：深灰背景、暖红强调色、圆角封面和半透明面板。
- 首版界面默认简体中文；文案集中管理，为将来国际化留出边界。
- 外部音乐仅允许官方或授权预览及来源链接，绝不缓存、下载、代理或完整播放第三方受版权保护音频。
- AI 服务商密钥与未来支付凭据只能保留在服务端环境变量。
- PostgreSQL 是业务数据唯一事实来源。AI 音频只保存授权服务商或对象存储 URL，不保存第三方外部歌曲。
- 创建 AI 任务前预留点数；只在成功时结算，失败、取消或超时仅释放一次。
- 首版只创建待支付订单，不接入或模拟微信/支付宝支付成功；未来回调必须幂等。

---

## 文件结构

- web/prisma/schema.prisma：PostgreSQL 模型、关系和枚举。
- web/src/lib/auth.ts、db.ts：认证会话和数据库单例。
- web/src/lib/credits.ts、orders.ts：点数账本和待支付订单。
- web/src/lib/music-search.ts：合规搜索服务端标准化。
- web/src/lib/ai/types.ts、registry.ts、providers/*.ts：多服务商生成协议与适配器。
- web/src/lib/jobs.ts：生成任务创建、轮询与终态结算。
- web/src/components/player/*：迷你播放器、完整播放页和队列。
- web/src/components/search/*、studio/*、credits/*：功能组件。
- web/src/app/api/**/route.ts：经认证和参数校验的 API。
- web/tests/*、web/e2e/*：单元、组件和浏览器验收测试。

### 任务 1：搭建独立网站和统一视觉外壳

**文件：** 新建 web/package.json、web/src/app/layout.tsx、web/src/app/page.tsx、web/src/app/globals.css、web/src/components/layout/site-shell.tsx、sidebar.tsx、mobile-nav.tsx；测试 web/tests/site-shell.test.tsx。

**接口：** 产出 SiteShell({ children })，供所有站点页面使用。

- [ ] **步骤 1：写失败的外壳测试。** 渲染 SiteShell 后断言“搜索音乐”和“AI 写歌”导航入口可见。
- [ ] **步骤 2：运行 cd web && npm test -- site-shell.test.tsx。** 预期：因 SiteShell 不存在失败。
- [ ] **步骤 3：实现最小外壳。** 使用 min-h-screen、深灰背景和浅色文字；桌面显示侧边栏，窄屏显示移动端导航。定义 --background: #171717、--panel: rgba(39,39,42,.78)、--accent: #d84a4a。
- [ ] **步骤 4：运行 cd web && npm run lint && npm test -- site-shell.test.tsx。** 预期：通过。
- [ ] **步骤 5：提交。** git add web；git commit -m "feat: scaffold music creator website"。

### 任务 2：接入 PostgreSQL、用户账户和登录

**文件：** 新建 web/docker-compose.yml、web/.env.example、web/prisma/schema.prisma、web/prisma/seed.ts、web/src/lib/db.ts、web/src/lib/auth.ts、认证路由、登录/注册页和 web/tests/auth/sign-up.test.ts。

**接口：** 产出 createUser({ name, email, password }) 和 requireUser()，后者返回当前用户 id 与 USER/ADMIN 角色。

- [ ] **步骤 1：写失败的注册测试。** 注册 Ava 后断言用户邮箱正确，且对应 CreditAccount 的 available 和 reserved 都为 0。
- [ ] **步骤 2：运行 cd web && npm test -- auth/sign-up.test.ts。** 预期：模型和认证模块不存在而失败。
- [ ] **步骤 3：实现数据模型和注册事务。** 创建 User、Account、Session、CreditAccount、CreditLedger、CreditOrder、GenerationJob、GeneratedWork、Favourite、ListeningEvent 和 ProviderConfig。User.email、CreditAccount.userId 和 CreditLedger.idempotencyKey 必须唯一；只保存密码哈希。注册事务同时创建零余额账户。
- [ ] **步骤 4：运行 cd web && docker compose up -d db && npx prisma migrate dev --name init && npm test -- auth/sign-up.test.ts。** 预期：通过。
- [ ] **步骤 5：提交。** git add web；git commit -m "feat: add website accounts and database"。

### 任务 3：实现点数账本、待支付订单和幂等结算

**文件：** 新建 web/src/lib/credits.ts、orders.ts、web/src/app/api/orders/route.ts、点数套餐页面与 web/tests/credits.test.ts、web/tests/orders.test.ts。

**接口：** 产出 reserveCredits(userId, amount, key)、settleReservation(key)、releaseReservation(key)、createPendingOrder(userId, packageId)。

- [ ] **步骤 1：写失败的账本测试。** 充值 20 后预留 8，连续两次释放同一 job_1，断言余额为 available: 20、reserved: 0。
- [ ] **步骤 2：运行 cd web && npm test -- credits.test.ts orders.test.ts。** 预期：账本函数不存在而失败。
- [ ] **步骤 3：实现事务。** 每次状态变更使用 PostgreSQL 事务，并按幂等键 upsert 账本记录；预留从 available 转入 reserved，结算扣除 reserved，释放转回 available。套餐只创建 PENDING 订单，UI 显示“微信支付 / 支付宝即将接入”，前后端绝不为待支付订单充值。
- [ ] **步骤 4：运行 cd web && npm run lint && npm test -- credits.test.ts orders.test.ts。** 预期：通过，重复调用只有一次账务影响。
- [ ] **步骤 5：提交。** git add web；git commit -m "feat: add credit orders and ledger"。

### 任务 4：接入合规联网搜索和来源标识

**文件：** 新建 web/src/lib/music-search.ts、web/src/app/api/music-search/route.ts、搜索组件、搜索页和 web/tests/music-search.test.ts、web/tests/search-results.test.tsx。

**接口：** 产出 searchMusic(query)，返回含 id、title、artist、artworkUrl、previewUrl、sourceName、sourceUrl 的 SearchTrack。

- [ ] **步骤 1：写失败的标准化测试。** 给定 iTunes 项目后，断言来源为 iTunes、预览 URL 可用、来源 URL 指向 itunes。
- [ ] **步骤 2：运行 cd web && npm test -- music-search.test.ts search-results.test.tsx。** 预期：搜索客户端不存在而失败。
- [ ] **步骤 3：实现服务端搜索。** 用 Zod 校验 1–100 字符关键词，fetch 带超时与响应解析。每一项明确标注来源；仅当 previewUrl 存在时显示播放按钮，来源链接必须使用 target=_blank 和 rel=noreferrer。
- [ ] **步骤 4：运行 cd web && npm run lint && npm test -- music-search.test.ts search-results.test.tsx。** 预期：通过，结果不提供外部完整播放 URL。
- [ ] **步骤 5：提交。** git add web；git commit -m "feat: add licensed music search"。

### 任务 5：实现多服务商适配器和生成任务

**文件：** 新建 web/src/lib/ai/types.ts、registry.ts、providers/replicate.ts、providers/suno.ts、providers/udio.ts、web/src/lib/jobs.ts、生成/任务查询/内部轮询路由，以及 web/tests/ai/registry.test.ts、web/tests/jobs.test.ts。

**接口：** 产出 AiProvider.createJob、AiProvider.getJobStatus、createGeneration(userId, input) 和 pollPendingJobs()。

- [ ] **步骤 1：写失败的成功结算测试。** 模拟服务商返回 SUCCEEDED、授权音频 URL 和标题，轮询后断言新增一个 GeneratedWork，且 8 点数从预留变为已结算。
- [ ] **步骤 2：运行 cd web && npm test -- ai/registry.test.ts jobs.test.ts。** 预期：任务模块不存在而失败。
- [ ] **步骤 3：实现协议与状态转换。** GenerationInput 包含 providerId、modelId、prompt、可选 lyrics、style、mood、language、durationSeconds。注册表拒绝禁用服务商或缺少凭据。先建预留和 QUEUED 任务再发请求；成功时一个事务创建作品、标记 SUCCEEDED 并结算，失败/取消/超时标记终态且只释放一次。接入每家服务商时必须使用最新官方 API 文档。
- [ ] **步骤 4：运行 cd web && npm run lint && npm test -- ai/registry.test.ts jobs.test.ts。** 预期：通过，终态任务重复轮询不会重复建作品或扣点。
- [ ] **步骤 5：提交。** git add web；git commit -m "feat: add multi-provider generation jobs"。

### 任务 6：构建 AI 写歌工作台、作品库和管理页

**文件：** 新建写歌表单、任务状态、作品卡片、创作页、作品库、服务商管理页和管理 API；测试 song-form、generation-status、admin/providers。

**接口：** 消费生成 API 和服务商配置，产出 AI 写歌工作台、任务进度与当前用户作品库。

- [ ] **步骤 1：写失败的工作台测试。** 未登录渲染表单时显示“8 点数”；点击“开始创作”后显示“请先登录”。
- [ ] **步骤 2：运行 cd web && npm test -- song-form.test.tsx generation-status.test.tsx admin/providers.test.ts。** 预期：组件不存在而失败。
- [ ] **步骤 3：实现工作台。** 表单包括服务商/模型、主题提示词、曲风、情绪、语言、时长和可选歌词；提交前显示价格、余额、预计时长。页面打开时轮询任务；失败显示原因和退回点数提示。作品库只查询当前用户。管理 API 只允许 ADMIN 修改启用状态与点数价格，绝不返回密钥。
- [ ] **步骤 4：运行 cd web && npm run lint && npm test -- song-form.test.tsx generation-status.test.tsx admin/providers.test.ts。** 预期：通过，普通用户修改配置返回 403。
- [ ] **步骤 5：提交。** git add web；git commit -m "feat: add AI studio and works library"。

### 任务 7：加入与 Windows 一致的播放器和队列

**文件：** 新建 player-store.ts、player-provider.tsx、mini-player.tsx、now-playing.tsx、queue-panel.tsx；修改网站外壳、搜索结果、作品卡片；测试 player-store、mini-player、now-playing。

**接口：** 产出 enqueue(item)、play(item)、next()、previous()、setRepeat(mode)、setShuffle(enabled)。

- [ ] **步骤 1：写失败的播放器测试。** 队列包含外部预览与 AI 作品，预览结束后断言当前曲目变为 AI 作品；渲染 SiteShell 后断言 mini-player 带 fixed 和 bottom-0 类。
- [ ] **步骤 2：运行 cd web && npm test -- player-store.test.ts mini-player.test.tsx now-playing.test.tsx。** 预期：播放器模块不存在而失败。
- [ ] **步骤 3：实现安全播放。** PlayerProvider 只持有一个 HTMLAudioElement，只接受 previewUrl 或用户拥有的授权作品 URL。迷你播放器与展开页复用 Windows 视觉：封面、暖红进度条、音量、上一首/下一首、随机、循环和队列。仅有合法歌词字段时显示歌词，否则显示“暂无可用歌词”。
- [ ] **步骤 4：运行 cd web && npm run lint && npm test -- player-store.test.ts mini-player.test.tsx now-playing.test.tsx。** 预期：通过；预览结束时推进队列，不替换成外部完整歌曲。
- [ ] **步骤 5：提交。** git add web；git commit -m "feat: add unified music player"。

### 任务 8：加入验收测试、环境安全和交接文档

**文件：** 新建 web/e2e/auth-and-orders.spec.ts、search-and-player.spec.ts、generation.spec.ts、web/README.md；修改 web/.env.example、.gitignore。

**接口：** 使用种子数据和模拟外部服务验证完整流程。

- [ ] **步骤 1：写失败的订单验收测试。** 用户登录后购买 100 点数，断言页面显示“待支付”和“当前余额：0”。
- [ ] **步骤 2：运行 cd web && npm run test:e2e -- auth-and-orders.spec.ts。** 预期：测试夹具完成前失败。
- [ ] **步骤 3：补齐测试夹具和文档。** README 说明 Docker 数据库、迁移、种子、测试、构建、服务商配置和延期的支付回调。env 示例只列 DATABASE_URL、AUTH_SECRET、ITUNES_SEARCH_URL、REPLICATE_API_TOKEN、SUNO_API_KEY、UDIO_API_KEY、INTERNAL_JOB_TOKEN 名称且不写值。Playwright 模拟外部搜索与生成，不调用真实服务或消耗点数。
- [ ] **步骤 4：运行 cd web && npm run lint && npm test && npm run test:e2e && npm run build。** 预期：全部测试和生产构建通过。
- [ ] **步骤 5：运行 rg -n "BEGIN .*PRIVATE KEY|sk-[A-Za-z0-9]|DATABASE_URL=.*@" web -g "!node_modules" -g "!README.md" -g "!.env.example"。** 预期：未发现密钥。
- [ ] **步骤 6：提交。** git add web .gitignore；git commit -m "test: verify music creator website"。

## 最终验收清单

- [ ] 账户及所有用户数据均按身份和角色控制访问。
- [ ] 待支付订单绝不增加余额。
- [ ] 每个终态任务只发生一次结算或释放。
- [ ] 已禁用或未配置的 AI 服务商拒绝创建付费任务。
- [ ] 搜索结果明确来源，只播放授权预览。
- [ ] AI 完整作品和外部预览可共存于 Windows 风格播放队列。
- [ ] 桌面侧边栏/固定播放器和移动端导航/迷你播放器均可用。
