# AirBrx Cache Rules Engine - Complete Testing Plan & Results Tracker

## Executive Summary

This document provides a comprehensive testing plan for validating the AirBrx cache rules engine using the NWEA Assessment dataset. It covers 25 cache rules (10 original + 15 advanced) across 13 advanced conflict scenarios.

**Testing Goals:**
1. Validate priority-based rule resolution works correctly
2. Verify multi-dimensional cache key isolation (tenant, role, origin, time)
3. Confirm cache hit/miss behavior matches expectations
4. Measure performance improvements and cost savings
5. Identify edge cases and rule design issues

---

## Test Environment Setup

### Prerequisites Checklist

```bash
# ✅ Infrastructure
[ ] Snowflake 30-day trial activated
[ ] NWEA.ASSESSMENT_BSD database populated (3 schools, 150 students, 450 test results)
[ ] AirBrx gateway deployed and configured
[ ] Rules loaded: nwea_conflict_testing_v1 + nwea_advanced_conflict_testing_v2

# ✅ Logging & Monitoring
[ ] AirBrx debug logging enabled
[ ] Snowflake query history tracking enabled
[ ] Cache metrics dashboard configured
[ ] Log aggregation (Splunk/DataDog/CloudWatch) connected

# ✅ Test Tools
[ ] SQL client (DBeaver/DataGrip/Snowflake UI)
[ ] HTTP client (Postman/curl/Python script)
[ ] Performance monitoring (query duration tracking)
[ ] Cache inspection tools

# ✅ Documentation
[ ] All test queries saved in version control
[ ] Expected results documented
[ ] Baseline performance metrics recorded
```

### Environment Variables

```bash
# AirBrx Configuration
export AIRBRX_GATEWAY_URL="https://airbrx.gateway.local"
export AIRBRX_LOG_LEVEL="DEBUG"
export AIRBRX_LOG_CACHE_DECISIONS="true"
export AIRBRX_METRICS_ENABLED="true"

# Snowflake Configuration
export SNOWFLAKE_ACCOUNT="your_account"
export SNOWFLAKE_WAREHOUSE="COMPUTE_WH"
export SNOWFLAKE_DATABASE="NWEA"
export SNOWFLAKE_SCHEMA="ASSESSMENT_BSD"

# Test Configuration
export TEST_USER_ID="test-user-001"
export TEST_USER_ROLE="teacher"
export TEST_TENANT="standard"
export TEST_ENVIRONMENT="development"
```

---

## Test Execution Matrix

### Phase 1: Basic Rule Validation (Tests 1.1 - 1.3)

| Test ID | Query Type | Expected Rule | Priority | TTL | Status | Notes |
|---------|-----------|---------------|----------|-----|--------|-------|
| 1.1 | Pure baseline | rule_global_nwea_baseline | 10 | 60s | ⬜ Not Run | No conflicts |
| 1.2 | UC1 district summary | rule_uc1_district_term_summary | 40 | 300s | ⬜ Not Run | Baseline + UC1 conflict |
| 1.3 | UC2 view query | rule_uc2_class_growth_fall_winter | 70 | 900s | ⬜ Not Run | View specificity |

**Execution Steps for Test 1.1:**
```bash
# Step 1: Clear cache
curl -X DELETE ${AIRBRX_GATEWAY_URL}/cache/clear

# Step 2: Execute query (expect MISS)
time curl -X POST ${AIRBRX_GATEWAY_URL}/query \
  -H "Content-Type: application/json" \
  -d '{"sql": "SELECT COUNT(*) FROM DISTRICT;"}'

# Step 3: Verify in logs
# Expected: "rule_applied": "rule_global_nwea_baseline", "cache_status": "MISS"

# Step 4: Execute same query (expect HIT)
time curl -X POST ${AIRBRX_GATEWAY_URL}/query \
  -H "Content-Type: application/json" \
  -d '{"sql": "SELECT COUNT(*) FROM DISTRICT;"}'

# Expected: "cache_status": "HIT", response time <100ms
```

**Results Template:**
```
Test 1.1 Results:
- Request 1: Duration=1.234s, Snowflake Query ID=01abc..., Cache=MISS ✅
- Request 2: Duration=0.045s, Cache=HIT ✅
- Rule Applied: rule_global_nwea_baseline ✅
- Priority: 10 ✅
- TTL: 60s ✅
- Cache Key: sha256:d4f2... ✅
- Issues: None
```

---

### Phase 2: Column-Specificity Tests (Tests 2.1 - 2.3, 5.1 - 5.4)

| Test ID | Distinguishing Columns | Expected Rule | Priority | Conflict With |
|---------|------------------------|---------------|----------|---------------|
| 2.1 | TERM present, terms_present absent | UC1 | 40 | UC5 (60) |
| 2.2 | terms_present present | UC5 | 60 | UC1 (40) |
| 2.3 | math_score + reading_score | UC6 | 50 | UC1 (40) |
| 5.1 | below_25 + mid_25_75 + above_75 | UC7 | 55 | UC1 (40) |
| 5.2 | Only 2 of 3 band columns | UC1 or Baseline | 40/10 | UC7 (doesn't match) |
| 5.3 | math_score + reading_score (CTE) | UC6 | 50 | UC1 (40) |
| 5.4 | Only math_score | UC1 | 40 | UC6 (doesn't match) |

**Critical Validation Points:**
- [ ] Verify `op: includes` requires ALL specified columns
- [ ] Confirm partial column match does NOT trigger rule
- [ ] Validate fallback to lower-priority rule when columns missing

---

### Phase 3: Role & Tenant Multi-Dimensional Tests (Tests 3.1 - 3.3, CS1, CS2)

| Test ID | Dimension | Value | Expected Rule | Priority | Cache Key Includes |
|---------|-----------|-------|---------------|----------|--------------------|
| 3.1 | userRole | teacher | UC8 default | 45 | [userId, sql] |
| 3.2 | userRole | district_admin | UC8 admin override | 75 | [userRole, sql] |
| 3.3 | userId | user-001 | UC3 student growth | 80 | [userId, sql] |
| CS1.1 | tenant + time | premium + 08:30 | Premium override | 85 | [tenant, sql] |
| CS1.2 | tenant + time | standard + 08:30 | Morning peak | 65 | [sql, requestHour] |
| CS2.1 | debug | true | Debug bypass | 99 | [] (no cache) |

**Multi-User Isolation Test:**
```bash
# Execute same query with 3 different users
for user in user-001 user-002 user-003; do
  curl -H "x-user-id: $user" ... | jq '.cache_key'
done

# Expected: 3 distinct cache keys
# user-001|sha256:abc...
# user-002|sha256:abc...
# user-003|sha256:abc...
```

---

### Phase 4: No-Cache Override Tests (Tests 4.1 - 4.2, CS2, CS10)

| Test ID | Scenario | Competing Rules | Expected Winner | Cache Enabled |
|---------|----------|-----------------|-----------------|---------------|
| 4.1 | UC4 completeness | Baseline (10), UC4 (90) | UC4 | ❌ No |
| CS2.1 | Debug + UC4 | UC4 (90), Debug (99) | Debug | ❌ No |
| CS2.2 | Debug + Premium | Premium (85), Debug (99) | Debug | ❌ No |
| CS10.1 | Tableau Prep + UC8 | UC8 (75), Exploratory (95) | Exploratory | ❌ No |
| CS10.2 | DBeaver + UC4 | UC4 (90), Exploratory (95) | Exploratory | ❌ No |

**Validation:**
- [ ] Every request hits Snowflake (no cache)
- [ ] Response time consistently slow (never <100ms)
- [ ] Cache status always shows "BYPASS" or "DISABLED"

---

### Phase 5: Advanced Multi-Rule Conflicts (CS3 - CS13)

#### CS3: Large Result + Heavy Aggregation + UC1
**Queries:** CS3.1 (8 aggregations), CS3.2 (estimated 15K rows), CS3.3 (only 3 aggregations)

| Query | Agg Count | Est. Rows | Matching Rules | Expected Winner | TTL |
|-------|-----------|-----------|----------------|-----------------|-----|
| CS3.1 | 8 | <10K | Large(35), UC1(40), Heavy(48) | Heavy Agg | 1800s |
| CS3.2 | 8 | 15K | Large(35), UC1(40), Heavy(48) | Heavy Agg | 1800s |
| CS3.3 | 3 | <10K | UC1(40), Join(42) | Join Count | 400s |

---

#### CS4: Current Date + UC6 + Window Function
**Queries:** CS4.1 (CURRENT_DATE + window), CS4.2 (window only), CS4.3 (UC6 pattern)

| Query | Has CURRENT_DATE | Has Window Fn | Has UC6 Cols | Winner | TTL |
|-------|------------------|---------------|--------------|--------|-----|
| CS4.1 | ✅ | ✅ | ✅ | Current Date (72) | 30s |
| CS4.2 | ❌ | ✅ | ✅ | Window Fn (53) | 600s |
| CS4.3 | ❌ | ❌ | ✅ | UC6 (50) | 300s |

**Insight:** Temporal functions override analytical optimizations

---

#### CS5: Subquery No-Cache vs Premium Tenant (Conflicting Actions!)
**Critical Test:** Same query, different cache behavior depending on priority winner

| Scenario | Tenant | Matching Rules | Winner | Cache Action |
|----------|--------|----------------|--------|--------------|
| CS5.1 | premium | Subquery(82), Premium(85) | Premium | ENABLED (85>82) |
| CS5.2 | standard | Subquery(82) | Subquery | DISABLED |

**Discussion Point:** What happens when higher-priority rule wants caching but lower-priority wants no-cache? 
- Answer: Higher priority's action always wins (cache enabled in this case)

---

#### CS13: Kitchen Sink Query (8+ Rule Collision)
**The Ultimate Conflict Test**

**Query Characteristics:**
- 5 tables joined
- 7 aggregation functions
- Window function (ROW_NUMBER)
- CURRENT_DATE() function
- LIMIT 100
- WHERE filter on 'West View'

**Matching Rules:**
1. Baseline (10) ✅
2. Large Result Set (35) ✅
3. Limit Clause (38) ✅
4. UC1 District Summary (40) ✅
5. Join Count Penalty (42) ✅
6. Aggregation Heavy (48) ✅
7. West View Specific (52) ✅
8. Window Function (53) ✅
9. Morning Peak (65) - if 7-9 AM ✅
10. Current Date (72) ✅
11. Premium Tenant (85) - if premium ✅

**Expected Winner:** Premium Tenant (85) if header present, otherwise Current Date (72)

---

## Detailed Test Execution Checklist

### For Each Test Case:

#### Pre-Execution
- [ ] Document expected rule ID
- [ ] Document expected priority
- [ ] Document expected TTL
- [ ] Document expected cache key elements
- [ ] Clear cache if needed for clean test

#### Execution
- [ ] Execute query first time → capture MISS
- [ ] Verify Snowflake query executed
- [ ] Record response time (should be slow)
- [ ] Execute query second time → capture HIT
- [ ] Verify Snowflake query NOT executed
- [ ] Record response time (should be <100ms)

#### Validation
- [ ] Correct rule applied (check logs)
- [ ] Priority matches expected
- [ ] TTL matches expected
- [ ] Cache key format correct
- [ ] Cache isolation working (if multi-dimensional)
- [ ] Results identical between MISS and HIT

#### Documentation
- [ ] Screenshot of AirBrx logs
- [ ] Snowflake query history entry
- [ ] Performance metrics
- [ ] Any unexpected behavior
- [ ] Timestamp of test execution

---

## Results Tracking Template

### Test Execution Log

```csv
Test_ID,Date,Time,Query_Hash,Expected_Rule,Actual_Rule,Match,Expected_Priority,Actual_Priority,Expected_TTL,Actual_TTL,First_Request_Ms,Second_Request_Ms,Cache_Hit_Rate,Snowflake_Query_Count,Issues
1.1,2025-12-09,10:15:30,abc123,rule_global_nwea_baseline,rule_global_nwea_baseline,✅,10,10,60,60,1234,45,50%,1,None
1.2,2025-12-09,10:18:45,def456,rule_uc1_district_term_summary,rule_uc1_district_term_summary,✅,40,40,300,300,2341,52,50%,1,None
```

### Conflict Resolution Analysis

```
Conflict Scenario: CS1 - Premium Tenant + Morning Peak + UC1
Date: 2025-12-09 08:30:00
Context: x-tenant=premium, x-request-time=08:30:00

Matching Rules:
1. rule_global_nwea_baseline (priority 10) - ✅ Matched
2. rule_uc1_district_term_summary (priority 40) - ✅ Matched
3. rule_time_based_morning_peak (priority 65) - ✅ Matched
4. rule_tenant_premium_override (priority 85) - ✅ Matched

Winner: rule_tenant_premium_override (priority 85)
Reason: Highest priority among all matching rules

Cache Behavior:
- Enabled: Yes
- TTL: 60 seconds
- Cache Key: premium|sha256:abc123...

Verification:
- Rule correctly identified ✅
- Priority ordering correct ✅
- Cache key includes tenant ✅
- TTL matches expectation ✅
- Cache isolation verified ✅

Issues: None
```

---

## Performance Metrics Dashboard

### Overall Statistics

| Metric | Target | Current | Status |
|--------|--------|---------|--------|
| **Total Tests Executed** | 120 | 0 | 🟡 In Progress |
| **Tests Passed** | 100% | - | - |
| **Average Cache Hit Rate** | >75% | - | - |
| **Average Response Time (HIT)** | <100ms | - | - |
| **Average Response Time (MISS)** | 1-3s | - | - |
| **Snowflake Queries Saved** | >50% | - | - |
| **Rules Validated** | 25/25 | 0/25 | 🔴 Not Started |

### Per-Rule Performance

| Rule ID | Priority | Tests Run | Pass Rate | Avg TTL | Hit Rate | Snowflake Saved |
|---------|----------|-----------|-----------|---------|----------|-----------------|
| rule_global_nwea_baseline | 10 | 0 | - | 60s | - | - |
| rule_uc1_district_term_summary | 40 | 0 | - | 300s | - | - |
| rule_uc2_class_growth_fall_winter | 70 | 0 | - | 900s | - | - |
| ... | ... | ... | ... | ... | ... | ... |

### Conflict Resolution Statistics

| Scenario | Conflicts | Expected Winner | Actual Winner | Match Rate |
|----------|-----------|-----------------|---------------|------------|
| CS1: Premium + Morning + UC1 | 4 rules | Premium (85) | - | - |
| CS2: Debug Override | 3 rules | Debug (99) | - | - |
| CS3: Large + Agg + UC1 | 3 rules | Heavy Agg (48) | - | - |
| ... | ... | ... | - | - |

---

## Issue Tracking

### Discovered Issues

#### Issue #1: [Example]
- **Severity:** Medium
- **Test ID:** CS5.1
- **Description:** Conflicting cache actions (subquery wants no-cache, premium wants cache)
- **Expected Behavior:** Higher priority's action wins
- **Actual Behavior:** [To be determined]
- **Resolution:** [To be determined]
- **Status:** Open

### Priority Gaps Identified

| Gap Range | Missing Priorities | Impact | Recommendation |
|-----------|-------------------|--------|----------------|
| 10-35 | 11-34 | Low specificity rules have no intermediate options | Consider adding 15, 20, 25, 30 |
| 40-47 | 41, 43-46 | Dashboard tier densely packed | Good coverage |
| 48-60 | 49, 51, 54, 56-59 | Several analytical rules need fine-tuning | Add if needed |
| 60-85 | Many gaps | Large jump from UC5 to Premium | Consider 68, 78 for role overrides |

---

## Optimization Opportunities

### High-Impact Optimizations

1. **UC1 District Summary (40)** - Most frequently accessed dashboard
   - Current TTL: 300s
   - Recommended: Consider 600s for historical terms
   - Potential Savings: 40% reduction in Snowflake queries

2. **UC2 Class Growth (70)** - View already cached
   - Current TTL: 900s (15 min)
   - Recommended: Increase to 1800s (30 min) for completed terms
   - Rationale: Fall→Winter growth data changes slowly

3. **Premium Tenant (85)** - Short TTL may be too aggressive
   - Current TTL: 60s
   - Recommended: Evaluate if 120s acceptable for premium UX
   - Benefit: Reduce "premium" Snowflake load by 50%

### Cache Key Strategy Review

| Current Strategy | Use Cases | Sharing Level | Optimization Opportunity |
|-----------------|-----------|---------------|--------------------------|
| [standardizedSql] | UC1, UC6, UC7 | All users share | ✅ Optimal for public dashboards |
| [userId, standardizedSql] | UC3, UC8 | Per-user isolation | ⚠️ May over-isolate; consider [userRole] |
| [userRole, standardizedSql] | UC5 | Per-role sharing | ✅ Good balance |
| [tenant, standardizedSql] | Premium | Per-tenant | ✅ Appropriate for multi-tenancy |

---

## Test Automation Script

### Python Test Runner

```python
#!/usr/bin/env python3
"""
AirBrx Cache Rules Engine - Automated Test Execution
Usage: python airbrx_test_runner.py --config test_config.json
"""

import requests
import json
import time
import csv
from datetime import datetime
from typing import Dict, List, Optional

class AirBrxTestRunner:
    def __init__(self, gateway_url: str, snowflake_conn: Dict):
        self.gateway_url = gateway_url
        self.snowflake_conn = snowflake_conn
        self.results = []
        
    def clear_cache(self):
        """Clear AirBrx cache before test run"""
        response = requests.delete(f"{self.gateway_url}/cache/clear")
        return response.status_code == 200
        
    def execute_query(self, sql: str, headers: Dict = None) -> Dict:
        """Execute query via AirBrx gateway"""
        payload = {"sql": sql}
        start_time = time.time()
        
        response = requests.post(
            f"{self.gateway_url}/query",
            json=payload,
            headers=headers or {}
        )
        
        duration_ms = (time.time() - start_time) * 1000
        result = response.json()
        result['duration_ms'] = duration_ms
        
        return result
        
    def run_test_case(self, test_case: Dict) -> Dict:
        """Execute single test case with validation"""
        print(f"
Running Test {test_case['id']}: {test_case['description']}")
        
        # First request (should be MISS)
        result1 = self.execute_query(test_case['sql'], test_case.get('headers'))
        
        # Wait 1 second
        time.sleep(1)
        
        # Second request (should be HIT if cache enabled)
        result2 = self.execute_query(test_case['sql'], test_case.get('headers'))
        
        # Validate
        validation = {
            'test_id': test_case['id'],
            'timestamp': datetime.now().isoformat(),
            'expected_rule': test_case['expected_rule'],
            'actual_rule': result1.get('rule_applied', {}).get('rule_id'),
            'rule_match': result1.get('rule_applied', {}).get('rule_id') == test_case['expected_rule'],
            'expected_ttl': test_case['expected_ttl'],
            'actual_ttl': result1.get('cache_decision', {}).get('ttl_seconds'),
            'first_request_ms': result1['duration_ms'],
            'second_request_ms': result2['duration_ms'],
            'cache_hit_second': result2.get('cache_decision', {}).get('action') == 'hit',
            'passed': True,
            'issues': []
        }
        
        # Check validations
        if not validation['rule_match']:
            validation['passed'] = False
            validation['issues'].append(f"Rule mismatch: expected {test_case['expected_rule']}, got {validation['actual_rule']}")
            
        if validation['actual_ttl'] != validation['expected_ttl']:
            validation['passed'] = False
            validation['issues'].append(f"TTL mismatch: expected {test_case['expected_ttl']}, got {validation['actual_ttl']}")
            
        # Print result
        status = "✅ PASS" if validation['passed'] else "❌ FAIL"
        print(f"  Result: {status}")
        if validation['issues']:
            for issue in validation['issues']:
                print(f"    - {issue}")
                
        self.results.append(validation)
        return validation
        
    def run_test_suite(self, test_suite_file: str):
        """Run entire test suite from JSON file"""
        with open(test_suite_file, 'r') as f:
            test_suite = json.load(f)
            
        print(f"
=== AirBrx Test Suite: {test_suite['name']} ===")
        print(f"Total Tests: {len(test_suite['tests'])}")
        print(f"
Starting execution...
")
        
        for test_case in test_suite['tests']:
            self.run_test_case(test_case)
            
        # Summary
        passed = sum(1 for r in self.results if r['passed'])
        total = len(self.results)
        pass_rate = (passed / total * 100) if total > 0 else 0
        
        print(f"

=== Test Summary ===")
        print(f"Passed: {passed}/{total} ({pass_rate:.1f}%)")
        print(f"Failed: {total - passed}/{total}")
        
        # Save results
        self.save_results('test_results.csv')
        
    def save_results(self, filename: str):
        """Save test results to CSV"""
        with open(filename, 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=self.results[0].keys())
            writer.writeheader()
            writer.writerows(self.results)
        print(f"
Results saved to {filename}")

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description='AirBrx Test Runner')
    parser.add_argument('--gateway', default='http://localhost:8080', help='AirBrx gateway URL')
    parser.add_argument('--suite', required=True, help='Test suite JSON file')
    
    args = parser.parse_args()
    
    runner = AirBrxTestRunner(args.gateway, {})
    runner.run_test_suite(args.suite)
```

---

## Success Criteria

### Phase 1: Basic Validation ✅
- [ ] All 25 rules load successfully
- [ ] Baseline (priority 10) matches when no other rules apply
- [ ] View-based rules (UC2, UC8) correctly match their views
- [ ] No-cache rules (UC4, priority 90) disable caching

### Phase 2: Conflict Resolution ✅
- [ ] Higher priority always wins in conflicts
- [ ] Column-specific rules match only when ALL columns present
- [ ] Role/tenant dimensions create separate cache entries
- [ ] Debug mode (99) overrides all other rules

### Phase 3: Performance ✅
- [ ] Cache HITs respond in <100ms
- [ ] Cache MISSes show Snowflake query execution
- [ ] Overall cache hit rate >75%
- [ ] Snowflake query reduction >50%

### Phase 4: Edge Cases ✅
- [ ] Partial column matches fall back correctly
- [ ] Temporal functions detected properly
- [ ] Subquery patterns handled correctly
- [ ] LIMIT clause variations work as expected

---

## Next Steps After Testing

1. **Rule Tuning**
   - Adjust TTLs based on actual usage patterns
   - Fill priority gaps if needed
   - Optimize cache key strategies

2. **Production Rollout**
   - Start with baseline + UC1 only
   - Gradually enable more rules
   - Monitor cache hit rates per rule
   - Set up alerting for anomalies

3. **Cost Analysis**
   - Calculate Snowflake compute savings
   - Measure cache storage costs
   - ROI analysis per use case
   - Identify highest-value rules

4. **Documentation Updates**
   - Document discovered edge cases
   - Update rule descriptions
   - Create runbooks for common issues
   - Build internal knowledge base

5. **Advanced Features**
   - Implement cache invalidation hooks
   - Add cache warming strategies
   - Build smart TTL adjustment
   - Create A/B testing framework

---

## Appendix: Quick Reference

### Priority Tiers
- **0-10**: Reserved/Baseline
- **11-39**: Preview/Experimental
- **40-60**: Dashboard/Use Case tier
- **61-85**: Advanced/Optimization tier
- **86-95**: Environment/Tenant overrides
- **96-99**: Admin/Debug overrides

### Common Cache Key Patterns
```
standardizedSql only:          sha256:abc123...
userId + standardizedSql:      user-001|sha256:abc123...
userRole + standardizedSql:    teacher|sha256:abc123...
tenant + standardizedSql:      premium|sha256:abc123...
origin + standardizedSql:      api|sha256:abc123...
```

### Troubleshooting Guide
**Issue**: Cache never hits
- Check if SQL normalization is consistent
- Verify cache key elements match between requests
- Confirm TTL hasn't expired
- Check if a higher-priority no-cache rule is matching

**Issue**: Wrong rule applied
- Review all matching rules' priorities
- Verify all condition fields are present
- Check for typos in rule conditions
- Validate `op: includes` logic

**Issue**: Performance not improved
- Verify cache is actually hitting (check logs)
- Ensure Snowflake queries not executing on HITs
- Check if TTL too short
- Review cache key isolation strategy