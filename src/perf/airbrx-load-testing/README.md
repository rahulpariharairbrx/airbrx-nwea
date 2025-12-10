# AirBrx K6 Load Testing

## Quick Start

1. Start infrastructure:
   ```bash
   make start
   ```

2. Run smoke test:
   ```bash
   k6 run k6-tests/smoke-test.js
   ```

3. Run full load test:
   ```bash
   make test-local
   ```

4. View results:
   ```bash
   make dashboard
   ```

## Services

- **Grafana**: http://localhost:3000 (admin/admin123)
- **InfluxDB**: http://localhost:8086
- **AirBrx**: http://localhost:8080

## Available Commands

- `make start` - Start services
- `make stop` - Stop services
- `make logs` - View logs
- `make test-local` - Run load test
- `make status` - Check health
- `make dashboard` - Open Grafana
- `make clean` - Clean up

For detailed documentation, see the complete setup guide.
