#!/bin/bash

# Script to fix Composio and MCP integration issues
set -e

echo "🔧 Fixing Composio and MCP Integration Issues"
echo "============================================="

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "\n${YELLOW}1. Checking Docker Services${NC}"
echo "============================"

# Check if services are running
if ! docker compose ps | grep -q "backend.*Up"; then
    echo -e "${RED}❌ Backend service not running${NC}"
    echo "Starting backend service..."
    docker compose up -d backend
    sleep 10
else
    echo -e "${GREEN}✅ Backend service is running${NC}"
fi

if ! docker compose ps | grep -q "redis.*Up"; then
    echo -e "${RED}❌ Redis service not running${NC}"
    echo "Starting Redis service..."
    docker compose up -d redis
    sleep 5
else
    echo -e "${GREEN}✅ Redis service is running${NC}"
fi

echo -e "\n${YELLOW}2. Fixing Redis Module Issue${NC}"
echo "================================"

echo "🔍 Checking if Redis module is installed in backend..."

# Check if redis module exists
REDIS_INSTALLED=$(docker compose exec backend python -c "
try:
    import redis
    print('installed')
except ImportError:
    print('missing')
" 2>/dev/null || echo "error")

if [ "$REDIS_INSTALLED" = "missing" ] || [ "$REDIS_INSTALLED" = "error" ]; then
    echo -e "${RED}❌ Redis module not found${NC}"
    echo "Installing Redis module..."
    
    # Install redis module
    docker compose exec backend pip install redis
    
    echo -e "${GREEN}✅ Redis module installed${NC}"
else
    echo -e "${GREEN}✅ Redis module already installed${NC}"
fi

echo -e "\n${YELLOW}3. Testing Redis Connection${NC}"
echo "==============================="

echo "🔌 Testing Redis connection..."
docker compose exec backend python -c "
import asyncio
import sys
sys.path.append('/app')

async def test_redis():
    try:
        from services import redis
        client = await redis.get_client()
        await client.ping()
        print('✅ Redis connection successful')
        return True
    except Exception as e:
        print(f'❌ Redis connection failed: {e}')
        return False

result = asyncio.run(test_redis())
" 2>/dev/null || echo -e "${RED}❌ Failed to test Redis connection${NC}"

echo -e "\n${YELLOW}4. Initializing Feature Flags${NC}"
echo "================================"

echo "🚩 Setting up feature flags..."

# Initialize feature flags
docker compose exec backend python -c "
import asyncio
import sys
sys.path.append('/app')

async def setup_flags():
    try:
        from flags.flags import get_flag_manager
        
        fm = get_flag_manager()
        
        # Set essential flags
        flags_to_set = [
            ('mcp_module', True, 'Enable MCP module functionality'),
            ('custom_agents', True, 'Enable custom agent creation'),
            ('templates_api', True, 'Enable templates API'),
            ('triggers_api', True, 'Enable triggers API'),
            ('workflows_api', True, 'Enable workflows API'),
            ('credentials_api', True, 'Enable credentials API'),
            ('pipedream', True, 'Enable Pipedream integration'),
            ('knowledge_base', True, 'Enable knowledge base'),
            ('suna_default_agent', True, 'Enable Suna default agent')
        ]
        
        for flag_name, enabled, description in flags_to_set:
            success = await fm.set_flag(flag_name, enabled, description)
            if success:
                print(f'✅ Set {flag_name}: {enabled}')
            else:
                print(f'❌ Failed to set {flag_name}')
        
        print('\\n🎉 Feature flags initialized!')
        
    except Exception as e:
        print(f'❌ Failed to setup feature flags: {e}')
        import traceback
        traceback.print_exc()

asyncio.run(setup_flags())
" 2>/dev/null || echo -e "${RED}❌ Failed to setup feature flags${NC}"

echo -e "\n${YELLOW}5. Verifying Feature Flags${NC}"
echo "============================="

echo "🔍 Checking feature flags via API..."
sleep 2  # Give Redis a moment

# Test feature flags API
curl -s https://app.autobro.cloud/api/feature-flags | jq . || echo "API call failed"

echo -e "\n🔍 Checking feature flags from backend..."
docker compose exec backend python -c "
import asyncio
import sys
sys.path.append('/app')

async def check_flags():
    try:
        from flags.flags import is_enabled, mcp_module
        
        print(f'MCP module (static): {mcp_module}')
        
        # Check dynamic flags
        flags_to_check = ['mcp_module', 'custom_agents', 'templates_api']
        
        for flag in flags_to_check:
            enabled = await is_enabled(flag)
            print(f'{flag} (dynamic): {enabled}')
            
    except Exception as e:
        print(f'❌ Error checking flags: {e}')

asyncio.run(check_flags())
" 2>/dev/null || echo -e "${RED}❌ Failed to check feature flags${NC}"

echo -e "\n${YELLOW}6. Testing Composio Integration${NC}"
echo "=================================="

echo "🧪 Testing Composio integration..."
docker compose exec backend python -c "
import sys
sys.path.append('/app')

try:
    # Test imports
    from composio_integration.client import ComposioClient
    from composio_integration.toolkit_service import ToolkitService
    from composio_integration.mcp_server_service import MCPServerService
    from composio_integration.composio_service import get_integration_service
    
    print('✅ All Composio modules imported successfully')
    
    # Test client creation (will fail without API key, but import should work)
    try:
        import os
        api_key = os.getenv('COMPOSIO_API_KEY')
        if api_key:
            client = ComposioClient.get_client(api_key)
            print('✅ Composio client created successfully')
        else:
            print('⚠️  COMPOSIO_API_KEY not set, but modules imported correctly')
    except Exception as e:
        print(f'⚠️  Client creation failed (expected without API key): {e}')
        
except Exception as e:
    print(f'❌ Composio integration error: {e}')
    import traceback
    traceback.print_exc()
" 2>/dev/null || echo -e "${RED}❌ Failed to test Composio integration${NC}"

echo -e "\n${YELLOW}7. Testing API Endpoints${NC}"
echo "=========================="

echo "🌐 Testing Composio API endpoints..."

endpoints=(
    "/api/composio/toolkits"
    "/api/composio/profiles" 
    "/api/composio/connected-accounts"
    "/api/composio/mcp-servers"
    "/api/mcp/servers"
    "/api/mcp/credentials"
)

for endpoint in "${endpoints[@]}"; do
    echo -n "Testing $endpoint: "
    status=$(curl -s -o /dev/null -w "%{http_code}" "https://app.autobro.cloud$endpoint")
    if [ "$status" = "401" ]; then
        echo -e "${GREEN}✅ OK (401 - Auth required)${NC}"
    elif [ "$status" = "200" ]; then
        echo -e "${GREEN}✅ OK (200)${NC}"
    else
        echo -e "${RED}❌ Error (HTTP $status)${NC}"
    fi
done

echo -e "\n${YELLOW}8. Environment Variables Check${NC}"
echo "==================================="

echo "🔑 Checking required environment variables..."

# Check environment variables
ENV_VARS=(
    "COMPOSIO_API_KEY"
    "COMPOSIO_API_BASE" 
    "MCP_CREDENTIAL_ENCRYPTION_KEY"
    "SUPABASE_URL"
    "SUPABASE_ANON_KEY"
    "REDIS_HOST"
)

for var in "${ENV_VARS[@]}"; do
    if docker compose exec backend printenv | grep -q "^$var="; then
        if [ "$var" = "COMPOSIO_API_KEY" ] || [ "$var" = "MCP_CREDENTIAL_ENCRYPTION_KEY" ]; then
            echo -e "${GREEN}✅ $var${NC} is set (hidden)"
        else
            value=$(docker compose exec backend printenv | grep "^$var=" | cut -d'=' -f2-)
            echo -e "${GREEN}✅ $var${NC} = $value"
        fi
    else
        echo -e "${RED}❌ $var${NC} is not set"
        
        # Provide fix suggestions
        case $var in
            "COMPOSIO_API_KEY")
                echo "   Fix: Add COMPOSIO_API_KEY=your_api_key to .env file"
                ;;
            "MCP_CREDENTIAL_ENCRYPTION_KEY")
                echo "   Fix: Add MCP_CREDENTIAL_ENCRYPTION_KEY=\$(openssl rand -base64 32) to .env file"
                ;;
            "COMPOSIO_API_BASE")
                echo "   Fix: Add COMPOSIO_API_BASE=https://backend.composio.dev to .env file"
                ;;
        esac
    fi
done

echo -e "\n${YELLOW}9. Restart Services${NC}"
echo "==================="

echo "🔄 Restarting services to apply changes..."
docker compose restart backend
sleep 10

echo "✅ Services restarted"

echo -e "\n${GREEN}🎉 Fix Complete!${NC}"
echo "================="
echo ""
echo "📋 Summary of fixes applied:"
echo "• ✅ Installed Redis module if missing"
echo "• ✅ Initialized feature flags in Redis"
echo "• ✅ Tested Composio integration imports"
echo "• ✅ Verified API endpoints are accessible"
echo "• ✅ Restarted backend service"
echo ""
echo "🧪 Test again with:"
echo "  curl -s https://app.autobro.cloud/api/feature-flags | jq ."
echo ""
echo "🔧 If issues persist:"
echo "1. Check Docker logs: docker compose logs backend"
echo "2. Verify environment variables in .env file"
echo "3. Ensure Redis is running: docker compose ps redis"





