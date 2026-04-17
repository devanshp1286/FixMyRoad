# Login Troubleshooting Guide

## Error: "Software caused connection abort (errno = 103)"

This error means the Flutter app **cannot connect to Supabase**. The connection is being rejected or reset.

### Quick Checklist

✅ **1. Check Internet Connection**
```
- Ensure device/emulator has internet access
- Try opening a web browser and visiting supabase.co
- If on Android emulator: needs to use host's network
```

✅ **2. Verify Supabase Credentials**

The credentials in [flutter_app/lib/core/constants.dart](flutter_app/lib/core/constants.dart):
```dart
static const supabaseUrl = 'https://umuqhnzqutumhuykuiwc.supabase.co';
static const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
```

Verify they are correct by:
1. Go to [Supabase Dashboard](https://app.supabase.com/)
2. Select your project "fixmyroad"
3. Go to Settings → API
4. Compare the URLs and keys match

✅ **3. Check Firewall/VPN**
- Some firewalls block Supabase connections
- Try disabling VPN if you have one
- Check if port 443 (HTTPS) is blocked

✅ **4. Test Direct Connection**

Create a test by running this in terminal:
```bash
curl -I https://umuqhnzqutumhuykuiwc.supabase.co
```

Should return HTTP 200. If it times out or connection refused → network issue.

✅ **5. Check Supabase Status**

Visit [Supabase Status Page](https://status.supabase.com/) to see if there are any outages.

✅ **6. Device-Specific Issues**

**Android Emulator:**
- Uses `10.0.2.2` to reach host PC
- If your backend is on PC: that's fine
- For Supabase: needs internet through emulator's network

**Physical Phone:**
- Ensure WiFi/mobile data is enabled
- Check if device is on same network as development machine
- Some public WiFi blocks Supabase

✅ **7. Clear Cache and Rebuild**

```bash
cd flutter_app
flutter clean
flutter pub get
flutter run
```

## Error Messages Guide

| Error | Cause | Solution |
|-------|-------|----------|
| "Software caused connection abort (errno = 103)" | Connection reset | Check firewall, verify URL |
| "Connection timeout" | Server not responding | Check internet, Supabase status |
| "Invalid credentials" | Wrong email/password | Verify login credentials |
| "Email not confirmed" | Email verification required | Disable in Supabase Auth settings |
| "No internet connection" | Device offline | Enable WiFi/mobile data |

## Testing Supabase Connection

### Option A: From Flutter Console

The updated login screen now shows debug output. Run:
```bash
flutter run
```

Watch the console for messages like:
```
[Login] Attempting login for user@example.com...
[Login] ✓ Auth successful for user@example.com
[Login] Fetching profile...
[Login] ✓ Profile found: citizen
```

### Option B: Direct Test

Open [Supabase Docs](https://supabase.com/docs/guides/api) and try:
```bash
curl -X GET 'https://umuqhnzqutumhuykuiwc.supabase.co/rest/v1/profiles?limit=1' \
  -H 'apikey: YOUR_ANON_KEY' \
  -H 'Authorization: Bearer YOUR_ANON_KEY'
```

## Common Solutions

### Errno 103 (Connection Reset)

**Most likely causes:**
1. ❌ Firewall blocking Supabase
2. ❌ Invalid Supabase credentials
3. ❌ Wrong URL in constants.dart
4. ❌ Supabase project paused/deleted

**Fix:**
```dart
// In flutter_app/lib/core/constants.dart
static const supabaseUrl = 'https://umuqhnzqutumhuykuiwc.supabase.co';
// Verify this matches your project URL in Supabase dashboard
```

### Timeout Issues

**Most likely causes:**
1. ❌ Network too slow
2. ❌ Supabase server overloaded
3. ❌ DNS resolution failing

**Fix:**
```dart
// Already increased timeout in login_screen.dart
.timeout(const Duration(seconds: 15), ...)
```

## Still Having Issues?

1. **Check Flutter Doctor:**
   ```bash
   flutter doctor -v
   ```

2. **Enable Network Logging:**
   Add this to your app to log all network calls

3. **Test Supabase Directly:**
   Use Supabase Client in Python:
   ```python
   from supabase import create_client
   url = 'https://umuqhnzqutumhuykuiwc.supabase.co'
   key = 'YOUR_ANON_KEY'
   supabase = create_client(url, key)
   ```

4. **Report the Full Error:**
   Look in Flutter console for complete error message with full stacktrace

## For Android Emulator Users

If using Android emulator, it has a different localhost:

```dart
// For emulator backend on PC:
static const aiWorkerUrl = 'http://10.0.2.2:8000';

// For real device on local network:
static const aiWorkerUrl = 'http://192.168.1.100:8000';  // Your PC's local IP
```

But for Supabase (cloud service), use the full URL:
```dart
static const supabaseUrl = 'https://umuqhnzqutumhuykuiwc.supabase.co';
```

## Enable Debug Mode

To see all network requests, add to main.dart:

```dart
// Add this in main() before Supabase.initialize()
if (kDebugMode) {
  // Enable Supabase debug logging
  Supabase.instance.client.functions.setAuth('DEBUG');
}
```

---

**Still stuck?** Check the Flutter console output - it now shows detailed debug messages like:
- `[Init] Supabase initialized` ✓
- `[Login] ✓ Auth successful` ✓
- `[Login] Profile error: ...` ✗
