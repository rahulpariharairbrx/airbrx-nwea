# NWEA / Beaverton K-12 Snowflake Dataset (UUID v4)

This project contains a clean Snowflake script that builds a realistic K-12
assessment dataset for a single district (Beaverton School District) with UUID v4
keys. It is intended for analytics, benchmarking, and query-optimization
experiments (e.g., via AirBrx, BI tools, or Gen-AI agents).

The dataset models:

- **1 District** – Beaverton School District
- **3 High Schools** – West View, ISB, BASE
- **1 Educator per school**
- **2 Classes per school** – Math, Reading (6 classes total)
- **25 Students per class** – 150 students total
- **3 test results per student** for 2025 terms – Fall, Winter, Spring  
  → ~450 rows in `TEST_RESULTS`

All primary keys are generated with Snowflake’s `UUID_STRING()` function
(UUID v4).

---

## Schema Overview

Database & schema:

- Database: `NWEA`
- Schema: `ASSESSMENT_BSD`

Tables:

1. `DISTRICT`
2. `SCHOOL`
3. `EDUCATOR`
4. `CLASS`
5. `STUDENT`
6. `TEST_RESULTS`

Entity relationships (simplified):

- `DISTRICT` 1-to-many `SCHOOL`
- `SCHOOL` 1-to-many `EDUCATOR`
- `SCHOOL` 1-to-many `CLASS`
- `CLASS` 1-to-many `STUDENT`
- `STUDENT` 1-to-many `TEST_RESULTS`
- `CLASS`   1-to-many `TEST_RESULTS`
- `SCHOOL`  1-to-many `TEST_RESULTS`

See the Mermaid ER diagram in this repo for a visual representation.

---

## Data Volumes

Approximate row counts after running the script:

| Table        | Rows | Notes                                              |
|-------------:|-----:|----------------------------------------------------|
| DISTRICT     |    1 | Beaverton School District                          |
| SCHOOL       |    3 | West View, ISB, BASE                               |
| EDUCATOR     |    3 | One educator per school                            |
| CLASS        |    6 | 2 subjects (Math, Reading) per school              |
| STUDENT      |  150 | 25 students per class                              |
| TEST_RESULTS |  450 | 3 terms per student (Fall/Winter/Spring 2025)      |

---

## Requirements

- A Snowflake account
- Role with privileges to create database/schema/tables (e.g. `SYSADMIN`)
- A running virtual warehouse (e.g. `COMPUTE_WH`)
- Snowsight or any Snowflake SQL client

---

## How to Run the Script

1. **Open a Snowflake worksheet**

   Log into Snowsight, create a new worksheet.

2. **Set role and warehouse**

   ```sql
   USE ROLE SYSADMIN;             -- or ACCOUNTADMIN
   USE WAREHOUSE COMPUTE_WH;      -- adjust to your warehouse
