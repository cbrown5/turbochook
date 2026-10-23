# data-raw/fish_coral_cover_sites.R
# ---------------------------------------------------------------------------
# Make the fish_coral_cover_sites dataset from the raw CSV.
# Run this script, then commit the changed data/fish_coral_cover_sites.rda.
# ---------------------------------------------------------------------------

fish_coral_cover_sites <- utils::read.csv(
  "data-raw/fish-coral-cover-sites.csv",
  stringsAsFactors = FALSE
)

# The two survey conditions are fixed sets of levels, not free text.
fish_coral_cover_sites$flow <- factor(
  fish_coral_cover_sites$flow,
  levels = c("Mild", "Strong")
)
fish_coral_cover_sites$logged <- factor(
  fish_coral_cover_sites$logged,
  levels = c("Not logged", "Logged")
)

usethis::use_data(fish_coral_cover_sites, overwrite = TRUE)
