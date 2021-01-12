# Copyright 2019 Observational Health Data Sciences and Informatics
#
# This file is part of PneumoniaTxPath
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#' Create the exposure and outcome cohorts
#'
#' @details
#' This function will create the exposure and outcome cohorts following the definitions included in
#' this package.
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
#' @param oracleTempSchema     Should be used in Oracle to specify a schema where the user has write
#'                             priviliges for storing temporary tables.
#' @param outputFolder         Name of local folder to place results; make sure to use forward slashes
#' @param noteTitle            Name of note
#' @param noteKeyword          Specific keyword in note for cohort extraction
#'                             (/)
#'
#' @export

createCohorts <- function(connectionDetails,
                          cdmDatabaseSchema,
                          cohortDatabaseSchema,
                          cohortTable = "cohort",
                          oracleTempSchema,
                          outputFolder, 
                          keywordSearch,
                          noteTitle,
                          noteKeyword) {
  if (!file.exists(outputFolder))
    dir.create(outputFolder)
  
  conn <- DatabaseConnector::connect(connectionDetails)
  
  .createCohorts(connection = conn,
                 cdmDatabaseSchema = cdmDatabaseSchema,
                 cohortDatabaseSchema = cohortDatabaseSchema,
                 cohortTable = cohortTable,
                 oracleTempSchema = oracleTempSchema,
                 outputFolder = outputFolder,
                 keywordSearch = keywordSearch,
                 noteTitle = noteTitle,
                 noteKeyword = noteKeyword)
  
  # Check number of subjects per cohort:
  ParallelLogger::logInfo("Counting cohorts")
  sql <- SqlRender::loadRenderTranslateSql("GetCounts.sql",
                                           "PneumoniaTxPath",
                                           dbms = connectionDetails$dbms,
                                           oracleTempSchema = oracleTempSchema,
                                           cdm_database_schema = cdmDatabaseSchema,
                                           work_database_schema = cohortDatabaseSchema,
                                           study_cohort_table = cohortTable)
  counts <- DatabaseConnector::querySql(conn, sql)
  colnames(counts) <- SqlRender::snakeCaseToCamelCase(colnames(counts))
  counts <- addCohortNames(counts)
  utils::write.csv(counts, file.path(outputFolder, "CohortCounts.csv"), row.names = FALSE)
  
  DatabaseConnector::disconnect(conn)
}

addCohortNames <- function(data, IdColumnName = "cohortDefinitionId", nameColumnName = "cohortName") {
  pathToCsv <- system.file("settings", "CohortsToCreate.csv", package = "PneumoniaTxPath")
  cohortsToCreate <- utils::read.csv(pathToCsv)
  
  idToName <- data.frame(cohortId = c(cohortsToCreate$cohortId),
                         cohortName = c(as.character(cohortsToCreate$name)))
  idToName <- idToName[order(idToName$cohortId), ]
  idToName <- idToName[!duplicated(idToName$cohortId), ]
  names(idToName)[1] <- IdColumnName
  names(idToName)[2] <- nameColumnName
  data <- merge(data, idToName, all.x = TRUE)
  # Change order of columns:
  idCol <- which(colnames(data) == IdColumnName)
  if (idCol < ncol(data) - 1) {
    data <- data[, c(1:idCol, ncol(data) , (idCol+1):(ncol(data)-1))]
  }
  return(data)
}

.createCohorts <- function(connection,
                           cdmDatabaseSchema,
                           vocabularyDatabaseSchema = cdmDatabaseSchema,
                           cohortDatabaseSchema,
                           cohortTable,
                           oracleTempSchema,
                           outputFolder,
                           keywordSearch,
                           noteTitle,
                           noteKeyword) {
  
    title <- noteTitle
    note_title <- vector()
    for (i in 1:length(title)){
      if(i==1){note_title <- paste0("note_title like", " '%", title[i], "%'")}
      else{
        text <- paste0("or note_title like", " '%", title[i], "%'")
        note_title <- paste(note_title, text)  
      }

    keyword <- noteKeyword
    note_keyword <- vector()
    for (i in 1:length(keyword)){
      if(i==1){note_keyword <- paste0("note_text like", " '%", keyword[i], "%'")}
      else{
        text <- paste0("or note_text like", " '%", keyword[i], "%'")
        note_keyword <- paste(note_keyword, text)  
      }
    }
    
  }
  # Create study cohort table structure:
  sql <- SqlRender::loadRenderTranslateSql(sqlFilename = "CreateCohortTable.sql",
                                           packageName = "PneumoniaTxPath",
                                           dbms = attr(connection, "dbms"),
                                           oracleTempSchema = oracleTempSchema,
                                           cohort_database_schema = cohortDatabaseSchema,
                                           cohort_table = cohortTable)
  DatabaseConnector::executeSql(connection, sql, progressBar = FALSE, reportOverallTime = FALSE)
  
  
  # Insert rule names in cohort_inclusion table:
  pathToCsv <- system.file("cohorts", "InclusionRules.csv", package = "PneumoniaTxPath")
  inclusionRules <- readr::read_csv(pathToCsv, col_types = readr::cols()) 
  inclusionRules <- data.frame(cohort_definition_id = inclusionRules$cohortId,
                               rule_sequence = inclusionRules$ruleSequence,
                               name = inclusionRules$ruleName)
  DatabaseConnector::insertTable(connection = connection,
                                 tableName = "#cohort_inclusion",
                                 data = inclusionRules,
                                 dropTableIfExists = TRUE,
                                 createTable = TRUE,
                                 tempTable = TRUE,
                                 oracleTempSchema = oracleTempSchema)
  
  
  # Instantiate cohorts:
  pathToCsv <- system.file("settings", "CohortsToCreate.csv", package = "PneumoniaTxPath")
  cohortsToCreate <- read.csv(pathToCsv)
  for (i in 1:nrow(cohortsToCreate)) {
    writeLines(paste("Creating cohort:", cohortsToCreate$name[i]))
    sql <- SqlRender::loadRenderTranslateSql(sqlFilename = paste0(cohortsToCreate$name[i], ".sql"),
                                             packageName = "PneumoniaTxPath",
                                             dbms = attr(connection, "dbms"),
                                             oracleTempSchema = oracleTempSchema,
                                             cdm_database_schema = cdmDatabaseSchema,
                                             vocabulary_database_schema = vocabularyDatabaseSchema,
                                             target_database_schema = cohortDatabaseSchema,
                                             target_cohort_table = cohortTable,
                                             target_cohort_id = cohortsToCreate$cohortId[i],
                                             keywordSearch = shQuote(substr(keywordSearch,1,1)),
                                             noteTitle = note_title,
                                             noteKeyword = note_keyword)
    DatabaseConnector::executeSql(connection, sql)
  }
  
  # Fetch cohort counts:
  sql <- "SELECT cohort_definition_id, COUNT(*) AS count FROM @cohort_database_schema.@cohort_table GROUP BY cohort_definition_id"
  sql <- SqlRender::render(sql,
                           cohort_database_schema = cohortDatabaseSchema,
                           cohort_table = cohortTable)
  sql <- SqlRender::translate(sql, targetDialect = attr(connection, "dbms"))
  counts <- DatabaseConnector::querySql(connection, sql)
  names(counts) <- SqlRender::snakeCaseToCamelCase(names(counts))
  counts <- merge(counts, data.frame(cohortDefinitionId = cohortsToCreate$cohortId,
                                     cohortName  = cohortsToCreate$name))
  write.csv(counts, file.path(outputFolder, "CohortCounts.csv"))
  
  
  # Fetch inclusion rule stats and drop tables:
  fetchStats <- function(tableName) {
    sql <- "SELECT * FROM #@table_name"
    sql <- SqlRender::render(sql, table_name = tableName)
    sql <- SqlRender::translate(sql = sql, 
                                targetDialect = attr(connection, "dbms"),
                                oracleTempSchema = oracleTempSchema)
    stats <- DatabaseConnector::querySql(connection, sql)
    names(stats) <- SqlRender::snakeCaseToCamelCase(names(stats))
    fileName <- file.path(outputFolder, paste0(SqlRender::snakeCaseToCamelCase(tableName), ".csv"))
    readr::write_csv(x = stats, file = fileName)
    
    sql <- "TRUNCATE TABLE #@table_name; DROP TABLE #@table_name;"
    sql <- SqlRender::render(sql, table_name = tableName)
    sql <- SqlRender::translate(sql = sql, 
                                targetDialect = attr(connection, "dbms"),
                                oracleTempSchema = oracleTempSchema)
    DatabaseConnector::executeSql(connection, sql)
  }
  fetchStats("cohort_inclusion")
  fetchStats("cohort_inc_result")
  fetchStats("cohort_inc_stats")
  fetchStats("cohort_summary_stats")
}

