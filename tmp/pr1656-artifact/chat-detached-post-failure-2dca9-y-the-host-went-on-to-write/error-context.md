# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: chat-detached-post-failure.spec.ts >> a chat POST killed in flight still shows the reply the host went on to write
- Location: test/e2e/chat-detached-post-failure.spec.ts:79:1

# Error details

```
Error: expect(locator).toBeVisible() failed

Locator: locator('article[data-message-id]').filter({ hasText: 'You said: cut-1787503150374' })
Expected: visible
Timeout: 30000ms
Error: element(s) not found

Call log:
  - Expect "toBeVisible" with timeout 30000ms
  - waiting for locator('article[data-message-id]').filter({ hasText: 'You said: cut-1787503150374' })

```

```yaml
- list:
  - listitem:
    - button "E2E Harness Co Current company"
- button "Collapse sidebar"
- list:
  - listitem:
    - button "Overview"
  - listitem:
    - button "Company"
  - listitem:
    - button "Chat"
  - listitem:
    - button "Work"
  - listitem:
    - button "Brain"
  - listitem:
    - button "Workspace"
  - listitem:
    - button "Approvals"
  - listitem:
    - button "Finance"
  - listitem:
    - button "Workflows"
  - listitem:
    - button "Settings"
- list:
  - listitem:
    - button "Live"
  - listitem:
    - button "Feedback"
  - listitem:
    - link "Join our Discord":
      - /url: https://discord.tinyhumans.ai
- button "Toggle Sidebar"
- main:
  - complementary:
    - heading "Chat" [level=2]
    - button "New message" [disabled]
    - button "Channels" [expanded]
    - list:
      - listitem:
        - button "engineering-desk"
      - listitem:
        - button "content-desk"
      - listitem:
        - button "legal"
    - button "Direct messages" [expanded]
    - list:
      - listitem:
        - button "Chief Executive"
      - listitem:
        - button "Engineer"
      - listitem:
        - button "Writer"
      - listitem:
        - button "Operations"
      - listitem:
        - button "Page Builder"
      - listitem:
        - button "Researcher"
  - heading "engineering-desk" [level=1]
  - 'button "Copy channel name: #engineering-desk"'
  - text: How things are built and technical plans.
  - button "1 Show teammates"
  - heading "#engineering-desk" [level=2]
  - paragraph: "This is the very beginning of #engineering-desk. How things are built and technical plans."
  - paragraph: Today
  - article:
    - text: You 4:39 PM
    - paragraph: cut-1787503150374
  - paragraph: Couldn't send — cannot reach the company host at this origin
  - 'textbox "Message #engineering-desk"'
  - group "What this message is for":
    - button "Just chatting"
    - button "Do it once" [pressed]
    - button "Build me the workflow"
  - button "Mention someone"
  - button "Attach a file" [disabled]
  - button "Add an emoji" [disabled]
  - button "Formatting"
  - button "Send" [disabled]
  - paragraph: Enter to send · Shift+Enter for a new line
- region "Notifications alt+T"
```

# Test source

```ts
  54  |  * reported itself as a 60-second wait for `Couldn't send`, the loudest symptom
  55  |  * being the one thing that was not wrong.
  56  |  *
  57  |  * So from the moment the send starts, `chat/history` answers `[]`. The channel
  58  |  * is hydrated before that and is never reopened or reloaded; the durable read
  59  |  * is barred from the window under test. If the bubble appears, the released
  60  |  * frame is the only thing that can have put it there.
  61  |  */
  62  | 
  63  | const ENGINEERING = { id: "engineering", channel: "engineering-desk" };
  64  | 
  65  | /** How long the response is withheld before the connection is cut. */
  66  | const CUT_AFTER_MS = 8_000;
  67  | 
  68  | test.beforeEach(async ({ page }) => {
  69  |   // Same tour-skip shim the rest of the suite uses — the first-run modal
  70  |   // swallows every click otherwise.
  71  |   await page.addInitScript(() => {
  72  |     const real = Storage.prototype.getItem;
  73  |     Storage.prototype.getItem = function getItem(key: string) {
  74  |       return key.startsWith("oc-tour:") ? '{"skipped":true}' : real.call(this, key);
  75  |     };
  76  |   });
  77  | });
  78  | 
  79  | test("a chat POST killed in flight still shows the reply the host went on to write", async ({
  80  |   page,
  81  | }) => {
  82  |   test.skip(LIVE_BRAIN, "asserts the offline echo brain's `You said: <text>` reply.");
  83  |   // The deliberate pause plus a settle window at the end runs past the suite's
  84  |   // 60s default, so the budget is stated rather than inherited.
  85  |   test.setTimeout(150_000);
  86  | 
  87  |   let cuts = 0;
  88  |   // Named before the route is registered so the premise reading taken inside it
  89  |   // can target this turn's own reply.
  90  |   const marker = `cut-${Date.now()}`;
  91  | 
  92  |   // The durable transcript, barred from the window under test — see the header.
  93  |   // Held only from the send onwards, so the channel still hydrates normally
  94  |   // first: what is excluded is a re-read landing *during* the cut, not the
  95  |   // hydration the premise depends on.
  96  |   let holdHistory = false;
  97  |   await page.route("**/chat/history*", async (route) => {
  98  |     if (!holdHistory) {
  99  |       await route.continue();
  100 |       return;
  101 |     }
  102 |     await route.fulfill({
  103 |       status: 200,
  104 |       contentType: "application/json",
  105 |       body: "[]",
  106 |     });
  107 |   });
  108 | 
  109 |   // What was on screen at the moment of the cut, read inside the handler and
  110 |   // asserted after it. An `expect` that throws inside a route handler aborts
  111 |   // the handler, so `route.abort` never runs, the POST never fails, and the
  112 |   // run dies waiting for an error line that was never going to appear —
  113 |   // reporting a premise violation as a timeout somewhere else entirely.
  114 |   let repliesAtCut: number | null = null;
  115 |   await page.route("**/chat", async (route) => {
  116 |     if (route.request().method() !== "POST") {
  117 |       await route.continue();
  118 |       return;
  119 |     }
  120 |     // Upstream first: the host accepts the turn and starts running it. Only
  121 |     // then is the answer thrown away.
  122 |     await route.fetch();
  123 |     await new Promise((resolve) => setTimeout(resolve, CUT_AFTER_MS));
  124 |     cuts += 1;
  125 |     // The premise, recorded rather than assumed: at the moment the connection
  126 |     // is cut, nothing has drawn this reply yet — it can only appear later from
  127 |     // the released frame, which is exactly what the assertions below pin.
  128 |     // `reply` targets this turn's own echo, not the total bubble count, so a
  129 |     // line that would render the answer early fails the test instead of this
  130 |     // reading hardening nothing.
  131 |     repliesAtCut = await reply(page, marker).count();
  132 |     await route.abort("connectionaborted");
  133 |   });
  134 | 
  135 |   await openChannel(page, ENGINEERING.id);
  136 | 
  137 |   await page.getByPlaceholder(/^Message /).fill(marker);
  138 |   holdHistory = true;
  139 |   await page.keyboard.press("Enter");
  140 | 
  141 |   // The operator is told the request failed, and that stays true — a reply
  142 |   // arriving later does not mean the send worked, and a console that quietly
  143 |   // swallowed the error would leave them unable to tell a delivered message
  144 |   // from a dropped one.
  145 |   await expect(page.getByText(/Couldn't send/).first()).toBeVisible({ timeout: 60_000 });
  146 |   expect(cuts, "the chat POST must actually have been cut").toBe(1);
  147 |   expect(repliesAtCut, "nothing had drawn this reply when the connection was cut").toBe(0);
  148 | 
  149 |   // …and the answer is on screen anyway, drawn from the frame that was held
  150 |   // while the POST's fate was unknown and released when it turned out to have
  151 |   // died. Before the outcome split this assertion failed: the throw was
  152 |   // reported as `onSendEnd`, which discarded the frame, and the reply was gone
  153 |   // for good short of a reload.
> 154 |   await expect(reply(page, marker)).toBeVisible({ timeout: 30_000 });
      |                                     ^ Error: expect(locator).toBeVisible() failed
  155 |   await expect(reply(page, marker)).toHaveCount(1);
  156 | 
  157 |   // Releasing must not be a licence to double-render: nothing else is going to
  158 |   // deliver this reply, so a second bubble could only come from the frame being
  159 |   // both replayed and rendered live.
  160 |   await page.waitForTimeout(5_000);
  161 |   await expect(reply(page, marker)).toHaveCount(1);
  162 | });
  163 | 
```