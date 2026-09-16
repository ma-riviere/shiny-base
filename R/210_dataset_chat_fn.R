# Dataset assistant helpers (210_dataset_chat): the ellmer client bound to one
# dataset snapshot, its single `query` tool, and the sandboxed DuckDB runner the
# tool executes in the dedicated `chat` mirai daemon.
#
# SECURITY: the SQL is model-written from user prompts and dataset values, so it
# is untrusted. Bounds: one statement (semicolons refused, then wrapped as a
# subquery so anything but a SELECT is a syntax error), a fresh in-memory DuckDB
# per call with external access disabled and the configuration locked, a 20 s
# walltime (mirai .timeout), 200 rows / 4 000 chars of output, and a tool-call
# budget per user turn. Prompts, answers and SQL are never logged.

CHAT_TOOL_BUDGET <- 8L
CHAT_QUERY_TIMEOUT_MS <- 20000L
CHAT_MAX_TOKENS <- 2048L

CHAT_SYSTEM_PROMPT <- paste(readLines("data/chat-system-prompt.md", warn = FALSE), collapse = "\n")

# Client bound to ONE dataset snapshot (row + data.frame). NULL dataset = idle
# client (no tool, prompt says so): chat_server() needs a client at creation.
dataset_chat_client <- function(dataset, data, language, state) {
    api_key <- Sys.getenv("CHAT_API_KEY", "")
    client <- ellmer::chat_openai_compatible(
        base_url = getOption("chat_base_url"),
        model = getOption("chat_model"),
        # ellmer requires a string: it becomes the Bearer token. Empty for the
        # local endpoint, which has no auth and ignores the header.
        credentials = function() api_key,
        system_prompt = dataset_chat_system_prompt(dataset, data, language),
        params = ellmer::params(max_tokens = CHAT_MAX_TOKENS),
        # Ling-3.0-tiny: llama.cpp's parser drops tool calls emitted inside an unclosed think block
        api_args = list(chat_template_kwargs = list(enable_thinking = FALSE))
    )
    if (!is.null(data)) {
        client$register_tool(dataset_chat_query_tool(data, state))
    }
    return(client)
}

dataset_chat_system_prompt <- function(dataset, data, language) {
    language_name <- switch(language %||% "en", fr = "French", "English")
    prompt <- sub("{language}", language_name, CHAT_SYSTEM_PROMPT, fixed = TRUE)
    notes <- if (is.null(dataset) || is.null(data)) {
        "<dataset>\nNo dataset is selected. Ask the user to select one on the Explore page.\n</dataset>"
    } else {
        dataset_chat_notes(dataset, data)
    }
    return(paste(prompt, notes, sep = "\n\n"))
}

# The DATASET.md equivalent of plumber2-base: shape + columns, so the model
# knows the exact (quoted) identifiers without a first DESCRIBE round trip.
# Name and description are user-supplied text: they sit inside the <dataset>
# block, which the prompt declares untrusted.
dataset_chat_notes <- function(dataset, data) {
    description <- dataset$description %||% ""
    columns <- sprintf('- "%s" (%s)', names(data), vapply(data, dataset_chat_sql_type, character(1)))
    paste(
        c(
            "<dataset>",
            sprintf("Name: %s", dataset$name),
            if (nzchar(description)) sprintf("Description: %s", description),
            sprintf("The table `dataset` has %d rows and %d columns:", nrow(data), ncol(data)),
            columns,
            "</dataset>"
        ),
        collapse = "\n"
    )
}

dataset_chat_sql_type <- function(column) {
    if (inherits(column, "POSIXct")) {
        return("TIMESTAMP")
    }
    if (inherits(column, "Date")) {
        return("DATE")
    }
    switch(
        class(column)[1],
        integer = "INTEGER",
        numeric = "DOUBLE",
        logical = "BOOLEAN",
        "VARCHAR"
    )
}

# ------ TOOL ------------------------------------------------------------------

# `state` is a module-level environment: the in-flight mirai (so the Stop
# button and session end can cancel it) and the per-turn call counter.
# The description carries a quoted example built from the dataset's own columns:
# small models drop the quotes around dotted names (`Sepal.Length` = table
# `Sepal`, column `Length` to DuckDB) whatever the system prompt says.
dataset_chat_query_tool <- function(data, state) {
    example <- dataset_chat_sql_example(data)
    ellmer::tool(
        coro::async(function(sql) {
            state$tool_calls <- state$tool_calls + 1L
            if (state$tool_calls > CHAT_TOOL_BUDGET) {
                return("Budget exhausted: no more queries for this question. Answer with what you already have.")
            }
            if (grepl(";", sql, fixed = TRUE)) {
                return("Error: one statement only, without semicolons.")
            }
            state$query <- mirai::mirai(
                run_dataset_query(sql, data),
                sql = sql,
                data = data,
                run_dataset_query = run_dataset_query,
                .timeout = CHAT_QUERY_TIMEOUT_MS,
                .compute = "chat"
            )
            # A timed-out or cancelled mirai rejects the promise (errorValue)
            result <- tryCatch(
                await(promises::as.promise(state$query)),
                error = \(e) "Error: the query timed out or was cancelled."
            )
            state$query <- NULL
            return(result)
        }),
        name = "query",
        description = paste(
            "Run ONE DuckDB SELECT statement over the read-only table `dataset`.",
            sprintf("Column names must be double-quoted exactly as listed, e.g. %s.", example),
            "Aggregate before selecting rows and keep a LIMIT: results are capped at 200 rows."
        ),
        arguments = list(
            sql = ellmer::type_string(sprintf(
                "A single SELECT statement (CTEs allowed, no semicolons), every column name in double quotes, e.g. %s.",
                example
            ))
        )
    )
}

# Prefers a column whose name needs quoting (dots, spaces, ...) and an
# aggregate, the context in which the quotes get dropped; the plain alias
# shows that dots do not belong in aliases either (`AS avg_Sepal.Length` was
# the next mistake once the quotes were right).
dataset_chat_sql_example <- function(data) {
    columns <- names(data)
    needs_quotes <- !grepl("^[A-Za-z_][A-Za-z0-9_]*$", columns)
    column <- if (any(needs_quotes)) columns[needs_quotes][1] else columns[1]
    alias <- tolower(gsub("[^A-Za-z0-9]+", "_", column))
    expression <- if (is.numeric(data[[column]])) {
        sprintf('avg("%s") AS avg_%s', column, alias)
    } else {
        sprintf('count(DISTINCT "%s") AS n_%s', column, alias)
    }
    return(sprintf("SELECT %s FROM dataset", expression))
}

# Runs INSIDE the chat daemon: everything it needs travels with it (no app
# globals, hence the literal defaults). Returns text for the model, never errors.
run_dataset_query <- function(sql, data, max_rows = 200L, max_chars = 4000L) {
    # Limits and extension switches go in the driver config, BEFORE the lock
    # (locked settings refuse later changes); external access stays on until the
    # data.frame is materialized (it also gates data.frame replacement scans).
    driver <- duckdb::duckdb(
        config = list(
            threads = "1",
            memory_limit = "256MB",
            max_temp_directory_size = "64MB",
            autoinstall_known_extensions = "false",
            autoload_known_extensions = "false",
            allow_community_extensions = "false",
            allow_unsigned_extensions = "false"
        ),
        allow_extensions = FALSE,
        # No extension/secret store under ~/.duckdb (nothing is ever downloaded here)
        shared_home = FALSE
    )
    con <- DBI::dbConnect(driver)
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
    duckdb::duckdb_register(con, "dataset_df", data)
    DBI::dbExecute(con, "CREATE TABLE dataset AS SELECT * FROM dataset_df")
    duckdb::duckdb_unregister(con, "dataset_df")
    DBI::dbExecute(con, "SET enable_external_access = false")
    DBI::dbExecute(con, "SET lock_configuration = true")

    # Newlines around the model SQL so a trailing `--` comment cannot swallow the wrapper
    wrapped <- sprintf("SELECT * FROM (\n%s\n) AS chat_query LIMIT %d", sql, max_rows + 1L)
    result <- tryCatch(DBI::dbGetQuery(con, wrapped), error = \(e) e)
    if (inherits(result, "error")) {
        text <- paste0("Error: ", conditionMessage(result))
        # Unresolved names are nearly always unquoted identifiers: repeat the
        # exact quoted columns so the retry does not need a DESCRIBE round trip
        if (grepl("Binder Error", text, fixed = TRUE)) {
            columns <- paste0('"', utils::head(names(data), 40L), '"', collapse = ", ")
            if (ncol(data) > 40L) {
                columns <- paste0(columns, ", ...")
            }
            text <- paste0(text, "\nHint: column names must be double-quoted exactly as listed: ", columns)
        }
        return(text)
    }

    truncated <- nrow(result) > max_rows
    if (truncated) {
        result <- result[seq_len(max_rows), , drop = FALSE]
    }
    text <- paste(utils::capture.output(utils::write.csv(result, row.names = FALSE)), collapse = "\n")
    if (nchar(text) > max_chars) {
        text <- substr(text, 1L, max_chars)
        truncated <- TRUE
    }
    if (truncated) {
        text <- paste0(text, "\n[truncated: aggregate or add a smaller LIMIT]")
    }
    return(text)
}
