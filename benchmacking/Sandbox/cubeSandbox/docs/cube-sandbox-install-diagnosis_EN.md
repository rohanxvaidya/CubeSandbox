# Cube Sandbox Installation Hang Diagnosis Report

## Environment Information
- **installation path**: `/home/mz/cube-sandbox-one-click-v0.4.0`, unzip the installation package in this folder. 
- **Script**: `online-install.sh`. In the unzip package folder, or in the cubesandbox source code path: `deploy/one-click/`
- **Configuration Parameters**:
  - `CUBE_PVM_ENABLE=1`
  - `MIRROR=cn`
  - `http_proxy=http://proxy.ims.intel.com:911`
  - `https_proxy=http://proxy.ims.intel.com:911`

## Diagnostic Results

### ✅ Verified Normal
1. **Proxy Connectivity**: Proxy connection is working normally ✓
2. **China Mirror Connectivity**: `latest.json` can be retrieved successfully ✓
3. **Disk Space**: `/data/cubelet` has **303GB of free space** ✓
4. **System Memory**: 754GB total memory, 701GB available ✓
5. **CPU Load**: 2.36 load average (within the normal range) ✓

### ⚠️ Potential Causes of the Hang

#### **1. curl/wget Is Not Following Redirects (Most Likely Cause)**
- **Issue**: The download URL returns a 302 redirect
- **Current Behavior**: The script uses `curl -fSL` or `wget -q`
- **Fix**: Add the `-L` option to follow redirects
- **Impact**: The download may fail or return an HTML error page instead of the actual package

#### **2. Slow Network Speed Causing Download Timeout**
- File size: **Approximately 2GB** (`cube-sandbox-one-click-v0.4.0.tar.gz`)
- If the network connection is unstable, downloading a large file may take a long time

#### **3. Pre-check Stage Hanging**
The initial checks performed by the script include:
- OS and glibc version validation
- KVM support check (`/dev/kvm`)
- XFS filesystem validation
- cgroup v2 check
- Memory check (≥8GB)

If the script hangs at one of these checks, it may be necessary to skip it.

## Recommended Solutions

### Solution 1: Skip Pre-checks and Re-run (Quick Fix)
```bash
cd /home/mz/cube-sandbox-one-click-v0.4.0
sudo -E bash -c 'http_proxy=http://proxy.ims.intel.com:911 https_proxy=http://proxy.ims.intel.com:911 CUBE_PVM_ENABLE=1 MIRROR=cn ONE_CLICK_SKIP_PRECHECK=1 bash online-install.sh'
```

### Solution 2: Use wget and Increase Timeout
```bash
cd /home/mz/cube-sandbox-one-click-v0.4.0
sudo -E bash -c 'http_proxy=http://proxy.ims.intel.com:911 https_proxy=http://proxy.ims.intel.com:911 CUBE_PVM_ENABLE=1 MIRROR=cn bash online-install.sh --skip-precheck'
```

### Solution 3: Manual Download + Local Installation
```bash
# 1. Manually download the package from a location with proxy access
curl -x http://proxy.ims.intel.com:911 -L \
  "https://cnb.cool/CubeSandbox/CubeSandbox/-/releases/download/v0.4.0/cube-sandbox-one-click-v0.4.0.tar.gz" \
  -o /tmp/cube-sandbox-one-click-v0.4.0.tar.gz

# 2. Verify file integrity
file /tmp/cube-sandbox-one-click-v0.4.0.tar.gz
tar -tzf /tmp/cube-sandbox-one-click-v0.4.0.tar.gz | head

# 3. Run installation using the local file
cd /home/mz/cube-sandbox-one-click-v0.4.0
sudo -E bash -c 'CUBE_PVM_ENABLE=1 bash online-install.sh --url=file:///tmp/cube-sandbox-one-click-v0.4.0.tar.gz'
```

## Troubleshooting Steps

### 1. Check the Current Installation Progress
```bash
# Check whether any installation-related processes are running
ps aux | grep -i install

# Inspect the temporary directory
ls -lah /tmp/ | grep cube

# Review installation logs, if available
find /var/log -name "*cube*" -o -name "*sandbox*" 2>/dev/null
```

### 2. Force Terminate the Stalled Process
```bash
# Identify the hung process PID
ps aux | grep "online-install\|bash.*online"

# Terminate the process
sudo kill -9 <PID>

# Clean up temporary files
sudo rm -rf /tmp/tmp.*  # Clear temporary directories
```

### 3. Re-check Network Connectivity
```bash
# Test the proxy connection
timeout 10 curl -v -x http://proxy.ims.intel.com:911 https://api.github.com

# Test the China mirror
timeout 10 curl -I https://download.cubesandbox.com/release/latest.json

# Test download speed
timeout 30 curl -x http://proxy.ims.intel.com:911 -w "@curl-format.txt" -o /dev/null \
  "https://cnb.cool/CubeSandbox/CubeSandbox/-/releases/download/v0.4.0/cube-sandbox-one-click-v0.4.0.tar.gz"
```

## Recommended Core Fix

Edit `online-install.sh` and modify the download command as follows:

**Original Code** (Lines 375-382):
```bash
if command -v curl >/dev/null 2>&1; then
  curl -fSL "${DOWNLOAD_URL}" -o "${WORK_DIR}/bundle.tar.gz"
elif command -v wget >/dev/null 2>&1; then
  wget -q "${DOWNLOAD_URL}" -O "${WORK_DIR}/bundle.tar.gz"
```

**Fixed Code**:
```bash
if command -v curl >/dev/null 2>&1; then
  curl -fSL -L "${DOWNLOAD_URL}" -o "${WORK_DIR}/bundle.tar.gz"  # Add -L
elif command -v wget >/dev/null 2>&1; then
  wget -q -L "${DOWNLOAD_URL}" -O "${WORK_DIR}/bundle.tar.gz"    # Add -L
```

## Fastest Resolution

**Execute Immediately**:
```bash
cd /home/mz/cube-sandbox-one-click-v0.4.0
sudo killall -9 bash curl wget 2>/dev/null || true
sudo -E bash -c 'http_proxy=http://proxy.ims.intel.com:911 https_proxy=http://proxy.ims.intel.com:911 CUBE_PVM_ENABLE=1 MIRROR=cn bash online-install.sh --skip-precheck'
```

---

If the installation stalls at any point, press `Ctrl+C` to stop it and then try the solutions above.
