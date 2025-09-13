#!/bin/bash

# Demo script for OTUI - uses fake environment variables for testing the UI
# This won't actually connect to OpenStack but will show the interface

echo "Setting up demo OpenStack environment variables..."

export OS_AUTH_URL="https://demo.openstack.org:5000/v3"
export OS_USERNAME="demo"
export OS_PASSWORD="demopassword"
export OS_PROJECT_NAME="demo"
export OS_REGION_NAME="RegionOne"
export OS_USER_DOMAIN_NAME="Default"
export OS_PROJECT_DOMAIN_NAME="Default"

echo "Environment variables set:"
echo "  OS_AUTH_URL=$OS_AUTH_URL"
echo "  OS_USERNAME=$OS_USERNAME"
echo "  OS_PROJECT_NAME=$OS_PROJECT_NAME"
echo "  OS_REGION_NAME=$OS_REGION_NAME"
echo ""
echo "Note: This will attempt to connect to the demo URL above."
echo "The TUI should start and show an error about authentication,"
echo "but the interface should be visible."
echo ""
echo "Starting OTUI..."

swift run otui