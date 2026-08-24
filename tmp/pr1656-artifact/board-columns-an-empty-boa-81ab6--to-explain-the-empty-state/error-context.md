# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: board-columns.spec.ts >> an empty board leaves its column affordances to explain the empty state
- Location: test/e2e/board-columns.spec.ts:116:1

# Error details

```
Error: expect(locator).toBeVisible() failed

Locator: getByTestId('ledger-board')
Expected: visible
Timeout: 15000ms
Error: element(s) not found

Call log:
  - Expect "toBeVisible" with timeout 15000ms
  - waiting for getByTestId('ledger-board')

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
  - heading "E2E empty board 1787503117992 0" [level=1]:
    - button "E2E empty board 1787503117992"
    - text: "0"
  - group: About this list
  - button "Refresh"
  - button "Record"
  - textbox "Search ledger entries":
    - /placeholder: Search every field
  - combobox "Filter by status": Every status
  - button "Board"
  - button "Rendered file"
  - paragraph: Nothing recorded here yet.
- region "Notifications alt+T"
```

# Test source

```ts
  43  |     }
  44  |   });
  45  | });
  46  | 
  47  | async function dismissTour(page: Page) {
  48  |   const skip = page.getByRole("button", { name: "Skip for now" });
  49  |   for (let attempt = 0; attempt < 5; attempt += 1) {
  50  |     if (!(await skip.isVisible().catch(() => false))) return;
  51  |     await skip.click({ force: true }).catch(() => {});
  52  |     await page.waitForTimeout(300);
  53  |   }
  54  |   await expect(skip).toHaveCount(0);
  55  | }
  56  | 
  57  | /** The column headers the board actually renders, left to right. */
  58  | function columnLabels(page: Page) {
  59  |   // By testid, not by shape. An empty column collapses to a rail (issue #1101)
  60  |   // and renders its label inside a button rather than the open column's header
  61  |   // row, so a structural selector would silently stop counting the very columns
  62  |   // this asserts the order of.
  63  |   return page.getByTestId("ledger-board").getByTestId("column-label");
  64  | }
  65  | 
  66  | /**
  67  |  * Issue #1140 — the two things retiring the Tasks page could have taken.
  68  |  *
  69  |  * `#/tasks` is in every operator's history and fingers, and `#/tasks/<id>` is
  70  |  * linked from chat, from an approval card and from a workflow run's rows. The
  71  |  * first has to land on the board and the second has to keep opening the card,
  72  |  * and both failures are quiet: the router drops an address it does not know and
  73  |  * renders Overview, which looks like a link that worked.
  74  |  */
  75  | test("the retired #/tasks lands on the board, and #/tasks/<id> still opens the card", async ({
  76  |   page,
  77  |   request,
  78  | }) => {
  79  |   const title = `e2e retired route ${Date.now()}`;
  80  |   const seeded = await request.post(`${API}/tasks`, { data: { title } });
  81  |   expect(seeded.ok()).toBeTruthy();
  82  |   const id = (await seeded.json()).id as string;
  83  | 
  84  |   await page.goto("/#/tasks");
  85  |   await dismissTour(page);
  86  | 
  87  |   // The board, and the address rewritten to name where it actually is. A push
  88  |   // rather than a replace would leave `#/tasks` one Back away, bouncing the
  89  |   // operator forward again on arrival.
  90  |   await expect(columnLabels(page)).toHaveText(EXPECTED_COLUMNS, { timeout: 15_000 });
  91  |   await expect.poll(() => new URL(page.url()).hash).toBe("#/ledgers/tasks");
  92  | 
  93  |   // And the card detail, which Ledgers deliberately does not reproduce.
  94  |   await page.goto(`/#/tasks/${id}`);
  95  |   await expect(page.getByRole("heading", { name: title })).toBeVisible({ timeout: 15_000 });
  96  |   expect(new URL(page.url()).hash).toBe(`#/tasks/${id}`);
  97  | });
  98  | 
  99  | test("the board renders the three phases in order, and none of the retired columns", async ({
  100 |   page,
  101 | }) => {
  102 |   await page.goto("/#/ledgers/tasks");
  103 |   await dismissTour(page);
  104 | 
  105 |   // The columns are a read now, not a literal, so the board is not itself
  106 |   // until they land.
  107 |   await expect(columnLabels(page)).toHaveText(EXPECTED_COLUMNS, { timeout: 15_000 });
  108 |   // The collapse, stated as its own assertion. Backlog went in #301; the four
  109 |   // stages between To-do and Done went in #1512, and they are the ones an
  110 |   // operator would notice missing — so each is named rather than counted.
  111 |   for (const gone of ["Backlog", "To-do", "Planning", "In progress", "Paused", "In review"]) {
  112 |     await expect(columnLabels(page).filter({ hasText: gone })).toHaveCount(0);
  113 |   }
  114 | });
  115 | 
  116 | test("an empty board leaves its column affordances to explain the empty state", async ({
  117 |   page,
  118 |   request,
  119 | }) => {
  120 |   // A ledger declared just for this assertion makes the empty condition
  121 |   // independent of cards that earlier specs may have added to the shared host.
  122 |   const marker = Date.now();
  123 |   const slug = `e2e-empty-board-${marker}`;
  124 |   const declared = await request.post(`${API}/ledgers`, {
  125 |     data: {
  126 |       slug,
  127 |       title: `E2E empty board ${marker}`,
  128 |       purpose: "A list used to verify empty board copy.",
  129 |       fields: [
  130 |         { name: "id", role: "id" },
  131 |         { name: "title", role: "title", required: true },
  132 |         { name: "status", role: "status", required: true },
  133 |       ],
  134 |       statuses: [{ name: "open" }, { name: "closed", closed: true }],
  135 |       checks: ["required-field", "known-status"],
  136 |     },
  137 |   });
  138 |   expect(declared.ok()).toBeTruthy();
  139 | 
  140 |   try {
  141 |     await page.goto(`/#/ledgers/${slug}`);
  142 |     await dismissTour(page);
> 143 |     await expect(page.getByTestId("ledger-board")).toBeVisible({ timeout: 15_000 });
      |                                                    ^ Error: expect(locator).toBeVisible() failed
  144 | 
  145 |     // Board columns already say what an empty board is for. A second status
  146 |     // line above them repeats the fact instead of helping the operator act.
  147 |     await expect(page.getByTestId("ledger-empty")).toHaveCount(0);
  148 |     await expect(page.getByTestId("ledger-filtered-empty")).toHaveCount(0);
  149 | 
  150 |     const search = page.getByPlaceholder("Search every field");
  151 |     await search.fill("no matching row");
  152 |     await expect(page.getByTestId("ledger-filtered-empty")).toHaveCount(0);
  153 | 
  154 |     // The list has no per-status-column affordance, so it retains both forms
  155 |     // of the above-list notice.
  156 |     await page.getByRole("button", { name: "List" }).click();
  157 |     await expect(page.getByTestId("ledger-filtered-empty")).toBeVisible({ timeout: 15_000 });
  158 |     await search.fill("");
  159 |     await expect(page.getByTestId("ledger-empty")).toBeVisible({ timeout: 15_000 });
  160 |   } finally {
  161 |     await request.delete(`${API}/ledgers/${slug}`);
  162 |   }
  163 | });
  164 | 
  165 | test("new work enters through one prompt box and lands in Pending", async ({ page, request }) => {
  166 |   await page.goto("/#/ledgers/tasks");
  167 |   await dismissTour(page);
  168 | 
  169 |   // Exactly one entry point on the whole board (issue #206's rule, kept).
  170 |   const addTask = page.getByRole("button", { name: "Add task" });
  171 |   await expect(addTask).toHaveCount(1);
  172 |   await addTask.click();
  173 |   await expect(page.getByRole("heading", { name: "New task" })).toBeVisible();
  174 | 
  175 |   // Title / Note / Priority stay gone from create — the host defaults priority
  176 |   // and the card's edit surface owns them (#278).
  177 |   await expect(page.locator("#new-prompt")).toBeVisible();
  178 |   for (const gone of ["#new-title", "#new-note", "#new-priority"]) {
  179 |     await expect(page.locator(gone)).toHaveCount(0);
  180 |   }
  181 | 
  182 |   // Assignee came *back* in #1106, and is the one exception to "one field".
  183 |   // #301 removed it on the reasoning that the host defaults it; what that missed
  184 |   // is that the host's default is a planning pass which picks an owner, and picks
  185 |   // one silently when two teammates fit. Offering it here is the pre-empt.
  186 |   //
  187 |   // The rule that keeps this from re-breaking what #301 fixed is the *default*,
  188 |   // asserted below rather than the control's absence: an operator who ignores it
  189 |   // types a prompt, hits Create, and gets exactly the unassigned card they got
  190 |   // before — the field is omitted from the body entirely when untouched.
  191 |   await expect(page.locator("#new-assignee")).toHaveCount(1);
  192 | 
  193 |   // A prompt longer than the title cap: the title is shortened and the full
  194 |   // text survives in the note, so nothing the operator typed is lost.
  195 |   const marker = `e2e board shape ${Date.now()}`;
  196 |   const long = `${marker} — and then a great deal more detail that runs well past the eighty character title cap so the note has to carry it`;
  197 |   await page.locator("#new-prompt").fill(long);
  198 |   await page.getByRole("button", { name: "Create", exact: true }).click();
  199 | 
  200 |   type Row = { title: string; note?: string; column: string; assignee: string };
  201 |   const find = async (): Promise<Row | undefined> => {
  202 |     const rows = (await (await request.get(`${API}/tasks`)).json()) as Row[];
  203 |     return rows.find((r) => r.title.startsWith(marker));
  204 |   };
  205 | 
  206 |   await expect.poll(async () => (await find()) !== undefined, { timeout: 15_000 }).toBe(true);
  207 |   const created = (await find())!;
  208 | 
  209 |   expect(created.column).toBe("pending");
  210 |   expect(created.title.length).toBeLessThanOrEqual(81); // 80 + the ellipsis
  211 |   expect(created.note).toBe(long);
  212 |   // The #1106 default, and the reason adding the control is a no-op for anyone
  213 |   // who does not use it: the prompt was the only thing filled in, so the card is
  214 |   // unassigned exactly as it was before the picker existed.
  215 |   expect(created.assignee).toBe("");
  216 | });
  217 | 
  218 | /**
  219 |  * Issue #501. This test states a **no-planner** contract, and only a host
  220 |  * without one keeps it.
  221 |  *
  222 |  * **The gesture moved in issue #1512.** Planning used to be a board column, and
  223 |  * this test used to drag a card into it. Collapsing the board to three phases
  224 |  * took the drop target away — `planning` is a stage now, one of the four that
  225 |  * read as Working — so the deliberate "plan this before anything runs" act is a
  226 |  * control on the card instead, which is where an *act* belonged rather than a
  227 |  * *state*. What it writes is unchanged: the `planning` stage, which edge-fires
  228 |  * exactly one pass.
  229 |  *
  230 |  * Its own comment used to say the no-dispatch assertion "lets the column ship
  231 |  * ahead of epic #183 §4's auto-advance". §4 has since landed as the planning
  232 |  * station (`src/harness/planning.rs`, issue #337), and a card entering Planning
  233 |  * on a planner-attached host now edge-fires exactly one pass and is **settled**
  234 |  * by it — never left sitting in `planning`:
  235 |  *
  236 |  * | pass outcome | where the card lands |
  237 |  * |---|---|
  238 |  * | a plan, nothing blocking, a valid assignee | `in_progress` — and the dispatch edge fires |
  239 |  * | a plan, a hard prerequisite missing | `todo`, with the gap on the note |
  240 |  * | the pass itself failed | `todo`, with the reason on the note |
  241 |  *
  242 |  * So on the live-brain lane both of this test's claims are false by design: the
  243 |  * card does not stay in `planning`, and the first row dispatches. `plan_task`
```