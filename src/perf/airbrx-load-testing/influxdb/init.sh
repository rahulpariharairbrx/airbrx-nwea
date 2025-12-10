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
