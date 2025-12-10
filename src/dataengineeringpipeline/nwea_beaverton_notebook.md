# NWEA Beaverton K-12 Dataset – Snowflake Notebook

This notebook creates a synthetic NWEA-style Beaverton dataset in Snowflake, with:

- Database: `NWEA`
- Schema: `ASSESSMENT_BSD`
- UUID v4 primary keys
- Beaverton School District → 3 schools → 6 classes → 150 students → ~450 test results
- Dashboard views for AirBrx / BI tools

---

## Section 1 – Setup

### Cell 1.1 – Role, Warehouse, Database, Schema

```sql
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
