SELECT c.SUBJECT_ID as person_id, c.cohort_start_date AS index_date,
c.cohort_end_date, op.observation_period_start_date, op.observation_period_end_date
into #Tx_cohort 
from (select *
  FROM @cohortDatabaseSchema.@cohortTable
  where COHORT_DEFINITION_ID = @cohortId) c
  left join (select distinct person_id, observation_period_start_date,
    observation_period_end_date from @cdmDatabaseSchema.observation_period) op
  on c.SUBJECT_ID = op.person_id;
  
select concept_id into #codeset from @vocabularyDatabaseSchema.concept where concept_id in (@includedConcept);

Insert into #codeset 
select descendant_concept_id as concept_id 
from @vocabularyDatabaseSchema.concept_ancestor 
where ancestor_concept_id in (@includedDescendantConcept);

delete #codeset where concept_id in (
select distinct concept_id from @vocabularyDatabaseSchema.concept where concept_id in (@excludedConcept)
UNION select distinct descendant_concept_id from @vocabularyDatabaseSchema.concept_ancestor where ancestor_concept_id in (@excludedDescendantConcept));


select de1.person_id, de1.index_date, de1.drug_start_date, de1.drug_end_date, de1.drug_concept_id, c1.concept_name, 
DENSE_RANK() over (partition by de1.person_id, de1.index_date order by de1.drug_start_date) as rn1
into #drug_seq
from
(select de0.person_id, de0.drug_concept_id, c1.index_date, de0.drug_exposure_start_date as drug_start_date, de0.drug_exposure_end_date as drug_end_date
from @cdmDatabaseSchema.drug_exposure de0
inner join #Tx_cohort c1
on de0.person_id = c1.person_id
where drug_concept_id in (select distinct concept_id from #codeset) and
c1.index_date <= de0.drug_exposure_start_date and c1.cohort_end_date >= de0.drug_exposure_start_date
) de1
inner join @vocabularyDatabaseSchema.concept c1
on de1.drug_concept_id = c1.concept_id;

select ds.*, d.concept_name as ingredient_name
into #drug_seq2
from #drug_seq ds 
JOIN (
select distinct descendant_concept_id, STUFF((SELECT '/' + concept_name from (
  select * from (
  	select distinct ancestor_concept_id, descendant_concept_id
  	from @vocabularyDatabaseSchema.concept_ancestor 
  	where descendant_concept_id in (select distinct drug_concept_id from #drug_seq)
  	) ac
  join (
    select concept_id, concept_name 
    from @vocabularyDatabaseSchema.concept 
    where vocabulary_id = 'RxNorm' and concept_class_id = 'Ingredient'
    ) c
  on ac.ancestor_concept_id = c.concept_id 
) d
where descendant_concept_id = a.descendant_concept_id for XML PATH('')),1,1,'') as concept_name 
from 
(select * from (
	select distinct ancestor_concept_id, descendant_concept_id
	from @vocabularyDatabaseSchema.concept_ancestor 
	where descendant_concept_id in (select distinct drug_concept_id from #drug_seq)
	) ac
  join (
    select concept_id, concept_name 
    from @vocabularyDatabaseSchema.concept 
    where vocabulary_id = 'RxNorm' and concept_class_id = 'Ingredient'
  ) c
  on ac.ancestor_concept_id = c.concept_id  ) as a
) d
on ds.drug_concept_id = d.descendant_concept_id;

select c.person_id, c.index_date, c.drug_start_date, max(c.drug_end_date) as drug_end_date, c.rn1, c.ingredient_name , c.flag3
into #drug_seq3  
from (
select distinct b.person_id, b.index_date, b.drug_start_date, b.drug_end_date, 
DENSE_RANK() over (partition by b.person_id, b.index_date order by b.drug_start_date) as rn1, 
b.ingredient_name, ISNULL(b.flag3,1) as flag3
from (
select *, dense_rank() over(partition by  person_id,  index_date, flag  order by rn1 )as flag2, 
case when (flag != 0 and dense_rank() over(partition by  person_id, index_date, flag order by rn1 ) > @minCollapseDays -1) then 2
when (flag = 0) then 0 end flag3
from (
select distinct ds2.person_id, ds2.index_date, ds2.drug_start_date, ds2.drug_end_date, ds2.rn1, ds2.ingredient_name , cast(ds3.flag as int) as flag
from #drug_seq2 ds2 
left join (
select distinct person_id, index_date, drug_start_date, rn1, ingredient_name,
STUFF((SELECT 1 from (select distinct person_id, index_date, drug_start_date, drug_end_date, rn1, ingredient_name from #drug_seq2) ds2 where person_id = ds.person_id and
index_date = ds.index_date and drug_start_date = ds.drug_start_date and rn1 = ds.rn1 for XML PATH('')),1,1,'') AS flag
from #drug_seq2 ds
) ds3
on ds2.person_id = ds3.person_id and ds2.index_date = ds3.index_date and ds2.drug_start_date = ds3.drug_start_date and ds2.rn1 = ds3.rn1
) a 
) b
) c 
group by c.person_id, c.index_date, c.drug_start_date, c.rn1, c.ingredient_name, c.flag3;

select a.*, datediff(dd, a.drug_start_date, a.drug_end_date) as gap 
into #drug_seq4 
from (
select distinct person_id, index_date, drug_start_date, drug_end_date, rn1, flag3,
ISNULL(STUFF((SELECT ', ' + ingredient_name from (select distinct person_id, index_date, drug_start_date, drug_end_date, rn1, ingredient_name, flag3 from #drug_seq3) ds2 where ds2.person_id = ds3.person_id and
ds2.index_date = ds3.index_date and ds2.drug_start_date = ds3.drug_start_date and ds2.rn1 = ds3.rn1 and flag3 = 2 for XML PATH('')),1,1,''), ds3.ingredient_name) AS ingredient_name
from #drug_seq3 ds3 ) a
order by person_id, index_date, rn1 ;

select person_id, index_date, ingredient_name, 
case when (flag3 != 2) then min(drug_start_date) when(flag3 = 2) then dateadd(dd, -1, min(drug_start_date)) end sdt, 
max(drug_end_date) as edt, count(*) as cnt, rn2-rn3 as grp,
row_number() over (partition by person_id, index_date order by  min(drug_start_date) ) as rn4, flag3
into #drug_seq5
from (
select person_id, index_date, drug_start_date, drug_end_date, ingredient_name, flag3,
row_number() over (partition by person_id, index_date, ingredient_name order by drug_start_date) rn2, 
row_number() over(partition by person_id, index_date order by drug_start_date) rn3 from (select * from #drug_seq4 where flag3 != 1 or (flag3 =1 and gap != 0)) c
) a
group by person_id, index_date, ingredient_name, rn2-rn3, flag3;

select year(d1.index_date) as index_year,
	d1.ingredient_name as d1_concept_name,
	 d2.ingredient_name as d2_concept_name,
	 d3.ingredient_name as d3_concept_name,
	 d4.ingredient_name as d4_concept_name,
	 d5.ingredient_name as d5_concept_name,
	 d6.ingredient_name as d6_concept_name,
	 d7.ingredient_name as d7_concept_name,
	 d8.ingredient_name as d8_concept_name,
	 d9.ingredient_name as d9_concept_name,
	 d10.ingredient_name as d10_concept_name,
	 d11.ingredient_name as d11_concept_name,
	 d12.ingredient_name as d12_concept_name,
	 d13.ingredient_name as d13_concept_name,
	 d14.ingredient_name as d14_concept_name,
	 d15.ingredient_name as d15_concept_name,
	 d16.ingredient_name as d16_concept_name,
	 d17.ingredient_name as d17_concept_name,
	 d18.ingredient_name as d18_concept_name,
	 d19.ingredient_name as d19_concept_name,
	 d20.ingredient_name as d20_concept_name,
	count(d1.person_id) as num_persons
into #final
from
(select *
from #drug_seq5
where rn4 = 1) d1
left join
(select *
from #drug_seq5
where rn4 = 2) d2
on d1.person_id = d2.person_id and d1.index_date = d2.index_date
left join
(select *
from #drug_seq5
where rn4 = 3) d3
on d1.person_id = d3.person_id and d1.index_date = d3.index_date
left join
(select *
from #drug_seq5
where rn4 = 4) d4
on d1.person_id = d4.person_id and d1.index_date = d4.index_date
left join
(select *
from #drug_seq5
where rn4 = 5) d5
on d1.person_id = d5.person_id and d1.index_date = d5.index_date
left join
(select *
from #drug_seq5
where rn4 = 6) d6
on d1.person_id = d6.person_id and d1.index_date = d6.index_date
left join
(select *
from #drug_seq5
where rn4 = 7) d7
on d1.person_id = d7.person_id and d1.index_date = d7.index_date
left join
(select *
from #drug_seq5
where rn4 = 8) d8
on d1.person_id = d8.person_id and d1.index_date = d8.index_date
left join
(select *
from #drug_seq5
where rn4 = 9) d9
on d1.person_id = d9.person_id and d1.index_date = d9.index_date
left join
(select *
from #drug_seq5
where rn4 = 10) d10
on d1.person_id = d10.person_id and d1.index_date = d10.index_date
left join
(select *
from #drug_seq5
where rn4 = 11) d11
on d1.person_id = d11.person_id and d1.index_date = d11.index_date
left join
(select *
from #drug_seq5
where rn4 = 12) d12
on d1.person_id = d12.person_id and d1.index_date = d12.index_date
left join
(select *
from #drug_seq5
where rn4 = 13) d13
on d1.person_id = d13.person_id and d1.index_date = d13.index_date
left join
(select *
from #drug_seq5
where rn4 = 14) d14
on d1.person_id = d14.person_id and d1.index_date = d14.index_date
left join
(select *
from #drug_seq5
where rn4 = 15) d15
on d1.person_id = d15.person_id and d1.index_date = d15.index_date
left join
(select *
from #drug_seq5
where rn4 = 16) d16
on d1.person_id = d16.person_id and d1.index_date = d16.index_date
left join
(select *
from #drug_seq5
where rn4 = 17) d17
on d1.person_id = d17.person_id and d1.index_date = d17.index_date
left join
(select *
from #drug_seq5
where rn4 = 18) d18
on d1.person_id = d18.person_id and d1.index_date = d18.index_date
left join
(select *
from #drug_seq5
where rn4 = 19) d19
on d1.person_id = d19.person_id and d1.index_date = d19.index_date
left join
(select *
from #drug_seq5
where rn4 = 20) d20
on d1.person_id = d20.person_id and d1.index_date = d20.index_date
group by 
  year(d1.index_date),
	d1.ingredient_name,
	 d2.ingredient_name,
	 d3.ingredient_name,
	 d4.ingredient_name,
	 d5.ingredient_name,
	 d6.ingredient_name,
	 d7.ingredient_name,
	 d8.ingredient_name,
	 d9.ingredient_name,
	 d10.ingredient_name,
	 d11.ingredient_name,
	 d12.ingredient_name,
	 d13.ingredient_name,
	 d14.ingredient_name,
	 d15.ingredient_name,
	 d16.ingredient_name,
	 d17.ingredient_name,
	 d18.ingredient_name,
	 d19.ingredient_name,
	 d20.ingredient_name;

select * into @cohortDatabaseSchema.event from #final order by num_persons desc;


truncate table #Tx_cohort;
drop table #Tx_cohort;
truncate table #codeset;
drop table #codeset;
truncate table #drug_seq;
drop table #drug_seq;
truncate table #drug_seq2;
drop table #drug_seq2;
truncate table #drug_seq3;
drop table #drug_seq3;
truncate table #drug_seq4;
drop table #drug_seq4;
truncate table #drug_seq5;
drop table #drug_seq5;
truncate table #final;
drop table #final;