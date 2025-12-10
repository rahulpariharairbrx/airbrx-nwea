// ============================================================================
// AirBrx Gateway - K6 Load Testing Script
// ============================================================================
// This script tests the AirBrx Gateway with realistic NWEA query patterns
// Run with: k6 run --out influxdb=http://localhost:8086/k6 airbrx_k6_loadtesting.js
// ============================================================================

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// ============================================================================
// Custom Metrics
// ============================================================================

const cacheHitRate = new Rate('cache_hit_rate');
const queryDuration = new Trend('query_duration');
const errorRate = new Rate('error_rate');
const requestCounter = new Counter('total_requests');

// ============================================================================
// CONFIGURATION
// ============================================================================

const AIRBRX_GATEWAY_URL = __ENV.AIRBRX_URL || 'http://rahul-parihar.app.airbrx.com:8080';
const INFLUXDB_URL = __ENV.INFLUXDB_URL || 'http://localhost:8086';
const INFLUXDB_DB = __ENV.INFLUXDB_DB || 'k6';

// Test configuration
export const options = {
  stages: [
    { duration: '30s', target: 5 },   // Ramp-up to 5 users
    { duration: '1m', target: 10 },   // Stay at 10 users
    { duration: '30s', target: 20 },  // Ramp-up to 20 users
    { duration: '2m', target: 20 },   // Stay at 20 users
    { duration: '30s', target: 0 },   // Ramp-down to 0 users
  ],
  thresholds: {
    http_req_duration: ['p(95)<2000'], // 95% of requests must complete below 2s
    http_req_failed: ['rate<0.05'],    // Error rate must be below 5%
    cache_hit_rate: ['rate>0.5'],      // Cache hit rate should be above 50%
  },
};

// ============================================================================
// Test Queries - NWEA Dashboard Use Cases
// ============================================================================

const TEST_QUERIES = [
  {
    name: 'UC1_District_Term_Summary',
    sql: `SELECT 
            s.SCHOOL_NAME,
            tr.SUBJECT,
            tr.TERM,
            COUNT(DISTINCT tr.STUDENT_ID) as student_count,
            AVG(tr.TEST_RIT_SCORE) as avg_rit_score
        FROM NWEA.ASSESSMENT_BSD.TEST_RESULTS tr
        JOIN NWEA.ASSESSMENT_BSD.SCHOOL s ON tr.SCHOOL_ID = s.SCHOOL_ID
        JOIN NWEA.ASSESSMENT_BSD.DISTRICT d ON s.DISTRICT_ID = d.DISTRICT_ID
        WHERE tr.TERM IN ('Fall 2025', 'Winter 2025', 'Spring 2025')
        GROUP BY s.SCHOOL_NAME, tr.SUBJECT, tr.TERM
        ORDER BY s.SCHOOL_NAME, tr.SUBJECT, tr.TERM`,
    weight: 20
  },
  {
    name: 'UC2_Class_Growth_Fall_Winter',
    sql: `SELECT * FROM NWEA.ASSESSMENT_BSD.VW_DASH_CLASS_GROWTH_2025 
        WHERE TERM_FROM = 'Fall 2025' AND TERM_TO = 'Winter 2025'
        ORDER BY GROWTH_RIT DESC
        LIMIT 100`,
    weight: 15
  },
  {
    name: 'UC3_Student_Term_Growth',
    sql: `SELECT * FROM NWEA.ASSESSMENT_BSD.VW_DASH_STUDENT_TERM_GROWTH_2025 
        WHERE STUDENT_ID <= 1000
        ORDER BY STUDENT_ID, SUBJECT, TERM`,
    weight: 10
  },
  {
    name: 'UC4_Educator_Completeness',
    sql: `SELECT 
            e.EDUCATOR_NAME,
            c.CLASS_NAME,
            COUNT(CASE WHEN tr.TERM = 'Fall 2025' THEN 1 END) as fall_results_count,
            COUNT(CASE WHEN tr.TERM = 'Winter 2025' THEN 1 END) as winter_results_count,
            COUNT(CASE WHEN tr.TERM = 'Spring 2025' THEN 1 END) as spring_results_count
        FROM NWEA.ASSESSMENT_BSD.EDUCATOR e
        JOIN NWEA.ASSESSMENT_BSD.CLASS c ON e.EDUCATOR_ID = c.EDUCATOR_ID
        LEFT JOIN NWEA.ASSESSMENT_BSD.TEST_RESULTS tr ON c.CLASS_ID = tr.CLASS_ID
        GROUP BY e.EDUCATOR_NAME, c.CLASS_NAME
        ORDER BY e.EDUCATOR_NAME, c.CLASS_NAME`,
    weight: 8
  },
  {
    name: 'UC5_At_Risk_Students',
    sql: `SELECT 
            s.STUDENT_ID,
            s.STUDENT_NAME,
            COUNT(DISTINCT tr.TERM) as terms_present,
            STRING_AGG(DISTINCT tr.TERM, ', ') as completed_terms
        FROM NWEA.ASSESSMENT_BSD.STUDENT s
        LEFT JOIN NWEA.ASSESSMENT_BSD.TEST_RESULTS tr ON s.STUDENT_ID = tr.STUDENT_ID
            AND tr.TERM IN ('Fall 2025', 'Winter 2025', 'Spring 2025')
        GROUP BY s.STUDENT_ID, s.STUDENT_NAME
        HAVING COUNT(DISTINCT tr.TERM) < 3
        ORDER BY terms_present, s.STUDENT_ID`,
    weight: 12
  },
  {
    name: 'UC6_Cross_Subject_Correlation',
    sql: `SELECT 
            tr1.STUDENT_ID,
            tr1.TERM,
            tr1.TEST_RIT_SCORE as math_score,
            tr2.TEST_RIT_SCORE as reading_score,
            (tr1.TEST_RIT_SCORE - tr2.TEST_RIT_SCORE) as score_difference
        FROM NWEA.ASSESSMENT_BSD.TEST_RESULTS tr1
        JOIN NWEA.ASSESSMENT_BSD.TEST_RESULTS tr2 
            ON tr1.STUDENT_ID = tr2.STUDENT_ID 
            AND tr1.TERM = tr2.TERM
        WHERE tr1.SUBJECT = 'Mathematics' 
            AND tr2.SUBJECT = 'Reading'
            AND tr1.TERM = 'Fall 2025'
        ORDER BY score_difference DESC
        LIMIT 500`,
    weight: 10
  },
  {
    name: 'UC7_Class_Distribution',
    sql: `SELECT 
            c.CLASS_NAME,
            tr.TERM,
            COUNT(CASE WHEN tr.TEST_PERCENTILE < 25 THEN 1 END) as below_25,
            COUNT(CASE WHEN tr.TEST_PERCENTILE BETWEEN 25 AND 75 THEN 1 END) as mid_25_75,
            COUNT(CASE WHEN tr.TEST_PERCENTILE > 75 THEN 1 END) as above_75
        FROM NWEA.ASSESSMENT_BSD.TEST_RESULTS tr
        JOIN NWEA.ASSESSMENT_BSD.CLASS c ON tr.CLASS_ID = c.CLASS_ID
        WHERE tr.TERM IN ('Fall 2025', 'Winter 2025', 'Spring 2025')
        GROUP BY c.CLASS_NAME, tr.TERM
        ORDER BY c.CLASS_NAME, tr.TERM`,
    weight: 10
  },
  {
    name: 'UC8_Educator_Portfolio',
    sql: `SELECT * FROM NWEA.ASSESSMENT_BSD.VW_DASH_EDUCATOR_PORTFOLIO_2025 
        WHERE EDUCATOR_ID <= 50
        ORDER BY EDUCATOR_ID, CLASS_NAME, TERM`,
    weight: 15
  }
];

// ============================================================================
// Helper Functions
// ============================================================================

function selectWeightedQuery() {
  const totalWeight = TEST_QUERIES.reduce((sum, q) => sum + q.weight, 0);
  let random = Math.random() * totalWeight;

  for (const query of TEST_QUERIES) {
    random -= query.weight;
    if (random <= 0) {
      return query;
    }
  }
  return TEST_QUERIES[0]; // Fallback
}

function executeQuery(queryObj) {
  const startTime = new Date().getTime();

  const payload = JSON.stringify({
    sql: queryObj.sql,
    parameters: {},
    metadata: {
      userId: `user_${__VU}`,
      sessionId: `session_${__VU}_${__ITER}`,
      requestId: `req_${__VU}_${__ITER}_${startTime}`,
      userRole: ['teacher', 'educator', 'district_admin'][Math.floor(Math.random() * 3)],
      origin: 'k6_load_test'
    }
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
      'X-Request-ID': `req_${__VU}_${__ITER}_${startTime}`,
      'X-User-ID': `user_${__VU}`,
    },
    timeout: '30s',
  };

  const response = http.post(`${AIRBRX_GATEWAY_URL}/query`, payload, params);
  const duration = new Date().getTime() - startTime;

  // Track metrics
  requestCounter.add(1);
  queryDuration.add(duration);

  // Check response
  const success = check(response, {
    'status is 200': (r) => r.status === 200,
    'response has data': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body && (body.data || body.result);
      } catch (e) {
        return false;
      }
    },
    'response time < 5s': (r) => r.timings.duration < 5000,
  });

  errorRate.add(!success);

  // Check for cache hit
  const cacheHit = response.headers['X-Cache-Status'] === 'HIT' ||
    response.headers['X-AirBrx-Cache'] === 'HIT';
  cacheHitRate.add(cacheHit);

  // Log details for debugging
  if (!success || __ENV.DEBUG) {
    console.log(`[${queryObj.name}] Status: ${response.status}, Duration: ${duration}ms, Cache: ${cacheHit ? 'HIT' : 'MISS'}`);
    if (!success) {
      console.log(`Error response: ${response.body.substring(0, 200)}`);
    }
  }

  return { success, duration, cacheHit };
}

// ============================================================================
// Main Test Function
// ============================================================================

export default function () {
  // Select a weighted random query
  const query = selectWeightedQuery();

  // Execute the query
  const result = executeQuery(query);

  // Think time between requests (simulate user behavior)
  const thinkTime = Math.random() * 3 + 1; // 1-4 seconds
  sleep(thinkTime);
}

// ============================================================================
// Setup and Teardown
// ============================================================================

export function setup() {
  console.log('========================================');
  console.log('AirBrx K6 Load Test Starting');
  console.log('========================================');
  console.log(`Gateway URL: ${AIRBRX_GATEWAY_URL}`);
  console.log(`InfluxDB URL: ${INFLUXDB_URL}`);
  console.log(`Total test queries: ${TEST_QUERIES.length}`);
  console.log('========================================');

  // Verify gateway is reachable
  const healthCheck = http.get(`${AIRBRX_GATEWAY_URL}/health`);
  if (healthCheck.status !== 200) {
    console.warn(`Warning: Gateway health check failed with status ${healthCheck.status}`);
  } else {
    console.log('✓ Gateway is reachable');
  }

  return {
    startTime: new Date().toISOString(),
    gatewayUrl: AIRBRX_GATEWAY_URL
  };
}

export function teardown(data) {
  console.log('========================================');
  console.log('AirBrx K6 Load Test Complete');
  console.log('========================================');
  console.log(`Started at: ${data.startTime}`);
  console.log(`Ended at: ${new Date().toISOString()}`);
  console.log('========================================');
  console.log('Check Grafana for detailed metrics:');
  console.log('http://localhost:3000');
  console.log('========================================');
}