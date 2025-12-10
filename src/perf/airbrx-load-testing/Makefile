.PHONY: help start stop restart logs test test-local clean status dashboard

help:
	@echo "AirBrx K6 Load Testing - Available Commands:"
	@echo "  make start       - Start InfluxDB and Grafana"
	@echo "  make stop        - Stop all services"
	@echo "  make restart     - Restart all services"
	@echo "  make logs        - Show service logs"
	@echo "  make test-local  - Run K6 test locally"
	@echo "  make clean       - Clean up volumes and data"
	@echo "  make status      - Check service health"
	@echo "  make dashboard   - Open Grafana dashboard"

start:
	@echo "Starting InfluxDB and Grafana..."
	@docker-compose up -d
	@sleep 15
	@echo "Services ready!"
	@echo "Grafana: http://localhost:3000 (admin/admin123)"
	@echo "InfluxDB: http://localhost:8086"

stop:
	@docker-compose down

restart:
	@docker-compose restart

logs:
	@docker-compose logs -f

test-local:
	@echo "Running K6 test locally..."
	@k6 run --out influxdb=http://localhost:8086/k6 k6-tests/airbrx-load-test.js

clean:
	@docker-compose down -v
	@rm -rf k6-results/*

status:
	@docker-compose ps
	@echo ""
	@curl -s http://localhost:8086/ping && echo "✓ InfluxDB: OK" || echo "✗ InfluxDB: Failed"
	@curl -s http://localhost:3000/api/health > /dev/null && echo "✓ Grafana: OK" || echo "✗ Grafana: Failed"

dashboard:
	@open http://localhost:3000 || xdg-open http://localhost:3000 || echo "Visit http://localhost:3000"
