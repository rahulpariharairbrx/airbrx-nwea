#!/bin/bash
# ============================================================================
# AirBrx K6 Load Testing - Automated Setup Script
# ============================================================================
# This script automates the complete setup of the K6 load testing infrastructure
# including InfluxDB, Grafana, and all necessary configurations.
#
# Usage: ./setup-airbrx-testing.sh [options]
# Options:
#   --quick       Quick setup without confirmations
#   --no-docker   Skip Docker service startup
#   --help        Show this help message
# ============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="airbrx-load-testing"
INFLUXDB_PORT=8086
GRAFANA_PORT=3000
AIRBRX_PORT=8080

# Parse command line arguments
QUICK_MODE=false
NO_DOCKER=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --quick) QUICK_MODE=true ;;
        --no-docker) NO_DOCKER=true ;;
        --help) 
            head -n 20 "$0" | grep "^#" | sed 's/^# //'
            exit 0
            ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

confirm() {
    if [ "$QUICK_MODE" = true ]; then
        return 0
    fi
    
    read -p "$1 (y/n) " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

check_command() {
    if command -v "$1" &> /dev/null; then
        print_success "$1 is installed"
        return 0
    else
        print_error "$1 is not installed"
        return 1
    fi
}

wait_for_service() {
    local url=$1
    local name=$2
    local max_attempts=30
    local attempt=0
    
    echo -n "Waiting for $name to be ready"
    while ! curl -s "$url" > /dev/null 2>&1; do
        if [ $attempt -ge $max_attempts ]; then
            print_error "$name failed to start after $max_attempts attempts"
            return 1
        fi
        echo -n "."
        sleep 2
        ((attempt++))
    done
    echo ""
    print_success "$name is ready"
}

# ============================================================================
# Main Setup Flow
# ============================================================================

clear
print_header "AirBrx K6 Load Testing - Automated Setup"
echo ""
echo "This script will set up:"
echo "  • Project directory structure"
echo "  • Docker Compose infrastructure (InfluxDB + Grafana)"
echo "  • K6 test scripts"
echo "  • Grafana dashboards and datasources"
echo ""

if ! confirm "Continue with setup?"; then
    print_warning "Setup cancelled"
    exit 0
fi

# Step 1: Check Prerequisites
print_header "Step 1: Checking Prerequisites"

MISSING_DEPS=0

if ! check_command "docker"; then
    print_info "Install Docker: https://docs.docker.com/get-docker/"
    MISSING_DEPS=1
fi

if ! check_command "docker-compose"; then
    print_info "Install Docker Compose: https://docs.docker.com/compose/install/"
    MISSING_DEPS=1
fi

if ! check_command "curl"; then
    print_error "curl is required but not installed"
    MISSING_DEPS=1
fi

# K6 is optional if using Docker
if ! check_command "k6"; then
    print_warning "K6 not installed locally (will use Docker image)"
    print_info "To install K6: https://k6.io/docs/getting-started/installation/"
else
    K6_VERSION=$(k6 version | head -n1)
    print_info "K6 version: $K6_VERSION"
fi

if [ $MISSING_DEPS -eq 1 ]; then
    print_error "Please install missing dependencies and run setup again"
    exit 1
fi

print_success "All prerequisites satisfied"
echo ""

# Step 2: Create Project Structure
print_header "Step 2: Creating Project Structure"

# Create project directory if it doesn't exist
if [ ! -d "$PROJECT_NAME" ]; then
    mkdir "$PROJECT_NAME"
    print_success "Created project directory: $PROJECT_NAME"
else
    print_warning "Project directory already exists: $PROJECT_NAME"
    if ! confirm "Continue and overwrite existing files?"; then
        exit 0
    fi
fi

cd "$PROJECT_NAME"

# Create directory structure
DIRS=(
    "k6-tests"
    "k6-tests/scenarios"
    "k6-results"
    "k6-results/logs"
    "grafana/provisioning/datasources"
    "grafana/provisioning/dashboards"
    "grafana/dashboards"
    "influxdb"
    "prometheus"
)

for dir in "${DIRS[@]}"; do
    mkdir -p "$dir"
    print_success "Created directory: $dir"
done

echo ""

# Step 3: Generate Configuration Files
print_header "Step 3: Generating Configuration Files"

# 3.1: Create docker-compose.yml
print_info "Creating docker-compose.yml..."
cat > docker-compose.yml << 'EOF'
version: '3.8'

networks:
  k6-network:
    driver: bridge

volumes:
  influxdb-data:
  grafana-data:

services:
  influxdb:
    image: influxdb:1.8
    container_name: k6-influxdb
    networks:
      - k6-network
    ports:
      - "8086:8086"
    environment:
      - INFLUXDB_DB=k6
      - INFLUXDB_HTTP_AUTH_ENABLED=false
      - INFLUXDB_ADMIN_USER=admin
      - INFLUXDB_ADMIN_PASSWORD=admin123
    volumes:
      - influxdb-data:/var/lib/influxdb
      - ./influxdb/init.sh:/docker-entrypoint-initdb.d/init.sh:ro
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8086/ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: k6-grafana
    networks:
      - k6-network
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin123
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
    depends_on:
      influxdb:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
EOF
print_success "Created docker-compose.yml"

# 3.2: Create InfluxDB init script
print_info "Creating InfluxDB initialization script..."
cat > influxdb/init.sh << 'EOF'
#!/bin/bash
set -e

echo "Waiting for InfluxDB to be ready..."
until curl -s http://localhost:8086/ping > /dev/null 2>&1; do
  sleep 2
done

echo "Creating K6 database..."
influx -execute "CREATE DATABASE k6"

echo "Creating retention policies..."
influx -execute "CREATE RETENTION POLICY \"k6_30d\" ON \"k6\" DURATION 30d REPLICATION 1 DEFAULT"

echo "InfluxDB initialization complete!"
EOF
chmod +x influxdb/init.sh
print_success "Created influxdb/init.sh"

# 3.3: Create Grafana datasource config
print_info "Creating Grafana datasource configuration..."
cat > grafana/provisioning/datasources/influxdb.yml << 'EOF'
apiVersion: 1

datasources:
  - name: InfluxDB-K6
    type: influxdb
    access: proxy
    url: http://influxdb:8086
    database: k6
    isDefault: true
    jsonData:
      timeInterval: "5s"
      httpMode: GET
    version: 1
    editable: true
EOF
print_success "Created Grafana datasource config"

# 3.4: Create Grafana dashboard provisioning
print_info "Creating Grafana dashboard provisioning..."
cat > grafana/provisioning/dashboards/dashboards.yml << 'EOF'
apiVersion: 1

providers:
  - name: 'AirBrx K6 Dashboards'
    orgId: 1
    folder: 'K6 Load Testing'
    type: file
    disableDeletion: false
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: true
EOF
print_success "Created Grafana dashboard provisioning"

# 3.5: Create .env file
print_info "Creating .env file..."
cat > .env << 'EOF'
# InfluxDB Configuration
INFLUXDB_DB=k6
INFLUXDB_ADMIN_USER=admin
INFLUXDB_ADMIN_PASSWORD=admin123

# Grafana Configuration
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=admin123

# AirBrx Gateway
AIRBRX_URL=http://localhost:8080

# K6 Configuration
K6_OUT=influxdb=http://localhost:8086/k6
EOF
print_success "Created .env file"

# 3.6: Create Makefile
print_info "Creating Makefile..."
cat > Makefile << 'EOF'
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
EOF
print_success "Created Makefile"

# 3.7: Create smoke test
print_info "Creating smoke test script..."
cat > k6-tests/smoke-test.js << 'EOF'
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
EOF
print_success "Created smoke test"

# 3.8: Create README
print_info "Creating README..."
cat > README.md << 'EOF'
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
EOF
print_success "Created README.md"

echo ""

# Step 4: Start Docker Services (optional)
if [ "$NO_DOCKER" = false ]; then
    print_header "Step 4: Starting Docker Services"
    
    if confirm "Start InfluxDB and Grafana now?"; then
        print_info "Pulling Docker images (this may take a few minutes)..."
        docker-compose pull
        
        print_info "Starting services..."
        docker-compose up -d
        
        # Wait for services
        echo ""
        wait_for_service "http://localhost:$INFLUXDB_PORT/ping" "InfluxDB"
        wait_for_service "http://localhost:$GRAFANA_PORT/api/health" "Grafana"
        
        print_success "All services started successfully"
    else
        print_warning "Skipping service startup. Run 'make start' when ready."
    fi
else
    print_warning "Docker startup skipped (--no-docker flag)"
fi

echo ""

# Step 5: Verify Setup
print_header "Step 5: Setup Verification"

echo ""
echo "Checking service health..."
echo ""

# Check InfluxDB
if curl -s "http://localhost:$INFLUXDB_PORT/ping" > /dev/null 2>&1; then
    print_success "InfluxDB is accessible at http://localhost:$INFLUXDB_PORT"
else
    print_warning "InfluxDB not accessible (may need to start services)"
fi

# Check Grafana
if curl -s "http://localhost:$GRAFANA_PORT/api/health" > /dev/null 2>&1; then
    print_success "Grafana is accessible at http://localhost:$GRAFANA_PORT"
else
    print_warning "Grafana not accessible (may need to start services)"
fi

# Check AirBrx
if curl -s "http://localhost:$AIRBRX_PORT/health" > /dev/null 2>&1; then
    print_success "AirBrx gateway is accessible at http://localhost:$AIRBRX_PORT"
else
    print_warning "AirBrx gateway not accessible - make sure it's running"
fi

echo ""

# Step 6: Final Instructions
print_header "Setup Complete!"

echo ""
echo -e "${GREEN}✓ Project structure created${NC}"
echo -e "${GREEN}✓ Configuration files generated${NC}"
echo -e "${GREEN}✓ Docker services configured${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Next Steps:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "1. Copy your K6 test script:"
echo -e "   ${YELLOW}cp <your-script> k6-tests/airbrx-load-test.js${NC}"
echo ""
echo "2. Copy your Grafana dashboard:"
echo -e "   ${YELLOW}cp <your-dashboard.json> grafana/dashboards/airbrx-dashboard.json${NC}"
echo ""
echo "3. Ensure AirBrx gateway is running:"
echo -e "   ${YELLOW}curl http://localhost:8080/health${NC}"
echo ""
echo "4. Run a quick smoke test:"
echo -e "   ${YELLOW}k6 run k6-tests/smoke-test.js${NC}"
echo ""
echo "5. Run the full load test:"
echo -e "   ${YELLOW}make test-local${NC}"
echo ""
echo "6. View results in Grafana:"
echo -e "   ${YELLOW}make dashboard${NC}"
echo -e "   Or visit: ${GREEN}http://localhost:3000${NC}"
echo -e "   Login: ${GREEN}admin / admin123${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Useful Commands:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  make start      - Start all services"
echo "  make stop       - Stop all services"
echo "  make logs       - View service logs"
echo "  make status     - Check service health"
echo "  make test-local - Run K6 load test"
echo "  make dashboard  - Open Grafana dashboard"
echo "  make clean      - Clean up everything"
echo ""
echo -e "${GREEN}Happy Load Testing! 🚀${NC}"
echo ""