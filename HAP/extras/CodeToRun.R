# Make sure to install all dependencies (not needed if already done):
# install.packages("SqlRender")
# install.packages("DatabaseConnector")
# install.packages("ggplot2")
# install.packages("ParallelLogger")
# install.packages("readr")
# install.packages("tibble")
# install.packages("dplyr")
# install.packages("RJSONIO")
# install.packages("devtools")
# devtools::install_github("FeatureExtraction")
# devtools::install_github("ROhdsiWebApi")
# devtools::install_github("CohortDiagnostics")


library(HAP)

# USER INPUTS
#=======================
# The folder where the study intermediate and result files will be written:
outputFolder <- "./HAP"

# Optional: specify where the temporary files will be created:
options(andromedaTempFolder = file.path("andromedaTemp"))


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

databaseId <- "your Database ID"
databaseName <- "your Database Name"
databaseDescription <- "your Database Description"

oracleTempSchema <- NULL

# table name where the cohorts will be generated
cohortTable <- 'cohortTable'

#=======================

execute(connectionDetails,
        databaseId,
        databaseName,
        databaseDescription,
        cdmDatabaseSchema,
        cohortDatabaseSchema,
        oracleTempSchema,
        cohortTable,
        outputFolder,
        createCohorts = T,
        cohortDiagnostics = T,
        runPathway = T,
        packageResults = T)


# To view the cohortDiagnostics results:
# Optional: if there are results zip files from multiple sites in a folder, this merges them, which will speed up starting the viewer:
CohortDiagnostics::preMergeDiagnosticsFiles(file.path(outputFolder, "diagnosticsExport"))

# Use this to view the results. Multiple zip files can be in the same folder. If the files were pre-merged, this is automatically detected: 
CohortDiagnostics::launchDiagnosticsExplorer(file.path(outputFolder, "diagnosticsExport"))

# Please send the result zip file to ted9219@ajou.ac.kr

