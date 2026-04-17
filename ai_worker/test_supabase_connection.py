#!/usr/bin/env python3
"""
Diagnostic script to test AI Worker connectivity and Supabase access
"""
import os
import sys
from supabase_client import supabase

print("\n" + "="*80)
print("FixMyRoad AI Worker - Diagnostic Test")
print("="*80)

# Test 1: Check Supabase connection
print("\n[TEST 1] Checking Supabase connection...")
try:
    # Try to get auth status
    auth_status = supabase.auth.get_session()
    print("✓ Supabase client initialized")
    print(f"  URL: {os.getenv('SUPABASE_URL', 'https://umuqhnzqutumhuykuiwc.supabase.co')}")
except Exception as e:
    print(f"✗ Supabase initialization failed: {e}")
    sys.exit(1)

# Test 2: Check ai_results table accessibility
print("\n[TEST 2] Checking ai_results table access...")
try:
    # Try to select one row to test permissions
    response = supabase.table("ai_results").select("*").limit(1).execute()
    print(f"✓ ai_results table is accessible")
    print(f"  Record count: {len(response.data) if response.data else 0}")
except Exception as e:
    print(f"✗ Cannot access ai_results table: {e}")
    print(f"  Error type: {type(e).__name__}")

# Test 3: Check reports table accessibility
print("\n[TEST 3] Checking reports table access...")
try:
    response = supabase.table("reports").select("*").limit(1).execute()
    print(f"✓ reports table is accessible")
    print(f"  Record count: {len(response.data) if response.data else 0}")
except Exception as e:
    print(f"✗ Cannot access reports table: {e}")

# Test 4: Check status_history table accessibility
print("\n[TEST 4] Checking status_history table access...")
try:
    response = supabase.table("status_history").select("*").limit(1).execute()
    print(f"✓ status_history table is accessible")
    print(f"  Record count: {len(response.data) if response.data else 0}")
except Exception as e:
    print(f"✗ Cannot access status_history table: {e}")

# Test 5: Try a test insert to ai_results (with rollback)
print("\n[TEST 5] Testing ai_results INSERT capability...")
try:
    test_row = {
        "report_id": "test-diagnostic-" + os.urandom(4).hex(),
        "severity": "shallow",
        "relative_depth": 0.02,
        "confidence": 0.95,
        "repair_cost_min": 100,
        "repair_cost_max": 200,
    }
    print(f"  Attempting to insert test row: {test_row}")
    response = supabase.table("ai_results").insert(test_row).execute()
    print(f"✓ INSERT successful")
    
    # Now delete it
    supabase.table("ai_results").delete().eq("report_id", test_row["report_id"]).execute()
    print(f"✓ Cleanup: test row deleted")
except Exception as e:
    print(f"✗ INSERT failed: {e}")
    print(f"  Error type: {type(e).__name__}")

# Test 6: Check recent reports without ai_results
print("\n[TEST 6] Checking recent reports in database...")
try:
    response = supabase.table("reports").select("id, status, submitted_at").order("submitted_at", ascending=False).limit(5).execute()
    if response.data:
        print(f"✓ Found {len(response.data)} recent reports:")
        for report in response.data:
            print(f"  - Report {report['id'][:8]}... | Status: {report['status']}")
    else:
        print("✓ No reports found (table might be empty)")
except Exception as e:
    print(f"✗ Query failed: {e}")

print("\n" + "="*80)
print("Diagnostic test complete")
print("="*80 + "\n")
