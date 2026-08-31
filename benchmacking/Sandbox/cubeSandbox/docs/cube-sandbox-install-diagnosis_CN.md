# Cube Sandbox 安装卡住问题诊断报告

## 环境信息
- **安装路径**: `/home/mz/cube-sandbox-one-click-v0.4.0`, unzip the installation package in this folder. 
- **脚本**: `online-install.sh`. In the unzip package folder, or in the cubesandbox source code path: `deploy/one-click/`
- **配置参数**:
  - `CUBE_PVM_ENABLE=1`
  - `MIRROR=cn`
  - `http_proxy=http://proxy.ims.intel.com:911`
  - `https_proxy=http://proxy.ims.intel.com:911`

## 诊断结果

### ✅ 已验证正常
1. **网络代理**: 代理连接正常 ✓
2. **中国镜像连接**: 可以获取 `latest.json` ✓
3. **磁盘空间**: `/data/cubelet` 有 **303GB 可用空间** ✓
4. **系统内存**: 754GB 总内存，701GB 可用 ✓
5. **CPU 负载**: 2.36 load average（正常范围）✓

### ⚠️ 可能导致卡住的原因

#### **1. curl/wget 没有跟随重定向（最可能）**
- **问题**: 下载 URL 返回 302 重定向
- **当前**: 脚本使用 `curl -fSL` 或 `wget -q`
- **解决**: 需要添加 `-L` 选项跟随重定向
- **影响**: 下载文件会失败或返回 HTML 错误页面

#### **2. 网络速度慢导致下载超时**
- 文件大小: **约 2GB** (`cube-sandbox-one-click-v0.4.0.tar.gz`)
- 如果网络连接不稳定，大文件下载可能需要很长时间

#### **3. 前置检查卡住**
脚本执行的初始检查包括:
- OS 和 glibc 版本检查
- KVM 支持检查（`/dev/kvm`）
- XFS 文件系统检查
- cgroup v2 检查
- 内存检查（≥8GB）

如果卡在某个检查上，可能需要跳过它。

## 建议的解决方案

### 方案 1: 跳过预检查并重新运行（快速修复）
```bash
cd /home/mz/cube-sandbox-one-click-v0.4.0
sudo -E bash -c 'http_proxy=http://proxy.ims.intel.com:911 https_proxy=http://proxy.ims.intel.com:911 CUBE_PVM_ENABLE=1 MIRROR=cn ONE_CLICK_SKIP_PRECHECK=1 bash online-install.sh'
```

### 方案 2: 使用 wget 并增加超时时间
```bash
cd /home/mz/cube-sandbox-one-click-v0.4.0
sudo -E bash -c 'http_proxy=http://proxy.ims.intel.com:911 https_proxy=http://proxy.ims.intel.com:911 CUBE_PVM_ENABLE=1 MIRROR=cn bash online-install.sh --skip-precheck'
```

### 方案 3: 手动下载 + 本地安装
```bash
# 1. 在代理可用的地方手动下载文件
curl -x http://proxy.ims.intel.com:911 -L \
  "https://cnb.cool/CubeSandbox/CubeSandbox/-/releases/download/v0.4.0/cube-sandbox-one-click-v0.4.0.tar.gz" \
  -o /tmp/cube-sandbox-one-click-v0.4.0.tar.gz

# 2. 检查文件完整性
file /tmp/cube-sandbox-one-click-v0.4.0.tar.gz
tar -tzf /tmp/cube-sandbox-one-click-v0.4.0.tar.gz | head

# 3. 使用本地文件运行安装
cd /home/mz/cube-sandbox-one-click-v0.4.0
sudo -E bash -c 'CUBE_PVM_ENABLE=1 bash online-install.sh --url=file:///tmp/cube-sandbox-one-click-v0.4.0.tar.gz'
```

## 排查步骤

### 1. 查看当前安装进度
```bash
# 检查是否有运行中的进程
ps aux | grep -i install

# 查看临时目录
ls -lah /tmp/ | grep cube

# 查看安装日志（如果有）
find /var/log -name "*cube*" -o -name "*sandbox*" 2>/dev/null
```

### 2. 强制终止卡住的进程
```bash
# 找到卡住的进程 PID
ps aux | grep "online-install\|bash.*online"

# 杀死进程
sudo kill -9 <PID>

# 清理临时文件
sudo rm -rf /tmp/tmp.*  # 清理临时目录
```

### 3. 重新诊断网络
```bash
# 测试代理连接
timeout 10 curl -v -x http://proxy.ims.intel.com:911 https://api.github.com

# 测试 CN 镜像
timeout 10 curl -I https://download.cubesandbox.com/release/latest.json

# 测试文件下载速度
timeout 30 curl -x http://proxy.ims.intel.com:911 -w "@curl-format.txt" -o /dev/null \
  "https://cnb.cool/CubeSandbox/CubeSandbox/-/releases/download/v0.4.0/cube-sandbox-one-click-v0.4.0.tar.gz"
```

## 核心问题修复建议

编辑 `online-install.sh`，修改下载命令：

**原始代码** (第 375-382 行):
```bash
if command -v curl >/dev/null 2>&1; then
  curl -fSL "${DOWNLOAD_URL}" -o "${WORK_DIR}/bundle.tar.gz"
elif command -v wget >/dev/null 2>&1; then
  wget -q "${DOWNLOAD_URL}" -O "${WORK_DIR}/bundle.tar.gz"
```

**修复后的代码**:
```bash
if command -v curl >/dev/null 2>&1; then
  curl -fSL -L "${DOWNLOAD_URL}" -o "${WORK_DIR}/bundle.tar.gz"  # 添加 -L
elif command -v wget >/dev/null 2>&1; then
  wget -q -L "${DOWNLOAD_URL}" -O "${WORK_DIR}/bundle.tar.gz"    # 添加 -L
```

## 最快解决方案

**立即执行**:
```bash
cd /home/mz/cube-sandbox-one-click-v0.4.0
sudo killall -9 bash curl wget 2>/dev/null || true
sudo -E bash -c 'http_proxy=http://proxy.ims.intel.com:911 https_proxy=http://proxy.ims.intel.com:911 CUBE_PVM_ENABLE=1 MIRROR=cn bash online-install.sh --skip-precheck'
```

---

如有任何卡住，按 `Ctrl+C` 停止，然后尝试上述解决方案。
