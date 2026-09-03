#!/bin/bash
# Endpoint tests for the legacy API
# Usage: ./scripts/test-api.sh <base-url>

set -euo pipefail

BASE_URL="${1:-http://localhost:5000}"

echo "Testing API at: $BASE_URL"
echo "=================================="
echo ""

# Colours
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

test_endpoint() {
    local method=$1
    local endpoint=$2
    local data=$3
    local expected_status=$4

    echo -n "Testing $method $endpoint... "

    if [ "$method" == "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" "$BASE_URL$endpoint")
    else
        response=$(curl -s -w "\n%{http_code}" \
            -X "$method" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$BASE_URL$endpoint")
    fi

    status_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    if [ "$status_code" == "$expected_status" ]; then
        echo -e "${GREEN}✓ PASSED (${status_code})${NC}"

        if [ -n "$body" ]; then
            echo "$body" | jq '.' 2>/dev/null || echo "$body"
        fi

        return 0
    else
        echo -e "${RED}✗ FAILED (expected ${expected_status}, got ${status_code})${NC}"
        echo "Response: $body"
        return 1
    fi
}

echo "1. Health Check"
test_endpoint "GET" "/health" "" "200"
echo ""

echo "2. Get All Products"
test_endpoint "GET" "/api/v1/products" "" "200"
echo ""

echo "3. Get Specific Product"
test_endpoint "GET" "/api/v1/products/1" "" "200"
echo ""

echo "4. Get Non-existent Product"
test_endpoint "GET" "/api/v1/products/999" "" "404"
echo ""

echo "5. Create Order"
test_endpoint "POST" "/api/v1/orders" '{"product_id": 1, "quantity": 2}' "201"
echo ""

echo "6. Get All Orders"
test_endpoint "GET" "/api/v1/orders" "" "200"
echo ""

echo "7. Create Order with Invalid Product"
test_endpoint "POST" "/api/v1/orders" '{"product_id": 999, "quantity": 1}' "404"
echo ""

echo "8. Create Order without product_id"
test_endpoint "POST" "/api/v1/orders" '{"quantity": 1}' "400"
echo ""

echo "9. Get Stats"
test_endpoint "GET" "/api/v1/stats" "" "200"
echo ""

echo "=================================="
echo -e "${GREEN}All endpoint tests passed!${NC}"