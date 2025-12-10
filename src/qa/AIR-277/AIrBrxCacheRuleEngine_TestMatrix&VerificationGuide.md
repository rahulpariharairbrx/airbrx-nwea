# AirBrx Cache Rules Engine - Test Matrix & Verification Guide

## Overview
This document provides a comprehensive test matrix for validating the AirBrx cache rules engine with the NWEA Assessment dataset. Each test case includes expected behavior, verification steps, and conflict resolution logic.

---

## Test Execution Framework

### Pre-Test Setup
```bash
# Set test context variables
export TEST_USER_ID="test-user-001"
export TEST_USER_ROLE="teacher"
export TEST_TENANT="standard"

# Enable AirBrx logging
export AIRBRX_LOG_LEVEL="DEBUG"
export AIRBRX_LOG_CACHE_DECISIONS="true"
```

### Verification Checklist (Per Test)
- [ ] **Rule ID Applied**: Which rule was selected
- [ ] **Priority Verified**: Correct priority rule won
- [ ] **Cache Status**: HIT, MISS, or BYPASS
- [ ] **TTL Value**: Matches expected seconds
- [ ] **Cache Key Elements**: Correct dimensions included
- [ ] **Snowflake Query**: Executed (MISS) or not (HIT)
- [ ] **Response Time**: <100ms for HIT, >500ms for MISS

---

## Section 1: Baseline vs Specific Rule Conflicts

### TEST 1.1: Pure Baseline Match
**Query**: `SELECT COUNT(*) FROM DISTRICT;`

| Attribute | Expected Value |
|-----------|---------------|
| **Matching Rules** | rule_global_nwea_baseline |
| **Priority** | 10 |
| **Rule Winner** | rule_global_nwea_baseline |
| **Cache Enabled** | ✅ Yes |
| **TTL** | 60 seconds |
| **Cache Key** | [standardizedSql] |
| **First Request** | MISS → Snowflake hit |
| **Second Request** | HIT → No Snowflake query |

**Why This Rule Wins**: Only the baseline rule matches (schema=NWEA.ASSESSMENT_BSD + statement=SELECT). No other rules have overlapping conditions.

**Verification Steps**:
```bash
# Request 1
curl -X POST https://airbrx.gateway/query \
  -H "Content-Type: application/json" \
  -d '{"sql": "SELECT COUNT(*) FROM DISTRICT;"}'

# Check logs for:
# - "rule_applied": "rule_global_nwea_baseline"
# - "cache_status": "MISS"
# - "snowflake_query_executed": true

# Request 2 (within 60s)
curl -X POST https://airbrx.gateway/query \
  -H "Content-Type: application/json" \
  -d '{"sql": "SELECT COUNT(*) FROM DISTRICT;"}'

# Check logs for:
# - "cache_status": "HIT"
# - "snowflake_query_executed": false
```

---

### TEST 1.2: Baseline vs UC1 Conflict
**Query**: District term summary with TERM column

| Attribute | Expected Value |
|-----------|---------------|
| **Matching Rules** | rule_global_nwea_baseline (10), rule_uc1_district_term_summary (40) |
| **Priority Comparison** | 40 > 10 |
| **Rule Winner** | rule_uc1_district_term_summary |
| **Cache Enabled** | ✅ Yes |
| **TTL** | 300 seconds |
| **Cache Key** | [standardizedSql] |

**Why UC1 Wins**: Both rules match, but UC1 has higher priority (40 vs 10). UC1 is more specific with table and column conditions.

**Conflict Resolution Logic**:
```
IF query matches (schema=NWEA.ASSESSMENT_BSD AND statement=SELECT)
  THEN baseline matches
IF query ALSO matches (tables=[TEST_RESULTS, SCHOOL, DISTRICT] AND columns=[TERM])
  THEN UC1 matches
SINCE UC1.priority (40) > baseline.priority (10)
  APPLY UC1
```

---

### TEST 1.3: Baseline vs UC2 View Conflict
**Query**: `SELECT * FROM VW_DASH_CLASS_GROWTH_2025 LIMIT 100;`

| Attribute | Expected Value |
|-----------|---------------|
| **Matching Rules** | rule_global_nwea_baseline (10), rule_uc2_class_growth_fall_winter (70) |
| **Rule Winner** | rule_uc2_class_growth_fall_winter |
| **TTL** | 900 seconds (15 minutes) |

**Why UC2 Wins**: View-specific match is highly specific and has much higher priority.

---

## Section 2: Same-Table Multi-Condition Conflicts

### TEST 2.1: UC1 vs UC5 Conflict
**Query**: TEST_RESULTS with TERM but not terms_present

| Attribute | Expected Value |
|-----------|---------------|
| **Matching Rules** | rule_global_nwea_baseline (10), rule_uc1_district_term_summary (40), rule_uc5_at_risk_students (60)? |
| **Rule Winner** | rule_uc1_district_term_summary |
| **Why UC5 Doesn't Match** | Missing terms_present column |

**Column-Based Disambiguation**:
- UC1 requires: `columns.includes('TERM')` ✅
- UC5 requires: `columns.includes('terms_present')` ❌
- Result: Only UC1 matches

---

### TEST 2.2: UC5 Specific Match
**Query**: At-risk students with terms_present

| Attribute | Expected Value |
|-----------|---------------|
| **Matching Rules** | rule_global_nwea_baseline (10), rule_uc5_at_risk_students (60) |
| **Rule Winner** | rule_uc5_at_risk_students |
| **TTL** | 600 seconds |
| **Cache Key** | [userRole, standardizedSql] |

**Multi-User Isolation Test**:
```bash
# User with role 'teacher'
curl -H "x-user-role: teacher" ...
# Cache Key: teacher|<sql_hash>

# User with role 'counselor'
curl -H "x-user-role: counselor" ...
# Cache Key: counselor|<sql_hash>
# Result: TWO separate cache entries
```

---

### TEST 2.3: UC6 vs UC1 Conflict
**Query**: Math/Reading correlation with TERM

| Attribute | Expected Value |
|-----------|---------------|
| **Matching Rules** | Baseline (10), UC1 (40), UC6 (50) |
| **Rule Winner** | rule_uc6_cross_subject_correlation |
| **Why UC6 Wins** | Has both math_score AND reading_score columns (more specific) |

**Priority Chain**:
```
baseline (10) → UC1 (40) → UC6 (50)
         ↓         ↓          ↓
   generic    specific   most specific
```

---

## Section 3: Role-Based Multi-Dimensional Conflicts

### TEST 3.1 vs 3.2: UC8 Teacher vs Admin
**Same SQL, Different Roles**

| Test | User Role | Matching Rule | Priority | TTL | Cache Key |
|------|-----------|---------------|----------|-----|-----------|
| 3.1 | teacher | rule_uc8_educator_portfolio_default | 45 | 600s | [userId, standardizedSql] |
| 3.2 | district_admin | rule_uc8_educator_portfolio_admin_override | 75 | 120s | [userRole, standardizedSql] |

**Multi-Dimensional Matching**:
```json
{
  "rule_uc8_default": {
    "conditions": {
      "tables": ["VW_DASH_EDUCATOR_PORTFOLIO_2025"],
      "userRole": ["teacher", "educator"]
    },
    "priority": 45
  },
  "rule_uc8_admin_override": {
    "conditions": {
      "tables": ["VW_DASH_EDUCATOR_PORTFOLIO_2025"],
      "userRole": ["district_admin"]
    },
    "priority": 75
  }
}
```

**Result**: Role dimension creates distinct cache behavior for same SQL!

---

## Section 4: No-Cache Override (Highest Priority)

### TEST 4.1: UC4 No-Cache Enforcement
**Query**: Educator completeness with fall_results_count

| Attribute | Expected Value |
|-----------|---------------|
| **Matching Rules** | Baseline (10), UC4 (90) |
| **Rule Winner** | rule_uc4_educator_completeness_nocache |
| **Cache Enabled** | ❌ No |
| **TTL** | 0 (disabled) |
| **Every Request** | Always hits Snowflake |

**Priority Override Logic**:
```
Even though multiple rules match, UC4's priority=90 (highest)
forces cache.enabled=false regardless of other rules.
```

**Verification**:
```bash
# Request 1
curl ... # Snowflake hit

# Request 2 (immediately after)
curl ... # Snowflake hit again (no cache)

# Check logs:
# "rule_applied": "rule_uc4_educator_completeness_nocache"
# "cache_action": "bypass"
# "reason": "rule_disabled_caching"
```

---

## Section 5: Column-Specificity Edge Cases

### TEST 5.1: UC7 Full Match (All 3 Bands)
**Has**: below_25, mid_25_75, above_75

| Attribute | Value |
|-----------|-------|
| **Rule Winner** | rule_uc7_class_distribution (55) |
| **All Columns Required** | ✅ Yes |

### TEST 5.2: UC7 Partial Match (Only 2 Bands)
**Has**: below_25, mid_25_75 (missing above_75)

| Attribute | Value |
|-----------|-------|
| **UC7 Matches?** | ❌ No (missing above_75) |
| **Fallback Rule** | UC1 (40) or Baseline (10) |

**Lesson**: `op: includes` requires ALL specified columns to match.

---

## Section 8: Complex Multi-Rule Conflicts

### TEST 8.1: Three-Way Conflict
**Query**: Has DISTRICT, SCHOOL, TEST_RESULTS, TERM, math_score, reading_score

| Rule | Priority | Matches? | Why/Why Not |
|------|----------|----------|-------------|
| Baseline | 10 | ✅ | Always matches SELECT on schema |
| UC1 | 40 | ✅ | Has DISTRICT, SCHOOL, TEST_RESULTS, TERM |
| UC6 | 50 | ✅ | Has math_score + reading_score |

**Winner**: UC6 (priority 50) - most specific column signature

---

### TEST 8.2: Four-Way Conflict
**Query**: Has STUDENT, TEST_RESULTS, TERM, terms_present, below_25, mid_25_75, above_75

| Rule | Priority | Matches? |
|------|----------|----------|
| Baseline | 10 | ✅ |
| UC1 | 40 | ✅ (has TERM) |
| UC7 | 55 | ✅ (has all band columns) |
| UC5 | 60 | ✅ (has terms_present) |

**Winner**: UC5 (priority 60) - highest priority among matches

**Conflict Resolution Tree**:
```
           Query Submitted
                 |
       +---------+---------+
       |                   |
   Match All Rules    Evaluate Priorities
       |                   |
   [10,40,55,60]      MAX(priorities)
       |                   |
       +------- 60 --------+
                 |
            Apply UC5
```

---

## Section 9: Cache Key Element Validation

### TEST 9.1: userId Isolation
**Same SQL, Different Users**

```bash
# User A
curl -H "x-user-id: user-001" ...
# Cache Key: user-001|<sql_hash>
# Result: MISS → Snowflake hit

# User B
curl -H "x-user-id: user-002" ...
# Cache Key: user-002|<sql_hash>
# Result: MISS → Snowflake hit (different cache entry)

# User A again
curl -H "x-user-id: user-001" ...
# Result: HIT (finds user-001 cache)
```

**Cache Key Strategy Comparison**:

| Cache Key Elements | Sharing Behavior | Use Case |
|-------------------|------------------|----------|
| [standardizedSql] | All users share | Public dashboards (UC1, UC6, UC7) |
| [userId, standardizedSql] | Per-user isolation | Student drilldowns (UC3) |
| [userRole, standardizedSql] | Per-role sharing | Role-based reports (UC5, UC8) |

---

## Section 10: Performance & Load Testing

### TEST 10.2: Deep Aggregation Stress Test
**Query**: 13 aggregation functions on TEST_RESULTS

| Metric | Expected Value |
|--------|---------------|
| **First Request** | 2-5 seconds (complex agg) |
| **Cached Request** | <100ms |
| **Cache Size** | ~50KB (result set) |
| **TTL** | 300s (UC1 rule) |

**Performance Validation**:
```sql
-- Monitor query performance
SELECT
  query_id,
  query_text,
  execution_time,
  bytes_scanned,
  rows_produced
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_text LIKE '%PERCENTILE_CONT%'
ORDER BY start_time DESC
LIMIT 10;
```

---

## Priority Conflict Decision Matrix

| Rule Combo | Priority Values | Winner | Reason |
|------------|----------------|--------|--------|
| Baseline vs UC1 | 10 vs 40 | UC1 | Higher priority + specificity |
| UC1 vs UC2 | 40 vs 70 | UC2 | View match more specific |
| UC1 vs UC6 | 40 vs 50 | UC6 | Column signature more specific |
| UC5 vs UC7 | 60 vs 55 | UC5 | Higher priority wins |
| UC6 vs UC8 | 50 vs 45 | UC6 | Higher priority |
| Any vs UC4 | X vs 90 | UC4 | Highest priority, forces no-cache |
| UC8 Teacher vs Admin | 45 vs 75 | Admin | Role-specific override |

---

## Logging & Analytics Integration

### AirBrx Log Format (Expected)
```json
{
  "timestamp": "2025-12-09T10:15:30.123Z",
  "request_id": "req-abc123",
  "query_hash": "sha256:...",
  "rules_evaluated": [
    {
      "rule_id": "rule_global_nwea_baseline",
      "priority": 10,
      "matched": true
    },
    {
      "rule_id": "rule_uc1_district_term_summary",
      "priority": 40,
      "matched": true
    }
  ],
  "rule_applied": {
    "rule_id": "rule_uc1_district_term_summary",
    "priority": 40,
    "reason": "highest_priority_match"
  },
  "cache_decision": {
    "action": "store",
    "ttl_seconds": 300,
    "cache_key": "std_sql:sha256:...",
    "cache_key_elements": ["standardizedSql"]
  },
  "snowflake_query": {
    "executed": true,
    "query_id": "01b1c...",
    "duration_ms": 1234
  }
}
```

### Metrics to Track
1. **Cache Hit Rate** by rule_id
2. **Priority Conflicts**: How often multiple rules match
3. **No-Cache Frequency**: UC4 invocations
4. **Snowflake Cost Savings**: Cache HITs × avg_query_cost
5. **TTL Expiration Distribution**: When caches expire

---

## Test Automation Script

```python
#!/usr/bin/env python3
"""
AirBrx Cache Rules Engine - Automated Test Suite
"""
import requests
import json
import time
from typing import Dict, List

class AirBrxTester:
    def __init__(self, gateway_url: str):
        self.gateway_url = gateway_url
        self.results = []
    
    def execute_test(self, test_case: Dict) -> Dict:
        """Execute single test case and validate results"""
        response = requests.post(
            f"{self.gateway_url}/query",
            json={"sql": test_case["sql"]},
            headers=test_case.get("headers", {})
        )
        
        log_entry = response.json()
        
        validation = {
            "test_id": test_case["id"],
            "passed": True,
            "failures": []
        }
        
        # Validate rule applied
        if log_entry["rule_applied"]["rule_id"] != test_case["expected_rule"]:
            validation["passed"] = False
            validation["failures"].append(
                f"Expected {test_case['expected_rule']}, "
                f"got {log_entry['rule_applied']['rule_id']}"
            )
        
        # Validate cache behavior
        if log_entry["cache_decision"]["action"] != test_case["expected_cache_action"]:
            validation["passed"] = False
            validation["failures"].append("Cache action mismatch")
        
        return validation
    
    def run_suite(self, test_cases: List[Dict]):
        """Run all test cases"""
        for test in test_cases:
            result = self.execute_test(test)
            self.results.append(result)
            print(f"Test {test['id']}: {'✅ PASS' if result['passed'] else '❌ FAIL'}")
            if not result['passed']:
                for failure in result['failures']:
                    print(f"  - {failure}")

# Example usage
if __name__ == "__main__":
    tester = AirBrxTester("https://airbrx.gateway.local")
    
    test_cases = [
        {
            "id": "TEST_1.1",
            "sql": "SELECT COUNT(*) FROM DISTRICT;",
            "expected_rule": "rule_global_nwea_baseline",
            "expected_cache_action": "store"
        },
        # Add more test cases...
    ]
    
    tester.run_suite(test_cases)
```

---

## Conflict Testing Checklist

### Before Testing
- [ ] All 10 rules loaded into AirBrx
- [ ] NWEA.ASSESSMENT_BSD schema populated
- [ ] Logging enabled at DEBUG level
- [ ] Cache storage cleared

### During Testing
- [ ] Run each test twice (MISS then HIT)
- [ ] Verify correct rule applied in logs
- [ ] Check Snowflake QUERY_HISTORY
- [ ] Monitor cache key format
- [ ] Validate TTL enforcement

### After Testing
- [ ] Generate conflict report
- [ ] Calculate cache hit rates per rule
- [ ] Identify priority gaps (e.g., 45→55 missing 50-54)
- [ ] Document unexpected behaviors
- [ ] Update rules based on findings

---

## Common Issues & Debugging

### Issue 1: Wrong Rule Applied
**Symptoms**: Expected rule_uc6 but got rule_uc1

**Debug Steps**:
1. Check if all required columns are in SELECT
2. Verify `op: includes` matches all columns
3. Compare priorities: Higher always wins
4. Check rule enabled status

### Issue 2: Cache Not Hitting
**Symptoms**: Every request shows MISS

**Debug Steps**:
1. Verify cache key elements match between requests
2. Check if userId/userRole changing between requests
3. Confirm TTL hasn't expired
4. Validate SQL normalization (whitespace differences)

### Issue 3: Multiple Rules Match Unexpectedly
**Symptoms**: Logs show 5+ rules matched

**Debug Steps**:
1. Review rule conditions - too broad?
2. Add more specific column requirements
3. Consider tightening `mode: ALL` conditions
4. May need intermediate priority values

---

## Next Steps: Advanced Scenarios

1. **Dynamic TTL Based on Data Freshness**
   - Shorter TTL during assessment windows
   - Longer TTL for historical data

2. **Cache Warming Strategies**
   - Pre-load popular UC1/UC2 queries
   - Schedule refresh before peak hours

3. **Invalidation Hooks**
   - Snowflake task triggers cache clear
   - Event-driven vs TTL-based

4. **Cost Attribution**
   - Track Snowflake compute savings per rule
   - ROI analysis by use case

---

## Success Metrics

| Metric | Target | Current | Status |
|--------|--------|---------|--------|
| Overall Cache Hit Rate | >75% | TBD | 🎯 |
| UC1 Hit Rate | >90% | TBD | 🎯 |
| UC4 No-Cache Enforcement | 100% | TBD | 🎯 |
| Priority Conflicts Resolved Correctly | 100% | TBD | 🎯 |
| Avg Response Time (cached) | <100ms | TBD | 🎯 |
| Snowflake Cost Reduction | >50% | TBD | 🎯 |