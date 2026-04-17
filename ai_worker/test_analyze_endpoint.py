"""
Test the /analyze endpoint directly to ensure it's working
"""
import requests
import json

# Test image URL (use a real image from your Supabase)
IMAGE_URL = "https://umuqhnzqutumhuykuiwc.supabase.co/storage/v1/object/public/pothole-images/3b4527a9-e563-4901-b694-45c2b3136442/1776450652007.jpg"
REPORT_ID = "test-endpoint-12345"

def test_health():
    """Test if /health endpoint works"""
    print("\n" + "="*70)
    print("[TEST 1] Testing /health endpoint...")
    print("="*70)
    try:
        response = requests.get('http://127.0.0.1:8000/health', timeout=5)
        print(f"✓ Status: {response.status_code}")
        print(f"✓ Response: {response.json()}")
        return True
    except Exception as e:
        print(f"✗ Failed: {e}")
        return False

def test_analyze():
    """Test the /analyze endpoint with a real image"""
    print("\n" + "="*70)
    print("[TEST 2] Testing /analyze endpoint (POST)...")
    print("="*70)
    
    payload = {
        'report_id': REPORT_ID,
        'image_url': IMAGE_URL
    }
    
    print(f"Sending request to: http://127.0.0.1:8000/analyze")
    print(f"Payload: {json.dumps(payload, indent=2)}")
    
    try:
        response = requests.post(
            'http://127.0.0.1:8000/analyze',
            json=payload,
            timeout=30,  # 30 second timeout
            headers={'Content-Type': 'application/json'}
        )
        print(f"\n✓ Status: {response.status_code}")
        if response.status_code == 200:
            print(f"✓ Analysis complete!")
            result = response.json()
            print(f"  - Severity: {result.get('severity')}")
            print(f"  - Depth: {result.get('relative_depth')}")
            print(f"  - Cost: ₹{result.get('repair_cost_min')} - ₹{result.get('repair_cost_max')}")
            print(f"  - Time: {result.get('processing_time_s'):.1f}s")
            return True
        else:
            print(f"✗ Error: {response.status_code}")
            print(f"Response: {response.text}")
            return False
    except requests.exceptions.Timeout:
        print(f"✗ TIMEOUT - Server took too long to respond")
        print(f"   This means /analyze is hanging (likely on image download or AI processing)")
        return False
    except requests.exceptions.ConnectionError as e:
        print(f"✗ CONNECTION ERROR: {e}")
        print(f"   Make sure backend is running: python main.py")
        return False
    except Exception as e:
        print(f"✗ Failed: {e}")
        return False

if __name__ == '__main__':
    print("\n🧪 TESTING AI WORKER ENDPOINTS\n")
    
    # Test health first
    if not test_health():
        print("\n❌ Backend is not running!")
        print("Start it with: cd d:\\fix\\ai_worker && python main.py")
        exit(1)
    
    # Test analyze endpoint
    if test_analyze():
        print("\n✅ /analyze endpoint is working!")
        print("Your Flutter app should be able to submit reports now.")
    else:
        print("\n❌ /analyze endpoint has issues")
        print("Check the AI Worker console output for errors")
