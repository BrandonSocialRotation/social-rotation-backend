#!/bin/bash

# Verify DATABASE_URL is set
if [ -z "$DATABASE_URL" ]; then
  echo "ERROR: DATABASE_URL is not set!"
  exit 1
fi

echo "Starting Rails server..."
echo "DATABASE_URL: ${DATABASE_URL:0:50}..."
echo "PORT: ${PORT:-8080}"
echo "RAILS_ENV: ${RAILS_ENV:-production}"

# Test database connection first
echo "Testing database connection..."
bundle exec rails runner "ActiveRecord::Base.connection.execute('SELECT 1')" 2>&1 || echo "Database connection test failed"

# Run migrations - capture output to see what happens
echo "Running database migrations..."
MIGRATION_OUTPUT=$(bundle exec rails db:migrate 2>&1)
MIGRATION_EXIT=$?
echo "$MIGRATION_OUTPUT"
if [ $MIGRATION_EXIT -eq 0 ]; then
  echo "Migrations completed successfully"
  # Verify users table exists
  echo "Verifying users table exists..."
  bundle exec rails runner "puts ActiveRecord::Base.connection.table_exists?('users') ? 'Users table exists' : 'Users table NOT found'" 2>&1
else
  echo "Migration exit code: $MIGRATION_EXIT"
  echo "Migration output: $MIGRATION_OUTPUT"
  echo "Attempting to continue anyway..."
fi

# Start scheduler in background (runs every minute)
echo "Starting scheduler..."
while true; do
  bundle exec rails scheduler:process 2>&1 | head -20
  sleep 60  # Wait 60 seconds before next run
done &
SCHEDULER_PID=$!
echo "Scheduler started with PID: $SCHEDULER_PID"

# Start scheduler in background (runs every minute)
echo "Starting scheduler..."
(
  while true; do
    bundle exec rails scheduler:process 2>&1 | head -20
    sleep 60  # Wait 60 seconds before next run
  done
) &
SCHEDULER_PID=$!
echo "Scheduler started with PID: $SCHEDULER_PID"

# Start the server
echo "Starting Rails server on port ${PORT:-8080}..."
exec bundle exec rails server -b 0.0.0.0 -p ${PORT:-8080} -e production

