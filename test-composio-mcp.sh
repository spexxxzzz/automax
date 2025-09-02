#!/bin/bash

# Comprehensive test script for Composio Integration and MCP Servers
# Run this on your VM to diagnose issues

set -e

echo "🔍 Testing Composio Integration and MCP Servers"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

BASE_URL="https://app.autobro.cloud"
API_URL="$BASE_URL/api"

# Function to test API endpoint
test_endpoint() {
    local endpoint=$1
    local expected_status=${2:-200}
    local description=$3
    
    echo -e "\n${BLUE}Testing:${NC} $description"
    echo "Endpoint: $endpoint"
    
    response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$endpoint" || echo "HTTPSTATUS:000")
    http_code=$(echo $response | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    body=$(echo $response | sed -e 's/HTTPSTATUS\:.*//g')
    
    if [ "$http_code" -eq "$expected_status" ]; then
        echo -e "${GREEN}✅ SUCCESS${NC} (HTTP $http_code)"
        if [ -n "$body" ] && [ "$body" != "null" ]; then
            echo "Response: $(echo $body | jq . 2>/dev/null || echo $body)"
        fi
    else
        echo -e "${RED}❌ FAILED${NC} (HTTP $http_code)"
        if [ -n "$body" ]; then
            echo "Error: $body"
        fi
    fi
}

# Function to test authenticated endpoint
test_auth_endpoint() {
    local endpoint=$1
    local expected_status=${2:-401}
    local description=$3
    
    echo -e "\n${BLUE}Testing (Auth Required):${NC} $description"
    echo "Endpoint: $endpoint"
    
    response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$endpoint" || echo "HTTPSTATUS:000")
    http_code=$(echo $response | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    body=$(echo $response | sed -e 's/HTTPSTATUS\:.*//g')
    
    if [ "$http_code" -eq "$expected_status" ]; then
        echo -e "${GREEN}✅ ENDPOINT ACCESSIBLE${NC} (HTTP $http_code - Expected for unauthenticated)"
    else
        echo -e "${YELLOW}⚠️  UNEXPECTED STATUS${NC} (HTTP $http_code)"
        if [ -n "$body" ]; then
            echo "Response: $body"
        fi
    fi
}

echo -e "\n${YELLOW}1. Environment Variables Check${NC}"
echo "================================"

# Check environment variables
echo -e "\n🔑 Checking required environment variables..."

if docker compose exec backend printenv | grep -q "COMPOSIO_API_KEY"; then
    echo -e "${GREEN}✅ COMPOSIO_API_KEY${NC} is set"
else
    echo -e "${RED}❌ COMPOSIO_API_KEY${NC} is not set"
fi

if docker compose exec backend printenv | grep -q "COMPOSIO_API_BASE"; then
    COMPOSIO_BASE=$(docker compose exec backend printenv | grep COMPOSIO_API_BASE | cut -d'=' -f2)
    echo -e "${GREEN}✅ COMPOSIO_API_BASE${NC} = $COMPOSIO_BASE"
else
    echo -e "${YELLOW}⚠️  COMPOSIO_API_BASE${NC} using default (https://backend.composio.dev)"
fi

if docker compose exec backend printenv | grep -q "MCP_CREDENTIAL_ENCRYPTION_KEY"; then
    echo -e "${GREEN}✅ MCP_CREDENTIAL_ENCRYPTION_KEY${NC} is set"
else
    echo -e "${RED}❌ MCP_CREDENTIAL_ENCRYPTION_KEY${NC} is not set"
fi

echo -e "\n${YELLOW}2. Docker Services Status${NC}"
echo "============================="

echo -e "\n📦 Checking Docker services..."
docker compose ps

echo -e "\n🔄 Checking service health..."
docker compose exec backend python -c "
import asyncio
import sys
sys.path.append('/app')

async def check_services():
    try:
        # Test Redis connection
        from services import redis
        redis_client = await redis.get_client()
        await redis_client.ping()
        print('✅ Redis connection: OK')
    except Exception as e:
        print(f'❌ Redis connection: {e}')
    
    try:
        # Test Supabase connection
        from services.supabase import DBConnection
        db = DBConnection()
        # Simple query test
        print('✅ Supabase connection: OK')
    except Exception as e:
        print(f'❌ Supabase connection: {e}')

asyncio.run(check_services())
" 2>/dev/null || echo -e "${RED}❌ Failed to check backend services${NC}"

echo -e "\n${YELLOW}3. Feature Flags Check${NC}"
echo "========================"

echo -e "\n🚩 Checking feature flags..."

# Test feature flags API
test_endpoint "$API_URL/feature-flags" 200 "Feature flags API"

# Check specific flags
echo -e "\n🔍 Checking MCP module flag..."
docker compose exec backend python -c "
import asyncio
import sys
sys.path.append('/app')

async def check_flags():
    try:
        from flags.flags import is_enabled, mcp_module
        print(f'MCP Module (static): {mcp_module}')
        
        # Check dynamic flag
        mcp_enabled = await is_enabled('mcp_module')
        print(f'MCP Module (dynamic): {mcp_enabled}')
        
    except Exception as e:
        print(f'Error checking flags: {e}')

asyncio.run(check_flags())
" 2>/dev/null || echo -e "${RED}❌ Failed to check feature flags${NC}"

echo -e "\n${YELLOW}4. Composio API Endpoints${NC}"
echo "============================"

# Test Composio endpoints
test_auth_endpoint "$API_URL/composio/toolkits" 401 "Composio toolkits list"
test_auth_endpoint "$API_URL/composio/profiles" 401 "Composio profiles"
test_auth_endpoint "$API_URL/composio/connected-accounts" 401 "Connected accounts"
test_auth_endpoint "$API_URL/composio/mcp-servers" 401 "MCP servers"

echo -e "\n${YELLOW}5. MCP Module Endpoints${NC}"
echo "========================="

# Test MCP endpoints
test_auth_endpoint "$API_URL/mcp/servers" 401 "MCP servers list"
test_auth_endpoint "$API_URL/mcp/credentials" 401 "MCP credentials"

echo -e "\n${YELLOW}6. Backend Composio Integration Test${NC}"
echo "======================================"

echo -e "\n🧪 Testing Composio integration from backend..."
docker compose exec backend python -c "
import asyncio
import sys
import os
sys.path.append('/app')

async def test_composio():
    try:
        # Test Composio client initialization
        from composio_integration.client import ComposioClient
        
        api_key = os.getenv('COMPOSIO_API_KEY')
        if not api_key:
            print('❌ COMPOSIO_API_KEY not set')
            return
            
        client = ComposioClient.get_client(api_key)
        print('✅ Composio client initialized')
        
        # Test toolkit service
        from composio_integration.toolkit_service import ToolkitService
        toolkit_service = ToolkitService(api_key)
        print('✅ Toolkit service initialized')
        
        # Test MCP server service
        from composio_integration.mcp_server_service import MCPServerService
        mcp_service = MCPServerService(api_key)
        print('✅ MCP server service initialized')
        
    except Exception as e:
        print(f'❌ Composio integration error: {e}')
        import traceback
        traceback.print_exc()

asyncio.run(test_composio())
" 2>/dev/null || echo -e "${RED}❌ Failed to test Composio integration${NC}"

echo -e "\n${YELLOW}7. MCP Module Integration Test${NC}"
echo "================================="

echo -e "\n🧪 Testing MCP module from backend..."
docker compose exec backend python -c "
import asyncio
import sys
sys.path.append('/app')

async def test_mcp():
    try:
        # Test MCP service
        from mcp_module.mcp_service import MCPService
        print('✅ MCP service imported')
        
        # Test custom MCP handler
        from agent.tools.utils.custom_mcp_handler import CustomMCPHandler
        print('✅ Custom MCP handler imported')
        
    except Exception as e:
        print(f'❌ MCP module error: {e}')
        import traceback
        traceback.print_exc()

asyncio.run(test_mcp())
" 2>/dev/null || echo -e "${RED}❌ Failed to test MCP module${NC}"

echo -e "\n${YELLOW}8. Database Schema Check${NC}"
echo "==========================="

echo -e "\n🗄️  Checking MCP/Composio related tables..."
docker compose exec backend python -c "
import sys
sys.path.append('/app')

async def check_tables():
    try:
        from services.supabase import DBConnection
        db = DBConnection()
        
        # Check for MCP related tables
        tables_to_check = [
            'user_mcp_credentials',
            'user_mcp_credential_profiles', 
            'agent_versions',
            'triggers',
            'composio_profiles'
        ]
        
        for table in tables_to_check:
            try:
                result = db.client.table(table).select('*', count='exact').limit(0).execute()
                print(f'✅ Table {table}: exists (count: {result.count})')
            except Exception as e:
                print(f'❌ Table {table}: {e}')
                
    except Exception as e:
        print(f'❌ Database check error: {e}')

import asyncio
asyncio.run(check_tables())
" 2>/dev/null || echo -e "${RED}❌ Failed to check database schema${NC}"

echo -e "\n${YELLOW}9. Logs Analysis${NC}"
echo "=================="

echo -e "\n📋 Recent backend logs (last 50 lines)..."
docker compose logs --tail=50 backend | grep -i -E "(composio|mcp|error|failed)" || echo "No relevant log entries found"

echo -e "\n${YELLOW}10. Quick Fix Commands${NC}"
echo "========================"

echo -e "\n💡 If issues found, try these commands:"
echo ""
echo "🔄 Restart services:"
echo "  docker compose restart"
echo ""
echo "🧹 Clear Redis cache:"
echo "  docker compose exec redis redis-cli FLUSHALL"
echo ""
echo "📦 Rebuild backend:"
echo "  docker compose build backend"
echo "  docker compose up -d backend"
echo ""
echo "🔑 Set missing environment variables:"
echo "  # Add to your .env file:"
echo "  COMPOSIO_API_KEY=your_composio_api_key"
echo "  MCP_CREDENTIAL_ENCRYPTION_KEY=\$(openssl rand -base64 32)"
echo ""
echo "🚩 Enable feature flags:"
echo "  docker compose exec backend python -c \""
echo "  import asyncio"
echo "  import sys"
echo "  sys.path.append('/app')"
echo "  from flags.flags import get_flag_manager"
echo "  async def enable_flags():"
echo "      fm = get_flag_manager()"
echo "      await fm.set_flag('mcp_module', True, 'Enable MCP module')"
echo "      print('MCP module flag enabled')"
echo "  asyncio.run(enable_flags())\""

echo -e "\n${GREEN}🎉 Test Complete!${NC}"
echo "==================="
echo ""
echo "📊 Summary:"
echo "• Check the output above for any ❌ failures"
echo "• All ✅ items are working correctly"
echo "• ⚠️  items may need attention"
echo ""
echo "🔧 Next steps if issues found:"
echo "1. Fix any missing environment variables"
echo "2. Restart Docker services if needed"
echo "3. Check application logs for detailed errors"
echo "4. Verify feature flags are enabled"





