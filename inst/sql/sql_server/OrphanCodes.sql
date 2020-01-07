{DEFAULT @cdm_database_schema = cdm_optum_extended_dod_v1027.dbo}
{DEFAULT @work_database_schema = scratch.dbo}
{DEFAULT @concept_counts_table = concept_counts}
{DEFAULT @concept_ids = 72714,72984,74125,74130}

IF OBJECT_ID('tempdb..#starting_concepts', 'U') IS NOT NULL
  DROP TABLE #starting_concepts;
  
IF OBJECT_ID('tempdb..#concept_synonyms', 'U') IS NOT NULL
  DROP TABLE #concept_synonyms;
  
IF OBJECT_ID('tempdb..#search_strings', 'U') IS NOT NULL
  DROP TABLE #search_strings;
  
IF OBJECT_ID('tempdb..#search_str_top1000', 'U') IS NOT NULL
  DROP TABLE #search_str_top1000;
  
IF OBJECT_ID('tempdb..#search_string_subset', 'U') IS NOT NULL
  DROP TABLE #search_string_subset;

IF OBJECT_ID('tempdb..#recommended_concepts', 'U') IS NOT NULL
  DROP TABLE #recommended_concepts;

-- Find directly included concept and source concepts that map to those
SELECT concept_id,
	concept_name
INTO #starting_concepts
FROM (
	SELECT c1.concept_id,
		c1.concept_name
	FROM @cdm_database_schema.concept c1
	WHERE c1.concept_id IN (@concept_ids)
	
	UNION
	
	SELECT c1.concept_id,
		c1.concept_name
	FROM @cdm_database_schema.concept_ancestor ca1
	INNER JOIN @cdm_database_schema.concept_relationship cr1
		ON ca1.descendant_concept_id = cr1.concept_id_2
			AND cr1.relationship_id = 'Maps to'
			AND cr1.invalid_reasON IS NULL
	INNER JOIN @cdm_database_schema.concept c1
		ON cr1.concept_id_1 = c1.concept_id
	WHERE ca1.ancestor_concept_id IN (@concept_ids)
	) tmp;

-- Find synonyms
SELECT cs1.concept_id,
	cs1.concept_synonym_name AS concept_name
INTO #concept_synonyms
FROM #starting_concepts sc1
INNER JOIN @cdm_database_schema.concept_synonym cs1
	ON sc1.concept_id = cs1.concept_id
WHERE concept_synonym_name IS NOT NULL;

-- Create list of search strings from concept names and synonyms, discarding those short than 5 and longer than 50 characters
SELECT concept_name,
	concept_name_length,
	concept_name_terms
INTO #search_strings
FROM (
	SELECT LOWER(concept_name) AS concept_name,
		LEN(concept_name) AS concept_name_length,
		LEN(concept_name) - LEN(REPLACE(concept_name, ' ', '')) + 1 AS concept_name_terms
	FROM #starting_concepts
	WHERE len(concept_name) > 5
		AND len(concept_name) < 50
	
	UNION
	
	SELECT LOWER(concept_name) AS concept_name,
		LEN(concept_name) AS concept_name_length,
		LEN(concept_name) - LEN(REPLACE(concept_name, ' ', '')) + 1 AS concept_name_terms
	FROM #concept_synonyms
	WHERE len(concept_name) > 5
		AND len(concept_name) < 50
	) tmp;


-- Order search terms by length (words and characters), take top 1000
SELECT concept_name,
	concept_name_length,
	concept_name_terms
INTO #search_str_top1000
FROM (
	SELECT concept_name,
		concept_name_length,
		concept_name_terms,
		row_number() OVER (
			ORDER BY concept_name_terms ASC,
				concept_name_length ASC
			) AS rn1
	FROM #search_strings
	) t1
WHERE rn1 < 1000;

-- If search string is substring of another search string, discard longer string
SELECT ss1.*
INTO #search_string_subset
FROM #search_str_top1000 ss1
LEFT JOIN #search_str_top1000 ss2
	ON ss2.concept_name_length < ss1.concept_name_length
		AND ss1.concept_name LIKE CONCAT (
			'%',
			ss2.concept_name,
			'%'
			)
WHERE ss2.concept_name IS NULL;

-- Create recommended list: concepts containing search string but not mapping to start set
SELECT DISTINCT c1.concept_id,
	c1.concept_name,
	c1.concept_count
INTO #recommended_concepts
FROM (
	SELECT c1.concept_id,
		c1.concept_name,
		a1.concept_count
	FROM @cdm_database_schema.concept c1
	LEFT JOIN #starting_concepts sc1
		ON c1.concept_id = sc1.concept_id
	INNER JOIN @work_database_schema.@concept_counts_table a1
		ON c1.concept_id = a1.concept_id
	WHERE sc1.concept_id IS NULL
	) c1
INNER JOIN #search_string_subset ss1
	ON LOWER(c1.concept_name) LIKE CONCAT (
			'%',
			ss1.concept_name,
			'%'
			);