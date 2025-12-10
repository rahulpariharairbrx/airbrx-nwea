-- ============================================================================
-- AirBrx Cache Rules Engine: Advanced Priority Conflict Test Queries
-- NWEA Assessment Database - Complex Multi-Dimensional Scenarios
-- ============================================================================
-- Purpose: Test advanced rule conflicts with temporal, tenant, role, and
--          query pattern dimensions
-- Database: NWEA.ASSESSMENT_BSD
-- Rule Set: nwea_advanced_conflict_testing_v2 (15 additional rules)
-- ============================================================================

USE DATABASE NWEA;
USE SCHEMA ASSESSMENT_BSD;

-- ============================================================================
-- CONFLICT SCENARIO 1: Premium Tenant + Morning Peak + UC1
-- Expected Winner: rule_tenant_premium_override (priority 85)
-- Competing Rules: UC1 (40), Morning Peak (65), Premium Tenant (85)
-- ============================================================================

-- QUERY CS1.1: Execute during morning hours (7-9 AM) with premium tenant
-- Simulate headers: x-tenant=premium, x-request-time=08:30:00
-- Expected: rule_tenant_premium_override wins, TTL=60s, cache key includes tenant
SELECT
  d.NAME AS DISTRICT,
  sc.NAME AS SCHOOL,
  c.SUBJECT,
  tr.TERM,
  COUNT(*) AS num_results,
  AVG(tr.SCORE) AS avg_score
FROM TEST_RESULTS tr
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE tr.TERM = 'Fall 2025'
GROUP BY d.NAME, sc.NAME, c.SUBJECT, tr.TERM;

-- QUERY CS1.2: Same query, standard tenant, morning hours
-- Simulate headers: x-tenant=standard, x-request-time=08:30:00
-- Expected: rule_time_based_morning_peak wins (priority 65), TTL=600s
-- Result: DIFFERENT cache entry from CS1.1 due to tenant dimension

-- QUERY CS1.3: Same query, premium tenant, afternoon
-- Simulate headers: x-tenant=premium, x-request-time=14:00:00
-- Expected: rule_tenant_premium_override still wins (doesn't require morning time)

-- ============================================================================
-- CONFLICT SCENARIO 2: Debug Header Overrides Everything
-- Expected Winner: rule_developer_debug_bypass (priority 99)
-- Competing Rules: Premium Tenant (85), UC4 No-Cache (90), Debug (99)
-- ============================================================================

-- QUERY CS2.1: UC4 completeness query with debug header
-- Simulate headers: x-debug=true
-- Expected: rule_developer_debug_bypass wins, cache disabled, priority 99 > 90
SELECT
  e.EDUCATOR_ID,
  e.FIRST_NAME || ' ' || e.LAST_NAME AS EDUCATOR_NAME,
  c.NAME AS CLASS_NAME,
  COUNT(CASE WHEN tr.TERM = 'Fall 2025' THEN 1 END) AS fall_results_count,
  COUNT(CASE WHEN tr.TERM = 'Winter 2025' THEN 1 END) AS winter_results_count
FROM CLASS c
JOIN EDUCATOR e ON c.EDUCATOR_ID = e.EDUCATOR_ID
LEFT JOIN TEST_RESULTS tr ON c.CLASS_ID = tr.CLASS_ID
GROUP BY e.EDUCATOR_ID, e.FIRST_NAME, e.LAST_NAME, c.NAME;

-- QUERY CS2.2: Premium tenant UC1 query with debug header
-- Simulate headers: x-debug=true, x-tenant=premium
-- Expected: Debug still wins over premium tenant
SELECT
  d.NAME,
  sc.NAME,
  tr.TERM,
  AVG(tr.SCORE) AS avg_score
FROM TEST_RESULTS tr
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE tr.TERM = 'Spring 2025'
GROUP BY d.NAME, sc.NAME, tr.TERM;

-- ============================================================================
-- CONFLICT SCENARIO 3: Large Result Set + Heavy Aggregation + UC1
-- Expected Winner: rule_aggregation_heavy_long_ttl (priority 48)
-- Competing Rules: Large Result (35), UC1 (40), Heavy Aggregation (48)
-- ============================================================================

-- QUERY CS3.1: UC1 pattern with 8 aggregations (heavy agg rule should win)
-- Expected: rule_aggregation_heavy_long_ttl (priority 48), TTL=1800s
SELECT
  d.NAME AS DISTRICT,
  sc.NAME AS SCHOOL,
  c.SUBJECT,
  tr.TERM,
  COUNT(DISTINCT s.STUDENT_ID) AS unique_students,      -- agg 1
  COUNT(*) AS total_results,                             -- agg 2
  AVG(tr.SCORE) AS avg_score,                            -- agg 3
  STDDEV(tr.SCORE) AS stddev_score,                      -- agg 4
  MIN(tr.SCORE) AS min_score,                            -- agg 5
  MAX(tr.SCORE) AS max_score,                            -- agg 6
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY tr.SCORE) AS median,  -- agg 7
  SUM(tr.SCORE) AS total_score                           -- agg 8
FROM TEST_RESULTS tr
JOIN STUDENT s ON tr.STUDENT_ID = s.STUDENT_ID
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE tr.TEST_YEAR = 2025
GROUP BY d.NAME, sc.NAME, c.SUBJECT, tr.TERM;

-- QUERY CS3.2: Same query but with estimated rows >10K flag
-- Simulate: estimatedRows=15000
-- Expected: Still aggregation_heavy wins (48 > 35)

-- QUERY CS3.3: Fewer aggregations (only 3)
-- Expected: Falls back to UC1 (priority 40) or join_count_penalty (42)
SELECT
  d.NAME,
  tr.TERM,
  COUNT(*) AS num_results,
  AVG(tr.SCORE) AS avg_score,
  MAX(tr.SCORE) AS max_score
FROM TEST_RESULTS tr
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE tr.TERM = 'Fall 2025'
GROUP BY d.NAME, tr.TERM;

-- ============================================================================
-- CONFLICT SCENARIO 4: Current Date Function + UC6 + Window Function
-- Expected Winner: rule_current_date_function_short_ttl (priority 72)
-- Competing Rules: UC6 (50), Window Function (53), Current Date (72)
-- ============================================================================

-- QUERY CS4.1: Math/Reading correlation with CURRENT_DATE and window function
-- Expected: rule_current_date_function_short_ttl wins (priority 72), TTL=30s
SELECT
  s.STUDENT_ID,
  s.FIRST_NAME,
  AVG(CASE WHEN c.SUBJECT = 'Math' THEN tr.SCORE END) AS math_score,
  AVG(CASE WHEN c.SUBJECT = 'Reading' THEN tr.SCORE END) AS reading_score,
  (math_score - reading_score) AS score_difference,
  ROW_NUMBER() OVER (ORDER BY score_difference DESC) AS performance_rank,
  DATEDIFF(day, tr.TEST_DATE, CURRENT_DATE()) AS days_since_test
FROM TEST_RESULTS tr
JOIN STUDENT s ON tr.STUDENT_ID = s.STUDENT_ID
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
WHERE tr.TERM = 'Fall 2025'
  AND tr.TEST_DATE >= CURRENT_DATE() - 90
GROUP BY s.STUDENT_ID, s.FIRST_NAME, tr.TEST_DATE;

-- QUERY CS4.2: Same pattern but without CURRENT_DATE
-- Expected: rule_window_function_medium_ttl wins (priority 53), TTL=600s
SELECT
  s.STUDENT_ID,
  AVG(CASE WHEN c.SUBJECT = 'Math' THEN tr.SCORE END) AS math_score,
  AVG(CASE WHEN c.SUBJECT = 'Reading' THEN tr.SCORE END) AS reading_score,
  ROW_NUMBER() OVER (ORDER BY math_score DESC) AS math_rank,
  ROW_NUMBER() OVER (ORDER BY reading_score DESC) AS reading_rank
FROM TEST_RESULTS tr
JOIN STUDENT s ON tr.STUDENT_ID = s.STUDENT_ID
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
WHERE tr.TERM = 'Fall 2025'
GROUP BY s.STUDENT_ID;

-- QUERY CS4.3: UC6 pattern without window functions
-- Expected: rule_uc6_cross_subject_correlation wins (priority 50), TTL=300s
SELECT
  s.STUDENT_ID,
  tr.TERM,
  AVG(CASE WHEN c.SUBJECT = 'Math' THEN tr.SCORE END) AS math_score,
  AVG(CASE WHEN c.SUBJECT = 'Reading' THEN tr.SCORE END) AS reading_score,
  (math_score - reading_score) AS delta
FROM TEST_RESULTS tr
JOIN STUDENT s ON tr.STUDENT_ID = s.STUDENT_ID
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
WHERE tr.TERM = 'Winter 2025'
GROUP BY s.STUDENT_ID, tr.TERM;

-- ============================================================================
-- CONFLICT SCENARIO 5: Subquery No-Cache vs Premium Tenant
-- Expected Winner: rule_tenant_premium_override (priority 85)
-- Competing Rules: Subquery No-Cache (82), Premium Tenant (85)
-- Note: This is an interesting conflict - different cache actions!
-- ============================================================================

-- QUERY CS5.1: Correlated subquery with premium tenant
-- Simulate headers: x-tenant=premium
-- Expected: Premium tenant wins (85 > 82), BUT conflict in cache behavior
-- Premium wants TTL=60s, Subquery wants cache disabled
-- Result: Premium priority wins, cache ENABLED with TTL=60s
SELECT
  s.STUDENT_ID,
  s.FIRST_NAME,
  s.LAST_NAME,
  (
    SELECT AVG(tr.SCORE)
    FROM TEST_RESULTS tr
    WHERE tr.STUDENT_ID = s.STUDENT_ID
      AND tr.TERM = 'Fall 2025'
  ) AS avg_fall_score,
  (
    SELECT AVG(tr.SCORE)
    FROM TEST_RESULTS tr
    WHERE tr.STUDENT_ID = s.STUDENT_ID
      AND tr.TERM = 'Winter 2025'
  ) AS avg_winter_score
FROM STUDENT s
WHERE s.SCHOOL_ID IN (SELECT SCHOOL_ID FROM SCHOOL WHERE NAME = 'West View')
ORDER BY avg_fall_score DESC;

-- QUERY CS5.2: Same query with standard tenant
-- Expected: rule_subquery_no_cache wins (priority 82), cache disabled
-- Simulate headers: x-tenant=standard

-- QUERY CS5.3: Non-correlated subquery (should not match subquery rule)
-- Expected: Falls back to UC1 or baseline
SELECT
  s.STUDENT_ID,
  s.FIRST_NAME,
  AVG(tr.SCORE) AS avg_score
FROM STUDENT s
JOIN TEST_RESULTS tr ON s.STUDENT_ID = tr.STUDENT_ID
WHERE s.SCHOOL_ID IN (SELECT SCHOOL_ID FROM SCHOOL WHERE STATE = 'OR')
GROUP BY s.STUDENT_ID, s.FIRST_NAME;

-- ============================================================================
-- CONFLICT SCENARIO 6: West View Specific + UC1 + Filter Specificity
-- Expected Winner: rule_filter_by_specific_school (priority 52)
-- Competing Rules: UC1 (40), West View Specific (52)
-- ============================================================================

-- QUERY CS6.1: UC1 pattern explicitly filtering West View
-- Expected: rule_filter_by_specific_school wins (priority 52), TTL=450s
SELECT
  d.NAME AS DISTRICT,
  sc.NAME AS SCHOOL,
  c.SUBJECT,
  tr.TERM,
  COUNT(*) AS num_results,
  AVG(tr.SCORE) AS avg_score
FROM TEST_RESULTS tr
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE sc.NAME = 'West View'
  AND tr.TERM = 'Spring 2025'
GROUP BY d.NAME, sc.NAME, c.SUBJECT, tr.TERM;

-- QUERY CS6.2: Same pattern for ISB (should NOT match West View rule)
-- Expected: Falls back to UC1 (priority 40), TTL=300s
SELECT
  d.NAME,
  sc.NAME,
  c.SUBJECT,
  tr.TERM,
  COUNT(*) AS num_results,
  AVG(tr.SCORE) AS avg_score
FROM TEST_RESULTS tr
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE sc.NAME = 'ISB'
  AND tr.TERM = 'Spring 2025'
GROUP BY d.NAME, sc.NAME, c.SUBJECT, tr.TERM;

-- ============================================================================
-- CONFLICT SCENARIO 7: Join Count Penalty + Aggregation + UC1
-- Expected Winner: rule_aggregation_heavy_long_ttl (priority 48)
-- Competing Rules: UC1 (40), Join Count (42), Heavy Agg (48)
-- ============================================================================

-- QUERY CS7.1: 5 joins + 6 aggregations
-- Expected: Heavy aggregation wins (48 > 42), TTL=1800s
SELECT
  d.NAME AS DISTRICT,
  sc.NAME AS SCHOOL,
  e.FIRST_NAME || ' ' || e.LAST_NAME AS EDUCATOR,
  c.NAME AS CLASS_NAME,
  tr.TERM,
  COUNT(DISTINCT s.STUDENT_ID) AS unique_students,
  AVG(tr.SCORE) AS avg_score,
  STDDEV(tr.SCORE) AS stddev_score,
  MIN(tr.SCORE) AS min_score,
  MAX(tr.SCORE) AS max_score,
  SUM(tr.SCORE) AS total_score
FROM TEST_RESULTS tr
JOIN STUDENT s ON tr.STUDENT_ID = s.STUDENT_ID
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
JOIN EDUCATOR e ON c.EDUCATOR_ID = e.EDUCATOR_ID
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE tr.TEST_YEAR = 2025
GROUP BY d.NAME, sc.NAME, e.FIRST_NAME, e.LAST_NAME, c.NAME, tr.TERM;

-- QUERY CS7.2: 5 joins but only 2 aggregations
-- Expected: rule_join_count_penalty wins (priority 42), TTL=400s
SELECT
  d.NAME,
  sc.NAME,
  e.FIRST_NAME,
  c.NAME,
  COUNT(*) AS num_results,
  AVG(tr.SCORE) AS avg_score
FROM TEST_RESULTS tr
JOIN STUDENT s ON tr.STUDENT_ID = s.STUDENT_ID
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
JOIN EDUCATOR e ON c.EDUCATOR_ID = e.EDUCATOR_ID
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE tr.TERM = 'Fall 2025'
GROUP BY d.NAME, sc.NAME, e.FIRST_NAME, c.NAME;

-- ============================================================================
-- CONFLICT SCENARIO 8: LIMIT Clause + UC1 + Preview Query
-- Expected Winner: rule_uc1_district_term_summary (priority 40)
-- Competing Rules: Baseline (10), Limit Clause (38), UC1 (40)
-- ============================================================================

-- QUERY CS8.1: UC1 pattern with LIMIT 50
-- Expected: UC1 wins (40 > 38), TTL=300s
-- Note: LIMIT doesn't affect rule matching, UC1 still most specific
SELECT
  d.NAME,
  sc.NAME,
  c.SUBJECT,
  tr.TERM,
  COUNT(*) AS num_results
FROM TEST_RESULTS tr
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE tr.TERM = 'Winter 2025'
GROUP BY d.NAME, sc.NAME, c.SUBJECT, tr.TERM
LIMIT 50;

-- QUERY CS8.2: Simple query with LIMIT 100 (matches preview rule)
-- Expected: rule_limit_clause_detection wins (priority 38), TTL=120s
SELECT
  s.STUDENT_ID,
  s.FIRST_NAME,
  s.LAST_NAME,
  tr.SCORE
FROM STUDENT s
JOIN TEST_RESULTS tr ON s.STUDENT_ID = tr.STUDENT_ID
WHERE tr.TERM = 'Fall 2025'
ORDER BY tr.SCORE DESC
LIMIT 100;

-- QUERY CS8.3: Same query with LIMIT 1000 (exceeds limit rule threshold)
-- Expected: Does NOT match limit rule, falls back to baseline (10)
SELECT
  s.STUDENT_ID,
  s.FIRST_NAME,
  tr.SCORE
FROM STUDENT s
JOIN TEST_RESULTS tr ON s.STUDENT_ID = tr.STUDENT_ID
WHERE tr.TERM = 'Fall 2025'
ORDER BY tr.SCORE DESC
LIMIT 1000;

-- ============================================================================
-- CONFLICT SCENARIO 9: API vs Dashboard Origin Isolation
-- Expected Winner: rule_api_vs_dashboard_isolation (priority 47)
-- Competing Rules: UC1 (40), API Isolation (47)
-- ============================================================================

-- QUERY CS9.1: UC1 pattern from API origin
-- Simulate headers: x-origin=api
-- Expected: API isolation wins (47 > 40), TTL=300s, cache key includes origin
SELECT
  d.NAME,
  sc.NAME,
  tr.TERM,
  AVG(tr.SCORE) AS avg_score
FROM TEST_RESULTS tr
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE tr.TERM = 'Spring 2025'
GROUP BY d.NAME, sc.NAME, tr.TERM;

-- QUERY CS9.2: Same query from dashboard origin
-- Simulate headers: x-origin=dashboard
-- Expected: UC1 wins (priority 40), separate cache from CS9.1

-- ============================================================================
-- CONFLICT SCENARIO 10: Exploratory No-Cache Override
-- Expected Winner: rule_exploratory_no_cache (priority 95)
-- Competing Rules: UC8 (45/75), UC4 (90), Exploratory (95)
-- ============================================================================

-- QUERY CS10.1: UC8 educator portfolio from Tableau Prep
-- Simulate headers: x-origin=tableau_prep
-- Expected: Exploratory no-cache wins (95 > 75), cache disabled
SELECT * FROM VW_DASH_EDUCATOR_PORTFOLIO_2025
WHERE SCHOOL = 'West View';

-- QUERY CS10.2: UC4 completeness from DBeaver
-- Simulate headers: x-origin=dbeaver
-- Expected: Exploratory wins (95 > 90), cache disabled
SELECT
  e.EDUCATOR_ID,
  c.NAME AS CLASS_NAME,
  COUNT(CASE WHEN tr.TERM = 'Fall 2025' THEN 1 END) AS fall_results_count
FROM CLASS c
JOIN EDUCATOR e ON c.EDUCATOR_ID = e.EDUCATOR_ID
LEFT JOIN TEST_RESULTS tr ON c.CLASS_ID = tr.CLASS_ID
GROUP BY e.EDUCATOR_ID, c.NAME;

-- ============================================================================
-- CONFLICT SCENARIO 11: DISTINCT Query + UC5 + Student Missing Terms
-- Expected Winner: rule_uc5_at_risk_students (priority 60)
-- Competing Rules: Distinct (36), UC5 (60)
-- ============================================================================

-- QUERY CS11.1: At-risk students with DISTINCT
-- Expected: UC5 wins (60 > 36), TTL=600s, cache key includes userRole
SELECT DISTINCT
  s.STUDENT_ID,
  s.FIRST_NAME,
  s.LAST_NAME,
  COUNT(DISTINCT tr.TERM) AS terms_present
FROM STUDENT s
LEFT JOIN TEST_RESULTS tr ON s.STUDENT_ID = tr.STUDENT_ID
WHERE tr.TEST_YEAR = 2025
GROUP BY s.STUDENT_ID, s.FIRST_NAME, s.LAST_NAME
HAVING COUNT(DISTINCT tr.TERM) < 3;

-- QUERY CS11.2: Simple DISTINCT without at-risk pattern
-- Expected: rule_distinct_select_short_ttl wins (priority 36), TTL=200s
SELECT DISTINCT
  s.STUDENT_ID,
  s.GRADE,
  s.STATUS
FROM STUDENT s
WHERE s.SCHOOL_ID IN (SELECT SCHOOL_ID FROM SCHOOL WHERE NAME = 'West View');

-- ============================================================================
-- CONFLICT SCENARIO 12: CI/CD Environment Override
-- Expected Winner: rule_ci_cd_test_no_cache (priority 98)
-- Competing Rules: Debug (99 - only if debug header), CI/CD (98), Any Other
-- ============================================================================

-- QUERY CS12.1: UC1 query in CI/CD environment
-- Simulate headers: x-environment=ci_cd
-- Expected: CI/CD no-cache wins (priority 98), cache disabled
SELECT
  d.NAME,
  sc.NAME,
  tr.TERM,
  COUNT(*) AS num_results
FROM TEST_RESULTS tr
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE tr.TERM = 'Fall 2025'
GROUP BY d.NAME, sc.NAME, tr.TERM;

-- QUERY CS12.2: Same query in production environment
-- Simulate headers: x-environment=production
-- Expected: UC1 wins (priority 40), cache enabled

-- ============================================================================
-- EXTREME CONFLICT SCENARIO 13: Maximum Rule Collision (8+ rules)
-- Expected Winner: rule_developer_debug_bypass (priority 99) IF debug header
--                  Otherwise: highest matching priority
-- ============================================================================

-- QUERY CS13.1: Kitchen sink query - triggers many rules
-- Matching: Baseline (10), Large Result (35), Limit (38), UC1 (40), 
--           Join Count (42), Heavy Agg (48), West View (52), Window (53),
--           Morning Peak (65), Current Date (72), Premium (85)
-- Simulate headers: x-tenant=premium, x-request-time=08:15:00
-- Expected: Premium tenant wins (priority 85), TTL=60s
SELECT
  d.NAME AS DISTRICT,
  sc.NAME AS SCHOOL,
  c.SUBJECT,
  tr.TERM,
  COUNT(DISTINCT s.STUDENT_ID) AS unique_students,
  AVG(tr.SCORE) AS avg_score,
  STDDEV(tr.SCORE) AS stddev_score,
  MIN(tr.SCORE) AS min_score,
  MAX(tr.SCORE) AS max_score,
  SUM(tr.SCORE) AS total_score,
  ROW_NUMBER() OVER (PARTITION BY tr.TERM ORDER BY AVG(tr.SCORE) DESC) AS rank_by_term,
  DATEDIFF(day, tr.TEST_DATE, CURRENT_DATE()) AS days_ago
FROM TEST_RESULTS tr
JOIN STUDENT s ON tr.STUDENT_ID = s.STUDENT_ID
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE sc.NAME = 'West View'
  AND tr.TEST_DATE >= CURRENT_DATE() - 90
  AND tr.TERM IN ('Fall 2025', 'Winter 2025', 'Spring 2025')
GROUP BY d.NAME, sc.NAME, c.SUBJECT, tr.TERM, tr.TEST_DATE
ORDER BY rank_by_term
LIMIT 100;

-- QUERY CS13.2: Same query with debug header
-- Simulate headers: x-debug=true, x-tenant=premium, x-request-time=08:15:00
-- Expected: Debug bypass wins (priority 99), cache disabled

-- ============================================================================
-- VALIDATION QUERIES: Verify cache behavior across dimensions
-- ============================================================================

-- VALIDATION 1: Same SQL, different tenants (should create separate caches)
-- Run with x-tenant=standard then x-tenant=premium
SELECT sc.NAME, AVG(tr.SCORE) AS avg_score
FROM TEST_RESULTS tr
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
WHERE tr.TERM = 'Fall 2025'
GROUP BY sc.NAME;

-- VALIDATION 2: Same SQL, different origins (should create separate caches)
-- Run with x-origin=api then x-origin=dashboard
SELECT s.STUDENT_ID, AVG(tr.SCORE) AS avg_score
FROM STUDENT s
JOIN TEST_RESULTS tr ON s.STUDENT_ID = tr.STUDENT_ID
WHERE tr.TERM = 'Winter 2025'
GROUP BY s.STUDENT_ID;

-- VALIDATION 3: Same SQL, different times (morning vs afternoon)
-- Run at 08:00 then 14:00 to test time-based rule
SELECT COUNT(*) AS result_count FROM TEST_RESULTS WHERE TERM = 'Fall 2025';

-- ============================================================================
-- PERFORMANCE BENCHMARK QUERIES
-- ============================================================================

-- BENCHMARK 1: Cache effectiveness on expensive query
-- First run: MISS (2-5 seconds), Second run: HIT (<100ms)
SELECT
  d.NAME,
  sc.NAME,
  c.SUBJECT,
  tr.TERM,
  COUNT(*) AS total_results,
  AVG(tr.SCORE) AS avg_score,
  STDDEV(tr.SCORE) AS stddev,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY tr.SCORE) AS p25,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY tr.SCORE) AS p50,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY tr.SCORE) AS p75,
  PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY tr.SCORE) AS p90
FROM TEST_RESULTS tr
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE tr.TEST_YEAR = 2025
GROUP BY d.NAME, sc.NAME, c.SUBJECT, tr.TERM;

-- ============================================================================
-- NEGATIVE TEST CASES: Queries that should NOT match advanced rules
-- ============================================================================

-- NEGATIVE 1: Has math_score but missing reading_score (should NOT match UC6)
SELECT
  s.STUDENT_ID,
  AVG(CASE WHEN c.SUBJECT = 'Math' THEN tr.SCORE END) AS math_score
FROM TEST_RESULTS tr
JOIN STUDENT s ON tr.STUDENT_ID = s.STUDENT_ID
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
GROUP BY s.STUDENT_ID;

-- NEGATIVE 2: Has 4 joins but <5 aggregations (should NOT match heavy agg rule)
SELECT
  d.NAME,
  sc.NAME,
  COUNT(*) AS num_results,
  AVG(tr.SCORE) AS avg_score
FROM TEST_RESULTS tr
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
GROUP BY d.NAME, sc.NAME;

-- NEGATIVE 3: LIMIT 150 (exceeds threshold, should NOT match limit rule)
SELECT * FROM STUDENT LIMIT 150;


-- ============================================================================
-- AirBrx Cache Rules Engine: Priority & Conflict Testing Suite
-- NWEA Assessment Database - Comprehensive Edge Cases
-- ============================================================================
-- Purpose: Test rule priority, conflicts, and multi-dimensional matching
-- Database: NWEA.ASSESSMENT_BSD
-- Target: AirBrx Cache Rules Engine validation
-- ============================================================================

USE DATABASE NWEA;
USE SCHEMA ASSESSMENT_BSD;

-- ============================================================================
-- SECTION 1: BASELINE vs SPECIFIC RULE CONFLICTS
-- Testing: rule_global_nwea_baseline (priority 10) vs higher priority rules
-- ============================================================================

-- TEST 1.1: Pure baseline match (should use rule_global_nwea_baseline, priority 10)
-- Expected: TTL=60s, cache enabled
-- Why: Only matches the baseline rule with no other overlapping conditions
SELECT COUNT(*) AS total_records FROM DISTRICT;

-- TEST 1.2: Baseline vs UC1 conflict (should use rule_uc1_district_term_summary, priority 40)
-- Expected: TTL=300s, cache enabled
-- Why: Matches both baseline (10) and UC1 (40), higher priority wins
SELECT
  d.NAME AS DISTRICT,
  sc.NAME AS SCHOOL,
  c.SUBJECT,
  tr.TERM,
  COUNT(*) AS num_results
FROM TEST_RESULTS tr
JOIN STUDENT s ON tr.STUDENT_ID = s.STUDENT_ID
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE tr.TERM = 'Fall 2025'
GROUP BY d.NAME, sc.NAME, c.SUBJECT, tr.TERM;

-- TEST 1.3: Baseline vs UC2 view conflict (should use rule_uc2_class_growth_fall_winter, priority 70)
-- Expected: TTL=900s, cache enabled
-- Why: View match is more specific than baseline
SELECT * FROM VW_DASH_CLASS_GROWTH_2025 LIMIT 100;

-- ============================================================================
-- SECTION 2: SAME-TABLE MULTI-CONDITION CONFLICTS
-- Testing: Multiple rules matching same base tables with different column filters
-- ============================================================================

-- TEST 2.1: UC1 vs UC5 conflict - both use TEST_RESULTS + different columns
-- Expected: UC1 wins (priority 40) because it has TERM column
-- Query has TERM but not terms_present
SELECT
  sc.NAME AS SCHOOL,
  tr.TERM,
  COUNT(DISTINCT s.STUDENT_ID) AS student_count,
  AVG(tr.SCORE) AS avg_score
FROM TEST_RESULTS tr
JOIN STUDENT s ON tr.STUDENT_ID = s.STUDENT_ID
JOIN SCHOOL sc ON s.SCHOOL_ID = sc.SCHOOL_ID
WHERE tr.TEST_YEAR = 2025
GROUP BY sc.NAME, tr.TERM;

-- TEST 2.2: UC5 specific match - should use rule_uc5_at_risk_students (priority 60)
-- Expected: TTL=600s, cacheKey includes userRole
-- Why: Has terms_present column which is specific to UC5
SELECT
  s.STUDENT_ID,
  s.FIRST_NAME,
  s.LAST_NAME,
  sc.NAME AS SCHOOL,
  COUNT(DISTINCT tr.TERM) AS terms_present,
  LISTAGG(DISTINCT tr.TERM, ', ') AS term_list
FROM STUDENT s
JOIN SCHOOL sc ON s.SCHOOL_ID = sc.SCHOOL_ID
LEFT JOIN TEST_RESULTS tr ON s.STUDENT_ID = tr.STUDENT_ID
  AND tr.TEST_YEAR = 2025
GROUP BY s.STUDENT_ID, s.FIRST_NAME, s.LAST_NAME, sc.NAME
HAVING COUNT(DISTINCT tr.TERM) < 3;

-- TEST 2.3: UC6 vs UC1 conflict - both use TEST_RESULTS, UC6 more specific
-- Expected: UC6 wins (priority 50) due to math_score/reading_score columns
SELECT
  s.STUDENT_ID,
  s.FIRST_NAME,
  AVG(CASE WHEN c.SUBJECT = 'Math' THEN tr.SCORE END) AS math_score,
  AVG(CASE WHEN c.SUBJECT = 'Reading' THEN tr.SCORE END) AS reading_score,
  tr.TERM
FROM TEST_RESULTS tr
JOIN STUDENT s ON tr.STUDENT_ID = s.STUDENT_ID
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
WHERE tr.TERM = 'Fall 2025'
GROUP BY s.STUDENT_ID, s.FIRST_NAME, tr.TERM;

-- ============================================================================
-- SECTION 3: ROLE-BASED CACHE KEY CONFLICTS (Multi-dimensional)
-- Testing: Same query with different user roles/contexts
-- ============================================================================

-- TEST 3.1: UC8 teacher role (should use rule_uc8_educator_portfolio_default, priority 45)
-- Simulate: userRole = 'teacher'
-- Expected: TTL=600s, cacheKey=[userId, standardizedSql]
SELECT * FROM VW_DASH_EDUCATOR_PORTFOLIO_2025
WHERE EDUCATOR_ID = 'some-uuid-here';

-- TEST 3.2: UC8 district_admin role (should use rule_uc8_educator_portfolio_admin_override, priority 75)
-- Simulate: userRole = 'district_admin'
-- Expected: TTL=120s, cacheKey=[userRole, standardizedSql]
-- Why: Same query but higher priority override for admin
SELECT * FROM VW_DASH_EDUCATOR_PORTFOLIO_2025
WHERE SCHOOL IN ('West View', 'ISB', 'BASE');

-- TEST 3.3: UC3 with userId scoping (should use rule_uc3_student_term_growth, priority 80)
-- Simulate: userId specific context
-- Expected: TTL=120s, cacheKey=[userId, standardizedSql]
-- Why: Per-user drilldown requires user isolation
SELECT
  s.STUDENT_ID,
  s.FIRST_NAME,
  s.LAST_NAME,
  AVG(CASE WHEN tr.TERM = 'Fall 2025' THEN tr.SCORE END) AS score_fall,
  AVG(CASE WHEN tr.TERM = 'Winter 2025' THEN tr.SCORE END) AS score_winter,
  AVG(CASE WHEN tr.TERM = 'Spring 2025' THEN tr.SCORE END) AS score_spring
FROM STUDENT s
JOIN TEST_RESULTS tr ON s.STUDENT_ID = tr.STUDENT_ID
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
WHERE s.STUDENT_ID = 'specific-student-uuid'
GROUP BY s.STUDENT_ID, s.FIRST_NAME, s.LAST_NAME;

-- ============================================================================
-- SECTION 4: NO-CACHE OVERRIDE TESTS (Highest priority enforcement)
-- Testing: rule_uc4_educator_completeness_nocache (priority 90)
-- ============================================================================

-- TEST 4.1: UC4 no-cache match (should use rule_uc4_educator_completeness_nocache, priority 90)
-- Expected: Cache DISABLED, always hits warehouse
-- Why: Has fall_results_count column, highest priority forces fresh data
SELECT
  e.EDUCATOR_ID,
  e.FIRST_NAME || ' ' || e.LAST_NAME AS EDUCATOR_NAME,
  sc.NAME AS SCHOOL,
  c.NAME AS CLASS_NAME,
  c.SUBJECT,
  COUNT(CASE WHEN tr.TERM = 'Fall 2025' THEN 1 END) AS fall_results_count,
  COUNT(CASE WHEN tr.TERM = 'Winter 2025' THEN 1 END) AS winter_results_count,
  COUNT(CASE WHEN tr.TERM = 'Spring 2025' THEN 1 END) AS spring_results_count
FROM CLASS c
JOIN SCHOOL sc ON c.SCHOOL_ID = sc.SCHOOL_ID
JOIN EDUCATOR e ON c.EDUCATOR_ID = e.EDUCATOR_ID
LEFT JOIN TEST_RESULTS tr ON c.CLASS_ID = tr.CLASS_ID AND tr.TEST_YEAR = 2025
GROUP BY e.EDUCATOR_ID, e.FIRST_NAME, e.LAST_NAME, sc.NAME, c.NAME, c.SUBJECT;

-- TEST 4.2: Similar query WITHOUT fall_results_count (should NOT match UC4)
-- Expected: Falls back to lower priority rule or baseline
SELECT
  e.EDUCATOR_ID,
  e.FIRST_NAME || ' ' || e.LAST_NAME AS EDUCATOR_NAME,
  sc.NAME AS SCHOOL,
  c.NAME AS CLASS_NAME,
  c.SUBJECT,
  COUNT(*) AS total_results
FROM CLASS c
JOIN SCHOOL sc ON c.SCHOOL_ID = sc.SCHOOL_ID
JOIN EDUCATOR e ON c.EDUCATOR_ID = e.EDUCATOR_ID
LEFT JOIN TEST_RESULTS tr ON c.CLASS_ID = tr.CLASS_ID
GROUP BY e.EDUCATOR_ID, e.FIRST_NAME, e.LAST_NAME, sc.NAME, c.NAME, c.SUBJECT;

-- ============================================================================
-- SECTION 5: COLUMN-SPECIFICITY EDGE CASES
-- Testing: Queries with overlapping table matches but distinct column signatures
-- ============================================================================

-- TEST 5.1: UC7 percentile bands (should use rule_uc7_class_distribution, priority 55)
-- Expected: TTL=300s
-- Why: Has all three band columns (below_25, mid_25_75, above_75)
SELECT
  d.NAME AS DISTRICT,
  sc.NAME AS SCHOOL,
  c.NAME AS CLASS_NAME,
  c.SUBJECT,
  tr.TERM,
  COUNT(*) AS num_results,
  COUNT(CASE WHEN tr.PERCENTILE < 25 THEN 1 END) AS below_25,
  COUNT(CASE WHEN tr.PERCENTILE BETWEEN 25 AND 75 THEN 1 END) AS mid_25_75,
  COUNT(CASE WHEN tr.PERCENTILE > 75 THEN 1 END) AS above_75
FROM TEST_RESULTS tr
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE tr.TERM = 'Spring 2025'
GROUP BY d.NAME, sc.NAME, c.NAME, c.SUBJECT, tr.TERM;

-- TEST 5.2: Partial band query (missing one band column)
-- Expected: Should NOT match UC7, falls back to UC1 or baseline
SELECT
  c.NAME AS CLASS_NAME,
  c.SUBJECT,
  COUNT(CASE WHEN tr.PERCENTILE < 25 THEN 1 END) AS below_25,
  COUNT(CASE WHEN tr.PERCENTILE BETWEEN 25 AND 75 THEN 1 END) AS mid_25_75
FROM TEST_RESULTS tr
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
WHERE tr.TERM = 'Spring 2025'
GROUP BY c.NAME, c.SUBJECT;

-- TEST 5.3: UC6 math/reading both present (should use rule_uc6_cross_subject_correlation, priority 50)
-- Expected: TTL=300s
WITH tr_math AS (
  SELECT STUDENT_ID, TERM, SCORE AS math_score
  FROM TEST_RESULTS
  WHERE TEST_YEAR = 2025 AND SUBJECT = 'Math'
),
tr_read AS (
  SELECT STUDENT_ID, TERM, SCORE AS reading_score
  FROM TEST_RESULTS
  WHERE TEST_YEAR = 2025 AND SUBJECT = 'Reading'
)
SELECT
  s.STUDENT_ID,
  tm.TERM,
  tm.math_score,
  tr.reading_score,
  (tm.math_score - tr.reading_score) AS math_minus_reading
FROM tr_math tm
JOIN tr_read tr ON tm.STUDENT_ID = tr.STUDENT_ID AND tm.TERM = tr.TERM
JOIN STUDENT s ON tm.STUDENT_ID = s.STUDENT_ID
WHERE tm.TERM = 'Fall 2025';

-- TEST 5.4: Only math_score present (should NOT match UC6)
-- Expected: Falls back to UC1 (priority 40) or baseline (priority 10)
SELECT
  s.STUDENT_ID,
  tr.TERM,
  AVG(CASE WHEN c.SUBJECT = 'Math' THEN tr.SCORE END) AS math_score
FROM TEST_RESULTS tr
JOIN STUDENT s ON tr.STUDENT_ID = s.STUDENT_ID
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
WHERE tr.TERM = 'Fall 2025'
GROUP BY s.STUDENT_ID, tr.TERM;

-- ============================================================================
-- SECTION 6: BOUNDARY CONDITION TESTS
-- Testing: Minimal/maximal matching conditions
-- ============================================================================

-- TEST 6.1: Query matching only schema + statement (baseline only)
-- Expected: rule_global_nwea_baseline (priority 10), TTL=60s
SELECT CURRENT_TIMESTAMP() AS query_time;

-- TEST 6.2: All tables present but no specific columns
-- Expected: Matches multiple rules, highest priority with all table conditions wins
SELECT
  d.NAME,
  sc.NAME,
  e.FIRST_NAME,
  c.NAME,
  s.FIRST_NAME,
  tr.SCORE
FROM DISTRICT d
JOIN SCHOOL sc ON d.DISTRICT_ID = sc.DISTRICT_ID
JOIN EDUCATOR e ON sc.SCHOOL_ID = e.SCHOOL_ID
JOIN CLASS c ON e.EDUCATOR_ID = c.EDUCATOR_ID
JOIN STUDENT s ON c.CLASS_ID = s.CLASS_ID
JOIN TEST_RESULTS tr ON s.STUDENT_ID = tr.STUDENT_ID
WHERE tr.TERM = 'Spring 2025'
LIMIT 10;

-- TEST 6.3: View query with filter (UC2, priority 70)
-- Expected: TTL=900s
SELECT
  DISTRICT,
  SCHOOL,
  CLASS_NAME,
  SUBJECT,
  score_delta
FROM VW_DASH_CLASS_GROWTH_2025
WHERE score_delta > 5
ORDER BY score_delta DESC;

-- ============================================================================
-- SECTION 7: NEGATIVE TEST CASES (Should NOT match specific rules)
-- Testing: Queries designed to miss rule conditions
-- ============================================================================

-- TEST 7.1: Missing required TERM column for UC1
-- Expected: Should NOT match UC1, falls back to baseline
SELECT
  d.NAME AS DISTRICT,
  sc.NAME AS SCHOOL,
  COUNT(*) AS num_results,
  AVG(tr.SCORE) AS avg_score
FROM TEST_RESULTS tr
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
GROUP BY d.NAME, sc.NAME;

-- TEST 7.2: Wrong statement type (UPDATE instead of SELECT)
-- Expected: Should NOT match any cache rules (all require SELECT)
-- (This is conceptual - don't actually run UPDATE in testing)
-- UPDATE TEST_RESULTS SET SCORE = SCORE + 1 WHERE TERM = 'Fall 2025';

-- TEST 7.3: Query on excluded table
-- Expected: Falls back to baseline or no cache
SELECT * FROM DISTRICT WHERE STATE = 'OR';

-- TEST 7.4: View query but wrong view name
-- Expected: Does not match UC2 or UC8 view-specific rules
CREATE OR REPLACE VIEW VW_TEST_TEMP AS
SELECT * FROM TEST_RESULTS WHERE TERM = 'Spring 2025';
SELECT * FROM VW_TEST_TEMP LIMIT 10;

-- ============================================================================
-- SECTION 8: COMPLEX MULTI-RULE CONFLICTS (3+ rules competing)
-- Testing: Scenarios where 3 or more rules could match
-- ============================================================================

-- TEST 8.1: Three-way conflict: Baseline (10) vs UC1 (40) vs UC6 (50)
-- Has: DISTRICT, SCHOOL, TEST_RESULTS, TERM, math_score, reading_score
-- Expected: UC6 wins (priority 50) due to most specific column match
SELECT
  d.NAME AS DISTRICT,
  sc.NAME AS SCHOOL,
  tr.TERM,
  AVG(CASE WHEN c.SUBJECT = 'Math' THEN tr.SCORE END) AS math_score,
  AVG(CASE WHEN c.SUBJECT = 'Reading' THEN tr.SCORE END) AS reading_score
FROM TEST_RESULTS tr
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE tr.TERM IN ('Fall 2025', 'Winter 2025', 'Spring 2025')
GROUP BY d.NAME, sc.NAME, tr.TERM;

-- TEST 8.2: Four-way conflict: Baseline (10) vs UC1 (40) vs UC5 (60) vs UC7 (55)
-- Has: STUDENT, TEST_RESULTS, TERM, terms_present, below_25, mid_25_75, above_75
-- Expected: UC5 (60) wins over UC7 (55) if terms_present is selected
SELECT
  s.STUDENT_ID,
  s.FIRST_NAME,
  COUNT(DISTINCT tr.TERM) AS terms_present,
  COUNT(CASE WHEN tr.PERCENTILE < 25 THEN 1 END) AS below_25,
  COUNT(CASE WHEN tr.PERCENTILE BETWEEN 25 AND 75 THEN 1 END) AS mid_25_75,
  COUNT(CASE WHEN tr.PERCENTILE > 75 THEN 1 END) AS above_75
FROM STUDENT s
LEFT JOIN TEST_RESULTS tr ON s.STUDENT_ID = tr.STUDENT_ID
WHERE tr.TERM IN ('Fall 2025', 'Winter 2025', 'Spring 2025')
GROUP BY s.STUDENT_ID, s.FIRST_NAME;

-- ============================================================================
-- SECTION 9: CACHE KEY ELEMENT VALIDATION
-- Testing: Verify different cache key strategies produce distinct cache entries
-- ============================================================================

-- TEST 9.1: Same query, different userId context (UC3)
-- Execute with userId='user-001', then userId='user-002'
-- Expected: Two separate cache entries
SELECT
  s.STUDENT_ID,
  AVG(CASE WHEN tr.TERM = 'Fall 2025' THEN tr.SCORE END) AS score_fall
FROM STUDENT s
JOIN TEST_RESULTS tr ON s.STUDENT_ID = tr.STUDENT_ID
WHERE s.SCHOOL_ID IN (SELECT SCHOOL_ID FROM SCHOOL WHERE NAME = 'West View')
GROUP BY s.STUDENT_ID;

-- TEST 9.2: Same query, different userRole context (UC5)
-- Execute with userRole='teacher', then userRole='admin'
-- Expected: Two separate cache entries due to userRole in cacheKey
SELECT
  s.STUDENT_ID,
  s.FIRST_NAME,
  COUNT(DISTINCT tr.TERM) AS terms_present
FROM STUDENT s
LEFT JOIN TEST_RESULTS tr ON s.STUDENT_ID = tr.STUDENT_ID
WHERE tr.TEST_YEAR = 2025
GROUP BY s.STUDENT_ID, s.FIRST_NAME
HAVING COUNT(DISTINCT tr.TERM) < 3;

-- TEST 9.3: Same query, same role but different SQL formatting
-- Expected: Should match same cache (standardizedSql normalization)
SELECT   s.STUDENT_ID  ,   COUNT(DISTINCT tr.TERM)   AS   terms_present
FROM   STUDENT   s
LEFT   JOIN   TEST_RESULTS   tr   ON   s.STUDENT_ID   =   tr.STUDENT_ID
WHERE  tr.TEST_YEAR  =  2025
GROUP   BY   s.STUDENT_ID
HAVING   COUNT(DISTINCT tr.TERM)   <   3;

-- ============================================================================
-- SECTION 10: STRESS TEST QUERIES (Large result sets, complex joins)
-- Testing: Performance and caching behavior under load
-- ============================================================================

-- TEST 10.1: Cartesian explosion (intentionally large)
-- Expected: Still gets cached if matches a rule
SELECT
  d.NAME AS DISTRICT,
  sc.NAME AS SCHOOL,
  c.NAME AS CLASS_NAME,
  s.FIRST_NAME AS STUDENT_FIRST,
  tr.TERM,
  tr.SCORE
FROM DISTRICT d
CROSS JOIN SCHOOL sc
CROSS JOIN CLASS c
CROSS JOIN STUDENT s
CROSS JOIN TEST_RESULTS tr
WHERE tr.TEST_YEAR = 2025
LIMIT 1000;

-- TEST 10.2: Deep aggregation hierarchy
-- Expected: Matches UC1 (priority 40), TTL=300s
SELECT
  d.NAME AS DISTRICT,
  sc.NAME AS SCHOOL,
  c.SUBJECT,
  tr.TERM,
  COUNT(DISTINCT s.STUDENT_ID) AS unique_students,
  COUNT(*) AS total_results,
  AVG(tr.SCORE) AS avg_score,
  STDDEV(tr.SCORE) AS stddev_score,
  MIN(tr.SCORE) AS min_score,
  MAX(tr.SCORE) AS max_score,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY tr.SCORE) AS p25,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY tr.SCORE) AS p50,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY tr.SCORE) AS p75
FROM TEST_RESULTS tr
JOIN STUDENT s ON tr.STUDENT_ID = s.STUDENT_ID
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE tr.TEST_YEAR = 2025
GROUP BY d.NAME, sc.NAME, c.SUBJECT, tr.TERM
ORDER BY d.NAME, sc.NAME, c.SUBJECT, tr.TERM;

-- ============================================================================
-- SECTION 11: TEMPORAL/DATE FILTER EDGE CASES
-- Testing: How date filters affect rule matching
-- ============================================================================

-- TEST 11.1: Specific date range (still UC1)
-- Expected: Matches UC1 (priority 40) because has DISTRICT, SCHOOL, TEST_RESULTS, TERM
SELECT
  d.NAME AS DISTRICT,
  sc.NAME AS SCHOOL,
  c.SUBJECT,
  tr.TERM,
  COUNT(*) AS num_results,
  AVG(tr.SCORE) AS avg_score
FROM TEST_RESULTS tr
JOIN CLASS c ON tr.CLASS_ID = c.CLASS_ID
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
JOIN DISTRICT d ON sc.DISTRICT_ID = d.DISTRICT_ID
WHERE tr.TEST_DATE BETWEEN '2025-01-01' AND '2025-03-31'
  AND tr.TERM = 'Winter 2025'
GROUP BY d.NAME, sc.NAME, c.SUBJECT, tr.TERM;

-- TEST 11.2: No TERM filter (might NOT match UC1)
-- Expected: Falls back to baseline or lower priority
SELECT
  sc.NAME AS SCHOOL,
  COUNT(*) AS num_results
FROM TEST_RESULTS tr
JOIN SCHOOL sc ON tr.SCHOOL_ID = sc.SCHOOL_ID
WHERE tr.TEST_DATE >= '2025-01-01'
GROUP BY sc.NAME;

-- ============================================================================
-- SECTION 12: NULL HANDLING AND OPTIONAL JOINS
-- Testing: LEFT JOIN scenarios from UC4 and UC8
-- ============================================================================

-- TEST 12.1: Classes with no test results (UC4 pattern)
-- Expected: Matches UC4 (priority 90), no cache
SELECT
  c.CLASS_ID,
  c.NAME AS CLASS_NAME,
  c.SUBJECT,
  COUNT(tr.TEST_RESULT_ID) AS result_count,
  COUNT(CASE WHEN tr.TERM = 'Fall 2025' THEN 1 END) AS fall_results_count
FROM CLASS c
LEFT JOIN TEST_RESULTS tr ON c.CLASS_ID = tr.CLASS_ID AND tr.TEST_YEAR = 2025
GROUP BY c.CLASS_ID, c.NAME, c.SUBJECT
HAVING COUNT(tr.TEST_RESULT_ID) = 0;

-- TEST 12.2: Educators with partial results (UC8 pattern)
-- Expected: Matches UC8 default (priority 45) if teacher role
SELECT
  e.EDUCATOR_ID,
  e.FIRST_NAME || ' ' || e.LAST_NAME AS EDUCATOR_NAME,
  c.NAME AS CLASS_NAME,
  AVG(CASE WHEN tr.TERM = 'Fall 2025' THEN tr.SCORE END) AS avg_fall_score,
  AVG(CASE WHEN tr.TERM = 'Winter 2025' THEN tr.SCORE END) AS avg_winter_score,
  AVG(CASE WHEN tr.TERM = 'Spring 2025' THEN tr.SCORE END) AS avg_spring_score
FROM EDUCATOR e
JOIN CLASS c ON e.EDUCATOR_ID = c.EDUCATOR_ID
LEFT JOIN TEST_RESULTS tr ON c.CLASS_ID = tr.CLASS_ID AND tr.TEST_YEAR = 2025
WHERE e.EDUCATOR_ID = 'specific-educator-uuid'
GROUP BY e.EDUCATOR_ID, e.FIRST_NAME, e.LAST_NAME, c.NAME;

-- ============================================================================
-- END OF EDGE CASE TEST SUITE
-- ============================================================================

-- VALIDATION QUERY: Check all rule priorities are distinct and ordered
-- (Conceptual - to document your rules)
/*
Rule Priority Order (Expected):
- rule_global_nwea_baseline: 10 (baseline)
- rule_uc1_district_term_summary: 40
- rule_uc8_educator_portfolio_default: 45
- rule_uc6_cross_subject_correlation: 50
- rule_uc7_class_distribution: 55
- rule_uc5_at_risk_students: 60
- rule_uc2_class_growth_fall_winter: 70
- rule_uc8_educator_portfolio_admin_override: 75
- rule_uc3_student_term_growth: 80
- rule_uc4_educator_completeness_nocache: 90 (highest, forces no-cache)
*/

-- ============================================================================
-- END OF ADVANCED CONFLICT TEST SUITE
-- ============================================================================

/*
SUMMARY OF ADVANCED TEST COVERAGE:

Dimensions Tested:
✅ Temporal (time of day)
✅ Tenant (standard vs premium)
✅ Role (teacher, admin, district_admin)
✅ Origin (api, dashboard, tableau_prep, dbeaver)
✅ Environment (production, ci_cd)
✅ Debug mode
✅ Query patterns (joins, aggregations, window functions, subqueries)
✅ SQL features (DISTINCT, LIMIT, CURRENT_DATE)
✅ Result size
✅ Filter specificity

Priority Ranges Covered:
- Baseline tier: 10-38
- Dashboard tier: 40-60
- Advanced tier: 65-85
- Override tier: 90-99

Expected Conflict Resolution Patterns:
1. Higher priority always wins
2. More specific conditions win at same priority
3. Debug/CI-CD modes override everything
4. Tenant/role dimensions create cache isolation
5. Temporal dimensions affect TTL strategy

Next Steps:
1. Execute each scenario twice (MISS then HIT)
2. Log all rule matching decisions
3. Verify cache key composition
4. Monitor Snowflake query execution
5. Calculate cache hit rates per rule
6. Identify priority gaps or conflicts
*/