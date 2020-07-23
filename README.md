
# HapTxPath

<!-- badges: start -->
<!-- badges: end -->

The goal of HapTxPath is to identify the treatment pattern of antibiotics used for the hospital-acquired pneumonia patients.

## Installation

You can install the released version of HapTxPath from with:

``` r
devtools::install_github("ABMI/HapTxPath")
```

## Example

This is a basic example which shows you how to solve a common problem:

``` r
library(HapTxPath)

# USER INPUTS
#=======================
# The folder where the study intermediate and result files will be written:
outputFolder <- "./HapTxPath"

# Specify where the temporary files (used by the ff package) will be created:
options(fftempdir = "temp directory")

# Details for connecting to the server:
dbms <- Sys.getenv("dbms")
user <- 'your id'
pw <- 'your password'
server <- Sys.getenv("server")
port <- Sys.getenv("port")

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
cohortId <- 'cohortId'

#=======================

execute(connectionDetails = connectionDetails,
        cdmDatabaseSchema = cdmDatabaseSchema,
        cohortDatabaseSchema = cohortDatabaseSchema,
        cohortTable = cohortTable,
        cohortId = cohortId,
        outputFolder = outputFolder,
        createCohorts = T,
        runDrugPathway = T,
        packageResults = T)

# Please send the result zip file to ted9219@ajou.ac.kr
```
