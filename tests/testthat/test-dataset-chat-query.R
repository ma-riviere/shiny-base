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
    expect_match(run_dataset_query("SELECT nope FROM dataset", query_fixture), "^Error: Binder Error")
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
