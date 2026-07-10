# In containers (IN_CONTAINER set by the docker-shiny base images) the library is
# already restored into R_LIBS_SITE: renv activation would shadow it with an empty
# project library. Locally, dev sessions activate the renv dev profile as usual.
if (!nzchar(Sys.getenv("IN_CONTAINER"))) {
    source("r-utils/init.R")
    source("renv/activate.R")
}

options(auth0_disable = as.logical(Sys.getenv("BYPASS_AUTH0")))
options(shiny.port = as.integer(Sys.getenv("APP_PORT", 9090)))
