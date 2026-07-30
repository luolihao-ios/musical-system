# Online Music Creator Site Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an independent dark-record-room music website for licensed music discovery and credit-based AI full-song generation.

**Architecture:** A Next.js app serves the responsive UI and API routes. PostgreSQL stores users, credit ledgers, orders, generation jobs and works through Prisma migrations. Server-only AI-provider adapters create and poll generation jobs; jobs settle credit reservations atomically.

**Tech Stack:** Next.js (App Router), TypeScript, Tailwind CSS, Prisma, PostgreSQL, Auth.js, Zod, Vitest, React Testing Library, Playwright, Docker Compose.

## Global Constraints

- This is independent from the existing Windows/iOS local music-player plan.
- Use deep gray, warm red accents, rounded cover art and translucent panels to match the Windows player.
- External music can use only licensed/official previews and source links. Never cache, download, proxy, or full-stream copyrighted third-party audio.
- Provider and future payment secrets remain server-only environment variables.
- PostgreSQL is the system of record. Store generated audio as authorized provider or object-storage URLs; do not store third-party external audio.
- Reserve credits before creating an AI job; settle only on success and release them once on failure, cancellation or timeout.
- First release creates pending credit orders but does not integrate or simulate successful WeChat Pay/Alipay payment. Future callbacks must be idempotent.

---

## File structure

- `web/prisma/schema.prisma`: PostgreSQL models and enums.
- `web/src/lib/auth.ts`, `db.ts`: session and database primitives.
- `web/src/lib/credits.ts`, `orders.ts`: ledger and pending-order transactions.
- `web/src/lib/music-search.ts`: server-side licensed result normalization.
- `web/src/lib/ai/types.ts`, `registry.ts`, `providers/*.ts`: provider-neutral AI contract and adapters.
- `web/src/lib/jobs.ts`: generation job lifecycle.
- `web/src/components/player/*`: mini player, expanded player and queue.
- `web/src/components/search/*`, `studio/*`, `credits/*`: feature UI.
- `web/src/app/api/**/route.ts`: authenticated and validated HTTP endpoints.
- `web/tests/*` and `web/e2e/*`: unit, component and browser tests.

### Task 1: Scaffold the independent website and matching visual shell

**Files:**
- Create: `web/package.json`, `web/next.config.ts`, `web/tsconfig.json`, `web/tailwind.config.ts`
- Create: `web/src/app/layout.tsx`, `web/src/app/page.tsx`, `web/src/app/globals.css`
- Create: `web/src/components/layout/site-shell.tsx`, `sidebar.tsx`, `mobile-nav.tsx`
- Test: `web/tests/site-shell.test.tsx`

**Interfaces:** Produces `SiteShell({ children }: { children: React.ReactNode })`.

- [ ] **Step 1: Write the failing shell test**

```tsx
it('renders the record-room music entry points', () => {
  render(<SiteShell><main>content</main></SiteShell>);
  expect(screen.getByRole('link', { name: '搜索音乐' })).toBeVisible();
  expect(screen.getByRole('link', { name: 'AI 写歌' })).toBeVisible();
});
```

- [ ] **Step 2: Verify the test fails**

Run: `cd web && npm test -- site-shell.test.tsx`

Expected: FAIL because `SiteShell` does not exist.

- [ ] **Step 3: Implement the minimal shell**

```tsx
export function SiteShell({ children }: { children: React.ReactNode }) {
  return <div className="min-h-screen bg-[#171717] text-zinc-100"><Sidebar /><main>{children}</main><MobileNav /></div>;
}
```

Define `--background: #171717`, `--panel: rgba(39,39,42,.78)`, and `--accent: #d84a4a`. On desktop render the sidebar; on narrow screens render mobile navigation.

- [ ] **Step 4: Verify and commit**

Run: `cd web && npm run lint && npm test -- site-shell.test.tsx`

Expected: PASS.

```powershell
git add web
git commit -m "feat: scaffold music creator website"
```

### Task 2: Add PostgreSQL, accounts and sign-in

**Files:**
- Create: `web/docker-compose.yml`, `web/.env.example`, `web/prisma/schema.prisma`, `web/prisma/seed.ts`
- Create: `web/src/lib/db.ts`, `web/src/lib/auth.ts`, `web/src/app/api/auth/[...nextauth]/route.ts`
- Create: `web/src/app/(auth)/sign-in/page.tsx`, `sign-up/page.tsx`, `web/src/app/api/sign-up/route.ts`
- Test: `web/tests/auth/sign-up.test.ts`

**Interfaces:** Produces `createUser(input: { name: string; email: string; password: string }): Promise<User>` and `requireUser(): Promise<{ id: string; role: 'USER' | 'ADMIN' }>`.

- [ ] **Step 1: Write the failing sign-up test**

```ts
it('creates a zero-credit account with the user', async () => {
  const user = await createUser({ name: 'Ava', email: 'ava@example.com', password: 'safe-password-123' });
  expect(user.email).toBe('ava@example.com');
  expect(await prisma.creditAccount.findUnique({ where: { userId: user.id } }))
    .toMatchObject({ available: 0, reserved: 0 });
});
```

- [ ] **Step 2: Verify the test fails**

Run: `cd web && npm test -- auth/sign-up.test.ts`

Expected: FAIL because the database schema and auth module are absent.

- [ ] **Step 3: Implement schema and registration**

Create models `User`, `Account`, `Session`, `CreditAccount`, `CreditLedger`, `CreditOrder`, `GenerationJob`, `GeneratedWork`, `Favourite`, `ListeningEvent`, and `ProviderConfig`. Use unique keys for `User.email`, `CreditAccount.userId`, and `CreditLedger.idempotencyKey`. Hash passwords; never persist plaintext. Registration uses one transaction to create both user and zeroed credit account.

- [ ] **Step 4: Migrate, test and commit**

Run: `cd web && docker compose up -d db && npx prisma migrate dev --name init && npm test -- auth/sign-up.test.ts`

Expected: PASS.

```powershell
git add web
git commit -m "feat: add website accounts and database"
```

### Task 3: Implement points, pending orders and safe settlement

**Files:**
- Create: `web/src/lib/credits.ts`, `web/src/lib/orders.ts`, `web/src/app/api/orders/route.ts`
- Create: `web/src/app/(site)/account/credits/page.tsx`, `web/src/components/credits/credit-packages.tsx`
- Test: `web/tests/credits.test.ts`, `web/tests/orders.test.ts`

**Interfaces:** Produces `reserveCredits(userId, amount, key)`, `settleReservation(key)`, `releaseReservation(key)`, and `createPendingOrder(userId, packageId)`.

- [ ] **Step 1: Write the failing idempotency test**

```ts
it('releases one reservation exactly once', async () => {
  await fund(user.id, 20);
  await reserveCredits(user.id, 8, 'job_1');
  await releaseReservation('job_1');
  await releaseReservation('job_1');
  expect(await balance(user.id)).toEqual({ available: 20, reserved: 0 });
});
```

- [ ] **Step 2: Verify the test fails**

Run: `cd web && npm test -- credits.test.ts orders.test.ts`

Expected: FAIL because ledger functions are absent.

- [ ] **Step 3: Implement transactions and the order screen**

Use a PostgreSQL transaction for each credit transition and ledger `upsert` by idempotency key. A reserve decrements `available` and increments `reserved`; settlement decrements `reserved`; release moves `reserved` back to `available`. Credit packages create only a `PENDING` order. Show “微信支付 / 支付宝即将接入”; neither UI nor API may credit a pending order.

- [ ] **Step 4: Verify and commit**

Run: `cd web && npm run lint && npm test -- credits.test.ts orders.test.ts`

Expected: PASS; duplicate calls have one accounting effect.

```powershell
git add web
git commit -m "feat: add credit orders and ledger"
```

### Task 4: Add licensed music search and clear source attribution

**Files:**
- Create: `web/src/lib/music-search.ts`, `web/src/app/api/music-search/route.ts`
- Create: `web/src/components/search/music-search.tsx`, `search-results.tsx`, `web/src/app/(site)/search/page.tsx`
- Test: `web/tests/music-search.test.ts`, `web/tests/search-results.test.tsx`

**Interfaces:** Produces `searchMusic(query: string): Promise<SearchTrack[]>`, where `SearchTrack` has `id`, `title`, `artist`, `artworkUrl`, `previewUrl | null`, `sourceName`, and `sourceUrl`.

- [ ] **Step 1: Write the failing normalizer test**

```ts
it('keeps an iTunes result as an attributed preview', () => {
  expect(normalizeItunes(item)).toMatchObject({
    sourceName: 'iTunes',
    previewUrl: 'https://audio.example/preview.m4a',
    sourceUrl: expect.stringContaining('itunes'),
  });
});
```

- [ ] **Step 2: Verify it fails**

Run: `cd web && npm test -- music-search.test.ts search-results.test.tsx`

Expected: FAIL because the search client is absent.

- [ ] **Step 3: Implement search API and UI**

Validate 1–100-character queries with Zod; use server-side fetch with a timeout and response parsing. Each result shows its source. Render an audio action only for `previewUrl` and an external source link with `target="_blank" rel="noreferrer"`.

- [ ] **Step 4: Verify and commit**

Run: `cd web && npm run lint && npm test -- music-search.test.ts search-results.test.tsx`

Expected: PASS; no result exposes a full external playback URL.

```powershell
git add web
git commit -m "feat: add licensed music search"
```

### Task 5: Add provider adapters and durable generation jobs

**Files:**
- Create: `web/src/lib/ai/types.ts`, `registry.ts`, `providers/replicate.ts`, `providers/suno.ts`, `providers/udio.ts`, `web/src/lib/jobs.ts`
- Create: `web/src/app/api/generations/route.ts`, `web/src/app/api/generations/[id]/route.ts`, `web/src/app/api/internal/jobs/poll/route.ts`
- Test: `web/tests/ai/registry.test.ts`, `web/tests/jobs.test.ts`

**Interfaces:** Produces `AiProvider.createJob(request)`, `AiProvider.getJobStatus(id)`, `createGeneration(userId, input)`, and `pollPendingJobs()`.

- [ ] **Step 1: Write the failing success-settlement test**

```ts
it('creates a work and charges only after provider success', async () => {
  mockProvider.getJobStatus.mockResolvedValue({
    state: 'SUCCEEDED', audioUrl: 'https://authorized.example/song.mp3', title: 'Night Train',
  });
  await pollPendingJobs();
  expect(await prisma.generatedWork.count()).toBe(1);
  expect(await balance(user.id)).toEqual({ available: 12, reserved: 0 });
});
```

- [ ] **Step 2: Verify it fails**

Run: `cd web && npm test -- ai/registry.test.ts jobs.test.ts`

Expected: FAIL because job modules are absent.

- [ ] **Step 3: Implement the adapter contract and job transitions**

Define `GenerationInput` as `providerId`, `modelId`, `prompt`, optional `lyrics`, `style`, `mood`, `language`, and `durationSeconds`. The registry must reject disabled providers and missing credentials. Create the reservation and `QUEUED` job before dispatch. A successful polling response transactionally creates `GeneratedWork`, marks the job `SUCCEEDED`, and settles credits; failure/cancellation/timeout marks a terminal status and releases once. Provider implementations must follow their official API documentation at implementation time.

- [ ] **Step 4: Verify and commit**

Run: `cd web && npm run lint && npm test -- ai/registry.test.ts jobs.test.ts`

Expected: PASS; double-polling a terminal job makes no duplicate work or charge.

```powershell
git add web
git commit -m "feat: add multi-provider generation jobs"
```

### Task 6: Build the AI studio, works library and provider administration

**Files:**
- Create: `web/src/components/studio/song-form.tsx`, `generation-status.tsx`, `web/src/components/works/work-card.tsx`
- Create: `web/src/app/(site)/create/page.tsx`, `library/page.tsx`, `web/src/app/admin/providers/page.tsx`, `web/src/app/api/admin/providers/route.ts`
- Test: `web/tests/song-form.test.tsx`, `web/tests/generation-status.test.tsx`, `web/tests/admin/providers.test.ts`

**Interfaces:** Consumes generation routes and provider config; produces AI studio, job progress and user-owned work library.

- [ ] **Step 1: Write the failing studio test**

```tsx
it('shows the price and blocks signed-out creation', async () => {
  render(<SongForm providers={[provider]} session={null} />);
  expect(screen.getByText('8 点数')).toBeVisible();
  await userEvent.click(screen.getByRole('button', { name: '开始创作' }));
  expect(screen.getByText('请先登录')).toBeVisible();
});
```

- [ ] **Step 2: Verify it fails**

Run: `cd web && npm test -- song-form.test.tsx generation-status.test.tsx admin/providers.test.ts`

Expected: FAIL because studio components are absent.

- [ ] **Step 3: Implement forms, polling and access control**

The form contains provider/model, prompt, style, mood, language, duration and optional lyrics. Show price, balance and estimated duration. Poll job status while open; show an actionable failure reason and refunded-credit message. Query works by current user only. Provider administration requires role `ADMIN` and may only change enabled status and credit pricing—never reveal keys.

- [ ] **Step 4: Verify and commit**

Run: `cd web && npm run lint && npm test -- song-form.test.tsx generation-status.test.tsx admin/providers.test.ts`

Expected: PASS; non-admin configuration update returns 403.

```powershell
git add web
git commit -m "feat: add AI studio and works library"
```

### Task 7: Add the shared Windows-style player and queue

**Files:**
- Create: `web/src/components/player/player-store.ts`, `player-provider.tsx`, `mini-player.tsx`, `now-playing.tsx`, `queue-panel.tsx`
- Modify: `web/src/components/layout/site-shell.tsx`, `web/src/components/search/search-results.tsx`, `web/src/components/works/work-card.tsx`
- Test: `web/tests/player-store.test.ts`, `web/tests/mini-player.test.tsx`, `web/tests/now-playing.test.tsx`

**Interfaces:** Produces `enqueue(item)`, `play(item)`, `next()`, `previous()`, `setRepeat(mode)`, and `setShuffle(enabled)`.

- [ ] **Step 1: Write failing player tests**

```ts
it('advances from a preview to a generated work', () => {
  const store = createPlayerStore([preview, work]);
  store.play(preview);
  store.onEnded();
  expect(store.getState().current?.id).toBe(work.id);
});
```

```tsx
it('keeps the mini player fixed in the site shell', () => {
  render(<SiteShell><div /></SiteShell>);
  expect(screen.getByTestId('mini-player')).toHaveClass('fixed', 'bottom-0');
});
```

- [ ] **Step 2: Verify they fail**

Run: `cd web && npm test -- player-store.test.ts mini-player.test.tsx now-playing.test.tsx`

Expected: FAIL because player modules are absent.

- [ ] **Step 3: Implement safe browser audio playback**

Use one HTMLAudioElement in `PlayerProvider`. It may only receive a search `previewUrl` or a user-owned authorized work URL. The fixed mini player and expanded page mirror Windows styling: cover, warm-red progress, volume, previous/next, shuffle, repeat and queue. Render lyrics only from a generated-work lyric field or licensed field; otherwise show “暂无可用歌词”.

- [ ] **Step 4: Verify and commit**

Run: `cd web && npm run lint && npm test -- player-store.test.ts mini-player.test.tsx now-playing.test.tsx`

Expected: PASS; ending a preview advances rather than replacing it with a full external song.

```powershell
git add web
git commit -m "feat: add unified music player"
```

### Task 8: Add browser coverage, secure configuration and handoff docs

**Files:**
- Create: `web/e2e/auth-and-orders.spec.ts`, `search-and-player.spec.ts`, `generation.spec.ts`
- Create: `web/README.md`
- Modify: `web/.env.example`, `.gitignore`

**Interfaces:** Verifies public flows with seeded data and mocked external providers.

- [ ] **Step 1: Write the failing pending-order acceptance test**

```ts
test('creating a pending order does not add credits', async ({ page }) => {
  await loginAs(page, 'ava@example.com');
  await page.goto('/account/credits');
  await page.getByRole('button', { name: '购买 100 点数' }).click();
  await expect(page.getByText('待支付')).toBeVisible();
  await expect(page.getByText('当前余额：0')).toBeVisible();
});
```

- [ ] **Step 2: Verify the test fails before fixtures are ready**

Run: `cd web && npm run test:e2e -- auth-and-orders.spec.ts`

Expected: FAIL until seed, pages and routes exist.

- [ ] **Step 3: Add fixtures and documentation**

Document Docker database start, migrations, seed, tests, production build, provider setup and the deferred WeChat/Alipay callback integration. `.env.example` contains names only: `DATABASE_URL`, `AUTH_SECRET`, `ITUNES_SEARCH_URL`, `REPLICATE_API_TOKEN`, `SUNO_API_KEY`, `UDIO_API_KEY`, and `INTERNAL_JOB_TOKEN`. Mock providers/search in Playwright so tests never spend credits.

- [ ] **Step 4: Run final verification and commit**

Run: `cd web && npm run lint && npm test && npm run test:e2e && npm run build`

Expected: all tests pass and production build succeeds.

Run: `rg -n "BEGIN .*PRIVATE KEY|sk-[A-Za-z0-9]|DATABASE_URL=.*@" web -g '!node_modules' -g '!README.md' -g '!.env.example'`

Expected: no secrets found.

```powershell
git add web .gitignore
git commit -m "test: verify music creator website"
```

## Final verification checklist

- [ ] Accounts and all user-owned records enforce identity and role access.
- [ ] Pending orders never credit balances.
- [ ] Every terminal job yields exactly one settlement/release result.
- [ ] Disabled/unconfigured providers reject paid job creation.
- [ ] Search labels its source and plays only authorized previews.
- [ ] Generated full works and previews coexist in the Windows-style queue.
- [ ] Desktop sidebar/fixed player and mobile navigation/mini player respond correctly.

