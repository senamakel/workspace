# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: board-drag.spec.ts >> a card drags from Working to Done, and the board scrolls to get there
- Location: test/e2e/board-drag.spec.ts:234:1

# Error details

```
Error: expect(received).toBe(expected) // Object.is equality

Expected: "done"
Received: "working"

Call Log:
- Timeout 15000ms exceeded while waiting on the predicate
```

# Page snapshot

```yaml
- generic [ref=e2]:
  - generic [ref=e4]:
    - generic [ref=e7]:
      - generic [ref=e9]:
        - list [ref=e11]:
          - listitem [ref=e12]:
            - button "E2E Harness Co Current company" [ref=e13]:
              - img [ref=e15]
              - generic [ref=e19]:
                - generic [ref=e20]: E2E Harness Co
                - generic [ref=e21]: Current company
              - img [ref=e22]
        - button "Collapse sidebar" [ref=e25]:
          - img
      - list [ref=e28]:
        - listitem [ref=e29]:
          - button "Overview" [ref=e30]:
            - img [ref=e31]
            - generic [ref=e36]: Overview
        - listitem [ref=e37]:
          - button "Company" [ref=e38]:
            - img [ref=e39]
            - generic [ref=e44]: Company
        - listitem [ref=e45]:
          - button "Chat" [ref=e46]:
            - img [ref=e47]
            - generic [ref=e50]: Chat
        - listitem [ref=e51]:
          - button "Work" [ref=e52]:
            - img [ref=e53]
            - generic [ref=e55]: Work
        - listitem [ref=e56]:
          - button "Brain" [ref=e57]:
            - img [ref=e58]
            - generic [ref=e66]: Brain
        - listitem [ref=e67]:
          - button "Workspace" [ref=e68]:
            - img [ref=e69]
            - generic [ref=e71]: Workspace
        - listitem [ref=e72]:
          - button "Approvals" [ref=e73]:
            - img [ref=e74]
            - generic [ref=e77]: Approvals
        - listitem [ref=e78]:
          - button "Finance" [ref=e79]:
            - img [ref=e80]
            - generic [ref=e83]: Finance
        - listitem [ref=e84]:
          - button "Workflows" [ref=e85]:
            - img [ref=e86]
            - generic [ref=e90]: Workflows
        - listitem [ref=e91]:
          - button "Settings" [ref=e92]:
            - img [ref=e93]
            - generic [ref=e96]: Settings
      - list [ref=e98]:
        - listitem [ref=e99]:
          - button "Live" [ref=e100]:
            - generic [ref=e103]: Live
        - listitem [ref=e104]:
          - button "Feedback" [ref=e105]:
            - img [ref=e106]
            - generic [ref=e108]: Feedback
        - listitem [ref=e109]:
          - link "Join our Discord" [ref=e110] [cursor=pointer]:
            - /url: https://discord.tinyhumans.ai
            - img [ref=e111]
            - generic [ref=e113]: Join our Discord
      - button "Toggle Sidebar" [ref=e114]
    - main [ref=e115]:
      - generic [ref=e117]:
        - generic [ref=e118]:
          - generic [ref=e119]:
            - heading "Tasks 11" [level=1] [ref=e120]:
              - button "Tasks" [ref=e121]:
                - text: Tasks
                - img [ref=e122]
              - generic "11 open" [ref=e124]: "11"
            - group [ref=e125]:
              - generic "About this list" [ref=e126] [cursor=pointer]
          - generic [ref=e127]:
            - button "Refresh" [ref=e128]:
              - img
              - text: Refresh
            - button "Add task" [ref=e129]:
              - img
              - text: Add task
        - generic [ref=e131]:
          - generic [ref=e132]:
            - generic [ref=e133]:
              - img
              - textbox "Search every field" [ref=e134]
            - combobox [ref=e135]:
              - generic [ref=e136]: Every status
              - img: ▼
            - textbox [ref=e137]: all
            - button "List" [ref=e138]:
              - img
              - text: List
            - button "Rendered file" [ref=e139]:
              - img
              - text: Rendered file
          - generic [ref=e141]:
            - generic [ref=e142]:
              - generic [ref=e143]:
                - generic [ref=e144]: Pending
                - generic [ref=e145]: "10"
              - generic [ref=e146]:
                - button "e2e planning settle 1787490849481 medium Planned · 2 steps" [ref=e148]:
                  - generic [ref=e149]:
                    - paragraph [ref=e150]: e2e planning settle 1787490849481
                    - generic [ref=e151]: medium
                  - generic [ref=e152]:
                    - img [ref=e153]
                    - generic [ref=e156]: Planned · 2 steps
                - button "e2e board shape 1787490849090 — and then a great deal more detail that runs well… medium e2e board shape 1787490849090 — and then a great deal more detail that runs well past the eighty character title cap so the note has to carry it" [ref=e158]:
                  - generic [ref=e159]:
                    - paragraph [ref=e160]: e2e board shape 1787490849090 — and then a great deal more detail that runs well…
                    - generic [ref=e161]: medium
                  - paragraph [ref=e162]: e2e board shape 1787490849090 — and then a great deal more detail that runs well past the eighty character title cap so the note has to carry it
                - button "e2e retired route 1787490848157 medium" [ref=e164]:
                  - generic [ref=e165]:
                    - paragraph [ref=e166]: e2e retired route 1787490848157
                    - generic [ref=e167]: medium
                - button "e2e stale 1787490847538 renamed medium ghost_1787490847503" [ref=e169]:
                  - generic [ref=e170]:
                    - paragraph [ref=e171]: e2e stale 1787490847538 renamed
                    - generic [ref=e172]: medium
                  - generic [ref=e173]:
                    - generic [ref=e174]: G1
                    - generic [ref=e175]: ghost_1787490847503
                - button "e2e unassign 1787490846851 medium" [ref=e177]:
                  - generic [ref=e178]:
                    - paragraph [ref=e179]: e2e unassign 1787490846851
                    - generic [ref=e180]: medium
                - button "e2e rename 1787490846268 renamed medium writer" [ref=e182]:
                  - generic [ref=e183]:
                    - paragraph [ref=e184]: e2e rename 1787490846268 renamed
                    - generic [ref=e185]: medium
                  - generic [ref=e186]:
                    - generic [ref=e187]: W
                    - generic [ref=e188]: writer
                - button "e2e unassigned card 1787490845884 medium" [ref=e190]:
                  - generic [ref=e191]:
                    - paragraph [ref=e192]: e2e unassigned card 1787490845884
                    - generic [ref=e193]: medium
                - button "e2e writer card 1787490845100 medium writer" [ref=e195]:
                  - generic [ref=e196]:
                    - paragraph [ref=e197]: e2e writer card 1787490845100
                    - generic [ref=e198]: medium
                  - generic [ref=e199]:
                    - generic [ref=e200]: W
                    - generic [ref=e201]: writer
                - button "e2e desk card 1787490844282 medium engineering" [ref=e203]:
                  - generic [ref=e204]:
                    - paragraph [ref=e205]: e2e desk card 1787490844282
                    - generic [ref=e206]: medium
                  - generic [ref=e207]:
                    - generic [ref=e208]: E
                    - generic [ref=e209]: engineering
                - button "e2e picker 1787490843640 medium" [ref=e211]:
                  - generic [ref=e212]:
                    - paragraph [ref=e213]: e2e picker 1787490843640
                    - generic [ref=e214]: medium
            - generic [ref=e215]:
              - generic [ref=e216]:
                - generic [ref=e217]: Working
                - generic [ref=e218]: "1"
              - button "e2e in-review to done 1787490850535 medium" [active] [ref=e221]:
                - generic [ref=e222]:
                  - paragraph [ref=e223]: e2e in-review to done 1787490850535
                  - generic [ref=e224]: medium
            - button "Expand Done, 0 cards" [ref=e226] [cursor=pointer]:
              - generic [ref=e227]: Done
              - generic [ref=e228]: "0"
  - region "Notifications alt+T"
```

# Test source

```ts
  218 |     return Math.round(inset.getBoundingClientRect().right - window.innerWidth);
  219 |   });
  220 |   expect(overshoot).toBeLessThanOrEqual(0);
  221 | 
  222 |   // Scrolled to the end, Done is a whole column inside the window rather than
  223 |   // a sliver of one pinned against the edge.
  224 |   await board(page).evaluate((el) => {
  225 |     el.scrollLeft = el.scrollWidth;
  226 |   });
  227 |   await page.waitForTimeout(300);
  228 |   const done = await column(page, DONE).boundingBox();
  229 |   const width = page.viewportSize()!.width;
  230 |   expect(done).not.toBeNull();
  231 |   expect(Math.min(done!.x + done!.width, width) - done!.x).toBeGreaterThan(200);
  232 | });
  233 | 
  234 | test("a card drags from Working to Done, and the board scrolls to get there", async ({
  235 |   page,
  236 |   request,
  237 | }) => {
  238 |   const title = `e2e in-review to done ${Date.now()}`;
  239 |   const { id, card } = await seedInReview(page, request, title);
  240 | 
  241 |   // Three phases of ~260px no longer overflow the default 1280px window, so
  242 |   // the board cannot scroll and the park below lands on zero. Narrow the
  243 |   // window so the board genuinely overflows: the sidebar stays expanded above
  244 |   // `md` (768px), and the park needs ~260px of overflow to land mid-range.
  245 |   const pane = () => board(page).evaluate((el) => el.clientWidth);
  246 |   const wide = await pane();
  247 |   await page.setViewportSize({ width: 800, height: 720 });
  248 |   // The board learns its own width through a `ResizeObserver`, so the frame
  249 |   // after `setViewportSize` is not the frame it has re-measured on. Everything
  250 |   // below turns on that measurement — which columns collapse, and by how much
  251 |   // the board overflows — so wait for it rather than for a timeout.
  252 |   await expect.poll(pane).toBeLessThan(wide);
  253 | 
  254 |   // And expand *again*, because narrowing the window is what created the rails.
  255 |   // `openBoard` ran `expandAll` at 1280px, where three phases fit and the board
  256 |   // therefore collapses nothing — so it found no rails and pinned nothing.
  257 |   // Narrowing is what makes the columns stop fitting, and an empty Done folds
  258 |   // itself into a ~40px rail. Dragging onto that rail is a different gesture
  259 |   // from the one this test is about — the rail opens under the drag, reflowing
  260 |   // the board mid-drop — and it also leaves the board barely wider than its
  261 |   // pane, so the park below lands on zero and the edge-scroll claim stops being
  262 |   // tested. Pinning every phase open puts the board back to the full
  263 |   // three-phase width the assertions below assume.
  264 |   await expandAll(page);
  265 |   await expect(board(page).locator('[data-collapsed="true"]')).toHaveCount(0);
  266 | 
  267 |   // Park the board so Working is on screen and Done is not. This is the
  268 |   // operator's actual starting position, and the case the gesture could not
  269 |   // finish before: nothing scrolls a nested container during an HTML5 drag.
  270 |   const scrolled = await board(page).evaluate((el) => {
  271 |     el.scrollLeft = Math.max(0, el.scrollWidth - el.clientWidth - 260);
  272 |     return el.scrollLeft;
  273 |   });
  274 |   await page.waitForTimeout(300);
  275 | 
  276 |   const box = await card.boundingBox();
  277 |   if (!box) throw new Error("the seeded card has no box");
  278 |   // The **board's** right edge, not the window's. On its own screen the board
  279 |   // ran to the window edge and the two were the same pixel; inside Ledgers it
  280 |   // sits past a nav and inside the section's padding. Riding the window edge
  281 |   // here would hold the pointer over the page *outside* the board, where its
  282 |   // `dragover` never fires — the test would fail for a reason that has nothing
  283 |   // to do with the behaviour, and the band is defined relative to the board
  284 |   // anyway.
  285 |   const edge = await board(page).boundingBox();
  286 |   if (!edge) throw new Error("the board has no box");
  287 |   const rightEdge = edge.x + edge.width - 8;
  288 | 
  289 |   await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  290 |   await page.mouse.down();
  291 |   // Ride the right edge and let the board bring Done to the pointer.
  292 |   // Vertically at the board's middle, not a fixed offset below the card. The
  293 |   // board is only as tall as the pane leaves it, and a pointer held below its
  294 |   // bottom edge is a pointer off the board — where its `dragover` never fires.
  295 |   const rideY = edge.y + edge.height / 2;
  296 |   for (let tick = 0; tick < 25; tick += 1) {
  297 |     await page.mouse.move(rightEdge - (tick % 2), rideY);
  298 |     await page.waitForTimeout(60);
  299 |   }
  300 |   const rode = await board(page).evaluate((el) => el.scrollLeft);
  301 |   expect(rode, "the board follows a drag held against its edge").toBeGreaterThan(scrolled);
  302 | 
  303 |   const done = await column(page, DONE).boundingBox();
  304 |   if (!done) throw new Error("Done has no box");
  305 |   await page.mouse.move(done.x + done.width / 2, done.y + done.height / 2);
  306 |   await page.waitForTimeout(150);
  307 |   await page.mouse.up();
  308 | 
  309 |   // The host's own record, which is the only thing that settles whether the
  310 |   // move happened rather than merely appeared to. It is also the assertion the
  311 |   // port could most easily have lost: the board writes through `patchTask` here
  312 |   // exactly as it did on its own screen, because entering a column fires work
  313 |   // and `record_entry` is refused for this ledger.
  314 |   await expect
  315 |     .poll(async () => (await (await request.get(`${API}/tasks/${id}`)).json()).task.column, {
  316 |       timeout: 15_000,
  317 |     })
> 318 |     .toBe("done");
      |      ^ Error: expect(received).toBe(expected) // Object.is equality
  319 | 
  320 |   // And the counts the operator was watching.
  321 |   await expect(column(page, DONE)).toContainText(title);
  322 |   await expect(column(page, WORKING)).not.toContainText(title);
  323 | });
  324 | 
  325 | test("a drop that misses every column says so instead of doing nothing", async ({
  326 |   page,
  327 |   request,
  328 | }) => {
  329 |   const title = `e2e drag near miss ${Date.now()}`;
  330 |   const { id, card } = await seedInReview(page, request, title);
  331 | 
  332 |   await board(page).evaluate((el) => {
  333 |     el.scrollLeft = el.scrollWidth;
  334 |   });
  335 |   await page.waitForTimeout(300);
  336 | 
  337 |   // The trailing gutter past the last column: board pixels that belong to no
  338 |   // column. This is where a near miss lands, and it used to swallow the whole
  339 |   // gesture without a word.
  340 |   const gutter = await board(page).locator("div[aria-hidden].w-4").first().boundingBox();
  341 |   if (!gutter) throw new Error("no trailing gutter");
  342 |   // The gutter's own middle, rather than a fixed offset down it. It is a flex
  343 |   // item stretched to the tallest column, so on a board holding a card or two
  344 |   // it is short — and a fixed 200px would drop *below* the board entirely,
  345 |   // which is a miss of a different kind than the one under test.
  346 |   await handDrag(page, card, gutter.x + gutter.width / 2, gutter.y + gutter.height / 2);
  347 | 
  348 |   await expect(page.getByText("Drop the card on a column to move it.")).toBeVisible({
  349 |     timeout: 5_000,
  350 |   });
  351 |   // Saying so is not the same as moving it: the card must stay where it was.
  352 |   // Unmoved: still the `in_review` stage, which reads as the Working column.
  353 |   const unmoved = (await (await request.get(`${API}/tasks/${id}`)).json()).task;
  354 |   expect(unmoved.stage).toBe("in_review");
  355 |   expect(unmoved.column).toBe("working");
  356 |   await expect(column(page, WORKING)).toContainText(title);
  357 | });
  358 | 
  359 | test("a move the host refuses names the card, the column, and the reason", async ({
  360 |   page,
  361 |   request,
  362 | }) => {
  363 |   const title = `e2e refused move ${Date.now()}`;
  364 |   const { card } = await seedInReview(page, request, title);
  365 | 
  366 |   // The host accepts working → done, so the refusal has to be induced. This
  367 |   // asserts the console's half of the contract: whatever the host says, the
  368 |   // operator reads it rather than watching the card snap back in silence.
  369 |   await page.route("**/tasks/*", async (route) => {
  370 |     if (route.request().method() !== "PATCH") return route.fallback();
  371 |     await route.fulfill({
  372 |       status: 400,
  373 |       contentType: "application/json",
  374 |       body: JSON.stringify({ code: "invalid_request", error: "the board is read-only right now" }),
  375 |     });
  376 |   });
  377 | 
  378 |   await board(page).evaluate((el) => {
  379 |     el.scrollLeft = el.scrollWidth;
  380 |   });
  381 |   await page.waitForTimeout(300);
  382 |   const done = await column(page, DONE).boundingBox();
  383 |   if (!done) throw new Error("Done has no box");
  384 |   await handDrag(page, card, done.x + done.width / 2, done.y + done.height / 2);
  385 | 
  386 |   // "Done" is the host's label for the column, reaching the toast through the
  387 |   // ledger's statuses rather than through a list the console keeps.
  388 |   await expect(page.getByText(`Could not move "${title}" to Done.`)).toBeVisible({
  389 |     timeout: 5_000,
  390 |   });
  391 |   await expect(page.getByText("the board is read-only right now")).toBeVisible();
  392 |   // Refused means refused: the optimistic move is rolled back.
  393 |   await expect(column(page, WORKING)).toContainText(title);
  394 | });
  395 | 
```