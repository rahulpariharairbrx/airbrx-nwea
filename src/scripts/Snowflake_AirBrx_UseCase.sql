//9. Quick validation + a Spring 2025 view for BI / AirBrx

USE DATABASE NWEA;
USE SCHEMA ASSESSMENT_BSD;

//1. Quick validation + a Spring 2025 view for BI / AirBrx
-- Basic counts
SELECT COUNT(*) AS districts FROM DISTRICT;
SELECT COUNT(*) AS schools   FROM SCHOOL;
SELECT COUNT(*) AS educators FROM EDUCATOR;
SELECT COUNT(*) AS classes   FROM CLASS;
SELECT COUNT(*) AS students  FROM STUDENT;
SELECT COUNT(*) AS results   FROM TEST_RESULTS;

-- Spring 2025 scores by school & subject (for cache-rule scenarios)
SELECT
  d.NAME  AS district,
  sc.NAME AS school,
  c.SUBJECT,
  COUNT(*)            AS num_results,
  AVG(tr.SCORE)       AS avg_score,
  AVG(tr.PERCENTILE)  AS avg_percentile
FROM TEST_RESULTS tr
JOIN STUDENT s   ON tr.STUDENT_ID = s.STUDENT_ID
JOIN CLASS c     ON tr.CLASS_ID   = c.CLASS_ID
JOIN SCHOOL sc   ON tr.SCHOOL_ID  = sc.SCHOOL_ID
JOIN DISTRICT d  ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE tr.TERM = 'Spring 2025'
GROUP BY d.NAME, sc.NAME, c.SUBJECT
ORDER BY d.NAME, sc.NAME, c.SUBJECT;


//Use Case 1 – District Term Summary by School & Subject (Fall/Winter/Spring 2025)

//Goal: A top-level dashboard for leadership (Ben/Amit-style “North Star” view) showing, for each school and subject, how students performed by term in 2025.
SELECT
  d.NAME        AS DISTRICT,
  sc.NAME       AS SCHOOL,
  c.SUBJECT,
  tr.TERM,
  COUNT(DISTINCT s.STUDENT_ID) AS num_students,
  COUNT(*)                     AS num_results,
  AVG(tr.SCORE)                AS avg_score,
  AVG(tr.PERCENTILE)           AS avg_percentile,
  AVG(tr.SCALED_SCORE)         AS avg_scaled_score
FROM TEST_RESULTS tr
JOIN STUDENT  s ON tr.STUDENT_ID = s.STUDENT_ID
JOIN CLASS    c ON tr.CLASS_ID   = c.CLASS_ID
JOIN SCHOOL   sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d  ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE tr.TEST_YEAR = 2025
  AND tr.TERM IN ('Fall 2025', 'Winter 2025', 'Spring 2025')
GROUP BY
  d.NAME, sc.NAME, c.SUBJECT, tr.TERM
ORDER BY
  d.NAME, sc.NAME, c.SUBJECT, tr.TERM;

//Use Case 2 – Fall 2025 vs Winter 2025 Class Progress (Inner Join on Terms)
//Goal: For each class and subject, show how average scores changed from Fall 2025 to Winter 2025. This is a classic “growth between benchmark windows” dashboard.
//Query (self-join on TEST_RESULTS, INNER JOIN required to have both terms):

WITH fall AS (
  SELECT
    CLASS_ID,
    SUBJECT,
    AVG(SCORE) AS avg_score_fall
  FROM TEST_RESULTS
  WHERE TEST_YEAR = 2025
    AND TERM = 'Fall 2025'
  GROUP BY CLASS_ID, SUBJECT
),
winter AS (
  SELECT
    CLASS_ID,
    SUBJECT,
    AVG(SCORE) AS avg_score_winter
  FROM TEST_RESULTS
  WHERE TEST_YEAR = 2025
    AND TERM = 'Winter 2025'
  GROUP BY CLASS_ID, SUBJECT
)
SELECT
  d.NAME        AS DISTRICT,
  sc.NAME       AS SCHOOL,
  c.NAME        AS CLASS_NAME,
  c.SUBJECT,
  f.avg_score_fall,
  w.avg_score_winter,
  (w.avg_score_winter - f.avg_score_fall) AS score_delta
FROM fall f
JOIN winter w
  ON f.CLASS_ID = w.CLASS_ID
 AND f.SUBJECT  = w.SUBJECT
JOIN CLASS  c ON f.CLASS_ID = c.CLASS_ID
JOIN SCHOOL sc ON c.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
ORDER BY
  d.NAME, sc.NAME, c.NAME, c.

  
//Use Case 3 – Fall vs Winter vs Spring 2025 Per-Student Growth (Inner & Outer Join Patterns)
//Goal: Drill-down on a single student or a set of students to see growth across all three terms. This is great for educator conferences / parent meetings.
//This version uses conditional aggregation instead of multiple joins (BI tools love this shape):  
  
  SELECT
  s.STUDENT_ID,
  s.FIRST_NAME,
  s.LAST_NAME,
  sc.NAME      AS SCHOOL,
  c.NAME       AS CLASS_NAME,
  c.SUBJECT,
  -- Term-specific scores
  AVG(CASE WHEN tr.TERM = 'Fall 2025'   THEN tr.SCORE END) AS score_fall,
  AVG(CASE WHEN tr.TERM = 'Winter 2025' THEN tr.SCORE END) AS score_winter,
  AVG(CASE WHEN tr.TERM = 'Spring 2025' THEN tr.SCORE END) AS score_spring
FROM STUDENT s
JOIN TEST_RESULTS tr ON s.STUDENT_ID = tr.STUDENT_ID
JOIN CLASS c         ON tr.CLASS_ID   = c.CLASS_ID
JOIN SCHOOL sc       ON tr.SCHOOL_ID  = sc.SCHOOL_ID
WHERE tr.TEST_YEAR = 2025
  AND sc.NAME IN ('West View', 'ISB', 'BASE')     -- district filter
GROUP BY
  s.STUDENT_ID, s.FIRST_NAME, s.LAST_NAME,
  sc.NAME, c.NAME, c.SUBJECT
ORDER BY
  sc.NAME, c.NAME, c.SUBJECT, s.LAST_NAME, s.FIRST_NAME;

  //We can parameterize a student, educator, or school easily by adding AND s.STUDENT_ID = :student_id or similar.
  
 
//Use Case 4 – Educator Dashboard with Classes & Missing Test Data (LEFT OUTER JOIN)
//Goal: For each educator, show each class and whether they actually have test results for specific terms. This uses LEFT JOIN so classes without assessments still show up (important for QA / data completeness dashboards).
//Query (LEFT OUTER JOIN from CLASS → TEST_RESULTS):
  
  SELECT
  e.EDUCATOR_ID,
  e.FIRST_NAME || ' ' || e.LAST_NAME AS EDUCATOR_NAME,
  sc.NAME      AS SCHOOL,
  c.CLASS_ID,
  c.NAME       AS CLASS_NAME,
  c.SUBJECT,
  -- Term counts: if zero, indicates missing assessments
  COUNT(CASE WHEN tr.TERM = 'Fall 2025'   THEN 1 END) AS fall_results_count,
  COUNT(CASE WHEN tr.TERM = 'Winter 2025' THEN 1 END) AS winter_results_count,
  COUNT(CASE WHEN tr.TERM = 'Spring 2025' THEN 1 END) AS spring_results_count
FROM CLASS c
JOIN SCHOOL sc   ON c.SCHOOL_ID   = sc.SCHOOL_ID
JOIN DISTRICT d  ON sc.DISTRICT_ID = d.DISTRICT_ID
JOIN EDUCATOR e  ON c.EDUCATOR_ID = e.EDUCATOR_ID
LEFT JOIN TEST_RESULTS tr
  ON c.CLASS_ID = tr.CLASS_ID
 AND tr.TEST_YEAR = 2025
GROUP BY
  e.EDUCATOR_ID,
  e.FIRST_NAME, e.LAST_NAME,
  sc.NAME, c.CLASS_ID, c.NAME, c.SUBJECT
ORDER BY
  sc.NAME, EDUCATOR_NAME, c.NAME, c.SUBJECT;

 // This view is perfect to cache for educators (high fanout, read-heavy, low write frequency).
  
//Use Case 5 – “At-Risk” Students Missing Any 2025 Term (Outer Join / Anti-Join Logic)
//Goal: Identify students who do not have all three terms (Fall/Winter/Spring 2025) recorded. This is a classic data-quality + intervention dashboard.
//Query (uses aggregation + HAVING to simulate outer/anti-join behavior):

  SELECT
  s.STUDENT_ID,
  s.FIRST_NAME,
  s.LAST_NAME,
  sc.NAME AS SCHOOL,
  COUNT(DISTINCT tr.TERM)           AS terms_present,
  LISTAGG(DISTINCT tr.TERM, ', ')   AS term_list
FROM STUDENT s
JOIN SCHOOL sc ON s.SCHOOL_ID = sc.SCHOOL_ID
LEFT JOIN TEST_RESULTS tr
  ON s.STUDENT_ID = tr.STUDENT_ID
 AND tr.TEST_YEAR = 2025
 AND tr.TERM IN ('Fall 2025', 'Winter 2025', 'Spring 2025')
GROUP BY
  s.STUDENT_ID, s.FIRST_NAME, s.LAST_NAME, sc.NAME
HAVING COUNT(DISTINCT tr.TERM) < 3
ORDER BY
  sc.NAME, s.LAST_NAME, s.FIRST_NAME;

 //This is a great candidate for aggressive caching: dashboard is read-heavy, recomputed nightly or hourly.
  
//Use Case 6 – Cross-Subject Correlation (Math vs Reading, Same Term)
//Goal: Show, for each student, how they perform in Math vs Reading in the same term (e.g., Fall 2025). This uses an INNER JOIN within TEST_RESULTS for two subjects.
//Query (self-join on subject within same term):
  
  WITH tr_math AS (
  SELECT
    STUDENT_ID,
    TERM,
    SCORE AS math_score
  FROM TEST_RESULTS
  WHERE TEST_YEAR = 2025
    AND SUBJECT = 'Math'
),
tr_read AS (
  SELECT
    STUDENT_ID,
    TERM,
    SCORE AS reading_score
  FROM TEST_RESULTS
  WHERE TEST_YEAR = 2025
    AND SUBJECT = 'Reading'
)
SELECT
  s.STUDENT_ID,
  s.FIRST_NAME,
  s.LAST_NAME,
  sc.NAME     AS SCHOOL,
  tm.TERM,
  tm.math_score,
  tr.reading_score,
  (tm.math_score - tr.reading_score) AS math_minus_reading
FROM tr_math tm
JOIN tr_read tr
  ON tm.STUDENT_ID = tr.STUDENT_ID
 AND tm.TERM       = tr.TERM
JOIN STUDENT s ON tm.STUDENT_ID = s.STUDENT_ID
JOIN SCHOOL  sc ON s.SCHOOL_ID  = sc.SCHOOL_ID
WHERE tm.TERM IN ('Fall 2025', 'Winter 2025', 'Spring 2025')
ORDER BY
  sc.NAME, tm.TERM, s.LAST_NAME, s.FIRST_NAME;
  
 // From here, BI can build scatter plots, distributions, etc.
  
//Use Case 7 – Class Performance Distribution (Percentiles, Buckets)
//Goal: For each class and term, show distribution of students across performance bands (e.g., percentile <25, 25–75, >75). This is more complex but extremely useful for teachers and principals.
//Query (CASE + GROUP BY on class + term):

 SELECT
  d.NAME       AS DISTRICT,
  sc.NAME      AS SCHOOL,
  c.NAME       AS CLASS_NAME,
  c.SUBJECT,
  tr.TERM,
  COUNT(*) AS num_results,
  COUNT(CASE WHEN tr.PERCENTILE < 25 THEN 1 END) AS below_25,
  COUNT(CASE WHEN tr.PERCENTILE BETWEEN 25 AND 75 THEN 1 END) AS mid_25_75,
  COUNT(CASE WHEN tr.PERCENTILE > 75 THEN 1 END) AS above_75
FROM TEST_RESULTS tr
JOIN CLASS   c  ON tr.CLASS_ID   = c.CLASS_ID
JOIN SCHOOL  sc ON tr.SCHOOL_ID  = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE tr.TEST_YEAR = 2025
  AND tr.TERM IN ('Fall 2025', 'Winter 2025', 'Spring 2025')
GROUP BY
  d.NAME, sc.NAME, c.NAME, c.SUBJECT, tr.TERM
ORDER BY
  d.NAME, sc.NAME, c.NAME, c.SUBJECT, tr.TERM;
 
 
//Use Case 8 – Educator Portfolio View (Multi-school potential, outer join flavor)
//Goal: Show all classes per educator with average scores per term, but also display educators even if some classes have no results yet. Again uses LEFT JOIN.

 SELECT
  e.EDUCATOR_ID,
  e.FIRST_NAME || ' ' || e.LAST_NAME AS EDUCATOR_NAME,
  sc.NAME      AS SCHOOL,
  c.CLASS_ID,
  c.NAME       AS CLASS_NAME,
  c.SUBJECT,
  AVG(CASE WHEN tr.TERM = 'Fall 2025'   THEN tr.SCORE END) AS avg_fall_score,
  AVG(CASE WHEN tr.TERM = 'Winter 2025' THEN tr.SCORE END) AS avg_winter_score,
  AVG(CASE WHEN tr.TERM = 'Spring 2025' THEN tr.SCORE END) AS avg_spring_score
FROM EDUCATOR e
JOIN CLASS c
  ON e.EDUCATOR_ID = c.EDUCATOR_ID
JOIN SCHOOL sc
  ON c.SCHOOL_ID = sc.SCHOOL_ID
LEFT JOIN TEST_RESULTS tr
  ON c.CLASS_ID = tr.CLASS_ID
 AND tr.TEST_YEAR = 2025
GROUP BY
  e.EDUCATOR_ID, e.FIRST_NAME, e.LAST_NAME,
  sc.NAME, c.CLASS_ID, c.NAME, c.SUBJECT
ORDER BY
  EDUCATOR_NAME, sc.NAME, c.NAME;
 
 //key dashboards into views you can point Tableau / Power BI / DBeaver at directly.
 
 //1) Class Growth Fall → Winter 2025
//View: VW_DASH_CLASS_GROWTH_2025
 
 CREATE OR REPLACE VIEW VW_DASH_CLASS_GROWTH_2025 AS
WITH fall AS (
  SELECT
    CLASS_ID,
    SUBJECT,
    AVG(SCORE) AS avg_score_fall
  FROM TEST_RESULTS
  WHERE TEST_YEAR = 2025
    AND TERM = 'Fall 2025'
  GROUP BY CLASS_ID, SUBJECT
),
winter AS (
  SELECT
    CLASS_ID,
    SUBJECT,
    AVG(SCORE) AS avg_score_winter
  FROM TEST_RESULTS
  WHERE TEST_YEAR = 2025
    AND TERM = 'Winter 2025'
  GROUP BY CLASS_ID, SUBJECT
)
SELECT
  d.NAME        AS DISTRICT,
  sc.NAME       AS SCHOOL,
  c.CLASS_ID,
  c.NAME        AS CLASS_NAME,
  c.SUBJECT,
  f.avg_score_fall,
  w.avg_score_winter,
  (w.avg_score_winter - f.avg_score_fall) AS score_delta
FROM fall f
JOIN winter w
  ON f.CLASS_ID = w.CLASS_ID
 AND f.SUBJECT  = w.SUBJECT
JOIN CLASS    c ON f.CLASS_ID      = c.CLASS_ID
JOIN SCHOOL   sc ON c.SCHOOL_ID    = sc.SCHOOL_ID
JOIN DISTRICT d  ON sc.DISTRICT_ID = d.DISTRICT_ID;

//2) Educator Portfolio View (All 2025 Terms)
//View: VW_DASH_EDUCATOR_PORTFOLIO_2025

CREATE OR REPLACE VIEW VW_DASH_EDUCATOR_PORTFOLIO_2025 AS
SELECT
  e.EDUCATOR_ID,
  e.FIRST_NAME || ' ' || e.LAST_NAME AS EDUCATOR_NAME,
  sc.NAME      AS SCHOOL,
  c.CLASS_ID,
  c.NAME       AS CLASS_NAME,
  c.SUBJECT,
  AVG(CASE WHEN tr.TERM = 'Fall 2025'   THEN tr.SCORE END) AS avg_fall_score,
  AVG(CASE WHEN tr.TERM = 'Winter 2025' THEN tr.SCORE END) AS avg_winter_score,
  AVG(CASE WHEN tr.TERM = 'Spring 2025' THEN tr.SCORE END) AS avg_spring_score
FROM EDUCATOR e
JOIN CLASS c
  ON e.EDUCATOR_ID = c.EDUCATOR_ID
JOIN SCHOOL sc
  ON c.SCHOOL_ID = sc.SCHOOL_ID
LEFT JOIN TEST_RESULTS tr
  ON c.CLASS_ID   = tr.CLASS_ID
 AND tr.TEST_YEAR = 2025
GROUP BY
  e.EDUCATOR_ID, e.FIRST_NAME, e.LAST_NAME,
  sc.NAME, c.CLASS_ID, c.NAME, c.SUBJECT;
