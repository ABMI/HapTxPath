#' Run drugPathway package
#'
#' @details
#' Run the drugPathway package, which implements the cohort pathway design.
#'
#' @param connectionDetails    An object of type \code{connectionDetails} as created using the
#'                             \code{\link[DatabaseConnector]{createConnectionDetails}} function in the
#'                             DatabaseConnector package.
#' @param cdmDatabaseSchema    Schema name where your patient-level data in OMOP CDM format resides.
#'                             Note that for SQL Server, this should include both the database and
#'                             schema name, for example 'cdm_data.dbo'.
#' @param cohortDatabaseSchema Schema name where intermediate data can be stored. You will need to have
#'                             write priviliges in this schema. Note that for SQL Server, this should
#'                             include both the database and schema name, for example 'cdm_data.dbo'.
#' @param cohortTable          The name of the table that will be created in the work database schema.
#'                             This table will hold the exposure and outcome cohorts used in this
#'                             study.
#' @param outputFolder         Name of local folder where the results were generated; make sure to use forward slashes
#'                             (/). Do not use a folder on a network drive since this greatly impacts
#'                             performance.
#' @param savePlot             Whether run the savePlot function
#' @param StartDays            The first date from index date (cohort start date) for investigating drug sequence 
#' @param EndDays              The last date from index date (cohort start date) for investigating drug sequence
#' @param pathLevel            Level of pathway depth                     
#'
#' @import dplyr
#' @export
#' 

runDrugPathway <- function(connectionDetails,
                           cdmDatabaseSchema,
                           cohortDatabaseSchema,
                           cohortTable,
                           outputFolder,
                           savePlot = F,
                           StartDays = 0,
                           EndDays = 365,
                           minCellCount = 5){
  
  pathToCsv <- system.file("settings", "CohortsToCreate.csv", package = "HAP")
  cohortsToCreate <- read.csv(pathToCsv)
  
  for(cohortId in cohortsToCreate$cohortId){
    #get drug exposure data
    drugExposureData <- getDrugExposureData(connectionDetails = connectionDetails,
                                            cdmDatabaseSchema = cdmDatabaseSchema,
                                            cohortDatabaseSchema = cohortDatabaseSchema,
                                            cohortTable = cohortTable,
                                            cohortId = cohortId,
                                            StartDays = StartDays,
                                            EndDays = EndDays)
    
    conceptSets <- drugExposureData %>% select (conceptId, CONCEPT_NAME) %>% distinct()
    
    #drugExposure data to sequence data
    sequenceData <- getSequenceData(cohortDatabaseSchema = cohortDatabaseSchema,
                                    cohortTable = cohortTable,
                                    cohortId = cohortId)
    
    #Results
    n <- totalN(connectionDetails = connectionDetails, 
                cohortDatabaseSchema = cohortDatabaseSchema,
                cohortTable = cohortTable,
                cohortId = cohortId)
    
    cultureResult <- createCultureResultTable(cdmDatabaseSchema,
                                             cohortDatabaseSchema,
                                             cohortTable = cohortTable,
                                             cohortId = cohortId,
                                             minCellCount = minCellCount)
    
    drugTable1 <- drugTable1(cohortDatabaseSchema = cohortDatabaseSchema,
                             cohortTable = cohortTable, 
                             cohortId = cohortId,
                             drugExposureData = drugExposureData)
    
    ParallelLogger::logInfo("Saving the table and pathway plots")
    
    #Save
    
    savefolder <- file.path(outputFolder, "drugPathway", cohortId)
    if (!file.exists(savefolder))
      dir.create(savefolder, recursive = TRUE)
    
    write.csv(n, file = file.path(savefolder, "totalN.csv"))
    write.csv(cultureResult, file = file.path(savefolder, "cultureResultTable.csv"))
    write.csv(drugTable1, file = file.path(savefolder, "drugTable1.csv"))
    write.csv(sequenceData, file = file.path(savefolder, "sequenceData.csv"))
    
    if(savePlot == T) PlotTxPathway(cohortDatabaseSchema,
                                    cohortTable,
                                    cohortId,
                                    conceptSets,
                                    drugExposureData,
                                    sequenceData,
                                    savefolder,
                                    StartDays = 0,
                                    EndDays = 365,
                                    pathLevel = 2)

  }
}


#' conceptSet to conceptId
#'
#' @details
#' Extract concept_id from the json file of concept set
#'
#' @param connectionDetails    An object of type \code{connectionDetails} as created using the
#'                             \code{\link[DatabaseConnector]{createConnectionDetails}} function in the
#'                             DatabaseConnector package.
#' @param cdmDatabaseSchema    Schema name where your patient-level data in OMOP CDM format resides.
#'                             Note that for SQL Server, this should include both the database and
#'                             schema name, for example 'cdm_data.dbo'.
#' @param cohortDatabaseSchema Schema name where intermediate data can be stored. You will need to have
#'                             write priviliges in this schema. Note that for SQL Server, this should
#'                             include both the database and schema name, for example 'cdm_data.dbo'.
#' @param cohortTable          The name of the table that will be created in the work database schema.
#'                             This table will hold the exposure and outcome cohorts used in this
#'                             study.
#' @param conceptSets          concept sets
#' @param conceptList          concept list
#'          
#'
#' @export
#' 
conceptIdfromJson <- function(connectionDetails = connectionDetails, 
                              cdmDatabaseSchema = cdmDatabaseSchema){ 
  
  #read json to R dataframe
  path <- system.file(package = "HAP", "json")
  conceptList <- lapply(list.files(path, full.names = T), function(x) jsonlite::fromJSON(x))
  
  includedConcept <- vector()
  includedDescendantConcept <- vector()
  excludedConcept <- vector()
  excludedDescendantConcept <- vector()
  
  for(i in 1:length(conceptList)){
    
    conceptSet <- conceptList[[i]]$items
    #Included concepts
    
    includedConcept <- c(includedConcept, conceptSet$concept$CONCEPT_ID[!conceptSet$includeDescendants])
    includedDescendantConcept <- c(includedDescendantConcept, conceptSet$concept$CONCEPT_ID[conceptSet$includeDescendants])
    
    #Excluded concepts
    excludedConcept <- c(excludedConcept, conceptSet$concept$CONCEPT_ID[conceptSet$isExcluded & !conceptSet$includeDescendants])
    excludedDescendantConcept <-c(excludedDescendantConcept, conceptSet$concept$CONCEPT_ID[conceptSet$isExcluded & conceptSet$includeDescendants])
    rm(conceptSet)
  }
  
  if(length(includedDescendantConcept) != 0){
    sql <- "select distinct descendant_concept_id as conceptId from @vocabularyDatabaseSchema.concept_ancestor 
      where ancestor_concept_id in (@conceptDescendant)"
    sql <- SqlRender::render(sql, vocabularyDatabaseSchema = cdmDatabaseSchema, conceptDescendant = includedDescendantConcept)
    sql <- SqlRender::translate(sql, targetDialect = connectionDetails$dbms)
    includedDescendantConcept <- DatabaseConnector::querySql(connection = DatabaseConnector::connect(connectionDetails), sql)
  }
  
  includedConceptId <- rbind(includedConcept, includedDescendantConcept)
  
  if(length(excludedDescendantConcept) != 0){
    sql <- "select distinct descendant_concept_id as conceptId from @vocabularyDatabaseSchema.concept_ancestor 
      where ancestor_concept_id in (@conceptDescendant)"
    sql <- SqlRender::render(sql, vocabularyDatabaseSchema = cdmDatabaseSchema, conceptDescendant = excludedDescendantConcept)
    sql <- SqlRender::translate(sql, targetDialect = connectionDetails$dbms)
    excludedDescendantConcept <- DatabaseConnector::querySql(connection = DatabaseConnector::connect(connectionDetails), sql)
  }
  
  excludedConceptId <- rbind(excludedConcept, excludedDescendantConcept)
  
  if(nrow(excludedConceptId)!=0){
    finalConceptId <- includedConceptId %>% filter(!CONCEPTID %in% excludedConceptId)  
  }else{finalConceptId <- includedConceptId}
  
  conceptSets <- finalConceptId
  
  return(conceptSets)
}

#' get drug_exposure table for creating sequence data
#'
#' @details
#' Extract concept_id from the json file of concept set
#'
#' @param connectionDetails    An object of type \code{connectionDetails} as created using the
#'                             \code{\link[DatabaseConnector]{createConnectionDetails}} function in the
#'                             DatabaseConnector package.
#' @param cdmDatabaseSchema    Schema name where your patient-level data in OMOP CDM format resides.
#'                             Note that for SQL Server, this should include both the database and
#'                             schema name, for example 'cdm_data.dbo'.
#' @param cohortDatabaseSchema Schema name where intermediate data can be stored. You will need to have
#'                             write priviliges in this schema. Note that for SQL Server, this should
#'                             include both the database and schema name, for example 'cdm_data.dbo'.
#' @param cohortTable          The name of the table that will be created in the work database schema.
#'                             This table will hold the exposure and outcome cohorts used in this
#'                             study.
#' @param cohortId             cohortId
#' @param StartDays            start days
#' @param EndDays              end days
#' @param conceptSets          concept Sets
#'          
#'
#' @export


getDrugExposureData <- function(connectionDetails = connectionDetails,
                                cdmDatabaseSchema = cdmDatabaseSchema,
                                cohortDatabaseSchema = cohortDatabaseSchema,
                                cohortTable = cohortTable,
                                cohortId = cohortId,
                                StartDays = StartDays,
                                EndDays = EndDays){
  
  path <- system.file(package = "HAP", "json")
  conceptList <- lapply(list.files(path, full.names = T), function(x) jsonlite::fromJSON(x))
  includedConcept <- vector()
  excludedConcept <- vector()
  
  for(i in 1:length(conceptList)){
    
    conceptSet <- conceptList[[i]]$items
    #Included concepts
    includedConcept <- c(includedConcept, conceptSet$concept$CONCEPT_ID)
    
    #Excluded concepts
    excludedConcept <- c(excludedConcept, conceptSet$concept$CONCEPT_ID[conceptSet$isExcluded])
    
    rm(conceptSet)
  }
  
  temporalSettings <- FeatureExtraction::createTemporalCovariateSettings(useDrugExposure = TRUE,
                                                                         temporalStartDays = StartDays:EndDays,
                                                                         temporalEndDays = StartDays:EndDays, 
                                                                         includedCovariateConceptIds = includedConcept,
                                                                         addDescendantsToInclude = T,
                                                                         excludedCovariateConceptIds = excludedConcept,
                                                                         addDescendantsToExclude = T)
  
  covariateData <- FeatureExtraction::getDbCovariateData(connectionDetails = connectionDetails,
                                                         cdmDatabaseSchema = cdmDatabaseSchema,
                                                         cohortDatabaseSchema = cohortDatabaseSchema,
                                                         cohortTable = cohortTable,
                                                         cohortId = cohortId,
                                                         rowIdField = "subject_id",
                                                         covariateSettings = temporalSettings)
  
  covariateData <- as.data.frame(covariateData$covariates)
  
  colnames(covariateData) <- c("subjectId","covariateId","covariateValue","time")
  
  drugExposureData <- covariateData %>%
    dplyr::mutate(cohortId = cohortId) %>%
    dplyr::mutate(conceptId = substr(covariateId, 1, nchar(covariateId)-3))
  
  sql <- "select * from @cohort_database_schema.@cohort_table where cohort_definition_id = @cohort_id"
  sql <- SqlRender::render(sql, 
                           cohort_database_schema = cohortDatabaseSchema, 
                           cohort_table = cohortTable, 
                           cohort_id = cohortId)
  
  cohort <- DatabaseConnector::querySql(connection = DatabaseConnector::connect(connectionDetails),
                                        sql = sql)
  
  cohort <- cohort %>% mutate(timePeriod = as.integer(COHORT_END_DATE - COHORT_START_DATE)+1)
  
  drugExposureData <- merge(x = cohort,
                            y = drugExposureData,
                            by.x = "SUBJECT_ID",
                            by.y = "subjectId",
                            all.x = T) %>%
    filter (time <= timePeriod)
  
  drugExposureData <- drugExposureData %>%
    group_by(SUBJECT_ID, COHORT_START_DATE) %>%
    mutate(timeFirst = min(time)) %>%
    group_by() %>%
    mutate(timeFirstId = time - timeFirst +1)
  
  
  drugExposure <- drugExposureData %>%
    group_by(SUBJECT_ID,
             COHORT_DEFINITION_ID,
             COHORT_START_DATE) %>%
    summarise(conceptId = unique(conceptId)) 
  
  usedConceptId <- unique(drugExposureData$conceptId)
  
  sql <- "select c.concept_name, a.descendant_concept_id as conceptId from (select * from @vocabulary_database_schema.concept_ancestor where descendant_concept_id in (@conceptId) ) a
  join (SELECT distinct * FROM @vocabulary_database_schema.concept where concept_class_id = 'Ingredient' and invalid_reason is null) c
  on c.concept_id = a.ancestor_concept_id"
  sql <- SqlRender::render(sql,
                           vocabulary_database_schema = cdmDatabaseSchema,
                           conceptId = usedConceptId)
  
  sql <- SqlRender::translate(sql,
                              targetDialect = connectionDetails$dbms)
  usedConceptIds <- DatabaseConnector::querySql(connection = DatabaseConnector::connect(connectionDetails),
                                                sql)
  drugExposureData <- merge(drugExposureData,
                            usedConceptIds,
                            by.x = "conceptId",
                            by.y = "CONCEPTID")
  
  return(drugExposureData)
}

#' get drug_exposure table for creating sequence data
#'
#' @details
#' Extract concept_id from the json file of concept set
#'
#' @param cohortDatabaseSchema Schema name where intermediate data can be stored. You will need to have
#'                             write priviliges in this schema. Note that for SQL Server, this should
#'                             include both the database and schema name, for example 'cdm_data.dbo'.
#' @param cohortTable          The name of the table that will be created in the work database schema.
#'                             This table will hold the exposure and outcome cohorts used in this
#'                             study.
#' @param cohortId             cohortId
#' @export

getSequenceData <- function(cohortDatabaseSchema = cohortDatabaseSchema,
                            cohortTable = cohortTable,
                            cohortId = cohortId){
  
  path <- system.file(package = "HAP", "json")
  conceptSets <- lapply(list.files(path, full.names = T), function(x) jsonlite::fromJSON(x))
  
  includedConcept <- vector()
  includedDescendantConcept <- vector()
  excludedConcept <- vector()
  excludedDescendantConcept <- vector()
  
  for(i in 1:length(conceptSets)){
    
    conceptSet <- conceptSets[[i]]$items
    #Included concepts
    
    includedConcept <- c(includedConcept,
                         conceptSet$concept$CONCEPT_ID[!conceptSet$includeDescendants])
    includedDescendantConcept <- c(includedDescendantConcept,
                                   conceptSet$concept$CONCEPT_ID[conceptSet$includeDescendants])
    
    #Excluded concepts
    excludedConcept <- c(excludedConcept,
                         conceptSet$concept$CONCEPT_ID[conceptSet$isExcluded & !conceptSet$includeDescendants])
    excludedDescendantConcept <-c(excludedDescendantConcept,
                                  conceptSet$concept$CONCEPT_ID[conceptSet$isExcluded & conceptSet$includeDescendants])
    
  }
  
  if(length(includedConcept) == 0) includedConcept <- 'NULL'
  if(length(includedDescendantConcept) == 0) includedDescendantConcept <- 'NULL'
  if(length(excludedConcept) == 0) excludedConcept <- 'NULL'
  if(length(excludedDescendantConcept) == 0) excludedDescendantConcept <- 'NULL'
  
  path <- system.file(package = "HAP", "sql", "sql_server", "TxPath.sql")
  sql <- SqlRender::readSql(path)
  
  sql <- SqlRender::render(sql,
                           cohortDatabaseSchema = cohortDatabaseSchema,
                           vocabularyDatabaseSchema = cdmDatabaseSchema,
                           cdmDatabaseSchema = cdmDatabaseSchema, 
                           includedConcept = includedConcept,
                           includedDescendantConcept = includedDescendantConcept, 
                           excludedConcept = excludedConcept,
                           excludedDescendantConcept = excludedDescendantConcept,
                           cohortTable = cohortTable,
                           cohortId = cohortId,
                           tempTable = "HapTempEvent",
                           minCollapseDays = 2)
  
  sql <- SqlRender::translate(sql,
                              targetDialect = connectionDetails$dbms)
  
  DatabaseConnector::executeSql(connection = DatabaseConnector::connect(connectionDetails), sql)
  
  sql <- "select * from @cohortDatabaseSchema.@tempTable"
  sql <- SqlRender::render(sql,
                           cohortDatabaseSchema = cohortDatabaseSchema,
                           tempTable = "HapTempEvent")
  
  table <- DatabaseConnector::querySql(connection = DatabaseConnector::connect(connectionDetails), sql)
  
  sql <- "drop table @cohortDatabaseSchema.@tempTable"
  
  sql <- SqlRender::render(sql,
                           cohortDatabaseSchema = cohortDatabaseSchema,
                           tempTable = "HapTempEvent")
  
  DatabaseConnector::executeSql(connection = DatabaseConnector::connect(connectionDetails), sql)
  
  return(table)
}

#' get drug_exposure table for creating sequence data
#'
#' @details
#' Extract concept_id from the json file of concept set
#'
#' @param cohortDatabaseSchema Schema name where intermediate data can be stored. You will need to have
#'                             write priviliges in this schema. Note that for SQL Server, this should
#'                             include both the database and schema name, for example 'cdm_data.dbo'.
#' @param cohortTable          The name of the table that will be created in the work database schema.
#'                             This table will hold the exposure and outcome cohorts used in this
#'                             study.
#' @param cohortId             cohortId
#' @export
#' 
totalN <- function(connectionDetails,
                   cohortDatabaseSchema,
                   cohortTable,
                   cohortId){
  sql <- "select count(*) as eventCount, count(distinct subject_id) as personCount from @cohortDatabaseSchema.@cohortTable where cohort_definition_id = @cohortId"
  sql <- SqlRender::render(sql,
                           cohortDatabaseSchema = cohortDatabaseSchema,
                           cohortTable = cohortTable,
                           cohortId = cohortId)
  sql <- SqlRender::translate(sql,
                              targetDialect = connectionDetails$dbms)
  totalN <- DatabaseConnector::querySql(connection = DatabaseConnector::connect(connectionDetails),
                                        sql)
  totalN <- totalN[1,1]
  
  return(totalN)
}


#' get table1 about drug exposure
#'
#' @details
#' Extract concept_id from the json file of concept set
#'
#' @param drugExposureData     Data extracted from drug exposure table
#' @param cohortDatabaseSchema Schema name where intermediate data can be stored. You will need to have
#'                             write priviliges in this schema. Note that for SQL Server, this should
#'                             include both the database and schema name, for example 'cdm_data.dbo'.
#' @param cohortTable          The name of the table that will be created in the work database schema.
#'                             This table will hold the exposure and outcome cohorts used in this
#'                             study.
#' @param cohortId             cohort Ids
#' @param conceptSets          concept set json files
#' 
#' @export
#' 
drugTable1 <- function(drugExposureData = drugExposureData,
                       cohortDatabaseSchema = cohortDatabaseSchema,
                       cohortTable = cohortTable,
                       cohortId = cohortId){
  
  drugExposure <- drugExposureData 

  N <- totalN(connectionDetails = connectionDetails,
              cohortDatabaseSchema = cohortDatabaseSchema,
              cohortTable = cohortTable,
              cohortId = cohortId)
  
  drugTable1 <- drugExposure %>%
    group_by(CONCEPT_NAME) %>%
    summarise(recordCount = n(), 
              eventCount = paste0(n_distinct(SUBJECT_ID, COHORT_START_DATE), " (", round(n_distinct(SUBJECT_ID, COHORT_START_DATE)/N*100,2),"%",")"))
  
  drugTable1 <- as.data.frame(drugTable1)
  
  return(drugTable1)
}

