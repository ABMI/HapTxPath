select r1.cohort_definition_id, r1.measurement_concept_id, concept.concept_name, count(*) as recordCounts, count(distinct r1.subject_id) as personCounts from (
  select c.*, m.measurement_id, measurement_concept_id, measurement_date, value_as_concept_id, value_source_value
  from (select * from @cohort_database_schema.@cohort_table where cohort_definition_id = @cohort_definition_id) c
  left join @cdm_database_schema.measurement m
  on c.subject_id = m.person_id
  where m.measurement_date >= c.cohort_start_date and m.measurement_date <= c.cohort_end_date
  and measurement_concept_id in (
    3023368,3026008, 3002619, 3025941, 3023419, 3009986, 3003714,
    3016914, 3025037, 3045330, 3024194, 3012475, 3029151, 3011797,
    3007234, 36303793, 3039448, 3015778, 3008334, 3040827, 3006761,
    3023419,3029151
  ) and m.value_as_concept_id != 0
) r1
left join @vocabulary_database_schema.concept concept
on r1.value_as_concept_id = concept.concept_id
group by cohort_definition_id, measurement_concept_id, concept_name
having count(distinct r1.subject_id) > @minCount