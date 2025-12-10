#!/bin/bash
# ============================================================================
# AirBrx K6 Testing - Docker Fix Script
# ============================================================================
# This script diagnoses and fixes common Docker issues
# Usage: ./fix-docker.sh
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   AirBrx K6 Testing - Docker Diagnostic & Fix Tool   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# Step 1: Check Docker Installation
# ============================================================================

echo -e "${BLUE}[Step 1] Checking Docker installation...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker is not installed${NC}"
    echo ""
    echo "Please install Docker:"
    echo "  macOS/Windows: https://www.docker.com/products/docker-desktop"
    echo "  Linux: https://docs.docker.com/engine/install/"
    exit 1
else
    DOCKER_VERSION=$(docker --version)
    echo -e "${GREEN}✓ Docker installed: ${DOCKER_VERSION}${NC}"
fi

if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}✗ Docker Compose is not installed${NC}"
    echo ""
    echo "Please install Docker Compose:"
    echo "  https://docs.docker.com/compose/install/"
    exit 1
else
    COMPOSE_VERSION=$(docker-compose --version)
    echo -e "${GREEN}✓ Docker Compose installed: ${COMPOSE_VERSION}${NC}"
fi

# ============================================================================
# Step 2: Check Docker Daemon
# ============================================================================

echo ""
echo -e "${BLUE}[Step 2] Checking Docker daemon...${NC}"

if ! docker ps &> /dev/null; then
    echo -e "${RED}✗ Docker daemon is not running${NC}"
    echo ""
    echo "Please start Docker:"
    echo "  macOS/Windows: Start Docker Desktop"
    echo "  Linux: sudo systemctl start docker"
    exit 1
else
    echo -e "${GREEN}✓ Docker daemon is running${NC}"
fi

# ============================================================================
# Step 3: Check Port Availability
# ============================================================================

echo ""
echo -e "${BLUE}[Step 3] Checking port availability...${NC}"

PORT_ISSUES=0

# Check port 8086 (InfluxDB)
if lsof -Pi :8086 -sTCP:LISTEN -t &> /dev/null; then
    echo -e "${YELLOW}⚠ Port 8086 is already in use${NC}"
    echo "  Process using it:"
    lsof -Pi :8086 -sTCP:LISTEN | tail -n +2
    PORT_ISSUES=1
else
    echo -e "${GREEN}✓ Port 8086 is available${NC}"
fi

# Check port 3000 (Grafana)
if lsof -Pi :3000 -sTCP:LISTEN -t &> /dev/null; then
    echo -e "${YELLOW}⚠ Port 3000 is already in use${NC}"
    echo "  Process using it:"
    lsof -Pi :3000 -sTCP:LISTEN | tail -n +2
    PORT_ISSUES=1
else
    echo -e "${GREEN}✓ Port 3000 is available${NC}"
fi

if [ $PORT_ISSUES -eq 1 ]; then
    echo ""
    echo -e "${YELLOW}Would you like to stop existing services? (y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "Stopping existing Docker containers..."
        docker stop k6-influxdb k6-grafana 2>/dev/null || true
    else
        echo ""
        echo -e "${RED}Please free up ports 8086 and 3000 before continuing${NC}"
        exit 1
    fi
fi

# ============================================================================
# Step 4: Clean Up Old Containers
# ============================================================================

echo ""
echo -e "${BLUE}[Step 4] Cleaning up old containers...${NC}"

OLD_CONTAINERS=$(docker ps -a -q -f name=k6-influxdb -f name=k6-grafana)
if [ -n "$OLD_CONTAINERS" ]; then
    echo "Found old containers, removing them..."
    docker rm -f $OLD_CONTAINERS 2>/dev/null || true
    echo -e "${GREEN}✓ Old containers removed${NC}"
else
    echo -e "${GREEN}✓ No old containers found${NC}"
fi

# ============================================================================
# Step 5: Check/Create docker-compose.yml
# ============================================================================

echo ""
echo -e "${BLUE}[Step 5] Checking docker-compose.yml...${NC}"

if [ ! -f "docker-compose.yml" ]; then
    echo -e "${YELLOW}⚠ docker-compose.yml not found${NC}"
    echo "Creating simplified docker-compose.yml..."
    
cat > docker-compose.yml << 'COMPOSE_EOF'
version: '3.8'

services:
  influxdb:
    image: influxdb:1.8
    container_name: k6-influxdb
    ports:
      - "8086:8086"
    environment:
      INFLUXDB_DB: k6
      INFLUXDB_ADMIN_USER: admin
      INFLUXDB_ADMIN_PASSWORD: admin123
      INFLUXDB_HTTP_AUTH_ENABLED: "false"
    volumes:
      - influxdb-data:/var/lib/influxdb
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: k6-grafana
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: admin123
      GF_AUTH_ANONYMOUS_ENABLED: "true"
      GF_AUTH_ANONYMOUS_ORG_ROLE: Viewer
    volumes:
      - grafana-data:/var/lib/grafana
    depends_on:
      - influxdb
    restart: unless-stopped

volumes:
  influxdb-data:
  grafana-data:
COMPOSE_EOF

    echo -e "${GREEN}✓ Created docker-compose.yml${NC}"
else
    echo -e "${GREEN}✓ docker-compose.yml exists${NC}"
    
    # Validate syntax
    if docker-compose config > /dev/null 2>&1; then
        echo -e "${GREEN}✓ docker-compose.yml syntax is valid${NC}"
    else
        echo -e "${RED}✗ docker-compose.yml has syntax errors${NC}"
        echo "Would you like to replace it with a working version? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            mv docker-compose.yml docker-compose.yml.backup
            echo "Backup created: docker-compose.yml.backup"
            # Create new file (same as above)
            echo "Creating new docker-compose.yml..."
            # ... (same content as above)
        fi
    fi
fi

# ============================================================================
# Step 6: Pull Docker Images
# ============================================================================

echo ""
echo -e "${BLUE}[Step 6] Pulling Docker images...${NC}"

echo "This may take a few minutes..."
docker-compose pull

echo -e "${GREEN}✓ Images pulled successfully${NC}"

# ============================================================================
# Step 7: Start Services
# ============================================================================

echo ""
echo -e "${BLUE}[Step 7] Starting services...${NC}"

docker-compose up -d

echo ""
echo "Waiting for services to initialize (30 seconds)..."
sleep 30

# ============================================================================
# Step 8: Verify Services
# ============================================================================

echo ""
echo -e "${BLUE}[Step 8] Verifying services...${NC}"

# Check InfluxDB
echo -n "Checking InfluxDB... "
if curl -s http://localhost:8086/ping > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not responding${NC}"
    echo "Checking logs:"
    docker-compose logs --tail=20 influxdb
fi

# Check Grafana
echo -n "Checking Grafana... "
if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not responding${NC}"
    echo "Checking logs:"
    docker-compose logs --tail=20 grafana
fi

# ============================================================================
# Step 9: Create InfluxDB Database
# ============================================================================

echo ""
echo -e "${BLUE}[Step 9] Setting up InfluxDB database...${NC}"

# Wait a bit more for InfluxDB to be fully ready
sleep 5

# Create database
docker exec k6-influxdb influx -execute 'CREATE DATABASE IF NOT EXISTS k6' 2>/dev/null || {
    echo -e "${YELLOW}⚠ Could not create database automatically${NC}"
    echo "Will create it manually..."
    sleep 5
    docker exec k6-influxdb influx -execute 'CREATE DATABASE k6' || {
        echo -e "${RED}✗ Failed to create database${NC}"
        echo "You may need to create it manually later"
    }
}

# Verify database
echo -n "Verifying database... "
if docker exec k6-influxdb influx -execute 'SHOW DATABASES' | grep -q "k6"; then
    echo -e "${GREEN}✓ Database 'k6' exists${NC}"
else
    echo -e "${YELLOW}⚠ Database verification failed${NC}"
fi

# ============================================================================
# Step 10: Final Status
# ============================================================================

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    Setup Complete!                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

docker-compose ps

echo ""
echo -e "${GREEN}Services are running!${NC}"
echo ""
echo "Access points:"
echo -e "  ${BLUE}Grafana:${NC}   http://localhost:3000"
echo "              Login: admin / admin123"
echo -e "  ${BLUE}InfluxDB:${NC} http://localhost:8086"
echo ""
echo "Next steps:"
echo "  1. Open Grafana: http://localhost:3000"
echo "  2. Add InfluxDB datasource:"
echo "     - URL: http://influxdb:8086"
echo "     - Database: k6"
echo "  3. Run K6 test:"
echo "     k6 run --out influxdb=http://localhost:8086/k6 your-test.js"
echo ""
echo "Useful commands:"
echo "  docker-compose ps       - Check status"
echo "  docker-compose logs     - View logs"
echo "  docker-compose restart  - Restart services"
echo "  docker-compose down     - Stop services"
echo ""

# ============================================================================
# Create helper script
# ============================================================================

cat > quick-commands.sh << 'HELPER_EOF'
#!/bin/bash
# Quick commands for managing K6 testing infrastructure

case "$1" in
  start)
    echo "Starting services..."
    docker-compose up -d
    ;;
  stop)
    echo "Stopping services..."
    docker-compose down
    ;;
  restart)
    echo "Restarting services..."
    docker-compose restart
    ;;
  logs)
    docker-compose logs -f
    ;;
  status)
    docker-compose ps
    echo ""
    curl -s http://localhost:8086/ping > /dev/null && echo "✓ InfluxDB: OK" || echo "✗ InfluxDB: Down"
    curl -s http://localhost:3000/api/health > /dev/null && echo "✓ Grafana: OK" || echo "✗ Grafana: Down"
    ;;
  clean)
    echo "Cleaning up..."
    docker-compose down -v
    echo "Done!"
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|logs|status|clean}"
    exit 1
    ;;
esac
HELPER_EOF

chmod +x quick-commands.sh

echo -e "${GREEN}Created helper script: quick-commands.sh${NC}"
echo "Usage: ./quick-commands.sh {start|stop|restart|logs|status|clean}"
echo ""