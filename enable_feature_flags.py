#!/usr/bin/env python3
"""
Enable all important feature flags for MCP integrations and custom agents
"""
import sys
import asyncio
import os

# Add backend to path
sys.path.append(os.path.join(os.path.dirname(__file__), 'backend'))

async def enable_all_flags():
    """Enable all important feature flags"""
    try:
        from flags.flags import get_flag_manager
        
        manager = get_flag_manager()
        
        # Important flags to enable
        flags_to_enable = {
            'mcp_module': 'Enable MCP module for custom integrations',
            'custom_agents': 'Enable custom agent creation and management', 
            'templates_api': 'Enable agent templates API',
            'triggers_api': 'Enable triggers and automation API',
            'workflows_api': 'Enable workflows API',
            'credentials_api': 'Enable credentials management API',
            'pipedream': 'Enable Pipedream integration',
            'knowledge_base': 'Enable knowledge base functionality',
            'suna_default_agent': 'Enable Suna default agent',
            'custom_mcp_servers': 'Enable custom MCP server integrations',
            'composio_integration': 'Enable Composio integration for external tools',
            'mcp_credential_profiles': 'Enable MCP credential profile management',
            'agent_builder_tools': 'Enable agent builder tools',
            'external_integrations': 'Enable external service integrations'
        }
        
        print("=== ENABLING FEATURE FLAGS ===")
        
        success_count = 0
        for flag_name, description in flags_to_enable.items():
            try:
                result = await manager.set_flag(flag_name, True, description)
                if result:
                    print(f"✅ {flag_name}: ENABLED")
                    success_count += 1
                else:
                    print(f"❌ {flag_name}: FAILED")
            except Exception as e:
                print(f"❌ {flag_name}: ERROR - {str(e)}")
        
        print(f"\n🎉 Successfully enabled {success_count}/{len(flags_to_enable)} feature flags")
        
        # Verify flags are enabled
        print("\n=== VERIFICATION ===")
        for flag_name in flags_to_enable.keys():
            try:
                enabled = await manager.is_enabled(flag_name)
                status = "✅ ENABLED" if enabled else "❌ DISABLED"
                print(f"{flag_name}: {status}")
            except Exception as e:
                print(f"{flag_name}: ERROR - {str(e)}")
                
    except Exception as e:
        print(f"Error enabling flags: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(enable_all_flags())
