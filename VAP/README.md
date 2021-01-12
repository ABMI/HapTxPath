
# PneumoniaTxPath

<!-- badges: start -->
<img src="https://img.shields.io/badge/Study%20Status-Started-blue.svg" alt="Study Status: Started">

- Analytics use case(s): **Characterization**
- Study type: **Clinical Application**
- Tags: **-**

- Study lead: **Chungsoo Kim**, **Rae Woong Park***, **Sandy Jeong Rhie**
- Study lead forums tag: **[[Chungsoo_Kim]](https://forums.ohdsi.org/u/Chungsoo_Kim)**
- Study start date: **Nov 1, 2020**
- Study end date: **-**
- Protocol: **-**
- Publications: **-**
- Results explorer: **-**

<!-- badges: end -->

The goal of PneumoniaTxPath is to identify the treatment pattern of antibiotics used for the hospital-acquired pneumonia patients.

## Installation

You can install the released version of PneumoniaTxPath from with:

``` r
devtools::install_github("ABMI/PneumoniaTxPath")
```

## Example

This is a basic example which shows you how to solve a common problem:

``` r
library(PneumoniaTxPath)

# USER INPUTS
#=======================
# The folder where the study intermediate and result files will be written:
outputFolder <- "./PneumoniaTxPath"

# Specify where the temporary files (used by the ff package) will be created:
options(fftempdir = "temp directory")

# Details for connecting to the server:
dbms <- 'your dbms type'
user <- 'your id'
pw <- 'your password'
server <- 'your server IP address'
port <- 'server port'

connectionDetails <- DatabaseConnector::createConnectionDetails(dbms = dbms,
                                                                server = server,
                                                                user = user,
                                                                password = pw,
                                                                port = port)

conn <- DatabaseConnector::connect(connectionDetails)

# Add the database containing the OMOP CDM data
cdmDatabaseSchema <- 'cdmDatabaseSchema'
# Add a database with read/write access as this is where the cohorts will be generated
cohortDatabaseSchema <- 'cohortDatabaseSchema'

oracleTempSchema <- NULL

# table name where the cohorts will be generated
cohortTable <- 'cohortTable'

# When you need to use the note table for searching right people
# noteTitle <- 'note title that you want to search keyword'
# noteKeyword <- 'Specific keyword in note_text column'

#=======================

execute(connectionDetails = connectionDetails,
        cdmDatabaseSchema = cdmDatabaseSchema,
        cohortDatabaseSchema = cohortDatabaseSchema,
        cohortTable = cohortTable,
        outputFolder = outputFolder,
        keywordSearch = F,
        createCohorts = F,
        runPathway = F,
        packageResults = T)

# Please send the result zip file to ted9219@ajou.ac.kr
```
