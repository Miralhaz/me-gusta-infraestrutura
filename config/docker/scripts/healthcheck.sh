#!/bin/bash
# =============================================================================
# MeGusta Database Healthcheck
# =============================================================================

set -e

MYSQL_HOST="localhost"
MYSQL_USER="${MYSQL_USER:-megusta_admin}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-sptech}"
MYSQL_DB="${MYSQL_DATABASE:-megusta}"

# Tenta conectar e fazer ping
if mysqladmin ping -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" --silent; then
    # Verifica se o database existe e está acessível
    if mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "USE \`$MYSQL_DB\`; SELECT 1;" --silent; then
        echo "OK: Database $MYSQL_DB is healthy"
        exit 0
    else
        echo "ERROR: Database $MYSQL_DB not accessible"
        exit 1
    fi
else
    echo "ERROR: MySQL ping failed"
    exit 1
fi