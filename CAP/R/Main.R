#' Execute the cohort pathway study
#'
#' @details
#' This function will execute the sepcified parts of the study
#'
#' @param connectionDetails    An object of type \code{connectionDetails} as created using the
#'                             \code{\link[DatabaseConnector]{createConnectionDetails}} function in the
#'                             DatabaseConnector package.
#' @param databaseName         A string representing a shareable name of your databasd
#' @param cdmDatabaseSchema    Schema name where your patient-level data in OMOP CDM format resides.
#'                             Note that for SQL Server, this should include both the database and
#'                             schema name, for example 'cdm_data.dbo'.
#' @param cohortDatabaseSchema Schema name where intermediate data can be stored. You will need to have
#'                             write priviliges in this schema. Note that for SQL Server, this should
#'                             include both the database and schema name, for example 'cdm_data.dbo'.
#' @param oracleTempSchema     Should be used in Oracle to specify a schema where the user has write
#'                             priviliges for storing temporary tables.
#' @param cohortTable          The name of the table that will be created in the work database schema.
#'                             This table will hold the exposure and outcome cohorts used in this
#'                             study.
#' @param outputFolder         Name of local folder to place results; make sure to use forward slashes
#' @param noteTitle            Name of note
#' @param noteKeyword          Specific keyword in note table for cohort extraction
#'                             (/)
#' @param keywordSearch        turn on the keyword search function in patient note table.
#'                             (/)
#' @param createCohorts        Whether to create the cohorts for the study
#' @param cohortDiagnostics
#' @param runPathway           Whether to run the treatment pathway visualization
#' @param packageResults       Whether to package the results (after removing sensitive details)

#' @export
execute <- function(connectionDetails,
                    databaseId,
                    databaseName,
                    databaseDescription,
                    cdmDatabaseSchema,
                    cohortDatabaseSchema,
                    oracleTempSchema,
                    cohortTable,
                    outputFolder,
                    noteTitle = NULL,
                    noteKeyword = NULL,
                    keywordSearch = F,
                    createCohorts = T,
                    cohortDiagnostics = T,
                    runPathway = T,
                    packageResults = T){
  
  if (!file.exists(outputFolder))
    dir.create(outputFolder, recursive = TRUE)
  
  ParallelLogger::addDefaultFileLogger(file.path(outputFolder, "log.txt"))
  
  if(createCohorts & (!is.null(noteTitle) & !is.null(noteKeyword))){
    ParallelLogger::logInfo("Creating Cohorts with specific keyword in note table")
    createCohorts(connectionDetails,
                  cdmDatabaseSchema=cdmDatabaseSchema,
                  cohortDatabaseSchema=cohortDatabaseSchema,
                  cohortTable=cohortTable,
                  outputFolder = outputFolder,
                  keywordSearch = T,
                  noteTitle = noteTitle,
                  noteKeyword = noteKeyword)
  }else if(createCohorts & (!is.null(noteTitle) || !is.null(noteKeyword))){
    ParallelLogger::logInfo("Please check the noteTitle or noteKeyword")
  }
  
  if(createCohorts & (is.null(noteTitle) & is.null(noteKeyword))){
    ParallelLogger::logInfo("Creating Cohorts")
    createCohorts(connectionDetails,
                  cdmDatabaseSchema=cdmDatabaseSchema,
                  cohortDatabaseSchema=cohortDatabaseSchema,
                  cohortTable=cohortTable,
                  outputFolder = outputFolder,
                  keywordSearch = F)
  }else if(createCohorts & (is.null(noteTitle) || is.null(noteKeyword))){
    ParallelLogger::logInfo("Please check the noteTitle or noteKeyword")
  }
  
  if(cohortDiagnostics){
    ParallelLogger::logInfo("Run cohort diagnostics")
    runCohortDiagnostics(connectionDetails,
                        cdmDatabaseSchema,
                        cohortDatabaseSchema = cohortDatabaseSchema,
                        cohortTable = cohortTable,
                        oracleTempSchema = oracleTempSchema,
                        outputFolder,
                        databaseId = databaseId,
                        databaseName = databaseName,
                        databaseDescription = databaseDescription,
                        createCohorts = FALSE,
                        runInclusionStatistics = FALSE,
                        runIncludedSourceConcepts = TRUE,
                        runOrphanConcepts = FALSE,
                        runTimeDistributions = FALSE,
                        runBreakdownIndexEvents = FALSE,
                        runIncidenceRates = TRUE,
                        runCohortOverlap = FALSE,
                        runCohortCharacterization = TRUE,
                        runTemporalCohortCharacterization = FALSE,
                        minCellCount = 5)
  }
  
  if(runPathway){
    ParallelLogger::logInfo("Run analysis of Pneumonia medication pathway")
    runDrugPathway(connectionDetails,
                   cdmDatabaseSchema,
                   cohortDatabaseSchema,
                   cohortTable,
                   outputFolder,
                   savePlot = T,
                   StartDays = 0,
                   EndDays = 3650,
                   minCellCount = 5)
  }
  
  if (packageResults) {
    ParallelLogger::logInfo("Packaging analysis results")
    exportResults(outputFolder = outputFolder)
  }
}
