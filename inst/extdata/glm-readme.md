# Analysis of fish dependence on coral habitat

## Introduction
This project will ask how abundance of fish juveniles depends on coral cover. The fish we are interested in is *Bolbometopon muricatum*, the bumphead parrotfish. Also known as 'topa' in the local language of our study region. We will analyze survey data from 49 sites, that includes benthic cover surveys and surveys fish abundance at the same locations. We are studying its juvenile habitat. 

## Aims of the analysis 

1. Does fish abundance depend on branching coral cover? 
2. What is the direction and strength of the relationship between fish abundance and branching coral cover? 
3. Does fish abundance depend on soft coral cover? 
4. What is the direction and strength of the relationship between fish abundance and branching coral cover? 

## Data methodology

The data was collected with the point intersect transect method. Divers swam along transects. There were several transects per site.  Along each transect they dropped points and recorded the type of benthic organism (in categories) on that point. Percentage cover for one organism type can then be calculated as the number of points with that organism divided by the total number of points on that transect. In our data we have percent cover of branching corals and percent cover of soft corals. 
Transects were averaged to give a single value for each site. 
At each site divers also counted the number of juvenile 'topa' along dive transects of the same length. 

## Analysis methodology 

We will use generalized linear models to analyze the relationship between topa and the two coral cover types. 
Topa abundance is probably over-dispersed, so we we will need to use a negative binomial family. We will use R and the MASS package: 

```
MASS::glm.nb(pres.topa ~ cb_cover*soft_cover, data = fish_coral_cover_sites)
```

To obtain a final model we should model selection, starting with a full model then working towards simpler models. We will use likelihood ratio tests to compare models. For example the first test would be: 

```
m1 <- MASS::glm.nb(pres.topa ~ cb_cover*soft_cover, data = fish_coral_cover_sites)
m2 <- MASS::glm.nb(pres.topa ~ cb_cover + soft_cover, data = fish_coral_cover_sites)
anova(m1, m2, test = "Chisq")
```

Then proceed with m2 if the interaction term is not significant. Elsewise to the next proceed with m1.

On completion of the model selection, we will do model diagnostics. This will include checking residuals and the dispersion parameter. Save these as png files. 

Write a diagnosticis report in an Rmarkdown file. 


## Instructions for the agent

The agent will produce a report that answers the above questions. The report will include a description of the data, the methods used for analysis, and the results of the analysis. The code will be written as R scripts. 

Each script should be modular and save intermediate results as datafiles and figures. The final report must be written in Rmarkdown format. The figures will be imported using markdown syntax, e.g. `![](outputs/plots/figure1.png)`. Don't use R code for figures in the markdown report. 
Summary tables should be imported from .csv files and created using the `knitr::kable()` function in Rmarkdown. 
The report must include the following sections:

- Study aims
- Data methodology
- Analysis methodology
- Results
  - Model selection and verification
  - Model fit statistics
  - Plots of predicted fish abundance (log-link scale) based on the final model, with confidence intervals
  - Relevant statistics (r2, p-values, etc.)

The agent is must produce diagnostic plots and a separate report on the model diagnostics. 

### Tech context
- We will use the R program
- tidyverse packages for data manipulation
- ggplot2 for data visualization
- use `theme_set(theme_classic())` for plots
- Use the `MASS` package for the negative binomial model, however don't load it globally with `library(MASS)`, instead use `MASS::glm.nb()` to avoid namespace conflicts.
- Use `visreg` package for plotting model effects and confidence intervals, e.g. `visreg::visreg(m2, "cb_cover", "soft_cover", gg=TRUE, scale = 'linear')`

Keep your scripts short and modular to facilitate debugging. Don't complete all of the steps below in one script. Finish scripts where it makes sense and save intermediate datasets. 

When using Rscript to run R scripts in terminal put quotes around the file, e.g. `Rscript "1_model.R"`

### Workflow 

1. Create a todo list and keep track of progress
2. Data processing including standardizing coral variables by number of points
3. Model selection and verification, produce diagnostic plots
4. Model diagnostic plots markdown report 
5. Create plots of predictions from the final model
6. Write report in markdown format

### Directory structure 

```
glm-test-case/
├── data/                              # Data files
│   ├── fish-coral-cover-sites.csv     # Raw data: fish counts and coral cover
│   └── ...                            # Intermediate datasets you save
├── glm-readme.md                      # This readme, with the project spec
├── outputs/                           # Generated outputs
│   ├── plots/                         # Plots (PNG files)
│   └── ...                            # Summary tables (CSV files)
└── scripts/                           # R scripts for the analysis
```

Put the .rmd reports in the top-level directory. 

## Meta data 

### fish-coral.csv

Location: `data/fish-coral-cover-sites.csv`

Variables
- site: Unique site IDs, use to join to benthic_cover.csv
- reef.ID: Unique reef ID
- pres.topa: number of Topa counted (local name for Bolbometopon)
- pres.habili: number of Habili counted (local name for Cheilinus) 
- secchi: Horizontal secchi depth (m), higher values mean the water is less turbid
- flow: Factor indicating if tidal flow was "Strong" or "Mild" at the site
- logged: Factor indicating if the site was in a region with logging "Logged" or without logging "Not logged"
- coordx: X coordinate in UTM zone 57S
- coordy: Y coordinate in UTM zone 57S
- cb_cover: Number of PIT points for branching coral cover
- soft_cover: Number of PIT points for soft coral cover
- n_pts: Number of PIT points at this site (for normalizing cover to get per cent cover)
- dist_to_logging_km: Linear distance to nearest log pond (site where logging occurs) in kilometres. 
