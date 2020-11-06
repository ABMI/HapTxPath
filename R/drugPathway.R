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
                           savePlot = T,
                           StartDays = 0,
                           EndDays = 365){
  
  # conceptIds from concept set json files
  conceptSets <- conceptIdfromJson(connectionDetails = connectionDetails, 
                                   cdmDatabaseSchema = cdmDatabaseSchema)
  
  pathToCsv <- system.file("settings", "CohortsToCreate.csv", package = "HapTxPath")
  cohortsToCreate <- read.csv(pathToCsv)
  
  for(cohortId in cohortsToCreate[1:5,3]){
    #get drug exposure data
    drugExposureData <- getDrugExposureData(connectionDetails = connectionDetails,
                                            cdmDatabaseSchema = cdmDatabaseSchema,
                                            cohortDatabaseSchema = cohortDatabaseSchema,
                                            cohortTable = cohortTable,
                                            cohortId = cohortId,
                                            StartDays = StartDays,
                                            EndDays = EndDays,
                                            conceptSets = conceptSets)
    
    #drugExposure data to sequence data
    sequenceData <- getSequenceData(cohortDatabaseSchema = cohortDatabaseSchema,
                                    cohortTable = cohortTable,
                                    cohortId = cohortId)
    
    #Results
    n <- totalN(connectionDetails = connectionDetails, 
                cohortDatabaseSchema = cohortDatabaseSchema,
                cohortTable = cohortTable,
                cohortId = cohortId)
    
    drugTable1 <- drugTable1(cohortDatabaseSchema = cohortDatabaseSchema,
                             cohortTable = cohortTable, 
                             cohortId = cohortId,
                             drugExposureData = drugExposureData,
                             conceptSets = conceptSets)
    
    ParallelLogger::logInfo("Saving the table and pathway plots")
    
    #Save
    
    savefolder <- file.path(outputFolder, "drugPathway", cohortId)
    if (!file.exists(savefolder))
      dir.create(savefolder, recursive = TRUE)
    
    write.csv(n, file = file.path(savefolder, "totalN.csv"))
    write.csv(drugTable1, file = file.path(savefolder, "table1.csv"))
    
    if(savePlot == T) PlotTxPathway(cohortDatabaseSchema,
                                    cohortTable,
                                    cohortId,
                                    conceptSets,
                                    drugExposureData,
                                    sequenceData,
                                    savefolder,
                                    StartDays = 0,
                                    EndDays = 365,
                                    pathLevel = 3)
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
#' @param outputFolder         Name of local folder where the results were generated; make sure to use forward slashes
#'                             (/). Do not use a folder on a network drive since this greatly impacts
#'                             performance.
#'
#' @export
#' 
conceptIdfromJson <- function(connectionDetails = connectionDetails, 
                              cdmDatabaseSchema = cdmDatabaseSchema){ 
  
  #read json to R dataframe
  path <- system.file(package = "HapTxPath", "json")
  conceptSets <- lapply(list.files(path, full.names = T), function(x) jsonlite::fromJSON(x))
  
  conceptList <- vector(mode = "list", length = length(list.files(path)))
  for(i in 1:length(conceptSets)){
    conceptSet <- conceptSets[[i]]$items
    #Included concepts
    concept <- conceptSet$concept$CONCEPT_ID[!conceptSet$includeDescendants]
    descendant <- conceptSet$concept$CONCEPT_ID[conceptSet$includeDescendants]
    includedConceptId <- data.frame(CONCEPTID = concept)
    
    if(length(descendant)!=0){
      sql <- "select distinct descendant_concept_id as conceptId 
      from @vocabularyDatabaseSchema.concept_ancestor 
      where ancestor_concept_id in (@conceptDescendant)"
      sql <- SqlRender::render(sql, vocabularyDatabaseSchema = cdmDatabaseSchema, conceptDescendant = descendant)
      sql <- SqlRender::translate(sql, targetDialect = connectionDetails$dbms)
      
      descendantConceptId <- DatabaseConnector::querySql(connection = DatabaseConnector::connect(connectionDetails), sql)
      includedConceptId <- rbind(includedConceptId, descendantConceptId)
    }
    
    #Excluded concepts
    excludedConcept <- conceptSet$concept$CONCEPT_ID[conceptSet$isExcluded & !conceptSet$includeDescendants]
    excludedDescendant <- conceptSet$concept$CONCEPT_ID[conceptSet$isExcluded & conceptSet$includeDescendants]
    excludedConceptId <- data.frame(CONCEPTID = excludedConcept)
    if(length(excludedDescendant)!=0){
      sql <- "select distinct descendant_concept_id as conceptId 
      from @vocabularyDatabaseSchema.concept_ancestor 
      where ancestor_concept_id in (@conceptDescendant)"
      sql <- SqlRender::render(sql, vocabularyDatabaseSchema = cdmDatabaseSchema, conceptDescendant = excludedDescendant)
      sql <- SqlRender::translate(sql, targetDialect = connectionDetails$dbms)
      
      excludedDescendantConceptId <- DatabaseConnector::querySql(connection = DatabaseConnector::connect(connectionDetails), sql)
      excludedConceptId <- rbind(excludedConceptId, excludedDescendantConceptId)
    }
    
    #do not consider "Mapped concepts"
    
    if(nrow(excludedConceptId)!=0){
      finalConceptId <- includedConceptId %>% filter(!CONCEPTID %in% excludedConceptId)  
    }else{finalConceptId <- includedConceptId}
    
    conceptList[i] <- finalConceptId
    
  }
  
  names(conceptList) <- c(substr(c(list.files(path)),1,nchar(c(list.files(path)))-5))
  
  return(conceptList)
  
}


getDrugExposureData <- function(connectionDetails = connectionDetails,
                                cdmDatabaseSchema = cdmDatabaseSchema,
                                cohortDatabaseSchema = cohortDatabaseSchema,
                                cohortTable = cohortTable,
                                cohortId = cohortId,
                                StartDays = StartDays,
                                EndDays = EndDays,
                                conceptSets = conceptSets){
  
  temporalSettings <- FeatureExtraction::createTemporalCovariateSettings(useDrugExposure = TRUE,
                                                                         temporalStartDays = StartDays:EndDays,
                                                                         temporalEndDays = StartDays:EndDays)
  
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
  sql <- SqlRender::render(sql, cohort_database_schema = cohortDatabaseSchema, cohort_table = cohortTable, cohort_id = cohortId)
  cohort <- querySql(connection = conn, sql = sql)
  cohort <- cohort %>% mutate(timePeriod = as.integer(COHORT_END_DATE - COHORT_START_DATE))
  
  drugExposureData <- merge(x = cohort, y = drugExposureData, by.x = "SUBJECT_ID", by.y = "subjectId", all.x = T) %>% filter (time-1 <= timePeriod)
  
  drugExposureData <- drugExposureData %>%
    filter(conceptId %in% unlist(conceptSets))
  
  drugExposureData <- drugExposureData %>%
    group_by(SUBJECT_ID, COHORT_START_DATE) %>%
    mutate(timeFirst = min(time)) %>%
    group_by() %>%
    mutate(timeFirstId = time - timeFirst +1)
  
  return(drugExposureData)
  
}

getSequenceData <- function(cohortDatabaseSchema = cohortDatabaseSchema,
                            cohortTable = cohortTable,
                            cohortId = cohortId){
  
  path <- system.file(package = "HapTxPath", "json")
  conceptSets <- lapply(list.files(path, full.names = T), function(x) jsonlite::fromJSON(x))
  
  includedConcept <- vector()
  includedDescendantConcept <- vector()
  excludedConcept <- vector()
  excludedDescendantConcept <- vector()
  
  for(i in 1:length(conceptSets)){
    
    conceptSet <- conceptSets[[i]]$items
    #Included concepts
    
    includedConcept <- c(includedConcept, conceptSet$concept$CONCEPT_ID[!conceptSet$includeDescendants])
    includedDescendantConcept <- c(includedDescendantConcept, conceptSet$concept$CONCEPT_ID[conceptSet$includeDescendants])
    
    #Excluded concepts
    excludedConcept <- c(excludedConcept, conceptSet$concept$CONCEPT_ID[conceptSet$isExcluded & !conceptSet$includeDescendants])
    excludedDescendantConcept <-c(excludedDescendantConcept, conceptSet$concept$CONCEPT_ID[conceptSet$isExcluded & conceptSet$includeDescendants])
    
  }
  
  if(length(includedConcept) == 0) includedConcept <- 'NULL'
  if(length(includedDescendantConcept) == 0) includedDescendantConcept <- 'NULL'
  if(length(excludedConcept) == 0) excludedConcept <- 'NULL'
  if(length(excludedDescendantConcept) == 0) excludedDescendantConcept <- 'NULL'
  
  path <- system.file(package = "HapTxPath", "sql", "sql_server", "TxPath.sql")
  sql <- SqlRender::readSql(path)
  sql <- SqlRender::render(sql, cohortDatabaseSchema = cohortDatabaseSchema, vocabularyDatabaseSchema = cdmDatabaseSchema,
                           cdmDatabaseSchema = cdmDatabaseSchema, 
                           includedConcept = includedConcept, includedDescendantConcept = includedDescendantConcept, 
                           excludedConcept = excludedConcept, excludedDescendantConcept = excludedDescendantConcept,
                           cohortTable = cohortTable, cohortId = cohortId, minCollapseDays = 2)
  sql <- SqlRender::translate(sql, targetDialect = connectionDetails$dbms)
  DatabaseConnector::executeSql(connection = DatabaseConnector::connect(connectionDetails), sql)
  
  sql <- "select * from @cohortDatabaseSchema.event"
  sql <- SqlRender::render(sql, cohortDatabaseSchema = cohortDatabaseSchema)
  table <- DatabaseConnector::querySql(connection = DatabaseConnector::connect(connectionDetails), sql)
  
  sql <- "drop table @cohortDatabaseSchema.event"
  sql <- SqlRender::render(sql, cohortDatabaseSchema = cohortDatabaseSchema)
  DatabaseConnector::executeSql(connection = DatabaseConnector::connect(connectionDetails), sql)
  
  return(table)
}


totalN <- function(connectionDetails, cohortDatabaseSchema, cohortTable, cohortId){
  sql <- "select count(*) as eventCount, count(distinct subject_id) as personCount from @cohortDatabaseSchema.@cohortTable where cohort_definition_id = @cohortId"
  sql <- SqlRender::render(sql, cohortDatabaseSchema = cohortDatabaseSchema, cohortTable = cohortTable, cohortId = cohortId)
  sql <- SqlRender::translate(sql, targetDialect = connectionDetails$dbms)
  totalN <- DatabaseConnector::querySql(connection = DatabaseConnector::connect(connectionDetails), sql)
  totalN <- totalN[1,1]
  
  return(totalN)
}

drugTable1 <- function(drugExposureData = drugExposureData,
                       cohortDatabaseSchema = cohortDatabaseSchema,
                       cohortTable = cohortTable,
                       cohortId = cohortId,
                       conceptSets = conceptSets){
  
  conceptList <- data.frame(setNum = NULL, conceptSetName = NULL, conceptId = NULL)
  
  for(i in 1:length(conceptSets)){
    conceptList <- rbind(conceptList, data.frame(data.frame(setNum = i,
                                                            conceptSetName = names(conceptSets[i]),
                                                            conceptId = conceptSets[[i]])))
  }
  
  drugExposure <- merge(drugExposureData,
                        conceptList,
                        by = "conceptId",
                        all.x = T)
  N <- totalN(connectionDetails = connectionDetails,
              cohortDatabaseSchema = cohortDatabaseSchema,
              cohortTable = cohortTable,
              cohortId = cohortId)
  drugTable1 <- drugExposure %>%
    group_by(conceptSetName) %>%
    summarise(recordCount = n(), 
              personCount = paste0(n_distinct(SUBJECT_ID), " (", round(n_distinct(SUBJECT_ID)/N*100,2),"%",")"))
  
  drugTable1 <- as.data.frame(drugTable1)
  
  return(drugTable1)
}

