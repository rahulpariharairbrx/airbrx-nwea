USE DATABASE NWEA;
USE SCHEMA ASSESSMENT;

SHOW TABLES;

SELECT COUNT(*) FROM SCHOOL;
SELECT COUNT(*) FROM STUDENT;
SELECT COUNT(*) FROM TEST_RESULTS;
SELECT * FROM STUDENT LIMIT 10;
SELECT * FROM TEST_RESULTS LIMIT 10;


//Below is a step-by-step script you can paste into a Snowflake worksheet and run in order.

//#1 District: Beaverton School District
//3 Schools: West View, ISB, BASE
//1 Educator per school
//2 Classes per school (Math, Reading) → 6 classes
//25 students per class → 150 students total
//3 test results per student for 2025 seasons (Fall, Winter, Spring) → 450 TEST_RESULTS rows
//All IDs are UUID_STRING() (UUID v4)

//This uses Snowflake’s UUID_STRING() function to generate RFC 4122 UUIDs. 
//Snowflake Docs

//1. Set context and create schema
-- Use a role/warehouse with CREATE privileges
USE ROLE SYSADMIN;                -- or ACCOUNTADMIN
USE WAREHOUSE COMPUTE_WH;       -- e.g. COMPUTE_WH

CREATE DATABASE IF NOT EXISTS NWEA;
CREATE SCHEMA IF NOT EXISTS NWEA.ASSESSMENT_BSD;

USE DATABASE NWEA;
USE SCHEMA ASSESSMENT_BSD;

//2. Create tables with UUID primary keys
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
  TERM            STRING,          -- e.g. 'Fall 2025'
  TEST_YEAR       NUMBER(4,0),     -- 2025
  TEST_DATE       DATE,
  TEST_NAME       STRING,
  SCORE           NUMBER(5,2),
  PERCENTILE      NUMBER(5,2),
  SCALED_SCORE    NUMBER(6,2),
  CONSTRAINT PK_TEST_RESULTS PRIMARY KEY (TEST_RESULT_ID)
);

//3. Insert the Beaverton School District
INSERT INTO DISTRICT (NAME, STATE, TIMEZONE)
VALUES ('Beaverton School District', 'OR', 'America/Los_Angeles');

//Insert 4 high schools (West View, ISB, BASE)
INSERT INTO SCHOOL (DISTRICT_ID, NAME, LEVEL, STATE, TIMEZONE)
SELECT DISTRICT_ID, 'West View', 'High', 'OR', 'America/Los_Angeles'
FROM DISTRICT WHERE NAME = 'Beaverton School District'
UNION ALL
SELECT DISTRICT_ID, 'ISB', 'High', 'OR', 'America/Los_Angeles'
FROM DISTRICT WHERE NAME = 'Beaverton School District'
UNION ALL
SELECT DISTRICT_ID, 'BASE', 'High', 'OR', 'America/Los_Angeles'
FROM DISTRICT WHERE NAME = 'Beaverton School District';

//5. Insert 1 educator per school (UUIDs auto-generated)
INSERT INTO EDUCATOR (SCHOOL_ID, FIRST_NAME, LAST_NAME, EMAIL)
SELECT SCHOOL_ID, 'Alex',   'Moore',  'alex.moore@westview.edu'
FROM SCHOOL WHERE NAME = 'West View'
UNION ALL
SELECT SCHOOL_ID, 'Jordan', 'Parker', 'jordan.parker@isb.edu'
FROM SCHOOL WHERE NAME = 'ISB'
UNION ALL
SELECT SCHOOL_ID, 'Taylor', 'Reed',   'taylor.reed@base.edu'
FROM SCHOOL WHERE NAME = 'BASE';


//6. Insert 2 classes per school (Math & Reading)
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


//7. Insert 25 students per class (150 total) with American-style names
//This uses arrays of first/last names and spreads them across students; IDs are UUIDs from the table defaults.

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
  9 AS GRADE,  -- high school
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




//Each of the 6 classes gets 25 students → 150 STUDENT rows total.
//STUDENT_ID is auto-filled with UUID_STRING() per row.

//8. Insert 3 test results per student (Fall/Winter/Spring 2025)
//Each student gets three results for the subject of their class; you can easily filter Spring later for your cache rules.
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

//Result: 150 students × 3 terms = 450 TEST_RESULTS rows
//(each with a UUID TEST_RESULT_ID).

//9. Quick validation + a Spring 2025 view for BI / AirBrx
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

//That gives you exactly the “3 schools × 2 classes × 25 students × Spring 2025” slice you described, with UUID-backed dimension tables suitable for AirBrx cache-rule and MCP experiments.

//If you want, next step I can layer on a Snowflake Scripting procedure that wraps all of this into a single CALL INIT_NWEA_BSD_DATASET() so you can rerun / reset easily in different environments.