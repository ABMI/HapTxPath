#' Run drugPathway package
#'
#' @details
#' Run the drugPathway package, which implements the cohort pathway design.
#'
#' @param cdmDatabaseSchema    Schema name where your patient-level data in OMOP CDM format resides.
#'                             Note that for SQL Server, this should include both the database and
#'                             schema name, for example 'cdm_data.dbo'.
#' @param cohortDatabaseSchema Schema name where intermediate data can be stored. You will need to have
#'                             write priviliges in this schema. Note that for SQL Server, this should
#'                             include both the database and schema name, for example 'cdm_data.dbo'.
#' @param minCellCount        
#'
#' @import dplyr
#' @export
#' 

#cultureResult

#Profiling the germ etiology in cohort using fact_relationship table in CDM 5.3.1

createCultureResultTable <- function(cdmDatabaseSchema,
                          cohortDatabaseSchema,
                          cohortTable,
                          cohortId,
                          minCellCount = 5){
  

  path <- system.file(package = "HAP", "sql", "sql_server", "BacteriaCulture.sql")
  sql <- SqlRender::readSql(path)
  sql <- SqlRender::render(sql, 
                           cdm_database_schema = cdmDatabaseSchema,
                           cohort_database_schema = cohortDatabaseSchema,
                           vocabulary_database_schema = cdmDatabaseSchema,
                           cohort_table = cohortTable,
                           cohort_definition_id = cohortId,
                           minCount = minCellCount)
  
  cultureResult <- DatabaseConnector::querySql(connection = DatabaseConnector::connect(connectionDetails), sql)
  cultureResult <- reshape2::dcast(data = cultureResult, COHORT_DEFINITION_ID + CONCEPT_NAME ~ MEASUREMENT_CONCEPT_ID, value.var = c("PERSONCOUNTS"))
  cultureResult[is.na(cultureResult)] <- 0
  
  return(cultureResult)
}
