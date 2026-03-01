# MODUS UI Audit

## Priority Overview
- **P0**: Critical issues causing crashes or data loss
- **P1**: Significant functional bugs affecting user experience
- **P2**: Minor issues, visual glitches, or code quality improvements

---

## P0 Issues

### 1. Invalid Tailwind Dynamic Class Syntax
**File**: `lib/modus_web/live/universe_live.ex:4104`  
**Issue**: Toast positioning uses invalid dynamic class interpolation

```heex
<%= if @breaking_event, do: "top-28", else: "top-16" %>
```

**Problem**: This creates invalid Tailwind classes. Should use conditional class binding:
```heex
class={"fixed #{if @breaking_event, do: "top-28", else: "top-16"} left-1/2 ..."}
```

---

### 2. Potential Nil Error in Conatus Display
**File**: `lib/modus_web/live/demo_live.ex:246-247`  
**Issue**: `@avg_conatus` could be nil causing runtime error

```heex
<span class="text-emerald-400 font-bold tabular-nums"><%= Float.round(@avg_conatus * 100, 0) %>%</span>
```

**Problem**: If `@avg_conatus` is `nil`, this will crash. Should use:
```heex
<span class="text-emerald-400 font-bold tabular-nums"><%= Float.round((@avg_conatus || 0) * 100, 0) %>%</span>
```

---

## P1 Issues

### 3. Unsafe Latency Display
**File**: `lib/modus_web/live/universe_live.ex:3904-3905`  
**Issue**: Potential nil error in latency calculation

```heex
<% latency = if is_number(@llm_metrics.avg_latency_ms), do: round(@llm_metrics.avg_latency_ms), else: 0 %>
```

**Problem**: `is_number/1` doesn't exist in Elixir. Should be `is_number/1` from Kernel or use pattern matching.

---

### 4. Unsafe Population Display in Stats
**File**: `lib/modus_web/live/universe_live.ex:4365`  
**Issue**: `@obs_world.population` accessed without nil checks

```heex
<div class="text-xl font-bold text-purple-400"><%= @obs_world.population %></div>
```

**Problem**: If `obs_world` is not properly initialized or loaded, this could fail.

---

### 5. Unsafe Rules Preset Access
**File**: `lib/modus_web/live/universe_live.ex:2559`  
**Issue**: `@rules["preset"]` accessed without nil guard

```heex
<%= if @rules["preset"] && @rules["preset"] != "Custom" do %>
```

**Problem**: If `@rules` is nil, this will crash.

---

### 6. Timer Cleanup on Component Unmount
**File**: `lib/modus_web/live/demo_live.ex:92`  
**Issue**: `Process.send_after` timers not cancelled on component termination

```elixir
Process.send_after(self(), {:dismiss_toast, toast.id}, 6_000)
```

**Problem**: Timers created in LiveView handlers persist after component unmount, potentially causing memory leaks or errors when the timer fires for a non-existent component.

---

## P2 Issues

### 7. Inefficient Empty List Check
**Files**: Multiple locations (e.g., `demo_live.ex:255`, `universe_live.ex:285`)  
**Issue**: Using `@list == []` instead of pattern matching

```heex
<%= if @event_feed == [] do %>
```

**Recommendation**: More idiomatic:
```heex
<%= if @event_feed == [] do %>
```
Actually, this is acceptable in Elixir. Consider using `Enum.empty?/1` for clarity.

---

### 8. Missing aria-labels on Icon Buttons
**Files**: Throughout `universe_live.ex`  
**Issue**: Icon-only buttons lack accessibility labels

```heex
<button phx-click="toggle_god_mode" class="ctrl-btn" title="God Mode — See All Agent Internals">
```

**Problem**: `title` attribute is not reliably announced by screen readers. Should use `aria-label`.

---

### 9. Chat Input Loses Focus on Agent Update
**File**: `lib/modus_web/live/universe_live.ex:650-656`  
**Issue**: Chat modal loses input focus when agent detail updates

```elixir
def handle_event("agent_detail_update", %{"detail" => detail}, socket) do
  # Don't update selected_agent while chat modal is open — it causes form re-render and input loss
  if socket.assigns.chat_open do
    {:noreply, socket}
  else
    {:noreply, assign(socket, selected_agent: detail)}
  end
end
```

**Problem**: This is a workaround. The proper fix would involve splitting the agent detail panel from the chat modal to prevent re-renders.

---

### 10. Scrollbar Styling Missing Semicolon
**File**: `assets/css/app.css:98`  
**Issue**: Minor CSS formatting

```css
::-webkit-scrollbar-thumb { background: rgba(255, 255, 255, 0.08); border-radius: 3px; }
```

Actually valid CSS without semicolon in single-property rule.

---

### 11. Hardcoded Magic Numbers in UI
**File**: Multiple locations  
**Issue**: Magic numbers for tick intervals, timeouts

- `demo_live.ex:92`: `6_000` ms toast timeout
- `demo_live.ex:1819`: Different 6_000 ms timeout  
- `universe_live.ex:1927`: 5_000 ms timeout

**Recommendation**: Extract to constants at the top of modules.

---

### 12. Unused Template Variables
**Files**: `universe_live.ex`  
**Issue**: Some assigned variables may never be used

- `text_mode` (line 178)
- `zen_mode` (line 179)

These appear to be assigned but may not have full implementations.

---

### 13. Mobile Panel Z-Index Conflict
**File**: `universe_live.ex:3398`  
**Issue**: Mobile bottom bar uses z-30 which may conflict with modals

```heex
<div class="fixed bottom-0 inset-x-0 md:hidden bg-[#0A0A0F]/95 ... z-30">
```

**Recommendation**: Use higher z-index for mobile navigation or ensure modals have proper z-index management.

---

### 14. Deprecated or Unused Components
**File**: `command_palette.ex`  
**Issue**: Command palette is defined but may not be fully integrated

The `CommandPalette` module defines commands but there's no visible command palette UI in the templates (Cmd+K functionality not visible).

---

## Summary

| Priority | Count | Key Issues |
|----------|-------|-------------|
| P0       | 2     | Invalid Tailwind syntax, nil crashes |
| P1       | 4     | Timer leaks, unsafe access patterns |
| P2       | 8     | Accessibility, code quality |

## Recommended Fix Order
1. Fix P0 issues immediately as they cause runtime crashes
2. Address P1 issues to prevent memory leaks and improve stability
3. Plan P2 improvements for accessibility and code quality
