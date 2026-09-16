# Containers already have their packages in R_LIBS_SITE (IN_CONTAINER comes from the base image).
# Activating renv there would hide that library behind an empty project library.
# Local sessions use the dev renv profile.
if (!nzchar(Sys.getenv("IN_CONTAINER"))) {
    source("r-utils/init.R")
    source("renv/activate.R")
}

options(auth0_disable = as.logical(Sys.getenv("BYPASS_AUTH0")))
options(shiny.port = as.integer(Sys.getenv("APP_PORT", 9090)))
