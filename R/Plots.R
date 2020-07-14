# @file Plots.R
#
# Copyright 2020 Observational Health Data Sciences and Informatics
#
# This file is part of HapTxPath
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
#' @param cohortDatabaseSchema               The plpData object returned by running getPlpData()
#' @param cohortTable             The cohort id corresponding to the outcome 
#' @param cohortId  Remove patients who have had the outcome before their target cohort index date from the plot
#' @param conceptSets       (integer) The time-at-risk starts at target cohort index date plus this value
#' @param drugExposureData       (integer) The time-at-risk ends at target cohort index date plus this value 
#' @param sequenceData           (binary) Whether to include a table at the bottom  of the plot showing the number of people at risk over time
#' @param outputFolder             (binary) Whether to include a confidence interval
#' @param StartDays              (string) The label for the y-axis  
#' @param EndDays              (string) The label for the y-axis          
#' @param pathLevel              (string) The label for the y-axis   
#' 
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
                          pathLevel = 3){
  
  saveFolder <- file.path(outputFolder, "plots")
    
  if (!file.exists(saveFolder))
    dir.create(saveFolder, recursive = TRUE)
  
  freqBarPlot <- freqBarPlot(cohortDatabaseSchema,
                             cohortTable,
                             cohortId,
                             conceptSets,
                             drugExposureData)
  
  export(freqBarPlot, file = file.path(saveFolder, "freqBarPlot.png"))
  
  # Not use in HAP cohort
  # longitudinalPlot <- longitudinalPlot(cohortDatabaseSchema,
  #                                      cohortTable,
  #                                      cohortId,
  #                                      conceptSets,
  #                                      drugExposureData,
  #                                      StartDays = 0, 
  #                                      EndDays = 365)
  # export(longitudinalPlot, file = file.path(saveFolder, "longitudinalPlot.png"))
  
  dailyPlot <- dailyPlot(cohortDatabaseSchema,
                         cohortTable,
                         cohortId,
                         conceptSets,
                         drugExposureData)
  
  export(dailyPlot, file = file.path(saveFolder, "dailyPlot.png"))
  
  sunburstPlot <- sunburstPlot(sequenceData)
  if(saveAsHtml == T) htmlwidgets::saveWidget(sunburstPlot, file = file.path(outputFolder, "sunburst.html"))
  htmlwidgets::saveWidget(sunburstPlot, file = file.path(outputFolder, "sunburst.png"))
  
  sankeyPlot <- sankeyPlot(sequenceData, pathLevel)
  if(saveAsHtml == T) htmlwidgets::saveWidget(sankeyPlot, file = file.path(outputFolder, "sankey.html"))
  htmlwidgets::saveWidget(sankeyPlot, file = file.path(outputFolder, "sankey.png"))
  
}

freqBarPlot <- function(cohortDatabaseSchema,
                        cohortTable,
                        cohortId,
                        conceptSets,
                        drugExposureData){
  
  drugExposureFiltered <- drugExposureData %>% filter(conceptId %in% unlist(conceptSets))
  
  for(i in 1:length(conceptSets)){
    if(i == 1){
      conceptList <- data.frame(setNum = i,
                                conceptSetName = names(conceptSets[i]),
                                conceptId = conceptSets[[i]])
    }else{
      conceptList <- rbind(conceptList, 
                           data.frame(setNum = i,
                                      conceptSetName = names(conceptSets[i]),
                                      conceptId = conceptSets[[i]]))
    }
  }
  
  drugExposure <- merge(drugExposureFiltered,
                        conceptList,
                        by = "conceptId",
                        all.x = T)
  N <- totalN(cohortDatabaseSchema, cohortTable, cohortId)
  drugTable1 <- drugExposure %>%
    group_by(conceptSetName) %>%
    summarise(records = n(), 
              person = n_distinct(subjectId), 
              percentile = round(person/N*100,2))
  
  drugTable1 <- as.data.frame(drugTable1)
  
  freqBarPlot <- plot_ly(drugTable1, x = ~conceptSetName, y = ~percentile, 
          hoverinfo = 'y', type = "bar", name = 'percentile', text = drugTable1$percentile, textposition = 'outside') %>%
    layout(xaxis = list(title = "Concept Set"), yaxis = list(title = "Proportion of patient having concept sets (%)"))
  
  return(freqBarPlot)

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
  
  periodN <- drugExposureDataT %>% group_by(timePeriod) %>% summarise(n = n_distinct(subjectId))
  
  drugExposureFilteredT <- drugExposureDataT %>% filter(conceptId %in% unlist(conceptSets))
  
  for(i in 1:length(conceptSets)){
    if(i == 1){
      conceptList <- data.frame(setNum = i,
                                conceptSetName = names(conceptSets[i]),
                                conceptId = conceptSets[[i]])
    }else{
      conceptList <- rbind(conceptList, 
                           data.frame(setNum = i,
                                      conceptSetName = names(conceptSets[i]),
                                      conceptId = conceptSets[[i]]))
    }
  }
  
  drugExposureT <- merge(drugExposureFilteredT,
                         conceptList,
                         by = "conceptId",
                         all.x = T)
  N <- totalN(cohortDatabaseSchema, cohortTable, cohortId)
  drugTable1 <- drugExposureT %>%
    group_by(conceptSetName, timePeriod) %>%
    summarise(records = n(), 
              person = n_distinct(subjectId), 
              percentile = round(person/N*100,2))
  
  drugTable1 <- as.data.frame(drugTable1)
  drugTable1 <- merge(drugTable1, periodN, by = "timePeriod", all.x = T) %>%
    mutate(period_percentile = round(person/n*100,2))
  
  longitudinalPlot <- plot_ly(drugTable1, x = ~timePeriod, y = ~period_percentile,
                              color = ~conceptSetName, type = 'scatter', mode = 'lines+markers') %>%
    layout(xaxis = list(title = "Follow-up time",
                        ticktext = seq(0, (EndDays-StartDays)/365)), 
           yaxis = list(title = "Percentage", 
                        ticktext = seq(0, 100, by = 20)))  
  
  return(longitudinalPlot)
  
}

dailyPlot <-function(drugExposureData, conceptSets, cohortDatabaseSchema, cohortTable, cohortId){
  
  periodN <- drugExposureData %>% group_by(time) %>% summarise(n = n_distinct(subjectId))
  
  drugExposureFiltered <- drugExposureData %>% filter(conceptId %in% unlist(conceptSets))
  
  for(i in 1:length(conceptSets)){
    if(i == 1){
      conceptList <- data.frame(setNum = i,
                                conceptSetName = names(conceptSets[i]),
                                conceptId = conceptSets[[i]])
    }else{
      conceptList <- rbind(conceptList, 
                           data.frame(setNum = i,
                                      conceptSetName = names(conceptSets[i]),
                                      conceptId = conceptSets[[i]]))
    }
  }
  
  drugExposure <- merge(drugExposureFiltered,
                        conceptList,
                        by = "conceptId",
                        all.x = T)
  N <- totalN(cohortDatabaseSchema, cohortTable, cohortId)
  drugTable1 <- drugExposure %>%
    group_by(conceptSetName, time) %>%
    summarise(records = n(), 
              person = n_distinct(subjectId), 
              percentile = round(person/N*100,2))
  
  drugTable1 <- as.data.frame(drugTable1)
  drugTable1 <- merge(drugTable1, periodN, by = "time", all.x = T) %>%
    mutate(period_percentile = round(person/n*100,2))
  
  dailyPlot <- plot_ly(drugTable1, x = ~time, y = ~period_percentile,
                       color = ~conceptSetName, type = 'scatter', mode = 'lines+markers') %>% 
    layout(xaxis = list(title = "Follow-up time"), 
           yaxis = list(title = "Percentage", 
           ticktext = seq(0, 100, by = 20)))  
  
  return(dailyPlot)
  
}

sunburstPlot <- function(sequenceData){
  
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
  
  sunburstPlot <- sunburstR::sund2b(sequenceCollapse)
  
  return(sunburstPlot)
}

sankeyPlot <- function(sequenceData, cohortDatabaseSchema, cohortTable, cohortId, pathLevel){
  
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
  
  node <- data.frame(name = name, label = label)
  node$label <- as.character(node$label)
  
  for (i in 1:pathLevel){
    if(length(as.factor(sequenceData[,i][!is.na(sequenceData[,i])]))!=0){
      pct <- data.frame(concept_name = paste0(sequenceData[,as.integer(i)], "_", i), NUM_PERSONS=sequenceData[,21])
      
      if(!"pctTable" %in% ls()){
        pctTable<-as.data.frame(pct %>%
                                  group_by(concept_name) %>%
                                  summarise(personCount = sum(NUM_PERSONS),
                                            percent = round(sum(NUM_PERSONS)/n*100,2)))
      }else{pctTable <- rbind(pctTable,
                              as.data.frame(pct %>%
                                              group_by(concept_name) %>%
                                              summarise(personCount = sum(NUM_PERSONS),
                                                        percent = round(sum(NUM_PERSONS)/n*100,2))))}
    }
  }
  
  node <- merge(node, pctTable, by.x = "label", by.y = "concept_name", all.x = T)
  node$label_2 <- as.factor(paste0(node$name, " (n=", node$personCount, ",", node$percent, "%)"))
  color <- data.frame(name = levels(node$name), color = rainbow(length(levels(node$name))))
  node <- merge(node, color, by = "name", all.x = T)
  
  n <- totalN(cohortDatabaseSchema, cohortTable, cohortId)
  for (i in 1:pathLevel){
    if(i == 1){
      
      link <- data.frame(source = paste0(table[,as.integer(i)], "_", i),
                         target = paste0(table[,as.integer(1+i)], "_", i+1), NUM_PERSONS=table[,21])
      link <- as.data.frame(link %>%
                              group_by(source, target) %>%
                              summarise(value = sum(NUM_PERSONS)) %>% group_by())
    }else{
      link2 <- as.data.frame(data.frame(source = paste0(table[,as.integer(i)], "_", i),
                                        target = paste0(table[,as.integer(1+i)], "_", i+1), NUM_PERSONS=table[,21]) %>%
                               group_by(source, target) %>%
                               summarise(value = sum(NUM_PERSONS)) %>% group_by())
      link <- rbind(link, link2)
    }
  }
  
  link$source <- match(link$source, node$label) -1
  link$target <- match(link$target, node$label) -1
  
  
  sankeyPlot <- plot_ly(type = "sankey",
          orientation = "c",
          alpha = 0.5,
          node = list(label = node$label_2,
                      pad = 15,
                      thickness = 15,
                      x = rep(0.2, length(node$label_2)),
                      color = node$color), 
          link = list(source = link$source, target = link$target, value = link$value)
  )
  
  return(sankeyPlot)
}
