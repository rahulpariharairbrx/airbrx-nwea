import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 1,
  iterations: 5,
  thresholds: {
    'http_req_duration': ['p(95)<5000'],
    'http_req_failed': ['rate<0.1'],
  },
};

const AIRBRX_URL = __ENV.AIRBRX_URL || 'http://localhost:8080';

export default function() {
  const url = `${AIRBRX_URL}/api/query`;
  
  const payload = JSON.stringify({
    sql: 'SELECT COUNT(*) FROM DISTRICT;',
    database: 'NWEA',
    schema: 'ASSESSMENT_BSD'
  });
  
  const response = http.post(url, payload, {
    headers: { 'Content-Type': 'application/json' }
  });
  
  check(response, {
    'status is 200': (r) => r.status === 200,
    'has response data': (r) => r.body.length > 0,
  });
  
  sleep(1);
}
