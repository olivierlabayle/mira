-- We initialise all subqueries
WITH studies AS (
    SELECT nct_id, phase, study_type, official_title AS study_title
    FROM ctgov.studies
),
-- Multiple conditions for the same nct_id
conditions AS (
    SELECT nct_id, array_agg(downcase_name) AS condition_names
    FROM ctgov.conditions
    GROUP BY nct_id
),
study_references AS (
    SELECT nct_id, pmid, reference_type
    FROM ctgov.study_references
),
designs AS (
    SELECT nct_id, primary_purpose
    FROM ctgov.designs
),
brief_summaries AS (
    SELECT nct_id, description AS brief_description
    FROM ctgov.brief_summaries
),
detailed_summaries AS (
    SELECT nct_id, description AS detailed_description
    FROM ctgov.detailed_descriptions
),
sponsors AS (
    SELECT nct_id, agency_class, lead_or_collaborator, name AS sponsor_name
    FROM ctgov.sponsors
),
interventions AS (
    SELECT id AS intervention_id, nct_id, intervention_type, name AS intervention_name
    FROM ctgov.interventions
    WHERE intervention_type IN ('BIOLOGICAL', 'DRUG')
),
dgi AS (
    SELECT nct_id, design_group_id, intervention_id
    FROM ctgov.design_group_interventions
),
design_groups AS (
    SELECT id AS design_group_id, nct_id, group_type, title AS group_title
    FROM ctgov.design_groups
),
/*
Here we aggregate interventions' information for each trial arm (group).
If the group has no interventions it is dropped (this can happen if a non ('BIOLOGICAL', 'DRUG') intervention existed)
- Even if the design_group_id is null, the intervention is kept as postgres can group on NULL values
- The order of the left joins is important to make sure interventions are retrieved even though they don't have a matching group
*/
group_interventions AS (
    SELECT
        i.nct_id,
        dg.design_group_id,
        jsonb_agg(
            jsonb_build_object(
                'intervention_id',   i.intervention_id,
                'intervention_type', i.intervention_type,
                'intervention_name', i.intervention_name
            )
            ORDER BY i.intervention_name
        ) FILTER (WHERE i.intervention_id IS NOT NULL) AS intervention_info
    FROM interventions i
    LEFT JOIN dgi ON i.nct_id = dgi.nct_id AND i.intervention_id = dgi.intervention_id
    LEFT JOIN design_groups dg ON dgi.nct_id = dg.nct_id AND dgi.design_group_id = dg.design_group_id
    GROUP BY i.nct_id, dg.design_group_id
    HAVING count(i.intervention_id) > 0
),
/*
Finally we add another level of aggregation at the study level where we aggregate all trial arms (groups)
*/
study_arms AS (
    SELECT
        gi.nct_id,
        jsonb_agg(
            jsonb_build_object(
                'group_id', gi.design_group_id,
                'group_title', CASE
                                WHEN dg.design_group_id IS NULL THEN 'NO_ARM_MATCH'
                                WHEN dg.group_title IS NULL     THEN 'UNTITLED'
                                ELSE dg.group_title
                            END,
                'group_type', CASE
                                WHEN dg.design_group_id IS NULL THEN 'NO_ARM_MATCH'
                                WHEN dg.group_type IS NULL      THEN 'UNCLASSIFIED'
                                ELSE dg.group_type
                            END,
                'interventions', gi.intervention_info
            )
            ORDER BY gi.design_group_id
        ) AS groups
    FROM group_interventions gi
    LEFT JOIN design_groups dg ON gi.nct_id = dg.nct_id AND gi.design_group_id = dg.design_group_id
    GROUP BY gi.nct_id
)
-- Final query
SELECT 
    s.nct_id, 
    s.phase, 
    s.study_type, 
    s.study_title,
    bs.brief_description,
    ds.detailed_description,
    sp.agency_class,
    sp.lead_or_collaborator, 
    sp.sponsor_name,
    d.primary_purpose,
    sr.pmid,
    sr.reference_type,
    c.condition_names,
    sa.groups
FROM studies s
LEFT JOIN study_arms sa ON s.nct_id = sa.nct_id
LEFT JOIN brief_summaries bs ON s.nct_id = bs.nct_id
LEFT JOIN detailed_summaries ds ON s.nct_id = ds.nct_id
LEFT JOIN sponsors sp ON s.nct_id = sp.nct_id
LEFT JOIN designs d ON s.nct_id = d.nct_id
LEFT JOIN study_references sr ON s.nct_id = sr.nct_id
LEFT JOIN conditions c ON s.nct_id = c.nct_id
LIMIT 20;


select * from ctgov.interventions where nct_id = 'NCT00000858';
select * from ctgov.design_groups where nct_id = 'NCT00000858';
select * from ctgov.design_group_interventions where nct_id = 'NCT00000116';

select count(DISTINCT nct_id) from ctgov.study_references;
select count(*) from ctgov.study_references;

-- Unicity checks ok on nct_id: brief_summaries, conditions, 