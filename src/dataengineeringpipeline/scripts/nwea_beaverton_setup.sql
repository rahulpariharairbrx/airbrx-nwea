/* =====================================================================
   NWEA Beaverton K-12 Dataset – Snowflake Setup Script
   ---------------------------------------------------------------------
   - Creates database + schema: NWEA.ASSESSMENT_BSD
   - Defines core tables (UUID v4 PKs):
       DISTRICT, SCHOOL, EDUCATOR, CLASS, STUDENT, TEST_RESULTS
   - Seeds synthetic data for Beaverton School District:
       1 district, 3 schools, 3 educators, 6 classes,
       150 students, 450 test_results (Fall/Winter/Spring 2025)
   - Creates key dashboard views for analytics:
       VW_DASH_CLASS_GROWTH_2025
       VW_DASH_STUDENT_TERM_GROWTH_2025
       VW_DASH_EDUCATOR_PORTFOLIO_2025
   ===================================================================== */

/*----------------------------------------------------------------------
  1. ROLE, WAREHOUSE, DATABASE, SCHEMA
  ----------------------------------------------------------------------*/

USE ROLE SYSADMIN;  -- adjust if needed

CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND   = 60
  AUTO_RESUME    = TRUE;

CREATE DATABASE IF NOT EXISTS NWEA;
CREATE SCHEMA IF NOT EXISTS NWEA.ASSESSMENT_BSD;

USE DATABASE NWEA;
USE SCHEMA   ASSESSMENT_BSD;
USE WAREHOUSE COMPUTE_WH;


/*----------------------------------------------------------------------
  2. CORE TABLE DDL (UUID v4 PRIMARY KEYS)
  ----------------------------------------------------------------------*/

CREATE OR REPLACE TABLE DISTRICT (
  DISTRICT_ID STRING DEFAULT UUID_STRING(),
  NAME        STRING,
  STATE       STRING,
  TIMEZONE    STRING,
  CONSTRAINT PK_DISTRICT PRIMARY KEY (DISTRICT_ID)
);

CREATE OR REPLACE TABLE SCHOOL (
  SCHOOL_ID   STRING DEFAULT UUID_STRING(),
  DISTRICT_ID STRING,
  NAME        STRING,
  LEVEL       STRING,
  STATE       STRING,
  TIMEZONE    STRING,
  CONSTRAINT PK_SCHOOL PRIMARY KEY (SCHOOL_ID)
);

CREATE OR REPLACE TABLE EDUCATOR (
  EDUCATOR_ID STRING DEFAULT UUID_STRING(),
  SCHOOL_ID   STRING,
  FIRST_NAME  STRING,
  LAST_NAME   STRING,
  EMAIL       STRING,
  CONSTRAINT PK_EDUCATOR PRIMARY KEY (EDUCATOR_ID)
);

CREATE OR REPLACE TABLE CLASS (
  CLASS_ID    STRING DEFAULT UUID_STRING(),
  SCHOOL_ID   STRING,
  EDUCATOR_ID STRING,
  NAME        STRING,
  SUBJECT     STRING,
  CONSTRAINT PK_CLASS PRIMARY KEY (CLASS_ID)
);

CREATE OR REPLACE TABLE STUDENT (
  STUDENT_ID      STRING DEFAULT UUID_STRING(),
  FIRST_NAME      STRING,
  LAST_NAME       STRING,
  GRADE           NUMBER(2,0),
  SCHOOL_ID       STRING,
  CLASS_ID        STRING,
  ENROLLMENT_DATE DATE,
  STATUS          STRING,
  CONSTRAINT PK_STUDENT PRIMARY KEY (STUDENT_ID)
);

CREATE OR REPLACE TABLE TEST_RESULTS (
  TEST_RESULT_ID  STRING DEFAULT UUID_STRING(),
  STUDENT_ID      STRING,
  SCHOOL_ID       STRING,
  CLASS_ID        STRING,
  SUBJECT         STRING,
  TERM            STRING,
  TEST_YEAR       NUMBER(4,0),
  TEST_DATE       DATE,
  TEST_NAME       STRING,
  SCORE           NUMBER(5,2),
  PERCENTILE      NUMBER(5,2),
  SCALED_SCORE    NUMBER(6,2),
  CONSTRAINT PK_TEST_RESULTS PRIMARY KEY (TEST_RESULT_ID)
);


/*----------------------------------------------------------------------
  3. SEED DIMENSIONS: DISTRICT, SCHOOLS, EDUCATORS, CLASSES
  ----------------------------------------------------------------------*/

-- 3.1 DISTRICT (Beaverton School District)
INSERT INTO DISTRICT (NAME, STATE, TIMEZONE)
VALUES ('Beaverton School District', 'OR', 'America/Los_Angeles');

-- 3.2 SCHOOLS (West View, ISB, BASE)
INSERT INTO SCHOOL (DISTRICT_ID, NAME, LEVEL, STATE, TIMEZONE)
SELECT DISTRICT_ID, 'West View', 'High', 'OR', 'America/Los_Angeles'
FROM DISTRICT WHERE NAME = 'Beaverton School District'
UNION ALL
SELECT DISTRICT_ID, 'ISB', 'High', 'OR', 'America/Los_Angeles'
FROM DISTRICT WHERE NAME = 'Beaverton School District'
UNION ALL
SELECT DISTRICT_ID, 'BASE', 'High', 'OR', 'America/Los_Angeles'
FROM DISTRICT WHERE NAME = 'Beaverton School District';

-- 3.3 EDUCATORS (1 per school)
INSERT INTO EDUCATOR (SCHOOL_ID, FIRST_NAME, LAST_NAME, EMAIL)
SELECT SCHOOL_ID, 'Alex',   'Moore',  'alex.moore@westview.edu'
FROM SCHOOL WHERE NAME = 'West View'
UNION ALL
SELECT SCHOOL_ID, 'Jordan', 'Parker', 'jordan.parker@isb.edu'
FROM SCHOOL WHERE NAME = 'ISB'
UNION ALL
SELECT SCHOOL_ID, 'Taylor', 'Reed',   'taylor.reed@base.edu'
FROM SCHOOL WHERE NAME = 'BASE';

-- 3.4 CLASSES (2 per school: Math, Reading)
INSERT INTO CLASS (SCHOOL_ID, EDUCATOR_ID, NAME, SUBJECT)
SELECT
  s.SCHOOL_ID,
  e.EDUCATOR_ID,
  s.NAME || ' - ' || subj.SUBJECT AS CLASS_NAME,
  subj.SUBJECT
FROM SCHOOL s
JOIN EDUCATOR e
  ON e.SCHOOL_ID = s.SCHOOL_ID
JOIN (
  SELECT 'Math' AS SUBJECT
  UNION ALL
  SELECT 'Reading' AS SUBJECT
) subj;


/*----------------------------------------------------------------------
  4. SEED STUDENTS (25 PER CLASS → 150 TOTAL)
  ----------------------------------------------------------------------*/

-- Generates 25 students for each class, with American-style names.
INSERT INTO STUDENT
  (FIRST_NAME, LAST_NAME, GRADE, SCHOOL_ID, CLASS_ID, ENROLLMENT_DATE, STATUS)
WITH name_lists AS (
  SELECT
    ARRAY_CONSTRUCT(
      'Liam','Noah','Oliver','Elijah','James',
      'Benjamin','Lucas','Henry','Alexander','Michael',
      'Emma','Olivia','Ava','Sophia','Isabella',
      'Mia','Charlotte','Amelia','Harper','Evelyn'
    ) AS first_names,
    ARRAY_CONSTRUCT(
      'Smith','Johnson','Williams','Brown','Jones',
      'Garcia','Miller','Davis','Rodriguez','Martinez',
      'Wilson','Anderson','Taylor','Thomas','Harris',
      'Clark','Lewis','Robinson','Walker','Young'
    ) AS last_names
)
SELECT
  nl.first_names[(rn-1) % ARRAY_SIZE(nl.first_names)]::STRING AS FIRST_NAME,
  nl.last_names[(rn-1) % ARRAY_SIZE(nl.last_names)]::STRING   AS LAST_NAME,
  9 AS GRADE,  -- high school grade
  c.SCHOOL_ID,
  c.CLASS_ID,
  DATEADD('day', - UNIFORM(0, 120, RANDOM()), '2024-09-01'::DATE) AS ENROLLMENT_DATE,
  'ACTIVE' AS STATUS
FROM CLASS c
CROSS JOIN name_lists nl
JOIN LATERAL (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn
  FROM TABLE(GENERATOR(ROWCOUNT => 25))
) g;


/*----------------------------------------------------------------------
  5. SEED TEST RESULTS (3 TERMS PER STUDENT → ~450 ROWS)
  ----------------------------------------------------------------------*/

INSERT INTO TEST_RESULTS
  (STUDENT_ID, SCHOOL_ID, CLASS_ID, SUBJECT, TERM, TEST_YEAR, TEST_DATE,
   TEST_NAME, SCORE, PERCENTILE, SCALED_SCORE)
SELECT
  s.STUDENT_ID,
  s.SCHOOL_ID,
  s.CLASS_ID,
  c.SUBJECT,
  t.TERM,
  2025 AS TEST_YEAR,
  DATEADD('day', UNIFORM(0, 30, RANDOM()), t.BASE_DATE) AS TEST_DATE,
  'MAP Growth' AS TEST_NAME,
  190 + UNIFORM(0, 40, RANDOM()) AS SCORE,
  10  + UNIFORM(0, 90, RANDOM()) AS PERCENTILE,
  190 + UNIFORM(0, 40, RANDOM()) AS SCALED_SCORE
FROM STUDENT s
JOIN CLASS c
  ON s.CLASS_ID = c.CLASS_ID
JOIN (
  SELECT 'Fall 2025'   AS TERM, TO_DATE('2025-10-15') AS BASE_DATE
  UNION ALL
  SELECT 'Winter 2025' AS TERM, TO_DATE('2025-01-20') AS BASE_DATE
  UNION ALL
  SELECT 'Spring 2025' AS TERM, TO_DATE('2025-04-20') AS BASE_DATE
) t;


/*----------------------------------------------------------------------
  6. DASHBOARD VIEWS FOR ANALYTICS / AIRBRX
  ----------------------------------------------------------------------*/

-- 6.1 Class Growth Fall → Winter 2025
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


-- 6.2 Student Term Growth (Fall / Winter / Spring 2025)
CREATE OR REPLACE VIEW VW_DASH_STUDENT_TERM_GROWTH_2025 AS
SELECT
  s.STUDENT_ID,
  s.FIRST_NAME,
  s.LAST_NAME,
  sc.NAME      AS SCHOOL,
  c.CLASS_ID,
  c.NAME       AS CLASS_NAME,
  c.SUBJECT,
  AVG(CASE WHEN tr.TERM = 'Fall 2025'   THEN tr.SCORE END) AS score_fall,
  AVG(CASE WHEN tr.TERM = 'Winter 2025' THEN tr.SCORE END) AS score_winter,
  AVG(CASE WHEN tr.TERM = 'Spring 2025' THEN tr.SCORE END) AS score_spring
FROM STUDENT s
JOIN TEST_RESULTS tr ON s.STUDENT_ID = tr.STUDENT_ID
JOIN CLASS c         ON tr.CLASS_ID   = c.CLASS_ID
JOIN SCHOOL sc       ON tr.SCHOOL_ID  = sc.SCHOOL_ID
WHERE tr.TEST_YEAR = 2025
GROUP BY
  s.STUDENT_ID, s.FIRST_NAME, s.LAST_NAME,
  sc.NAME, c.CLASS_ID, c.NAME, c.SUBJECT;


-- 6.3 Educator Portfolio (Class Averages by Term 2025)
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


/*----------------------------------------------------------------------
  7. OPTIONAL VALIDATION QUERIES (RUN MANUALLY IF DESIRED)
  ----------------------------------------------------------------------*/

-- SELECT COUNT(*) AS districts     FROM DISTRICT;
-- SELECT COUNT(*) AS schools       FROM SCHOOL;
-- SELECT COUNT(*) AS educators     FROM EDUCATOR;
-- SELECT COUNT(*) AS classes       FROM CLASS;
-- SELECT COUNT(*) AS students      FROM STUDENT;
-- SELECT COUNT(*) AS test_results  FROM TEST_RESULTS;

-- SELECT * FROM STUDENT      LIMIT 10;
-- SELECT * FROM TEST_RESULTS LIMIT 10;

-- SELECT * FROM VW_DASH_CLASS_GROWTH_2025          LIMIT 10;
-- SELECT * FROM VW_DASH_STUDENT_TERM_GROWTH_2025   LIMIT 10;
-- SELECT * FROM VW_DASH_EDUCATOR_PORTFOLIO_2025    LIMIT 10;
