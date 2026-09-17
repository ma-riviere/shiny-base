# Maintainer Notes

Sandbox app to test & document patterns & best practices (and the solutions explored).

## Cross-Module Communication

Three kinds of information we could need to pass around modules:

- **State** (which dataset is selected, the current filters, ...)
- **Signals**: a signal that something happened, without data attached ("the dataset list changed")
- **Actions**: a signal with data, aimed at a target ("open the rename modal for dataset 42", "go to the explore page")

### Through the parent: arguments down, return values up

Siblings never talk directly: A returns a value to the parent, the parent passes it to B. That's the default process, which keep the modules self-contained.

Two rules:

- **Pass reactives, not values.** A plain value is frozen at call time: `home_server("home", filter = input$filter)` gives home the filter as it was when the app started, forever. Pass the reactive object itself, without parentheses (`filter = reactive(input$filter)`), and let the child call it (`filter()`) when it needs the current value.
- **Return reactives**, in a named list when there are several, for the same reason.

App example: the sidebar filters feed the home page list.

```r
# Child A (sidebar)
sidebar_server <- function(id) {
    moduleServer(id, function(input, output, session) {
        # Child server logic

        list(
            row_count_filter = reactive(input$row_count_filter),
            age_filter = reactive(input$age_filter)
        )
    })
}

# Parent (server.R)
sidebar_module <- sidebar_server("sidebar")
home_server("home", row_count_filter = sidebar_module$row_count_filter, age_filter = sidebar_module$age_filter)

# Child B (home)
filtered_datasets <- reactive({
    datasets[n_rows >= row_count_filter()[1] & n_rows <= row_count_filter()[2]]
})
```

**Notes:**

- In this app, the sidebar keeps its filters in a `reactiveValues()` and returns that. Reading a field out of that (`sidebar_module$row_count_filter`) is a reactive read, which is not allowed in the body of `server.R`, so the parent has to wrap it: `reactive(sidebar_module$row_count_filter)` before passing it. Returning `reactive()`s from the child avoids the wrapping.

**Multiple reactiveVals vs one reactiveValues (petit r)**: readability/explicitness vs less typing. Prefer reactiveVals (explicit), especially with LLMs writing the code.

- A `reactive()` cannot be written by whoever receives it. A `reactiveVal` can. To share a `reactiveVal` with a module that should only read it, pass a proxy: `reactive(selected_id())`.

**Limit:** this method of passing information quickly becomes verbose/harder to trace with more than one generation. The solution is to create a shared `reactiveVal` at the common ancestor.

### Shared state: `reactiveVal` (one per shared value, created by the common ancestor)

When several modules read AND write the same value, the best practice is to have the common ancestor create a `reactiveVal()` and hand it over to all the children that will need it. That way, every module holds the same value (reference), and changes are seen by all (any reactive that reads it will invalidate). We pass states down, instead of up and down.

App example: the selected dataset. The sidebar dropdown sets it, clicking a row on the home page sets it too, and the explore and model pages read it.

```r
# Parent (server.R)
selected_dataset_id <- reactiveVal(NULL)
sidebar_server("sidebar", selected_dataset_id = selected_dataset_id)  # read + write
home_server("home", selected_dataset_id = selected_dataset_id)        # write (row click)
explore_server("explore", selected_dataset_id = selected_dataset_id)  # read
model_server("model", selected_dataset_id = selected_dataset_id)      # read

# Home: write selected dataset on click
observeEvent(input$dataset_click, {
    selected_dataset_id(values$datasets$id[row_idx])
    # Move to the explore page
})

# Sidebar: keep the dropdown in sync
observeEvent(selected_dataset_id(), {
    updateSelectInput(session, "selected_dataset", selected = as.character(selected_dataset_id()))
})

# Explore: read to display the data
observeEvent(list(watch("refresh_datasets"), selected_dataset_id()), {
    values$dataset <- db_get_dataset(selected_dataset_id())
})
```

**Why one `reactiveVal` per value, and not one `reactiveValues()` bag holding everything** (the "stratégie du petit r" from engineering-shiny/golem): the module signature says which shared values the module touches. With a bag, every module receives everything, and finding out who writes `r$selected_id` means searching the whole app. The price is more verbose module declarations.

**Gotcha: writes are deduplicated.** Setting a `reactiveVal` (or a `reactiveValues` field) to a value identical to the current one does nothing: no dependent re-runs. That is right for state (re-selecting the selected dataset is not a change) and wrong for events: a `reactiveVal` used as "open the modal for id X" stays silent when X is asked twice in a row. Events should go through triggers or callbacks (cf. later).

### Signals: triggers

Triggers should be used for "something happened, whoever cares should react", with no data attached.

```r
# Initialize in server.R (once)
shinyutils::init("refresh_data", "show_modal_home", "show_modal_dataset")

# Fire from any module
shinyutils::trigger("show_modal_home")

# React in any module (ignoreInit = TRUE by default)
shinyutils::on("refresh_data", { data(fetch_data()) })

# Create reactive dependency
observe({ shinyutils::watch("refresh_data"); ... })
```

**How it works behind the scenes** (40 lines in `shinyutils`, based on `gargoyle`):

- `init()` creates a `reactiveVal(0L)` counter per trigger name and stores it in `session$userData`
- `trigger()` adds one to the counter
- `watch()` reads the counter inside a reactive context, which makes that context depend on it.
- `on()` is the equivalent of `observeEvent(watch("x"), { ... }, ignoreInit = TRUE)`, i.e. reacts only to this trigger, and never runs at startup.

**Rules:**

- **No payload:** The data must live somewhere every listener can read, and the sender must update it BEFORE firing. E.g. the DB (`refresh_datasets`: listeners re-query)
- **Fired twice, handled once:** Two `trigger()` calls in the same observer bump the counter by two, but the listeners run once, at the next reactive flush. It's not a queue.

**If there is only one listener, and it is the parent: return a reactive instead of using a trigger.** `profile_modal_server()` returns `updated`, a counter bumped after each successful save (`reactive(updated())`, read-only proxy of a `reactiveVal`). Same rule as triggers: the data (`session$userData$auth0_info`) is written BEFORE the bump, and the listener re-reads it.

**PS: Why not use gargoyle?**

- Minimal re-implementation: I wanted to understand the logic
- Two less deps (gargoyle & attempt)

### Actions: callbacks

An action targets something and carries data: "open the rename modal for dataset 42", "go to the explore page". We cannot use a shared `reactiveVal` here since they deduplicate (renaming dataset 42 twice in a row: the second click does nothing). Instead, we use a callback that we pass along like a `reactiveVal()`.

Two directions:

- **Parent hands its own function down.** The child asks the parent to do something only the parent can do. Navigation: the navbar belongs to the top level, so the parent passes `nav_select_callback = \(page) nav_select("nav", page)` and a child calls `nav_select_callback("explore")`.
- **A module returns a function, the parent relays it to siblings.** The rename modal has its own module. It returns `open(dataset_id, dataset_name)`, and the parent passes it to the home & explore pages as `edit_dataset_callback`.
- **A module returns a function, the parent calls it itself.** The profile modal is only opened from the navbar's user menu, so it is the navbar's child: `navbar_server()` creates `profile_modal_server("profile")` and calls `profile_modal_module$open()` in its click observer. Nothing goes through `server.R`, and no trigger is needed.

**Rule for modals:** opened from one module, the modal is that module's child (profile). Opened from several, it is a sibling of the callers and the parent relays its `open()` (rename modal, opened from Home and Explore). Nesting costs a longer namespace (`navbar-profile-*` in the bookmark exclusions) and a move up one level if a second opener ever appears.

```r
# Owner (edit_dataset module): return the function
edit_dataset_modal_server <- function(id) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns
        values <- reactiveValues(pending_rename_id = NULL)

        open <- function(dataset_id, dataset_name) {
            values$pending_rename_id <- dataset_id
            showModal(edit_dataset_modal_ui(ns, current_name = dataset_name))
        }

        # Whoever calls the edit modal, the confirm_rename button will trigger this observer
        observeEvent(input$confirm_rename, {
            db_update_dataset_name(values$pending_rename_id, input$new_dataset_name)
            removeModal()
            trigger("refresh_datasets")
        })

        list(open = open)
    })
}

# Parent (server.R)
edit_dataset_modal_module <- edit_dataset_modal_server("edit_dataset")
home_server("home", edit_dataset_callback = edit_dataset_modal_module$open)
explore_server("explore", edit_dataset_callback = edit_dataset_modal_module$open)

# Caller (home): an action with a payload
observeEvent(input$edit, {
    edit_dataset_callback(dataset$id, dataset$name)
})
```

**The callback keeps its owner's `session` and `ns`** (it's a closure). The modal's inputs are namespaced by `edit_dataset` and land in that module's `input`, wherever the call came from. The caller never needs to know how the modal is built.

**Gotcha:** Reactive reads inside the callback belong to the caller. If called from an `observe()`, every reactive the callback reads becomes a dependency of that observer: a callback reading `values$n` makes the calling `observe()` re-run on every change of `n`, in another module, with no visible link. Call callbacks from `observeEvent()` handlers, or wrap reads inside the callback in `isolate()`.

### `session$userData`: the session-wide bag

Visible session-wide. Useful for user-wide settings & session facts, e.g. `auth0_info` (login claims).

Very tempting to use to simplify cross-module communication, but defeats encapsulation, and is worse than "petit r" for explicited-ness (module signature doesn't show what's being used). Anything a module changes at runtime is state and should go through a `reactiveVal` argument.

**Gotcha:** never use `purrr::pluck(session, "userData", ...)` inside a module. The module's session is a proxy (a classed environment) whose `$` method forwards userData to the real session. `pluck()` bypasses `$` and reads the environment directly, so it finds nothing and returns NULL. Always use `session$userData$....`

> TODO: engineering-shiny "R6 + triggers" pattern -> what's the use case?

## Dynamically generated/destroyed elements

When dynamically (re)generating UI elements (and associated servers), one has to be careful about managing observers and reactive elements. Some of the old observers are automatically suspended (e.g. the `render*()`), but others will stay active if not destroyed.

If not handled properly, at minimum it causes a **memory leak** by accumulating observers. At worst, zombie observers keep re-running, or get **duplicated**: if the module IDs are tied to the content (content-derived namespace), re-creating an element after deletion creates a second server on the same inputs, and both fire on every event (**multiple handlers firing**).

What happens to each kind of reactive when the UI element of its module disappears:

- Observers on the module's own inputs die. Nothing can set those inputs anymore, so they never fire again. They only pollute memory.
- Outputs are suspended. The client reports the missing element as hidden, and Shiny stops re-rendering it.
- Observers on reactives from outside the module (parent reactives, `invalidateLater()`, ...) stay alive, re-running on every change for the rest of the session.

Basic example/setup:

**Child module:**

```r
item_ui <- function(id, label) {
    ns <- NS(id)
    div(
        id = ns("wrapper"),
        span(label),
        numericInput(ns("qty"), "Quantity", 1),
        textOutput(ns("unit_label")),
        actionButton(ns("remove"), "x") # Button for the child to remove itself
    )
}

item_server <- function(id, label, unit) {
    moduleServer(id, function(input, output, session) {
        # Own input: dead once the element is gone (nothing can set input$remove anymore)
        observeEvent(input$remove, removeUI(paste0("#", session$ns("wrapper"))))

        # Output: suspended once the element is gone (the client reports it as hidden)
        output$unit_label <- renderText(unit())

        # Observer on a parent reactive: keeps re-running after removal, for the whole session
        observeEvent(unit(), {
            message(label, ": unit is now ", unit())  # Still printed for removed items
            updateNumericInput(session, "qty", label = paste0("Quantity (", unit(), ")"))
        })
    })
}
```

**Parent module (server only):**

```r
ns <- session$ns
unit <- reactive(input$unit)  # E.g. selectInput("unit", choices = c("kg", "lb"))

observeEvent(input$add, {
    id <- paste0("item_", input$add)  # actionButton: value starts at 0 and increments on every click
    label <- input$new_label

    insertUI(paste0("#", ns("container")), "beforeEnd", item_ui(ns(id), label))
    item_server(id, label, unit)
})
```

There are multiple solutions based on the expected/desired lifetime of the per-element server:

### No per-element server: one observer for all children (ID-passing)

The cleanest solution is to completely bypass the problem by **NOT** generating one server module per element, and instead only creating one observer/input per action, shared by all children. It is, however, the least Shiny-idiomatic solution, requiring custom JS code.

Here, elements/children are plain HTML rendered from the data. Their controls/actions write the element ID into ONE shared input, through a `Shiny.setInputValue()` call. Standard Shiny inputs cannot do this (one element = one input id), hence the JS. For this, we use a custom HTML `<button>` whose data attributes mirror the `Shiny.setInputValue()` call:

- `data-shiny-input` (which input to set, the same shared input on every child),
- `data-shiny-value` (the value to send, here the element id),
- `data-shiny-priority` (only set to `event` for repeatable actions).

One delegated listener in a static JS file reads them.

**Element helper:**

```r
# UI helper: htmltools escapes every attribute, so ids/values/titles coming from the data are injection-safe
input_button <- function(input_id, value, ..., event = FALSE, class = NULL, title = NULL) {
    tags$button(
        type = "button", class = class, title = title, `aria-label` = title,
        # Which input to set. Shared by all the children, e.g. item_delete for every delete button
        # (namespaced: home-item_delete). Read by this.dataset.shinyInput
        `data-shiny-input` = input_id,
        # The value the input is set to (as a string): the id of the element the action targets,
        # or of the selected element. Read by this.dataset.shinyValue
        `data-shiny-value` = as.character(value),
        # Flavour. "event" = repeatable action (fires on every click, even twice on the same element).
        # Absent = stable selection (deduplicated, bookmarkable). Read by this.dataset.shinyPriority
        `data-shiny-priority` = if (isTRUE(event)) "event",
        # Button content (icon, label, ...)
        ...
    )
}
```

**Parent module (server):**

```r
# Generating the children UI: plain HTML rendered from the data
output$list <- renderUI({
    purrr::pmap(items(), \(id, name, ...) {
        div(
            span(name),
            input_button(ns("item_delete"), id, icon("trash"), event = TRUE, title = "Delete")
        )
    }) |> tagList()
})

# Server: ONE observer per action type, shared by all elements
observeEvent(input$item_delete, {
    item_idx <- match(as.character(input$item_delete), as.character(items()$id))
    req(!is.na(item_idx))  # Never trust a client-supplied ID
    item_id <- items()$id[item_idx]  # Use the typed id from our own data, not the client string

    # Removal logic goes here (delete item_id from the DB, ...), then refresh (e.g. with a trigger)
})
```

**JS (e.g. `www/js/app.js`):**

```js
// One app-wide listener for every button[data-shiny-input], never removed
$(document).on("click", "button[data-shiny-input]", function () {
    var options = this.dataset.shinyPriority ? { priority: this.dataset.shinyPriority } : undefined;
    Shiny.setInputValue(this.dataset.shinyInput, this.dataset.shinyValue, options);
});
```

Two flavours of button: an _action_ (delete, edit) is sent with `priority: "event"` (R: `event = TRUE`), so it fires on every click, even twice on the same element, and is excluded from bookmarks. A _selection_ (e.g. click on a row/element to show more about it) is a stable value: it deduplicates repeats and is saved/restored by bookmarking like any other input.

PS: the custom JS is only needed for _actions_. A _selection_ is a state (which element is selected), and a native single input can hold it: `radioButtons()` or `selectInput()` with the element IDs as choices, styled as a list. An action (delete, edit) is an event plus an ID (what to do, to whom), and no native Shiny input emits that.

PPS: Why real buttons and data attributes instead of inline `onclick` strings (the classic "buttons in a DT table" idiom): keyboard support (Enter/Space) and screen-reader semantics for free, htmltools escapes attribute values (a malicious dataset name cannot break out of the markup, whereas an `onclick` string leaves the escaping to you), and one delegated listener survives every re-render.

**Exception: per-element download buttons:**

A download is the one action that cannot rely solely on the shared input. `downloadHandler()` binds to a real `<a>` link whose `href` Shiny fills with a session URL, and the browser has to navigate to that URL: there is no `Shiny.setInputValue()` equivalent for "download element N". One link per element would mean one handler per element, i.e. per-element server logic again. So the ID still travels through the shared input, and ONE hidden link per page does the actual download.

**UI (once per page):**

```r
shinyjs::hidden(downloadLink(ns("download_file"), label = NULL))
```

**Element (in the pmap above):**

```r
input_button(ns("item_download"), id, icon("download"), event = TRUE, title = "Download")
```

**Parent module (server):**

```r
values <- reactiveValues(download_id = NULL)

# Shared download action: store the target id, then click the real link
observeEvent(input$item_download, {
    item_idx <- match(as.character(input$item_download), as.character(items()$id))
    req(!is.na(item_idx))
    values$download_id <- items()$id[item_idx]
    # Native click: shinyjs::click() is a jQuery-triggered click, which fires the handlers
    # but NOT the anchor's default navigation, so no download starts
    shinyjs::runjs(sprintf("document.getElementById('%s').click();", ns("download_file")))
})

output$download_file <- downloadHandler(
    filename = \() paste0("item_", values$download_id, ".csv"),
    content = \(file) {
        req(values$download_id)
        write.csv(db_get_item(values$download_id), file, row.names = FALSE)
    }
)
# The link is display:none, so Shiny would suspend the output and never populate its href:
# clicking it would then do nothing, silently
outputOptions(output, "download_file", suspendWhenHidden = FALSE)
```

Limit: `values$download_id` is a single slot shared by all elements. Two clicks on different elements in quick succession can serve the second element's file to the first click. The heavier fix, if it ever matters, is a per-element URL from `session$registerDataObj()`, which turns each download button into a plain link.

**Limit: no per-element reactivity (children are stateless):**

With ID-passing, a child is a pure function of the parent's data: its HTML is rebuilt from the data on every change, and its only live parts are buttons that send an ID to the parent. Nothing reactive lives at the child level. A child-rendering function (like `dataset_row_ui()`) is fine, but it is not a module: it receives the child's data and the namespace of the shared handler (to point its buttons at the shared inputs), not a namespace of its own, since there is nothing per child to namespace.

The shared-input trick covers clicks only: a value input inside a child (a per-child text or numeric field) is one element = one input id, an output inside a child needs its own render function, and an async task needs a place to live. The moment a child needs any of those, it needs a server of its own.

In that case, use one of the two next solutions.

### Server dies with its element: `session$destroy()`

Solution to use when the lifetime of the child server is tied to the lifetime of its UI element: whoever removes the UI also destroys the module's server.

Before Shiny 1.14.0, this was usually done with the child module defining a custom `on_destroy` method (calling `$destroy()` all the child's named observers), and either calling it itself before `removeUI()`, or passing it back to its parent when the parent contols the removal of the children.

Since Shiny 1.14.0, `session$destroy()` does this natively: every observer, reactive, `reactiveVal()`/`reactiveValues()`, output, and nested child module registers an `onDestroy()` callback with its scope on creation, and `session$destroy()` invokes them all, then drops the input values stored under the namespace. It can be called either from within the child, or by the parent, passing the child id.

**Child-driven removal** (the element has its own remove button):

```r
observeEvent(input$remove, {
    removeUI(paste0("#", session$ns("wrapper")))
    session$destroy()
})
```

**Parent-driven removal** (the parent deletes an element, or reacts to the data): `session$destroy()` takes an optional module ID, the same id passed to `item_server()`, so the parent can invoke it directly, without requiring the child to define and return a custom destroy function.

```r
# Parent server
observeEvent(input$delete, {
    id <- paste0("item_", input$delete)
    removeUI(paste0("#", ns(id), "-wrapper"))
    session$destroy(id)
})
```

Notes:

- `session$destroy()` does not touch the UI: it needs to be used with `removeUI()`.
- Re-creating a module with the same id afterwards is safe: the old scope is gone, so no risk of multiple events firing from orphaned observers.

**Gotcha: reactives returned by a destroyed child.**

If a child returns a reactive() and the parent uses it in its own reactives, observers, or outputs, that reactive is destroyed with the child. Destroying a reactive invalidates everything that depends on it, right away, so the parent re-runs, calls the dead reactive, and gets "Can't access reactive; its module session has been destroyed". In an output the error is displayed; in an observer it ends the session.

In that situation, have the parent handle the `session$destroy(id)`, so that it drops its reference to that child's reactive in the same step. If the remove button is on the child, it should ask for its removal through a callback passed at creation (same style as `nav_select_callback`) or an ID-passing input.

**Note on IDs/namespeces for dynamic children**: use the content id as the module id whenever there is one (e.g. `item_<db_id>`). Since the scope dies with the element, there is no risk of collision, meaning we don't need a unique ID by element. A content-derived id has two advantages:

- Deterministic: the same data always yields the same module ids, so the parent can address a child from the data alone (`session$destroy(paste0("item_", id))`), with no registry of live children to maintain.
- Bookmark-friendly: a bookmark saves every input by its full id (`home-item_42-qty = 3`). On restore, Shiny loads that table for the session, and every input constructor (`numericInput()`, ...) looks its own id up in it when it is built, whether in the static UI or in a `renderUI()`/`insertUI()` later in the session. So the children need no restore code: the parent rebuilds them as usual from its data (`items()`, derived from persisted rows and the restored filter inputs), `item_ui(ns("item_42"))` builds `numericInput(ns("qty"))` again, and that constructor finds `home-item_42-qty` in the table and starts at 3 instead of its default. The only condition is that the child gets the same id as when the bookmark was saved.

Free-form elements with no identity (an "add a row" button) need a per-session counter for their ids: the `actionButton` click count works (it is bookmarked too, so ids created after a restore continue after the restored ones), or a UUID when several places can create elements. These ids cannot be rebuilt from any data, so bookmarking such a list means saving the live ids yourself (`onBookmark(function(state) state$values$item_ids <- ...)`) and re-creating the children from that list in `onRestore()`. Their inner inputs then restore on their own, as above.

### Server lives for the session: initialize once, gate while hidden

Solution for a low/fixed volume of elements (e.g. a dataset where each item is displayed with its own server) that are dynamically shown/hidden by the data (filter, tab, collapse). The servers are created once and never destroyed: when an element comes back, nothing is re-created, its server-side state is still there, and it simply resumes. The cost is memory: it grows with the number of distinct ids seen during the session.

App example: the Explore data preview. Each row is a module (`221_preview_row`). The parent (`220_data_preview`) creates one server per row the first time the sidebar's range slider brings it into view, and keeps it while the dataset stays selected (on a dataset switch it destroys them all, cf. previous section). A row's checkbox survives leaving and re-entering the range. Only the first 100 rows can be previewed: the pattern's cost is one server per distinct row ever shown, so the population has to be bounded.

The approach separates server initialization (once per unique ID, independently of rendering) from UI rendering (creation and deletion). The server never disappears, and thus is never duplicated. **Gating** is what makes the kept servers harmless while their UI is gone: the parent's data says which elements are shown, and the child's observers exit early (`req()`) while their id is not in it.

We only need to gate what depends on reactives defined outside of the module's scope. Own-input observers are Idle while hidden (resuming when the element is back), and outputs are suspended by Shiny. For the rest, what needs a gate depends on who triggers the work:

- Pull (lazy): a `reactive()` computes nothing by itself. It runs only when something downstream asks for its value, usually the child's outputs. While the element is hidden its outputs are suspended, nobody asks, and the reactive never runs. A `req(visible())` inside it is a safety net for the case where another consumer still pulls it (e.g. the parent), not the gate.
- Push (eager): an `observe()` runs on its own every time one of the reactives it reads changes, and it does side effects (`update*()`, messages, DB writes). Hiding the element does not stop it, so it has to be told: `req(visible())` as its first line makes it exit early while the element is hidden. And since an `observe()` depends on everything it reads, `visible()` included, it re-runs when the element comes back and applies the update it skipped in the meantime.

PS: this is why the gate lives in an `observe()` and not in an `observeEvent(unit(), ...)`. An `observeEvent()` re-runs on its event only: its handler is isolated, so a `req(visible())` inside it does not make it re-run when the element comes back, and the element shows a stale label until the next `unit()` change.

**Child module:**

```r
item_ui <- function(id) {
    ns <- NS(id)
    div(textOutput(ns("name")), numericInput(ns("qty"), "Quantity", 1))
}

item_server <- function(id, item_id, items, unit) {
    moduleServer(id, function(input, output, session) {
        visible <- reactive(item_id %in% items()$id)

        # Pull side: the output is suspended by Shiny while hidden, so item_data() is not pulled. The req() is a guard.
        item_data <- reactive({
            req(visible())
            items()[items()$id == item_id, ]
        })
        output$name <- renderText(item_data()$name)

        # Push side: observe() + req(). Exits early while hidden, re-runs when the element comes back
        observe({
            req(visible())
            updateNumericInput(session, "qty", label = paste0("Quantity (", unit(), ")"))
        })
    })
}
```

**Parent module (server only), fixed set of ids known at start:**

```r
ns <- session$ns
unit <- reactive(input$unit)
items <- reactive(all_items[all_items$category == input$category, ])  # Filtered: elements come and go

# Initialize once: exactly one server per element, namespace = content id
lapply(all_items$id, \(item_id) item_server(paste0("item_", item_id), item_id, items, unit))

# Render many: the UI is rebuilt from the data on every change, the servers are untouched
output$list <- renderUI(lapply(items()$id, \(item_id) item_ui(ns(paste0("item_", item_id)))) |> tagList())
```

**Parent module (server only), growing set of ids (elements appearing over time, e.g. from the DB):**

```r
loaded_ids <- reactiveVal(integer(0))

observeEvent(items(), {
    new_ids <- setdiff(items()$id, loaded_ids())
    lapply(new_ids, \(item_id) item_server(paste0("item_", item_id), item_id, items, unit))
    loaded_ids(union(loaded_ids(), new_ids))
})
```

PS: `lapply`, not a `for` loop. In a `for` loop, every argument the module only touches later (inside a reactive or an observer) is a promise that reads the loop variable when it finally runs, so every module sees the last value. `lapply` gives each iteration its own environment.

**Gotcha: the browser inputs are rebuilt, and a rebuilt input sends its constructor value.** The server survives, the DOM does not: `renderUI()` builds `item_ui()` again every time the element comes back, and the new `numericInput(ns("qty"), "Quantity", 1)` sends `1`, overwriting the quantity the user had typed (verified: set to 5, hidden, shown again, back to 1). What survives is the server side: `input$qty` keeps the typed value while the element is gone (only `session$destroy()` drops a module's inputs), as does any `reactiveVal`. So the element has to be rebuilt FROM that retained value. Two ways:

- The child renders its own inputs in an output, seeded from the retained value. This is what the preview rows do: the row's output builds the whole `<tr>`, checkbox included, with `checkboxInput(ns("selected"), value = isTRUE(isolate(input$selected)))`. `isolate()`, so that a click does not re-render the row.
- The parent passes the retained value to the UI function (`item_ui(ns(id), qty = isolate(qty()))`, from a reactive the child returned).

The same applies to state held in a `reactiveVal` and shown through an input: the input is rebuilt with its constructor value, only an output rebuilds from the state.

## Auth

The app delegates login to **Auth0** (a hosted identity provider): the app never sees a password. Auth0 authenticates the user (email/password, Google, ...) and sends back a signed ID token that says who the user is. Everything else (what the user may do, their data) is the app's business.

**Auth0 with a custom R package**

### Why Auth0

Three families of solutions exist for Shiny:

- **Hosting-level auth** (Posit Connect, ShinyProxy, reverse proxy with forward-auth): nothing to do in the app, but needs a platform or extra infra.
- **In-app local users** (`shinymanager`, `shinyauthr`, `polished`, ...): you store the passwords and handle resets, sessions, MFA yourself. Recommended for internal tools only.
- **Delegated login (OAuth/OIDC)**: the provider does the hard part, the app never sees a password. Costs a redirect round-trip that Shiny does not natively support (cf. "How a login works").

**Auth0:** simple to configure, everything included (hosted login page, social logins, MFA, email verification, user metadata, roles, Actions), free up to 25,000 monthly active users.

### Why a custom package (`ma-riviere/auth0r`)

`curso-r/auth0` exists (and was the starting point), but:

- **Bookmarks break**: it keeps extra URL parameters (like `_state_id_`) by appending them to the callback URL it sends to Auth0. Auth0 only accepts callback URLs that exactly match the registered ones, so a bookmarked link cannot go through a login. `auth0r` carries the bookmark id inside the login transaction instead, and the callback URL stays clean (cf. "Bookmarking with Auth0").
- **Weak security**: one `state` string generated at app start and shared by every login (so it is not a CSRF token), no PKCE, no nonce, no ID-token validation (it only calls `/userinfo` with the access token), and the app's server function runs even when no login happened (it just finds an empty `auth0_info`). `auth0r` validates the ID token (signature, issuer, audience, expiry, nonce) before the server logic runs, and denies by default.
- **Same package for Shiny and plumber2**: `auth0r` also verifies API access tokens (JWT) for plumber2 apps with a common interface, plus a partial Management API client (used by the admin panel and the ban toggle).

Private because it's messy, big chunks of AI code, I can make breaking changes, and I am no security expert.

### How a login works

Shiny poses two major constraints that shape the login flow:

- **R cannot redirect the browser from the server function.** A real HTTP redirect is a response to the page request, and only the UI (top level) produces that response, so the login logic must wrap around the UI. The server function runs over the websocket, where there is no HTTP response to send.
- **Shiny Server strips cookies from the websocket.** The server function never sees the login cookie, so anything that needs it must happen on the UI side.

PS: In local dev (`runApp()`) the cookies DO reach the server function, so a version that reads them there works locally and only breaks on Shiny Server.

**The flow:**

1. **Outbound**: `auth0r::auth0_ui()` creates a login transaction (random id, nonce, PKCE verifier, pending bookmark id), stores it in an encrypted httpOnly cookie (`auth0_state`), and redirects to Auth0 with the transaction id as `state`.
2. **Callback**: Auth0 comes back with `?code=...&state=...`. Still on the UI side, the wrapper matches the state against the cookie, exchanges the code for tokens (server to server), validates the ID token, and fetches the profile (`/userinfo`).
3. **Handoff:** Auth0 brought the browser to a URL it chose (`?code=...&state=...`), which is not the URL the app should be served at: it lacks the bookmark id and it carries a single-use code. So the wrapper keeps the validated login in R memory (two minutes) and redirects once more to a clean URL, `/?_login_id_=<one-time id>`, plus `&_state_id_=<bookmark>` if one was pending.
4. **Session start**: `auth0r::auth0_server()` consumes the login id (single use, bound to the browser by a cookie marker), fills `session$userData$auth0_claims` (validated claims), `auth0_info` (profile) and `auth0_credentials` (tokens), then calls the app's server function. Without a validated login the app server never runs: the browser gets an inert "Access denied" page (default-deny).
5. **URL cleanup**: once Shiny is connected, JS removes `code`, `state`, `_login_id_`, `_state_id_` from the address bar.

```r
# global.R
auth0_config <- auth0r::auth0_settings()

# ui.R
auth0r::auth0_ui_with_cookies(ui, info = auth0_config)

# server.R
authorize_callback <- function(claims, userinfo) {
    if (isTRUE(claims$email_verified %||% userinfo$email_verified)) return(TRUE)
    auth0r::auth0_authorization_result(FALSE, "Please verify your email address, then reload this page.")
}

auth0r::auth0_server(server, info = auth0_config, authorize = authorize_callback)
```

PS: `claims` are the ID-token fields (sub, email, email_verified, roles, ...), trusted because auth0r verified the token's signature, issuer, audience, expiry and nonce. authorize returns TRUE, or auth0_authorization_result(FALSE, "message") to put a custom message on the denial page (a bare FALSE shows a generic one).

The user is ID-ed by `session$userData$auth0_info$sub` (stable Auth0 id, e.g. `google-oauth2|123`), which is the key for `db_get_or_create_user()`.

**Notes:**

- Callback, handoff and websocket must hit the same process (the login lives in memory). Hence ONE container. Replicas would need sticky sessions.
- Production env needs `AUTH0_COOKIE_KEY` (32 random bytes, hex; makes the login process restart-resilient) and `AUTH0_APP_URL` (the exact callback/logout URL registered in Auth0).
- We cannot use the `cookies` package: it wraps UI responses in a `tagList()`, which destroys the redirect responses. Use `auth0r::auth0_ui_with_cookies()`.
- The login is server-side state, not a browser cookie, so Playwright's storage state cannot keep a session logged in. E2E tests need to log in once per describe block, on a shared page.

### Logout

`auth0r::logout_button()` is a plain `actionButton` with the reserved, non-namespaced id `._auth0logout_`, watched by the server wrapper at the top level (so any module can host it). The wrapper builds Auth0's `/oidc/logout` URL (`post_logout_redirect_uri` = `AUTH0_APP_URL`, which must be in "Allowed Logout URLs", and `id_token_hint` so Auth0 skips its confirmation page) and sends it to the browser, which navigates there (`location.replace`, so Back does not return to the dead session). Auth0 ends its session and sends the user back to the app, where a fresh login starts, this time with the login form (no SSO session left). Leaving the page also fires `onSessionEnded()`: the DB session is closed and the disconnect bookmark saved.

### Roles and permissions (RBAC)

Auth0 defines and assigns roles per user, the app (`data/permissions.yaml`) defines what each role can do.

**Auth0 side**: roles are created and assigned in the dashboard. Auth0 does not put them in the ID token by default: a post-login Action is needed to copy them into a custom claim.

```javascript
exports.onExecutePostLogin = async (event, api) => {
    if (event.authorization) {
        api.idToken.setCustomClaim("https://shiny-base.ma-riviere.com/roles", event.authorization.roles);
    }
};
```

PS: define/add the deploy actions (Actions > Library > Build custom), then drag it into the Login flow (Actions > Flows > Login)

**App side**: `data/permissions.yaml` maps roles to free-form `verb:object` permissions. `*` is a wildcard, `!` a denial (wins over wildcards).

```yaml
roles:
    admin: "*"
    dev: ["view:*", "!view:admin:auth0", "write:dataset"]
    user: ["view:home", "write:dataset"]
```

`shinyutils::can(<permission>)` reads the roles from the session claims, and asserts if the user has this permission.

```r
# UI
if (can("delete:dataset")) actionButton(ns("delete"), "Delete")

# Server
observeEvent(input$delete, {
    req(can("delete:dataset"))
    db_delete_dataset(id)
})
```

**Notes:**

- The default role is `user`.
- If `permissions.yaml` is missing, `can()` returns TRUE for everything, with a warning in the logs.
- If someone logs in with an unknown role, it will not match any known role from `permissions.yaml`, and `can()` will deny everything.
- Use `if (!can("view:admin")) return()` at the top of a module server to gate the entire module, no `req()` (not a reactive context).
- Roles are only updated on login, since they reach the app through the ID token.
- The UI is built before the app knows who the user is, so we cannot gate UI rendering. Render it for everyone and hide/show it from the server based on the roles. Furthermore, we need the UI element present for bookmarks to apply.

### Development bypass (no Auth0)

`AUTH0_DISABLE=true` (env, read by `auth0r::auth0_disabled()`) removes both wrappers. Each session gets a guest user (`guest_<hash>` sub, `is_guest = true`, wiped at the next app start) with the roles from `DEV_ROLES` (comma-separated, default `user`). CI runs shinytest2 and Playwright in this mode. `global.R` refuses to start with the bypass and `ENV=prod`.

### Banning a user

The admin panel's Users tab has a ban toggle per user card (needs `manage:admin:users`). A ban writes `status = 'banned'` in the users table FIRST, then asks Auth0 to block the account. The Auth0 block refuses every new token (login, silent SSO, refresh); the "revoke sessions/refresh tokens" endpoints are not called (unavailable on the free tier). The Shiny app checks `users.status` at login and in the 5-minute heartbeat: if banned, it closes the current session (toast, then `session$close()`).

### Bookmarking with Auth0

We use server-side bookmarking (`enableBookmarking(store = "server")`). The state is a folder `shiny_bookmarks/<state_id>/input.rds`, the URL carries its ID (`?_state_id_=<id>`). `shinyutils::use_bookmark_dir()` (global.R) makes Shiny read and write that layout everywhere: Shiny Server would otherwise nest states under `<bookmark_state_dir>/<user>/<app>-<hash>/`, where the cleanup never looks (its orphan sweep even deleted Shiny Server's folder, with every button-saved bookmark in it). Closing the tab saves the state the same way a click on the bookmark button does (`isolate(session$doBookmark())` in `onSessionEnded()`), and the DB row for the "Welcome back" offer is written once the state is on disk (`onBookmarked()`).

**Why not URL bookmarking:** Auth0 will not preserve the app's query string, so whatever must survive the login round-trip has to be stashed in the login cookie and re-appended on the handoff redirect. That cookie is capped at 4KB, which makes it incompatible with storing complex app state. Furthermore, saving the current state on disconnect and offering to restore it when the user logs back in requires server-side persistence.

## Dataset assistant

Uses `shinychat` and `ellmer`. The model is a small local model running on the deploy-main box, so the data never leaves our server. It can also connect to models from OpenRouter and NVidia NIM.

**The harness:** the model gets a description of the dataset (name, size, column names and types) and one tool, `query`, which runs a SQL `SELECT` over the data. We treat the SQl query as hostile: each query runs in a separate R worker with a 20 second limit, against a throwaway in-memory copy of the data, with DuckDB's file and extension access switched off and its settings locked. Only one `SELECT` per call is accepted, and results are cut at 200 rows. The tests in `tests/testthat/test-dataset-chat-query.R` try the usual escape routes (reading `/etc/passwd`, copying to a file, chaining statements) and expect them to fail.

**Notes:**

- Conversations are not saved. Switching dataset or pressing "New chat" starts over.
- The feature is off unless `CHAT_ENABLED=true`, and only roles with the `chat:dataset` permission see it.

## Optimization

Shiny Server runs **ONE** R process for the app, shared by every connected user. R does one thing at a time, meaning everybody waits for each other's tasks. So, we need to avoid doing work nobody will see, and avoid doing long work in that one process (use subprocesses/mirai instead).

### Don't compute what nobody is looking at

**Hide unused outputs:** use tabs or hide panels the user is not viewing, so Shiny stops updating their tables/plots (`suspendWhenHidden = TRUE`, default). Reactives are lazy: they recompute only when something reads them after a dependency changes. If only hidden outputs use a reactive, it can stay unevaluated. When an output becomes visible again, Shiny updates it if needed.

**Choose how to show/hide panels:** tabs already hide inactive pages. For other elements, use `conditionalPanel()` when visibility depends on browser inputs, e.g. sidebar controls shown only when `input.nav === 'model'`. The browser handles the change without asking R. Inside a module, pass `ns = ns` when the condition refers to that module's inputs.
Our loading overlay covers the initial display before Shiny's JavaScript applies the condition.

```r
conditionalPanel(
    condition = "input.nav === 'dataset' || input.nav === 'model'",
    ns = ns,
    # ...
)
```

Use `shinyjs::show/hide/toggle()` when visibility depends on information in R, such as permissions or loaded data.

**Skip background work on inactive pages:** hiding outputs does not stop separate observers. E.g., before an expensive DB query or saved-model load, check the active tab with `req(identical(active_page(), "model"))`.

**Exception:** some outputs must work while hidden. E.g. the shared download link uses `outputOptions(..., suspendWhenHidden = FALSE)` so Shiny generates its download URL.

### Lazy module loading

If a module is heavy and not always used, create its server on the first visit, not at startup (the UI should always be generated, for bookmarks and navigation).

Example in this app: `shinyutils::admin_server()`: server created on the first visit of the Admin tab, and its reactives/polling are gated on it being the active tab.

```r
# In the parent module
module_server <- function(id, active_page) {
    moduleServer(id, function(input, output, session) {
        initialized <- reactiveVal(FALSE)

        observe(label = "module_init", {
            req(!initialized())
            req(active_page() == "target_page")

            # Sub-modules instantiated only on first visit
            child_server("child", ...)

            initialized(TRUE)
        }) |> bindEvent(active_page(), ignoreInit = TRUE)
    })
}
```

**Warning: do not use `once = TRUE`:** it destroys the observer after the FIRST run even when `req()` aborts the body (the destroy is an `on.exit`).

**Bookmarking:** inputs of a late/lazy module still restore (their UI existed from the start), but an `onRestore()` inside it never runs. Restore custom state from the parent, if needed.

### Don't block the process: async

Use `ExtendedTask` + `mirai` to run long/blocking tasks in a worker process and returns a reactive result.

```r
fit_task <- ExtendedTask$new(\(data, formula) mirai::mirai(lm(formula, data = data), data = data, formula = formula))

observeEvent(input$fit, fit_task$invoke(values$data, formula))

observeEvent(fit_task$result(), { ... })
```

### Don't recompute what you already know

**Check for changes before fetching everything:** the admin Users tab uses `reactivePoll()` to query a small DB summary (a "fingerprint"). It refreshes the full data only when that summary changes. DB polling is skipped while the relevant view is hidden; admin actions also force a refresh so edits appear immediately. This avoids fetching the full list on every timer tick.

**Reuse repeated API results:** `memoise` caches Auth0 user/role lookups for five minutes. Repeated calls with the same arguments reuse the result. When the app changes a role or bans a user, it clears the relevant cached result so the next lookup sees the change.

**Cache expensive calculations when inputs repeat:** ordinary reactives retain their latest result; `bindCache()` can also reuse earlier results, e.g. when switching from settings A to B and back to A. Its cache key must describe everything that affects the result, including changes to the underlying data. Use `cache = "session"` for user-specific results; the default cache is shared across sessions. Not currently used here. See [Shiny's caching reference](https://shiny.posit.co/r/reference/shiny/latest/bindcache.html).

> TODO: `cache_dir` is set and cleared on stop but nothing uses `cache_memory()`/`cache_disk()`. Use it?

**Wait before processing rapid input changes:** if an expensive calculation runs on every edit, use `debounce()` to wait for a pause, or `throttle()` to update at intervals. Apply it to the cheap input reactive, before the expensive calculation. These server-side functions reduce downstream work, not messages from the browser, and are not an abuse-prevention rate limit. See [Shiny's debounce/throttle reference](https://shiny.posit.co/r/reference/shiny/latest/debounce.html).

**Let browsers reuse unchanged files:** caching CSS/JS avoids downloading the same content on each visit. Currently, `ui.R` adds `?v=<timestamp>` to the URLs for `main.min.css` and `app.js` to avoid stale versions. The timestamp changes when the page is generated, so the browser sees a new URL even if the file is unchanged. This is useful for development, but the opposite for prod.

> TODO: replace the timestamp with a file-content hash in prod. The URL would change only when the file changes, so unchanged files can stay cached.

## Front-end

`bslib` components plus one SCSS bundle compiled at startup, and a few dozen lines of JS.

### CSS/SASS

`www/sass/main.scss` imports partials: `_variables` (palette, spacing, radii, shadows, fonts), `_typo`, `_layout`, one partial per component (`_navbar`, `_sidebar`, `_buttons`, `_cards`, `_navs`, `_tables`, `_modals`, `_model_picker`, `_chat`), `_utils`.
`shinyutils::compile_sass()` in `global.R` compiles it to a minified `www/css/main.min.css` on start.

> TODO: make Bootstrap the single source: `bs_theme(primary = "#2563eb", ...)` and attach the partials with `bs_add_rules(sass_file(...))` instead of compiling them apart (they then see `$primary` and Bootstrap's mixins, bslib compiles and caches). Or a `_brand.yml`, auto-discovered by `bs_theme()`.

### JavaScript

Static files only (CSP-friendly, htmltools escapes attributes):

- `www/js/app.js` holds the delegated click handler behind `input_button()` (cf. Dynamic content)
- `shinyutils::use_js_helpers()` adds `scrollToBottom()` and Enter-submits-modal

In addition: `shinyjs`, `waiter`, `shiny.i18n`, `cookies` (js-cookie served locally, cf. Security).

`use_hex_loader()` shows a `waiter` overlay until auth is done, modules are created and the bookmark is restored (`is_restore_ready()`). It hides the half-built UI and the conditionalPanel flash.

### i18n

`shiny.i18n`:

- Client side: static text is wrapped in `<span class="i18n" data-key>`, `usei18n()` ships the dictionary, `update_lang()` swaps texts in the browser without re-render.
- Server-produced text (`renderUI`, toasts) uses `tr()` at render time.
  Language taken from Auth0 metadata, then cookie, then browser, then `en` (default).

**Gotcha:** in static UI `tr()` returns markup, so inside an attribute (`placeholder`, `title`) it comes out as escaped text; those are hardcoded English for now.

## ma-riviere/shinyutils

Reusable infrastructure/code/plumbing shared by my Shiny apps, so the app repo only keeps features. Same deal as `auth0r`: private, breaking changes allowed.

`db_connect()`, `init_i18n()`, `init_auth0()` store the pool / translator / Auth0 client inside the package. Every helper fetches them from there, so nothing is threaded through module arguments (`db_query()`, `tr()` just work).

## Infrastructure (Docker, CI/CD, server)

Push to `main` -> GitHub Actions formats, tests in a container, builds and pushes the image -> SSH to the server with a key that can only run the deploy command -> `docker compose up --wait` swaps the container if healthy -> Traefik routes the subdomain, Cloudflare in front.

The server is managed from a separate repo (`deploy-main`: OpenTofu + Ansible), independent from this app.

### Base images (`docker-shiny`)

My own reusable images, built from Debian slim + Posit's R binaries. One multi-stage Dockerfile produces three images:

- `builder`: R + compilation tools + preinstalled R packages (so app builds only install what's missing or differs from its lockfile, to speed things up).
- `runtime`: R + Shiny Server, no compilation tools or app packages (lower size). The app image copies its package library from `builder`.
- `test`: builder + Chrome for CI tests.

Rebuilt monthly for OS updates, keeping the R package lockfiles unchanged. Builder and runtime use the same R minor version (4.6 here).

### App image

The app's `Dockerfile` uses two stages, relying on the base `builder` and `runtime`:

- `builder`: restores the production `renv` lockfile on top of the base `builder` image's packages (reuses matching packages, installs missing or different versions, and removes unlisted packages through `clean = TRUE`).
- `runtime`: copies the resulting renv library, Shiny Server config and app code. Code goes last, so code-only changes reuse the cached package layers. This produces a smaller deployment image, and the server does not need to install R packages at startup.

At startup, `docker/prestart.R` checks writable folders and the DB, applies the schema and verifies expected columns. A failure prevents Shiny Server from starting. Previous container stays up.

The healthcheck uses `HEAD /`: checks that Shiny Server responds, without starting R. It doesn't check that the app itself works.

### Shiny Server in the container

ONE R process for the app (aside from mirai/ExtendedTask), with 25 concurrent sessions max (`simple_scheduler 25`, 503 beyond). `app_idle_timeout 600` kills the process 10 min after the last user leaves. `bookmark_state_dir` only switches Shiny Server's bookmarking support on; the app writes its states to the bind-mounted `shiny_bookmarks` folder itself (cf. "Bookmarking with Auth0"), so that directive points to a folder outside the app.

> TODO: switch to `runApp()` since its one app per container? Traefik + Docker already handle routing and restarts. No more env-to-`.Renviron` environment-copying workaround, and xtail log-forwarding to docker logs. And we don't really need a connection limit & idling. But needs updated/new base images.

### renv

`packages-dev.txt` -> `dev-4.6` (SQLite, test tooling)
`packages-docker.txt` -> `docker-4.6` (RPostgres).

CI restores dev, the Dockerfile restores docker.
Both are generated by `generate_profile()` (r-utils) against a dated PPM snapshot.

### `deploy/compose.yml`

Tells Docker how to run the app image: which settings, folders and networks it needs, and how much CPU/RAM it can use. CI replaces the image tag with the selected commit SHA and copies this file to `/srv/apps/shiny-base/compose.yml` on the server.

**Settings and secrets:** Compose reads two files beside the server's `compose.yml` and passes their contents into the container as environment variables:

- `db.env`: generated on the server by the infrastructure setup. Contains the Postgres host, port, database name, and this app's DB username/password (`PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`).
- `app.env`: maintained locally at this app's repo root, gitignored, then copied to `/srv/apps/shiny-base/app.env` by Ansible. Contains app settings/secrets: production mode, Auth0 credentials and callback URL, email/API settings, logging, bookmark paths and dataset assistant settings. Edit the local master and run Ansible to update the server copy; server-only edits would be overwritten.

These files are supplied when the container is created, not baked into the image. After changing them, recreate the container so it receives the new values. The startup script also writes them into `.Renviron`, because Shiny Server does not pass the full container environment to R.

**Connections:** this Compose file starts only the app container. Traefik, Postgres and the assistant's model already run separately on the server. Docker networks let the app communicate with them:

- `edge`: Traefik forwards requests for `shiny-base.ma-riviere.com` to the app's port 3838. The app publishes no port directly on the server. The `labels` configure this routing, HTTPS and browser security headers.
- `postgres`: access to the database, using the credentials from `db.env`.
- `llm`: access to the dataset assistant's model at `http://llm:8080/v1`.

**Persistent files:** `./data/` means `/srv/apps/shiny-base/data/` on the server. Its `bookmarks`, `logs` and `shinylogs` folders are mounted inside the container: writes go to the server folders and survive container replacement. The infrastructure setup creates these folders for user `shiny` (uid 997) and includes them in backups.

**Resources and lifecycle:** the whole container is limited to 2 CPUs and 4 GB RAM, including its worker processes. `MIRAI_WORKERS=2` sets the main mirai pool; chat adds one worker when enabled.

Docker restarts the container after an exit unless explicitly stopped (`restart: unless-stopped`). On shutdown, it allows 30 seconds for cleanup before forcing a stop. `init: true` handles signals and exited child processes; `no-new-privileges` prevents executable files from granting extra privileges.

> TODO: keep `./data/shinylogs` ? Still mounted and checked by prestart, but not currently in use (heavy, slows the app down).

### CI/CD

GitHub Actions runs `.github/workflows/deploy-shiny-base.yml`. CI checks the code; CD builds the app image and deploys it to the server.

**On a pull request:** Air checks R formatting/syntax. App changes also trigger tests; docs-only changes skip them. Tests run inside the `docker-shiny:4.6-test` image with the dev `renv` lockfile: shinytest2 checks Shiny behavior, Playwright does browser e2e flows. Auth0 is disabled for these tests, so they do not verify the real login flow.

**On a push to `main`:** the same checks run, then:

1. **Build:** the app's Dockerfile produces the image. GitHub Actions uploads it to GitHub Container Registry (GHCR) as `ghcr.io/ma-riviere/shiny-base:<commit SHA>`.
2. **Send Compose:** CI replaces `${IMAGE_TAG:-local}` with that SHA and sends the file to `/srv/apps/shiny-base/compose.yml` over SSH.
   Ansible prepares the env files and data folders separately, before app deployment. GitHub Actions uploads only Compose. Changing your local app.env requires running Ansible again before redeploying.
3. **Deploy:** CI calls the server's deploy command. It downloads the image and runs `docker compose up --wait` to replace the container and wait for its healthcheck. A failed check fails the workflow; it does not automatically restore the previous container.

The SSH key can only invoke the app's deployment commands, not open an interactive shell. CI verifies the server against saved SSH host keys. Production deployments run one at a time.

**Manual rebuild / rollback:** GitHub Actions -> CI/CD Pipeline -> Run workflow, using `main`:

- Leave `image_tag` empty to build and deploy the current commit, e.g. after updating a base image.
- Enter an existing image tag (normally an older commit SHA) to deploy that image without rebuilding.

Manual runs skip tests. Rollback changes the image only: it still uploads the current run's Compose file and uses the server's current env files and database. Schema changes from `prestart.R` are not undone.

**GitHub repo secrets:** `CICD_GITHUB_PAT` reads private repos/packages; `DEPLOY_HOST` + `DEPLOY_PORT` locate the server; `DEPLOY_SSH_KEY` authenticates deployment; `DEPLOY_KNOWN_HOSTS` verifies the server's identity.

### The server (`deploy-server`)

A shared Hetzner VPS managed by the separate `deploy-main` project. It provides Docker, routing (Traefik), Postgres, the assistant's model, backups and monitoring.

It prepares `/srv/apps/shiny-base/` with the env files and persistent folders described above. Shiny-base's CI uploads Compose and requests deployment; server configuration stays in `deploy-main`.

**Access/logs:** `ssh main`, then `docker logs shiny-base-shiny-1` for container output or `/srv/apps/shiny-base/data/logs/` for Shiny Server logs. Deploy/redeploy/rollback through shiny-base's GitHub Actions.

## Security

The app handles both anonymous visitors and logged-in users sending unexpected input: forged dataset IDs, malicious text/files, or prompts intended to misuse the assistant.

**The browser is not trusted:** someone can call `Shiny.setInputValue()` directly, even for a hidden or disabled control. R must check permissions and data ownership before acting. Login identifies the user, but it does not make their input safe.

### Edge: Cloudflare and Traefik

Requests reach Cloudflare first, then Traefik on the server, then the app container. Traefik requires Cloudflare's client certificate for this hostname (Authenticated Origin Pulls), so a direct request without that certificate is rejected. The app publishes no port that bypasses Traefik.

**Browser security headers:** configured by the `sb-sec-headers` labels in `deploy/compose.yml`. They require HTTPS on future visits (HSTS), prevent other sites from embedding the app in a frame, and disable unused browser features such as camera/microphone access. Cloudflare's HSTS setting takes precedence over the value in Compose.

The remaining headers limit referrer information, tell browsers to respect declared file types (`nosniff`), and ask crawlers not to index the app. Server/firewall configuration belongs to `deploy-main`.

### Content-Security-Policy

CSP is a response header telling the browser which sources it may use for scripts, styles, images and connections. Ours is defined in `deploy/compose.yml`: mostly the app itself, plus specific hosts needed for fonts and profile pictures.

**Limit:** Shiny needs inline JS/CSS, and htmlwidgets need to evaluate generated JavaScript. This requires `'unsafe-inline'` and `'unsafe-eval'`, so the policy does not prevent injected inline scripts from running. It restricts some ways to load content or send data elsewhere, but cannot make injected JavaScript safe. Escaping untrusted text remains necessary. See the [CSP reference](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy).

**When adding an external resource:** add its host to the matching directive (`img-src`, `font-src`, `connect-src`, etc.). Check the browser console if it fails to load; CSP violations appear there. Allow the specific hosts needed, rather than every HTTPS source.

A few app-specific exceptions:

- `img-src data:` allows embedded Bootstrap icons and Shiny plots.
- Fonts and Auth0 profile pictures use external hosts; picture redirects may require more than one allowed host.
- `connect-src` explicitly includes the app's `wss://` address for Shiny's WebSocket connection.
- The cookies package needs the JavaScript library js-cookie to send browser cookie values to R. Its default CDN URL is blocked by our CSP. ui.R serves the bundled copy from the installed package instead.

### Host and containers

`deploy-main` manages SSH access, firewall rules, updates and backups. Here, the app runs as the non-root user `shiny`, with CPU/RAM limits and `no-new-privileges` (executables cannot grant the process extra privileges). These reduce what a compromised app can do; they do not protect data already accessible to that app.

Postgres is reached over the private Docker network using this app's DB login. Its private tables and the cross-app `shared` tables are separated into schemas. `search_path` controls which schema Postgres looks in first; actual access comes from database permissions. User ownership checks still happen in the app's queries.

### Secrets

The env-file flow is described under Infrastructure: `db.env` is generated on the server; `app.env` comes from this repo's gitignored local master. Neither is copied into the app image. To change an app secret: update the local file, run Ansible to copy it, then recreate the container.

On the server, `app.env` is readable by root and the deploy group (`0640`). Inside the container, the startup script writes `.Renviron` for Shiny Server, readable/writable only by its owner (`0600`). These are plain-text files protected by file permissions, not encrypted storage.

CI's GitHub PAT accesses private repositories/packages. Docker receives it as a BuildKit secret for the package-install step, rather than saving it in an image layer. The required GitHub repository secrets are listed in the CI/CD section.

**Deploy-key risk:** the SSH key cannot open a shell, but it can upload Compose configuration that the server runs through Docker. A stolen key could therefore give an attacker control of the host. The restricted SSH command does not remove that risk. See [Docker's security model](https://docs.docker.com/engine/security/).

### Identity (`auth0r`)

Auth0 handles login; `auth0r` verifies the result before the app's server logic runs. It checks the token's signature, issuer, intended client and expiry. This app also requires a verified email. The full redirect flow is described under Auth.

**Protecting the login exchange:** PKCE requires a secret verifier when exchanging the temporary login code, so the code alone is insufficient. A nonce ties the returned identity token to the login attempt. Login state is kept in an encrypted `HttpOnly` cookie (browser JavaScript cannot read it); the one-use `_login_id_` then transfers the validated login to the Shiny session.

`AUTH0_APP_URL` sets the registered callback/logout URL explicitly. The app refuses to start in production with `AUTH0_DISABLE=true`, so the development bypass cannot silently disable login there.

### Untrusted text in the browser (XSS)

XSS means user-controlled content becomes executable code in someone else's browser. For example, a dataset name containing HTML must display as text, not become a page element.

Dataset names/descriptions are escaped by `htmltools`, and the admin log viewer escapes entries before adding formatting.

**Notes:**

- `HTML()` treats its contents as markup, so do not pass user text directly to it.
- `shiny.sanitize.errors = TRUE` hides ordinary Shiny error details in production. It does not sanitize text explicitly passed to a toast: some handlers currently display `e$message` themselves.

### Untrusted content in R (code execution)

**Model formulas:** R formulas can execute functions while fitting, so raw equation text cannot go straight into `lm()`. `validate_formula()` parses it and allows only dataset columns, numeric values and selected operators/functions (`log`, `sqrt`, `poly`, etc.). The allowlist is the security check; a separate formula environment controls how approved functions resolve.

**CSV uploads:** the server checks the extension and a 10 MB file limit, then reads Shiny's temporary upload file. Cell text is data, not R code. A different risk remains when downloading CSVs: spreadsheet programs may interpret cells starting with `=` as formulas when the file is opened.

**Database queries:** use dbplyr or the DB helpers that quote/bind values. A dataset name must remain a value, not become part of the SQL syntax. Ownership filters are still required even when the SQL is safely constructed.

**Dataset assistant:** both prompts and dataset contents can steer the model, so generated SQL is untrusted. Queries run in a separate mirai worker against a fresh DuckDB containing only the selected dataset. External file/network access and extensions are disabled, settings are locked, and queries must fit inside a read-only subquery.

**Saved models:** `unserialize()` reconstructs an R object from the DB and must only receive trusted blobs.

### Bookmarks

Disconnect bookmarks save input values to `input.rds`, excluding login parameters, action buttons and the chat namespace. They do not save `session$userData` or grant access to the selected dataset/model. The normal ownership checks still apply when restored. Cleanup removes bookmarks older than 30 minutes (CRON job).

Bookmarks and app logs are plain files in the mounted server folders. They can contain input values, dataset names and user identifiers, so treat them as private. Chat prompts/results are not deliberately logged by the app, and OpenTelemetry message-content capture stays off. The platform encrypts its backups, including database dumps and bookmarks.

## Testing

> TODO: testthat/shinytest2, e2e
