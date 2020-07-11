getDrugExposureData <- function(StartDays = -365,
                                EndDays = 0){
  
  temporalSettings <- createTemporalCovariateSettings(useDrugExposure = TRUE,
                                                      temporalStartDays = StartDays:EndDays,
                                                      temporalEndDays = StartDays:EndDays)
  
  covariateData <- getDbCovariateData(connectionDetails = connectionDetails,
                                         cdmDatabaseSchema = cdmDatabaseSchema,
                                         cohortDatabaseSchema = cohortDatabaseSchema,
                                         cohortTable = cohortTable,
                                         cohortId = cohortId,
                                         rowIdField = "subject_id",
                                         covariateSettings = temporalSettings)
  
  covariateData <- as.data.frame(covariateData$covariates)
  
  colnames(covariateData) <- c("subjectId","covariateId","covariateValue","time")
  
  covariateData <- covariateData %>%
    dplyr::mutate(cohortId = cohortId) %>%
    dplyr::mutate(conceptId = substr(covariateId, 1, nchar(covariateId)-3))
  return(covariateData)
}

conceptIdfromJson <- function(){ 
  
  #read json to R dataframe
  path <- system.file(package = "HapTxPath", "inst/json")
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
      
      descendantConceptId <- DatabaseConnector::querySql(connection = connect(connectionDetails), sql)
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
      
      excludedDescendantConceptId <- DatabaseConnector::querySql(connection = connect(connectionDetails), sql)
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

drugExposureData <- getDrugExposureData(StartDays = StartDays, EndDays = EndDays)
drugEraData <- getDrugEraData(StartDays = StartDays, EndDays = EndDays)

# conceptIds from concept set json files
conceptSets <- conceptIdfromJson()

totalN <- function(cohortDatabaseSchema, cohortTable, cohortId){
  sql <- "select count(*) as n from @cohortDatabaseSchema.@cohortTable where cohort_definition_id = @cohortId"
  sql <- SqlRender::render(sql, cohortDatabaseSchema = cohortDatabaseSchema, cohortTable = cohortTable, cohortId = cohortId)
  sql <- SqlRender::translate(sql, targetDialect = connectionDetails$dbms)
  totalN <- DatabaseConnector::querySql(connection = connect(connectionDetails), sql)
  totalN <- totalN[1,1]
  
  return(totalN)
}

drugTable1 <- function(drugExposureData){
  
  drugExposureFiltered <- drugExposureData %>% filter(conceptId %in% unlist(conceptSets))
  
  for(i in 1:length(conceptSets)){
    if(i == 1){
      conceptList <- data.frame(setNum = i,
                                conceptconceptSetName = names(conceptSets[i]),
                                conceptId = conceptSets[[i]])
    }else{
      conceptList <- rbind(conceptList, 
                           data.frame(setNum = i,
                                      conceptconceptSetName = names(conceptSets[i]),
                                      conceptId = conceptSets[[i]]))
    }
  }
  
  drugExposure <- merge(drugExposureFiltered,
                        conceptList,
                        by = "conceptId",
                        all.x = T)
  N <- totalN(cohortDatabaseSchema, cohortTable, cohortId)
  drugTable1 <- drugExposure %>%
    group_by(conceptconceptSetName) %>%
    summarise(recordCount = n(), 
              personCount = paste0(n_distinct(subjectId), " (", round(n_distinct(subjectId)/N*100,2),"%",")"))
  
  drugTable1 <- as.data.frame(drugTable1)
  
  return(drugTable1)
}

freqBarPlot <- function(drugExposureData){
  
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
  
  plot_ly(drugTable1, x = ~conceptSetName, y = ~percentile, 
          hoverinfo = 'y', type = "bar", name = 'percentile', text = drugTable1$percentile, textposition = 'outside') %>%
    layout(xaxis = list(title = "Concept Set"), yaxis = list(title = "Proportion of patient having concept sets (%)"))
}

longitudinalPlot <- function(drugExposureData){
  
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
  
  plot_ly(drugTable1, x = ~timePeriod, y = ~period_percentile,
          color = ~conceptSetName, type = 'scatter', mode = 'lines+markers') %>%
    layout(xaxis = list(title = "Follow-up time",
                        ticktext = seq(0, (EndDays-StartDays)/365)), 
           yaxis = list(title = "Percentage", 
                        ticktext = seq(0, 100, by = 20)))  
}

dailyPlot <-function(drugExposureData){
  
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
  
  plot_ly(drugTable1, x = ~time, y = ~period_percentile,
          color = ~conceptSetName, type = 'scatter', mode = 'lines+markers') %>%
    layout(xaxis = list(title = "Follow-up time"), 
           yaxis = list(title = "Percentage", 
                        ticktext = seq(0, 100, by = 20)))  
}

sequenceData <- function(cohortDatabaseSchema, cohortTable, cohortId, pathLevel){
  
  if(pathLevel > 20 | pathLevel < 1) cat("pathLevel must be between 1 and 20")  
  
  path <- file.path(getwd(),"inst", "conceptSets")  
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
  
  path <- file.path(getwd(), "inst","sql", "TxPath.sql")  
  sql <- SqlRender::readSql(path)
  sql <- SqlRender::render(sql, cohortDatabaseSchema = cohortDatabaseSchema, vocabularyDatabaseSchema = cdmDatabaseSchema,
                           cdmDatabaseSchema = cdmDatabaseSchema, 
                           includedConcept = includedConcept, includedDescendantConcept = includedDescendantConcept, 
                           excludedConcept = excludedConcept, excludedDescendantConcept = excludedDescendantConcept,
                           cohortTable = cohortTable, cohortId = cohortId, minCollapseDays = 2)
  sql <- SqlRender::translate(sql, targetDialect = connectionDetails$dbms)
  DatabaseConnector::executeSql(connection = connect(connectionDetails), sql)
  
  sql <- "select * from @cohortDatabaseSchema.event"
  sql <- SqlRender::render(sql, cohortDatabaseSchema = cohortDatabaseSchema)
  table <- DatabaseConnector::querySql(connection = connect(connectionDetails), sql)
  
  sql <- "drop table @cohortDatabaseSchema.event"
  sql <- SqlRender::render(sql, cohortDatabaseSchema = cohortDatabaseSchema)
  DatabaseConnector::executeSql(connection = connect(connectionDetails), sql)
  
  # sequenceData for sunburstPlot
  table2 <- table
  table <- as.data.frame(table %>%
                           group_by_at(vars(c(-INDEX_YEAR, -NUM_PERSONS))) %>%
                           summarise(NUM_PERSONS = sum(NUM_PERSONS)) %>% group_by())
  
  sequenceData <- do.call(paste, c(table[,1:(1+pathLevel-1)], sep = "-"))
  sequenceData <- data.frame(pathway = sequenceData, NUM_PERSONS = table$NUM_PERSONS)
  sequenceData <- sequenceData %>%
    group_by(pathway) %>%
    summarise(sum = sum(NUM_PERSONS)) %>%
    group_by()
  
  sequenceData$pathway <- as.character(sequenceData$pathway)
  sequenceData$pathway <- paste0(stringr::str_split(sequenceData$pathway,
                                                    pattern = "-NA", simplify = T)[,1], "-end")
  return(sequenceData)
  
  #nodeLink data for sankeyPlot
  
  label <- vector()
  name <- vector()
  
  for (i in 1:pathLevel){
    if(length(as.factor(table[,i][!is.na(table[,i])]))!= 0){
      label <- c(label, paste0(levels(as.factor(table[,i][!is.na(table[,i])])), "_", i))
      name <- c(name,levels(as.factor(table[,i][!is.na(table[,i])])))
    }
  }
  
  node <- data.frame(name = name, label = label)
  node$label <- as.character(node$label)
  
  for (i in 1:pathLevel){
    if(length(as.factor(table[,i][!is.na(table[,i])]))!=0){
      pct <- data.frame(concept_name = paste0(table[,as.integer(i)], "_", i), NUM_PERSONS=table[,21])
      
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
  
  
}

sunburstPlot <- function(sequenceData){
  sunburstR::sund2b(sequenceData)
  #sunburstR::sunburst(sequenceData)
}

sankeyPlot <- function(){
  
  plot_ly(type = "sankey",
          orientation = "c",
          alpha = 0.5,
          node = list(label = node$label_2,
                      pad = 15,
                      thickness = 15,
                      x = rep(0.2, length(node$label_2)),
                      color = node$color), 
          link = list(source = link$source, target = link$target, value = link$value)
  )
}

NofPatient <- totalN(cohortDatabaseSchema, cohortTable, cohortId)
drugTable1(drugExposureData)
freqBarPlot(drugExposureData)
longitudinalPlot(drugExposureData)
dailyPlot(drugExposureData)
dailyPlot(drugEraData)
sequenceData <- sunburstData(pathLevel = 3)
sunburstPlot(sequenceData)
