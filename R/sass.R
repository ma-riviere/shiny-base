sass::sass(
    input = list(
        sass::sass_file("www/sass/main.scss")
    ),
    output = "www/css/main.min.css",
    options = sass::sass_options(output_style = "compressed"),
    cache = NULL
)
