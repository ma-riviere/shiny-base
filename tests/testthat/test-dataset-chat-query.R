# Dataset assistant `query` tool (R/210_dataset_chat_fn.R): the SQL is model-written
# from user prompts and dataset values, so these tests pin the sandbox, not the
# model. No Shiny session needed: run_dataset_query() is the pure runner the
# tool ships to the `chat` mirai daemon.

query_fixture <- data.frame(
    id = 1:300,
    grp = rep(c("a", "b", "c"), 100),
    val = rep(c(1.5, 2.5, 3.5), 100),
    note = "text; with semicolon",
    stringsAsFactors = FALSE
)

resolve_promise <- function(promise, deadline_s = 30) {
    outcome <- NULL
    promises::then(promise, \(value) outcome <<- list(value = value), \(error) outcome <<- list(error = error))
    started <- Sys.time()
    while (is.null(outcome)) {
        if (as.numeric(Sys.time() - started, units = "secs") > deadline_s) {
            stop("promise not settled within ", deadline_s, " s")
        }
        later::run_now(0.05)
    }
    return(outcome)
}

# testthat runs from tests/testthat, where no .Rprofile activates renv: the
# daemon Rscript must be told where the packages are.
start_chat_daemon <- function(env = parent.frame()) {
    withr::local_envvar(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep), .local_envir = env)
    mirai::daemons(1, .compute = "chat")
    withr::defer(mirai::daemons(0, .compute = "chat"), envir = env)
}

test_that("a SELECT over the dataset table comes back as CSV text", {
    out <- run_dataset_query("SELECT grp, count(*) AS n FROM dataset GROUP BY grp ORDER BY grp", query_fixture)
    expect_match(out, '^"grp","n"\n"a",100\n"b",100\n"c",100$')
    expect_match(run_dataset_query("SELECT * FROM (DESCRIBE dataset)", query_fixture), "column_name")
    cte <- "WITH t AS (SELECT val FROM dataset) SELECT max(val) AS m FROM t"
    expect_match(run_dataset_query(cte, query_fixture), "3.5")
    expect_match(run_dataset_query("SELECT 1 AS x -- trailing comment", query_fixture), '"x"\n1')
})

test_that("the sandbox is locked once the model SQL runs", {
    settings <- run_dataset_query(
        "SELECT current_setting('enable_external_access') AS ext, current_setting('lock_configuration') AS lock",
        query_fixture
    )
    expect_match(settings, "FALSE,TRUE")
    for (sql in c(
        "SELECT * FROM read_csv('/etc/passwd')",
        "SELECT content FROM read_text('/etc/hostname')",
        "SELECT * FROM glob('/etc/*')"
    )) {
        expect_match(run_dataset_query(sql, query_fixture), "^Error: .*file system operations are disabled", info = sql)
    }
})

test_that("anything but one SELECT is a syntax error inside the wrapper", {
    for (sql in c(
        "COPY dataset TO '/tmp/leak.csv'",
        "ATTACH '/tmp/x.duckdb' AS x",
        "INSTALL httpfs",
        "LOAD httpfs",
        "SET enable_external_access = true",
        "PRAGMA enable_external_access",
        "DROP TABLE dataset",
        # duckdb-r executes every statement before the last one: the wrapper alone
        # is only safe because the tool refuses semicolons first (tested below)
        "SELECT 1); CREATE TABLE evil AS SELECT 1; SELECT 1 --"
    )) {
        expect_match(run_dataset_query(sql, query_fixture), "^Error: Parser Error", info = sql)
    }
})

test_that("output is capped and DuckDB errors are returned as text", {
    rows <- run_dataset_query("SELECT id FROM dataset", query_fixture)
    expect_match(rows, "\\[truncated")
    expect_equal(length(strsplit(rows, "\n")[[1]]), 200L + 2L) # header + 200 rows + marker
    long <- run_dataset_query("SELECT repeat('z', 500) AS z FROM dataset LIMIT 50", query_fixture)
    expect_lte(nchar(long), 4000L + 60L)
    expect_match(long, "\\[truncated")
    unresolved <- run_dataset_query("SELECT nope FROM dataset", query_fixture)
    expect_match(unresolved, "^Error: Binder Error")
    expect_match(unresolved, 'Hint: column names must be double-quoted exactly as listed: "id", "grp", "val", "note"$')
    expect_no_match(run_dataset_query("SELECT 1 FROM nope", query_fixture), "Hint:")
})

# Both mistakes loop forever without a correction: the model re-sends the query
# verbatim (measured against the live model, 2026-09-16).
test_that("a dotted alias is answered with the alias rule and the example", {
    dotted_alias <- run_dataset_query(
        'SELECT avg("val") AS avg_val.x FROM dataset',
        query_fixture,
        example = 'SELECT avg("a.b") AS avg_a_b FROM dataset'
    )
    expect_match(dotted_alias, "^Error: Parser Error")
    expect_match(dotted_alias, "Hint: an alias cannot contain a dot", fixed = TRUE)
    expect_match(dotted_alias, 'e.g. SELECT avg("a.b") AS avg_a_b FROM dataset.', fixed = TRUE)
    # Without an example (direct calls, tests) the rule is still stated
    expect_match(run_dataset_query('SELECT avg("val") AS a.b FROM dataset', query_fixture), "underscores only\\.$")
})

test_that("the tool description shows a quoted example built from the dataset's own columns", {
    state <- new.env()
    dotted <- dataset_chat_query_tool(data.frame(id = 1L, Sepal.Length = 5.1, Species = "setosa"), state)
    example <- 'SELECT avg("Sepal.Length") AS avg_sepal_length FROM dataset'
    expect_match(dotted@description, paste0("e.g. ", example, "."), fixed = TRUE)
    expect_match(dotted@arguments@properties$sql@description, example, fixed = TRUE)
    plain <- dataset_chat_query_tool(data.frame(region = "north", amount = 1.5), state)
    expect_match(plain@description, 'SELECT count(DISTINCT "region") AS n_region FROM dataset', fixed = TRUE)

    # Uploaded CSVs often lead with an index column: it needs quotes but
    # demonstrates neither rule, so a real name wins (prod dataset shape)
    indexed <- data.frame(check.names = FALSE, "...1" = 1L, "Sepal.Length" = 5.1, "Species" = "setosa")
    expect_match(dataset_chat_sql_example(indexed), example, fixed = TRUE)
    expect_match(dataset_chat_sql_example(data.frame(check.names = FALSE, "...1" = 1L)), '"...1"', fixed = TRUE)
})

test_that("the tool refuses semicolons, enforces the per-turn budget and runs through the chat daemon", {
    start_chat_daemon()
    state <- new.env()
    state$tool_calls <- 0L
    state$query <- NULL
    query_tool <- dataset_chat_query_tool(query_fixture, state)

    refused <- resolve_promise(query_tool(sql = "SELECT 1; SELECT 2"))
    expect_match(refused$value, "^Error: one statement only")

    ran <- resolve_promise(query_tool(sql = "SELECT count(*) AS n FROM dataset"))
    expect_match(ran$value, '"n"\n300')
    expect_null(state$query)

    state$tool_calls <- CHAT_TOOL_BUDGET
    exhausted <- resolve_promise(query_tool(sql = "SELECT 1"))
    expect_match(exhausted$value, "^Budget exhausted")
})

test_that("a runaway query is cut by the mirai walltime", {
    start_chat_daemon()
    slow <- mirai::mirai(
        run_dataset_query(sql, data),
        sql = "SELECT count(*) FROM range(100000000000) a, range(100000) b",
        data = query_fixture,
        run_dataset_query = run_dataset_query,
        .timeout = 1000,
        .compute = "chat"
    )
    outcome <- resolve_promise(promises::as.promise(slow))
    expect_true(!is.null(outcome$error))
})

test_that("the client is bound to the dataset snapshot it was built with", {
    start_chat_daemon()
    state <- new.env()
    state$tool_calls <- 0L
    state$query <- NULL

    small <- data.frame(id = 1:12, val = seq(2, 24, by = 2))
    big <- data.frame(id = 1:47, val = seq_len(47))

    # A rebind builds a NEW client; the previous one must not leak into it
    tool_small <- dataset_chat_query_tool(small, state)
    tool_big <- dataset_chat_query_tool(big, state)
    expect_match(resolve_promise(tool_small(sql = "SELECT count(*) AS n FROM dataset"))$value, '"n"\n12')
    expect_match(resolve_promise(tool_big(sql = "SELECT count(*) AS n FROM dataset"))$value, '"n"\n47')
})

test_that("the system prompt carries the dataset notes and the answer language", {
    dataset <- list(name = "Sales", description = "Quarterly figures")
    data <- data.frame(region = "north", amount = 1.5, count = 2L, ok = TRUE, when = Sys.Date())

    prompt <- dataset_chat_system_prompt(dataset, data, "fr")
    expect_match(prompt, "Answer in French", fixed = TRUE)
    expect_match(prompt, "Name: Sales", fixed = TRUE)
    expect_match(prompt, "Description: Quarterly figures", fixed = TRUE)
    expect_match(prompt, "has 1 rows and 5 columns", fixed = TRUE)
    expect_match(prompt, '- "region" (VARCHAR)', fixed = TRUE)
    expect_match(prompt, '- "amount" (DOUBLE)', fixed = TRUE)
    expect_match(prompt, '- "count" (INTEGER)', fixed = TRUE)
    expect_match(prompt, '- "ok" (BOOLEAN)', fixed = TRUE)
    expect_match(prompt, '- "when" (DATE)', fixed = TRUE)

    # No dataset selected: the model is told so, and gets no tool
    expect_match(dataset_chat_system_prompt(NULL, NULL, "en"), "No dataset is selected", fixed = TRUE)
    expect_match(dataset_chat_system_prompt(NULL, NULL, "en"), "Answer in English", fixed = TRUE)
})
