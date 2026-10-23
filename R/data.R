# data.R
# ---------------------------------------------------------------------------
# Example data shipped with the package, for trying the agent out on a real
# analysis. Two pieces that go together:
#   - fish_coral_cover_sites: the survey data, as a data frame
#   - glm_readme_path():      a spec sheet telling an agent what to do with it
# ---------------------------------------------------------------------------

#' Fish and coral cover at 49 reef sites
#'
#' Reef survey data from Kia, Solomon Islands: counts of juvenile fish and
#' benthic cover at the same 49 sites. Used as the example analysis for the
#' agent, together with the spec sheet at [glm_readme_path()].
#'
#' Cover is given as a count of survey points, not a percentage. Divide by
#' `n_pts` to get per cent cover.
#'
#' @format A data frame with 49 rows and 13 columns:
#' \describe{
#'   \item{site}{Site ID.}
#'   \item{reef.id}{Reef ID.}
#'   \item{pres.topa}{Number of 'topa' counted, the local name for the
#'     bumphead parrotfish *Bolbometopon muricatum*. These are juveniles.}
#'   \item{pres.habili}{Number of 'habili' counted, the local name for
#'     *Cheilinus* spp.}
#'   \item{secchi}{Horizontal secchi depth (m). Higher means clearer water.}
#'   \item{flow}{Tidal flow at the site, `"Mild"` or `"Strong"`.}
#'   \item{logged}{Whether the site is in a logged region, `"Not logged"` or
#'     `"Logged"`.}
#'   \item{coordx, coordy}{Site position, UTM zone 57S.}
#'   \item{cb_cover}{Number of survey points with branching coral.}
#'   \item{soft_cover}{Number of survey points with soft coral.}
#'   \item{n_pts}{Total survey points at the site. Divide the cover columns
#'     by this to get per cent cover.}
#'   \item{dist_to_logging_km}{Distance to the nearest log pond (km).}
#' }
#' @details
#' Benthic cover was measured with the point intersect transect method: divers
#' swam transects, dropped points along them and recorded the benthic organism
#' under each point. Fish were counted along transects of the same length.
#' Transects were averaged to one value per site.
#'
#' Counts of 'topa' are over-dispersed, so a negative binomial model fits
#' better than a Poisson one.
#' @source Hamilton, R.J., Almany, G.R., Brown, C.J., Pita, J., Peterson, N.A.
#'   and Choat, J.H. (2017). Logging degrades nursery habitat for an
#'   iconic coral reef fish. *Biological Conservation* 210, 273-280.
#'   \doi{10.1016/j.biocon.2017.04.024}
#' @examples
#' head(fish_coral_cover_sites)
#'
#' # cover columns are point counts, so standardise them first
#' d <- fish_coral_cover_sites
#' d$cb_pct <- 100 * d$cb_cover / d$n_pts
#' plot(pres.topa ~ cb_pct, data = d)
"fish_coral_cover_sites"

#' Path to the example analysis spec sheet
#'
#' The path to `glm-readme.md`, a worked specification for an analysis of
#' [fish_coral_cover_sites]: the aims, the methods, the workflow to follow
#' and the shape of the report to write. It is the kind of brief you would
#' hand a collaborator, written so an agent can follow it.
#'
#' It is a file rather than a data object because the agent reads it from
#' disk with its own `read_file` tool, the same as any other project file.
#'
#' @return A single string, the path to the file inside the installed package.
#' @details
#' Use [glm_example_setup()] to copy the spec and the data into a working
#' folder, laid out the way the spec expects.
#'
#' The spec is left exactly as it was written for a real analysis, warts and
#' all. One is worth knowing about: it calls the branching coral column
#' `CB_cover`, but in the data it is `cb_cover`. A capable agent notices and
#' carries on, which makes it a fair test rather than a problem to fix.
#' @seealso [glm_example_setup()] to set up a folder, [fish_coral_cover_sites]
#'   for the data it analyses, [turbochook()] to run it.
#' @examples
#' # read the brief yourself
#' cat(readLines(glm_readme_path()), sep = "\n")
#' @export
glm_readme_path <- function() {
  path <- system.file("extdata", "glm-readme.md", package = "turbochook")
  if (!nzchar(path)) {
    cli::cli_abort("Could not find {.file glm-readme.md} in the installed package.")
  }
  path
}

#' Set up the example analysis in a folder
#'
#' Copies the spec sheet from [glm_readme_path()] and the data from
#' [fish_coral_cover_sites] into `dir`, laid out the way the spec expects:
#' the spec at `glm-readme.md` and the data at `data/fish-coral-cover-sites.csv`.
#' Point an agent at the folder and it has everything it needs.
#'
#' @param dir Folder to set up. Made if it does not exist. Defaults to a new
#'   folder in the session's temporary directory, so you can try the example
#'   without leaving anything behind.
#' @return Invisibly, the path to `dir`.
#' @seealso [glm_readme_path()], [fish_coral_cover_sites], [turbochook()]
#' @examples
#' wd <- glm_example_setup()
#' list.files(wd, recursive = TRUE)
#'
#' \dontrun{
#' # then hand it to the agent
#' turbochook("Read glm-readme.md and do the analysis it asks for.", wd = wd)
#'
#' # or, since it is a long job, run it in a Ralph Loop
#' ralph("Read glm-readme.md and do the analysis it asks for.", wd = wd)
#' }
#' @export
glm_example_setup <- function(dir = tempfile("glm-example-")) {
  dir.create(file.path(dir, "data"), recursive = TRUE, showWarnings = FALSE)

  file.copy(glm_readme_path(), file.path(dir, "glm-readme.md"), overwrite = TRUE)

  # Fetch the dataset by name so R CMD check doesn't see a loose global
  sites <- get("fish_coral_cover_sites", envir = asNamespace("turbochook"))
  utils::write.csv(
    sites,
    file.path(dir, "data", "fish-coral-cover-sites.csv"),
    row.names = FALSE
  )

  cli::cli_alert_success("Example set up in {.file {dir}}")
  invisible(dir)
}
