if (Sys.getenv("RENV_PROFILE") == "") {
    Sys.setenv(RENV_PROFILE = paste0("dev-", version$major, ".", sub("\\..*", "", version$minor)))
}

source("r-utils/init.R")
source("renv/activate.R")

options(auth0_disable = as.logical(Sys.getenv("BYPASS_AUTH0")))
options(shiny.port = as.integer(Sys.getenv("APP_PORT", 9090)))
