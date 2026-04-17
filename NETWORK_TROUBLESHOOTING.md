# Network Troubleshooting - Supabase Connection Timeout

**The Problem**: Your system cannot reach Supabase servers
```
✗ ConnectTimeout: A connection attempt failed...
```

This means AI results CAN'T be saved because the AI worker can't reach Supabase either!

---

## Quick Diagnostic Commands

Run these in PowerShell to diagnose the issue:

### 1. Check if you can reach Supabase servers
```powershell
# Ping Supabase
ping umuqhnzqutumhuykuiwc.supabase.co

# Or test connection to the URL
Invoke-WebRequest -Uri "https://umuqhnzqutumhuykuiwc.supabase.co" -UseBasicParsing
```

Expected: Should get a response (status 403 or similar is OK, timeout is NOT OK)

### 2. Check DNS resolution
```powershell
# Resolve the hostname
Resolve-DnsName umuqhnzqutumhuykuiwc.supabase.co
```

Expected: Should show IP address(es)

### 3. Check internet connectivity
```powershell
# Ping Google (should work if internet is OK)
ping 8.8.8.8

# Or test access to Google
Invoke-WebRequest -Uri "https://www.google.com" -UseBasicParsing
```

### 4. Check if port 443 is accessible (HTTPS)
```powershell
# Test connection to port 443
$socket = New-Object Net.Sockets.TcpClient
$socket.Connect("umuqhnzqutumhuykuiwc.supabase.co", 443)
$socket.Connected  # Should return True
```

---

## Likely Issues & Solutions

### Issue 1: **Network/Firewall Blocking**
**Symptoms**:
- Ping fails to resolve or times out
- Port 443 connection fails
- Can access local sites but not Supabase

**Solution**:
```powershell
# 1. Check if Windows Firewall is blocking
# Settings → Privacy & Security → Windows Defender Firewall
# → Allow an app through firewall
# Make sure Python is allowed

# 2. Check corporate firewall (if on corporate network)
# Contact IT to whitelist: umuqhnzqutumhuykuiwc.supabase.co

# 3. Try disabling firewall temporarily (TESTING ONLY)
# In PowerShell (Admin):
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled $False
# Then test, then re-enable:
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled $True
```

### Issue 2: **VPN or Proxy Issue**
**Symptoms**:
- Connected to VPN and nothing works
- Local requests work fine

**Solution**:
```powershell
# Disconnect from VPN and try again
# If it works without VPN:
# 1. Configure VPN split tunneling (if available)
# 2. Add Supabase to VPN whitelist
# 3. Configure Python to use VPN proxy
```

### Issue 3: **ISP/Network Blocking**
**Symptoms**:
- DNS resolves but connection times out
- Other websites work but Supabase doesn't
- Works on mobile hotspot but not home WiFi

**Solution**:
```powershell
# 1. Try using different DNS:
# Settings → Network → WiFi → Properties
# → DNS servers: 8.8.8.8 (Google) or 1.1.1.1 (Cloudflare)

# 2. Test with mobile hotspot
# If it works on hotspot but not home WiFi, 
# it's your ISP or router blocking Supabase

# 3. Contact ISP if blocked
```

### Issue 4: **Supabase Server Down**
**Symptoms**:
- Was working before, now times out
- All tests fail
- Status page shows issues

**Solution**:
```
Check: https://status.supabase.com/
If red status, wait for Supabase to recover
```

### Issue 5: **Incorrect Supabase URL**
**Symptoms**:
- Different error: connection refused or 404

**Solution**:
Check the URL in `supabase_client.py`:
```python
SUPABASE_URL = "https://umuqhnzqutumhuykuiwc.supabase.co"
```

Should match your Supabase project URL (Dashboard → Settings → API)

---

## Step-by-Step Troubleshooting

### Step 1: Test Basic Internet
```powershell
# This must work first
ping 8.8.8.8
Invoke-WebRequest -Uri "https://www.google.com"
```

If fails → **Network is down or ISP blocking internet**

### Step 2: Test DNS
```powershell
Resolve-DnsName umuqhnzqutumhuykuiwc.supabase.co
```

If fails → **DNS issue, try different DNS servers**

### Step 3: Test Supabase Connection
```powershell
$socket = New-Object Net.Sockets.TcpClient
$socket.Connect("umuqhnzqutumhuykuiwc.supabase.co", 443)
$socket.Connected
```

If False → **Firewall or ISP blocking Supabase**

### Step 4: Check VPN/Proxy
```powershell
# If on VPN, try disconnecting
# Settings → Network → VPN → Disconnect

# Then run diagnostic again:
python test_supabase_connection.py
```

### Step 5: Try Alternative DNS
```powershell
# Temporary change to Cloudflare DNS
# (Settings → Network → WiFi → Properties → DNS servers)
# 1.1.1.1 (primary)
# 1.0.0.1 (secondary)

# Or in PowerShell:
Set-DnsClientServerAddress -InterfaceIndex (Get-NetAdapter | where {$_.Status -eq "up"}).InterfaceIndex -ServerAddresses ("1.1.1.1", "1.0.0.1")

# Then test again
python test_supabase_connection.py
```

---

## Testing with cURL (More Diagnostic)

```powershell
# Install curl if not available
# Then test:
curl -v https://umuqhnzqutumhuykuiwc.supabase.co/health

# Should show SSL handshake and response (403 is OK for this test)
# If timeout, network is blocking
```

---

## Environment Variables for Proxy

If behind corporate proxy:

```powershell
# Set proxy for Python (if needed)
$env:HTTP_PROXY = "http://proxy.company.com:8080"
$env:HTTPS_PROXY = "http://proxy.company.com:8080"

# Then run
python test_supabase_connection.py
```

---

## Check Supabase Status

1. Go to: https://status.supabase.com/
2. Look for "All Systems Operational"
3. If red, Supabase is having issues

---

## Contact ISP/Network Admin if:

- ✓ Internet works (Google, YouTube, etc.)
- ✓ DNS resolves Supabase URL
- ✗ Cannot connect to Supabase port 443
- → ISP or network firewall is blocking Supabase

**Tell them**: Need to whitelist `umuqhnzqutumhuykuiwc.supabase.co` on port 443

---

## Quick Command Reference

```powershell
# Check everything in one script
Write-Host "1. Internet connectivity..."
ping 8.8.8.8

Write-Host "`n2. DNS resolution..."
Resolve-DnsName umuqhnzqutumhuykuiwc.supabase.co

Write-Host "`n3. HTTPS port 443..."
$socket = New-Object Net.Sockets.TcpClient
$socket.Connect("umuqhnzqutumhuykuiwc.supabase.co", 443)
$socket.Connected

Write-Host "`n4. Run diagnostic..."
cd d:\fix\ai_worker
python test_supabase_connection.py
```

---

## After Fixing Connection

Once the diagnostic passes (all ✓), you're ready to:
1. Start AI worker
2. Submit report in Flutter
3. AI results will be saved to Supabase ✓
