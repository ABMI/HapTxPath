# @file Plots.R
#
# Copyright 2020 Observational Health Data Sciences and Informatics
#
# This file is part of HAP
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


#' Plot the outcome incidence over time
#'
#' @details
#' This creates a survival plot that can be used to pick a suitable time-at-risk period
#'
#' @param cohortDatabaseSchema Schema name where intermediate data can be stored. You will need to have
#'                             write priviliges in this schema. Note that for SQL Server, this should
#'                             include both the database and schema name, for example 'cdm_data.dbo'.
#' @param cohortTable          The name of the table that will be created in the work database schema.
#'                             This table will hold the exposure and outcome cohorts used in this
#'                             study.
#' @param cohortId             The number of cohort id      
#' @param conceptSets          Concept set json files created from ATLAS
#' @param drugExposureData     The covariate data of drug exposure table obtaining by FeatureExtraction package
#' @param sequenceData         The data reformatted by drug exposure date for visualization
#' @param outputFolder         Name of local folder to place results; make sure to use forward slashes
#'                             (/)
#' @param StartDays            The first date from index date (cohort start date) for investigating drug sequence 
#' @param EndDays              The last date from index date (cohort start date) for investigating drug sequence
#' @param pathLevel            Level of pathway depth  
#'
#' @import dplyr
#' @import plotly
#' @return
#' TRUE if it ran 
#'
#' @export

PlotTxPathway <- function(cohortDatabaseSchema,
                          cohortTable,
                          cohortId,
                          conceptSets,
                          drugExposureData,
                          sequenceData,
                          outputFolder,
                          StartDays = 0,
                          EndDays = 365,
                          pathLevel = 2){
  
  saveFolder <- file.path(outputFolder, "plots")
  
  if (!file.exists(saveFolder))
    dir.create(saveFolder, recursive = TRUE)
  
  freqBarPlot <- freqBarPlot(cohortDatabaseSchema = cohortDatabaseSchema,
                             cohortTable = cohortTable,
                             cohortId = cohortId,
                             conceptSets = conceptSets,
                             drugExposureData = drugExposureData)
  
  htmlwidgets::saveWidget(freqBarPlot, file = file.path(saveFolder, "freqBarPlot.html"))
  # Not use in HAP cohort
  # longitudinalPlot <- longitudinalPlot(cohortDatabaseSchema,
  #                                      cohortTable,
  #                                      cohortId,
  #                                      conceptSets,
  #                                      drugExposureData,
  #                                      StartDays = 0, 
  #                                      EndDays = 365)
  # export(longitudinalPlot, file = file.path(saveFolder, "longitudinalPlot.png"))
  
  dailyPlot <- dailyPlot(cohortDatabaseSchema = cohortDatabaseSchema,
                         cohortTable = cohortTable,
                         cohortId = cohortId,
                         conceptSets = conceptSets,
                         drugExposureData = drugExposureData)
  
  htmlwidgets::saveWidget(dailyPlot, file = file.path(saveFolder, "dailyPlot.html"))
  
  dailyGroupPlot <- dailyGroupPlot(cohortDatabaseSchema = cohortDatabaseSchema,
                         cohortTable = cohortTable,
                         cohortId = cohortId,
                         conceptSets = conceptSets,
                         drugExposureData = drugExposureData)
  
  htmlwidgets::saveWidget(dailyGroupPlot, file = file.path(saveFolder, "dailyGroupPlot.html"))
  
  sunburstPlot <- sunburstPlot(sequenceData = sequenceData,
                               pathLevel = pathLevel)
  htmlwidgets::saveWidget(sunburstPlot, file = file.path(saveFolder, "sunburst.html"))
  
  
  sankeyPlot <- sankeyPlot(sequenceData = sequenceData,
                           cohortDatabaseSchema = cohortDatabaseSchema,
                           cohortTable = cohortTable,
                           cohortId = cohortId,
                           pathLevel = pathLevel)
  htmlwidgets::saveWidget(sankeyPlot, file = file.path(saveFolder, "sankey.html"))
  
  
}

freqBarPlot <- function(cohortDatabaseSchema,
                        cohortTable,
                        cohortId,
                        conceptSets,
                        drugExposureData){
  
  N <- totalN(connectionDetails = connectionDetails,
              cohortDatabaseSchema = cohortDatabaseSchema,
              cohortTable = cohortTable,
              cohortId = cohortId)
  drugTable1 <- drugExposureData %>%
    group_by(CONCEPT_NAME) %>%
    summarise(records = n(), 
              person = n_distinct(SUBJECT_ID), 
              percentile = round(person/N*100,2)) %>% group_by()
  
  drugTable1 <- as.data.frame(drugTable1)
  xtitle <- list(title = "Antibiotics")
  ytitle <- list(title = "Proportion of patient having prescription of antibiotics (%)")
  Plot <- plotly::plot_ly(drugTable1, x = ~CONCEPT_NAME, y = ~percentile, 
                          hoverinfo = 'y', type = "bar", name = 'percentile', text = drugTable1$percentile, textposition = 'outside') %>%
    plotly::layout(xaxis = xtitle, yaxis = ytitle)
  
  return(Plot)
  
}

longitudinalPlot <- function(cohortDatabaseSchema,
                             cohortTable,
                             cohortId,
                             conceptSets,
                             drugExposureData,
                             StartDays = 0, 
                             EndDays = 365){
  
  drugExposureDataT <- transform(drugExposureData,
                                 timePeriod = cut(time, breaks = c(seq(StartDays,EndDays, by = 365)),
                                                  right = T, 
                                                  labels = c(1:(length(seq(StartDays, EndDays, by = 365))-1))-0.5))
  
  periodN <- drugExposureDataT %>% group_by(timePeriod) %>% summarise(n = n_distinct(SUBJECT_ID)) %>% group_by()
  
  drugExposureFilteredT <- drugExposureDataT %>% filter(conceptId %in% unlist(conceptSets))
  conceptList <- data.frame(setNum = NULL, conceptSetName = NULL, conceptId = NULL)
  
  for(i in 1:length(conceptSets)){
    
    conceptList <- rbind(conceptList, 
                         data.frame(setNum = i,
                                    conceptSetName = names(conceptSets[i]),
                                    conceptId = conceptSets[[i]]))
  }
  
  drugExposureT <- merge(drugExposureFilteredT,
                         conceptList,
                         by = "conceptId",
                         all.x = T)
  N <- totalN(cohortDatabaseSchema, cohortTable, cohortId)
  drugTable1 <- drugExposureT %>%
    group_by(conceptSetName, timePeriod) %>%
    summarise(records = n(), 
              person = n_distinct(SUBJECT_ID), 
              percentile = round(person/N*100,2)) %>% group_by()
  
  drugTable1 <- as.data.frame(drugTable1)
  drugTable1 <- merge(drugTable1, periodN, by = "timePeriod", all.x = T) %>%
    mutate(period_percentile = round(person/n*100,2))
  
  Plot <- plotly::plot_ly(drugTable1, x = ~timePeriod, y = ~period_percentile,
                          color = ~conceptSetName, type = 'scatter', mode = 'lines+markers') %>%
    layout(xaxis = list(title = "Follow-up time",
                        ticktext = seq(0, (EndDays-StartDays)/365)), 
           yaxis = list(title = "Percentage", 
                        ticktext = seq(0, 100, by = 20)))  
  
  return(Plot)
  
}

dailyPlot <-function(cohortDatabaseSchema,
                     cohortTable,
                     cohortId,
                     conceptSets,
                     drugExposureData){
  
  
  # 
  # conceptList <- data.frame(setNum = NULL, conceptSetName = NULL, conceptId = NULL)
  # 
  # for(i in 1:length(conceptSets)){
  #   
  #   conceptList <- rbind(conceptList, 
  #                        data.frame(setNum = i,
  #                                   conceptSetName = names(conceptSets[i]),
  #                                   conceptId = conceptSets[[i]]))
  # }
  drugExposure <- drugExposureData
  
  periodN <- drugExposure %>% group_by(timeFirstId) %>% summarise(n = n_distinct(SUBJECT_ID)) %>% group_by()
  
  N <- totalN(connectionDetails, cohortDatabaseSchema, cohortTable, cohortId)
  drugTable1 <- drugExposure %>%
    group_by(CONCEPT_NAME, timeFirstId) %>%
    summarise(records = n(), 
              person = n_distinct(SUBJECT_ID), 
              percentile = round(person/N*100,2)) %>% group_by()
  
  drugTable1 <- as.data.frame(drugTable1)
  drugTable1 <- merge(drugTable1, periodN, by= "timeFirstId", all.x = T) %>%
    mutate(period_percentile = round(person/n*100,2))
  
  Plot <- plotly::plot_ly(drugTable1, x = ~timeFirstId, y = ~period_percentile,
                          color = ~CONCEPT_NAME, type = 'scatter', mode = 'lines+markers') %>% 
    plotly::layout(xaxis = list(title = "Follow-up time"), 
                   yaxis = list(title = "Percentage", 
                                ticktext = seq(0, 100, by = 20)))  
  
  return(Plot)
  
}

dailyGroupPlot <-function(cohortDatabaseSchema,
                     cohortTable,
                     cohortId,
                     conceptSets,
                     drugExposureData){
  
  
  # 
  # conceptList <- data.frame(setNum = NULL, conceptSetName = NULL, conceptId = NULL)
  # 
  # for(i in 1:length(conceptSets)){
  #   
  #   conceptList <- rbind(conceptList, 
  #                        data.frame(setNum = i,
  #                                   conceptSetName = names(conceptSets[i]),
  #                                   conceptId = conceptSets[[i]]))
  # }
  pathToCsv <- system.file("settings", "drugClass.csv", package = "HAP")
  drugClass <- read.csv(pathToCsv)
  drugExposure <- merge(drugExposureData, drugClass, by.x = "CONCEPT_NAME", by.y = "conceptName")
  
  periodN <- drugExposure %>% group_by(timeFirstId) %>% summarise(n = n_distinct(SUBJECT_ID)) %>% group_by()
  
  N <- totalN(connectionDetails, cohortDatabaseSchema, cohortTable, cohortId)
  drugTable1 <- drugExposure %>%
    group_by(drugClass, timeFirstId) %>%
    summarise(records = n(), 
              person = n_distinct(SUBJECT_ID), 
              percentile = round(person/N*100,2)) %>% group_by()
  
  drugTable1 <- as.data.frame(drugTable1)
  drugTable1 <- merge(drugTable1, periodN, by= "timeFirstId", all.x = T) %>%
    mutate(period_percentile = round(person/n*100,2))
  
  Plot <- plotly::plot_ly(drugTable1, x = ~timeFirstId, y = ~period_percentile,
                          color = ~drugClass, type = 'scatter', mode = 'lines+markers') %>% 
    plotly::layout(xaxis = list(title = "Follow-up time"), 
                   yaxis = list(title = "Percentage", 
                                ticktext = seq(0, 100, by = 20)))  
  
  return(Plot)
  
}

sunburstPlot <- function(sequenceData, pathLevel){
  
  sequenceData <- as.data.frame(sequenceData %>%
                                  group_by_at(vars(c(-INDEX_YEAR, -NUM_PERSONS))) %>%
                                  summarise(NUM_PERSONS = sum(NUM_PERSONS)) %>% group_by())
  
  sequenceCollapse <- do.call(paste, c(sequenceData[,1:(1+pathLevel-1)], sep = "-"))
  sequenceCollapse <- data.frame(pathway = sequenceCollapse, NUM_PERSONS = sequenceData$NUM_PERSONS)
  sequenceCollapse <- sequenceCollapse %>%
    group_by(pathway) %>%
    summarise(sum = sum(NUM_PERSONS)) %>%
    group_by()
  
  sequenceCollapse$pathway <- as.character(sequenceCollapse$pathway)
  sequenceCollapse$pathway <- paste0(stringr::str_split(sequenceCollapse$pathway,
                                                        pattern = "-NA", simplify = T)[,1], "-end")
  
  Plot <- sunburstR::sund2b(sequenceCollapse)
  #Plot <- sunburstR::sunburst(sequenceCollapse)
  
  return(Plot)
}

sankeyPlot <- function(sequenceData,
                       cohortDatabaseSchema,
                       cohortTable,
                       cohortId,
                       pathLevel){
  
  sequenceData <- as.data.frame(sequenceData %>%
                                  group_by_at(vars(c(-INDEX_YEAR, -NUM_PERSONS))) %>%
                                  summarise(NUM_PERSONS = sum(NUM_PERSONS)) %>% group_by())
  
  #nodeLink data for sankeyPlot
  
  if(pathLevel > 20 | pathLevel < 1) cat("pathLevel must be between 1 and 20")  
  
  
  label <- vector()
  name <- vector()
  
  for (i in 1:pathLevel){
    if(length(as.factor(sequenceData[,i][!is.na(sequenceData[,i])]))!= 0){
      label <- c(label, paste0(levels(as.factor(sequenceData[,i][!is.na(sequenceData[,i])])), "_", i))
      name <- c(name,levels(as.factor(sequenceData[,i][!is.na(sequenceData[,i])])))
    }
  }
  
  n <- totalN(connectionDetails = connectionDetails,
              cohortDatabaseSchema = cohortDatabaseSchema,
              cohortTable = cohortTable,
              cohortId = cohortId)
  
  node <- data.frame(name = name, label = label)
  node$label <- as.character(node$label)
  
  for (i in 1:pathLevel){
    if(length(as.factor(sequenceData[,i][!is.na(sequenceData[,i])]))!=0){
      pct <- data.frame(concept_name = paste0(sequenceData[,as.integer(i)], "_", i), NUM_PERSONS=sequenceData[,21])
      
      if(!"pctTable" %in% ls()){
        pctTable<-as.data.frame(pct %>%
                                  group_by(concept_name) %>%
                                  summarise(personCount = sum(NUM_PERSONS),
                                            percent = round(sum(NUM_PERSONS)/n*100,2)) %>% group_by() ) 
      }else{pctTable <- rbind(pctTable,
                              as.data.frame(pct %>%
                                              group_by(concept_name) %>%
                                              summarise(personCount = sum(NUM_PERSONS),
                                                        percent = round(sum(NUM_PERSONS)/n*100,2)) %>% group_by()))}
    }
  }
  
  node <- merge(node, pctTable, by.x = "label", by.y = "concept_name", all.x = T)
  node$label_2 <- as.factor(paste0(node$name, " (n=", node$personCount, ",", node$percent, "%)"))
  color <- data.frame(name = levels(node$name), color = rainbow(length(levels(node$name))))
  node <- merge(node, color, by = "name", all.x = T)
  
  for (i in 1:pathLevel){
    if(i == 1){
      
      link <- data.frame(source = paste0(sequenceData[,as.integer(i)], "_", i),
                         target = paste0(sequenceData[,as.integer(i+1)], "_", i+1), NUM_PERSONS=sequenceData[,21])
      link <- as.data.frame(link %>%
                              group_by(source, target) %>%
                              summarise(value = sum(NUM_PERSONS)) %>% group_by())
    }else{
      link2 <- as.data.frame(data.frame(source = paste0(sequenceData[,as.integer(i)], "_", i),
                                        target = paste0(sequenceData[,as.integer(i+1)], "_", i+1), NUM_PERSONS=sequenceData[,21]) %>%
                               group_by(source, target) %>%
                               summarise(value = sum(NUM_PERSONS)) %>% group_by())
      link <- rbind(link, link2)
    }
  }
  
  link$source <- match(link$source, node$label) -1
  link$target <- match(link$target, node$label) -1
  
  
  Plot <- plotly::plot_ly(type = "sankey",
                          orientation = "c",
                          alpha = 0.5,
                          node = list(label = node$label_2,
                                      pad = 15,
                                      thickness = 15,
                                      x = rep(0.2, length(node$label_2)),
                                      color = node$color), 
                          link = list(source = link$source, target = link$target, value = link$value)
  )
  
  return(Plot)
}
