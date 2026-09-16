# The assistant gets a snapshot of the selected dataset and one tool, query().
# ellmer calls the model; a separate mirai worker runs its SQL against an in-memory DuckDB.
#
# Treat generated SQL as untrusted: prompts and dataset values can steer the model.
# The tool refuses semicolons, then the worker wraps the query in a read-only subquery.
# Each call gets a fresh DB with external access disabled and settings locked.
# Limits: 20 seconds per query, 200 rows / 4,000 characters of output, eight calls per question.
# The app does not log prompts, answers or SQL.

CHAT_TOOL_BUDGET <- 8L
CHAT_QUERY_TIMEOUT_MS <- 20000L
CHAT_MAX_TOKENS <- 2048L

CHAT_SYSTEM_PROMPT <- paste(readLines("data/chat-system-prompt.md", warn = FALSE), collapse = "\n")

# Create a client for this dataset's metadata and data.frame.
# chat_server() needs a client before selection, so NULL creates one without a query tool.
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

# Give the model column names/types and dataset size upfront, saving a DESCRIBE query.
# The prompt marks the <dataset> block as untrusted because it includes user-supplied text.
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

# Share the running query and call count with the server module through the state environment.
# This lets the Stop button or a closed session cancel the query.
# Include an example using this dataset's columns: Ling drops quotes despite the system prompt.
# E.g. unquoted Sepal.Length means column Length in table Sepal to DuckDB.
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
                run_dataset_query(sql, data, example),
                sql = sql,
                data = data,
                example = example,
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
            sprintf("Column names double-quoted exactly as listed, aliases without dots, e.g. %s.", example),
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

# Demonstrate both rules: quote the column name and use an alias without dots.
# Prefer names like Sepal.Length over CSV index columns (...1, X), which make poor examples.
# Use an aggregate because that is where Ling was dropping quotes and adding dotted aliases.
dataset_chat_sql_example <- function(data) {
    columns <- names(data)
    needs_quotes <- !grepl("^[A-Za-z_][A-Za-z0-9_]*$", columns)
    informative <- needs_quotes & grepl("[A-Za-z]", columns)
    column <- if (any(informative)) {
        columns[informative][1]
    } else if (any(needs_quotes)) {
        columns[needs_quotes][1]
    } else {
        columns[1]
    }
    alias <- tolower(gsub("[^A-Za-z0-9]+", "_", column))
    expression <- if (is.numeric(data[[column]])) {
        sprintf('avg("%s") AS avg_%s', column, alias)
    } else {
        sprintf('count(DISTINCT "%s") AS n_%s', column, alias)
    }
    return(sprintf("SELECT %s FROM dataset", expression))
}

# Runs in the chat worker, which cannot read app globals; pass its inputs explicitly.
# Query errors become text the model can use to correct its SQL.
run_dataset_query <- function(sql, data, example = "", max_rows = 200L, max_chars = 4000L) {
    # Set limits and disable extensions before locking the configuration; later changes would fail.
    # Keep external access until the data.frame is copied into a table: DuckDB needs it to read R data.
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
        # Ling repeats failed SQL unless the error says what to change.
        # Missing column quotes cause a Binder error; a dot in an unquoted alias causes a parser error.
        if (grepl("Binder Error", text, fixed = TRUE)) {
            columns <- paste0('"', utils::head(names(data), 40L), '"', collapse = ", ")
            if (ncol(data) > 40L) {
                columns <- paste0(columns, ", ...")
            }
            text <- paste0(text, "\nHint: column names must be double-quoted exactly as listed: ", columns)
        } else if (grepl('syntax error at or near "."', text, fixed = TRUE)) {
            text <- paste0(
                text,
                "\nHint: an alias cannot contain a dot. Quote the column, then alias it with letters",
                " and underscores only",
                if (nzchar(example)) paste0(", e.g. ", example) else "",
                "."
            )
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
