#!/bin/bash
# Setup script for EC2 instance
# This script installs and configures the Flask application on EC2

set -euo pipefail

LOG_FILE="/var/log/app-setup.log"
APP_DIR="/opt/flask-app"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "Starting application setup..."

# Update system packages
log "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

# Install required system packages
log "Installing system packages..."
apt-get install -y -qq \
    python3.11 \
    python3.11-venv \
    python3-pip \
    nginx \
    git \
    curl \
    wget \
    htop \
    unzip

# Create application directory
log "Creating application directory..."
mkdir -p "$APP_DIR"
mkdir -p /var/log/flask-app
chown ubuntu:ubuntu "$APP_DIR"
chown ubuntu:ubuntu /var/log/flask-app

# Copy application files (in real scenario, this would be from git or S3)
# For this setup, we assume files are copied via user-data or user script
log "Application files should be in $APP_DIR/app/"

# Create Python virtual environment
log "Setting up Python virtual environment..."
cd "$APP_DIR"
python3.11 -m venv venv
source venv/bin/activate

# Install Python dependencies
if [ -f "$APP_DIR/app/requirements.txt" ]; then
    log "Installing Python dependencies..."
    pip install --upgrade pip -q
    pip install -r "$APP_DIR/app/requirements.txt" -q
else
    log "WARNING: requirements.txt not found, installing default dependencies..."
    pip install --upgrade pip -q
    pip install Flask==3.0.0 gunicorn==21.2.0 werkzeug==3.0.1 -q
fi

# Configure Nginx
log "Configuring Nginx..."
if [ -f "$APP_DIR/nginx/default.conf" ]; then
    cp "$APP_DIR/nginx/default.conf" /etc/nginx/sites-available/flask-app
    ln -sf /etc/nginx/sites-available/flask-app /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
fi

# Test Nginx configuration
nginx -t

# Configure systemd service
log "Configuring systemd service..."
if [ -f "$APP_DIR/systemd/app.service" ]; then
    cp "$APP_DIR/systemd/app.service" /etc/systemd/system/flask-app.service
    systemctl daemon-reload
fi

# Set permissions
chown -R ubuntu:ubuntu "$APP_DIR"

# Start services
log "Starting services..."
systemctl enable flask-app.service
systemctl start flask-app.service
systemctl restart nginx

# Wait for service to be ready
log "Waiting for application to be ready..."
sleep 5

# Check service status
if systemctl is-active --quiet flask-app; then
    log "Flask application is running"
else
    log "ERROR: Flask application failed to start"
    systemctl status flask-app
    exit 1
fi

if systemctl is-active --quiet nginx; then
    log "Nginx is running"
else
    log "ERROR: Nginx failed to start"
    systemctl status nginx
    exit 1
fi

# Health check
log "Performing health check..."
if curl -f -s http://localhost/health > /dev/null; then
    log "Health check passed"
else
    log "WARNING: Health check failed"
fi

log "Setup completed successfully!"
log "Application is available on port 80"
log "Logs are available at:"
log "  - Application: /var/log/flask-app/"
log "  - Nginx: /var/log/nginx/"
