# Kinship SVG Arrows Bugfix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix invisible SVG arrows and replace the cluttered MRCA-to-branches connector section with a clean SVG inverted-Y fork.

**Architecture:** Two changes in two files — fix the arrow color class in the `arrow_connector` component, add a new `fork_connector` component, and swap the template section.

**Tech Stack:** Phoenix LiveView, HEEx templates, inline SVG

---

### Task 1: Fix arrow color

**Files:**
- Modify: `lib/web/live/kinship_live.ex:334`

**Step 1: Fix the color class**

In `arrow_connector`, change `text-base-200` to `text-base-300`:

```elixir
# Before (line 334):
<div class="py-1 text-base-200">

# After:
<div class="py-1 text-base-300">
```

**Step 2: Verify compilation**

Run: `mix compile`
Expected: Compilation succeeds with no warnings.

**Step 3: Commit**

```bash
git add lib/web/live/kinship_live.ex
git commit -m "fix: make kinship arrow connectors visible (text-base-300)"
```

---

### Task 2: Add fork_connector component

**Files:**
- Modify: `lib/web/live/kinship_live.ex` (add component after `arrow_connector`, before `kinship_person_avatar`)

**Step 1: Add the fork_connector function component**

Insert after the closing `end` of `arrow_connector` (after line 360) and before the `attr :person` line (line 362):

```elixir
  defp fork_connector(assigns) do
    ~H"""
    <div class="w-full max-w-2xl py-1 text-base-300">
      <svg viewBox="0 0 200 40" class="w-full h-10" preserveAspectRatio="none">
        <path
          d="M100 0 L100 15 M100 15 L50 40 M100 15 L150 40"
          stroke="currentColor"
          stroke-width="1.5"
          fill="none"
          stroke-linecap="round"
          stroke-linejoin="round"
          vector-effect="non-scaling-stroke"
        />
      </svg>
    </div>
    """
  end
```

Key details:
- `viewBox="0 0 200 40"` — abstract coordinate space, 200 wide × 40 tall
- The path draws: vertical line down from center (100,0 → 100,15), then two diagonal lines splitting to (50,40) left and (150,40) right — landing at the 25% and 75% horizontal positions (matching `flex-1` column centers)
- `vector-effect="non-scaling-stroke"` keeps stroke width consistent regardless of SVG scaling
- `preserveAspectRatio="none"` lets it stretch to fill the container width

**Step 2: Verify compilation**

Run: `mix compile`
Expected: Compilation succeeds. Warning about unused `fork_connector` is OK for now.

**Step 3: Commit**

```bash
git add lib/web/live/kinship_live.ex
git commit -m "feat: add fork_connector SVG component for kinship tree"
```

---

### Task 3: Replace connector section in template

**Files:**
- Modify: `lib/web/live/kinship_live.html.heex:177-191`

**Step 1: Replace the branch connectors + horizontal bar with fork_connector**

Remove lines 177-191 (the `<%!-- Branch connectors --%>` section and the `<%!-- Horizontal connector bar --%>` section):

```heex
                  <%!-- Branch connectors --%>
                  <div class="flex w-full max-w-2xl">
                    <div class="flex-1 flex justify-center">
                      <.arrow_connector direction={:down} />
                    </div>
                    <div class="flex-1 flex justify-center">
                      <.arrow_connector direction={:down} />
                    </div>
                  </div>

                  <%!-- Horizontal connector bar --%>
                  <div class="flex w-full max-w-2xl">
                    <div class="flex-1 border-t-2 border-r border-base-300 h-0"></div>
                    <div class="flex-1 border-t-2 border-l border-base-300 h-0"></div>
                  </div>
```

Replace with:

```heex
                  <%!-- Fork connector from MRCA to branches --%>
                  <.fork_connector />
```

**Step 2: Verify compilation**

Run: `mix compile`
Expected: Compilation succeeds with no warnings.

**Step 3: Run existing tests**

Run: `mix test test/user_flows/calculating_kinship_test.exs`
Expected: All tests pass (existing tests only check for `kinship-path` test_id presence, not connector internals).

**Step 4: Commit**

```bash
git add lib/web/live/kinship_live.html.heex
git commit -m "fix: replace cluttered connectors with SVG fork in kinship tree"
```

---

### Task 4: Run precommit and verify visually

**Step 1: Run precommit**

Run: `mix precommit`
Expected: Compilation, formatting, and all tests pass.

**Step 2: Verify visually**

Start dev server: `iex -S mix phx.server`
Navigate to the kinship page, select two people with a common ancestor (e.g. first cousins). Verify:
- Down arrows between nodes are visible (gray, not invisible)
- The MRCA-to-branches connection shows a clean inverted-Y fork (no horizontal line)
- Direct-line relationships (parent-child) still show simple down arrows
