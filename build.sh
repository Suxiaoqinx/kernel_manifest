#!/bin/bash
set -e

# ===== 设置自定义参数 =====
read -p "请输入 SoC 分支名称（默认：sm8650）: " SOC_BRANCH
SOC_BRANCH=${SOC_BRANCH:-sm8650}

read -p "请输入 manifest 文件名（默认：oneplus_ace3_pro_v.xml）: " MANIFEST_FILE
MANIFEST_FILE=${MANIFEST_FILE:-oneplus_ace3_pro_v.xml}

read -p "请输入自定义内核后缀（默认：oki-Coolapk@Suxiaoqing）: " CUSTOM_SUFFIX
CUSTOM_SUFFIX=${CUSTOM_SUFFIX:-oki-Coolapk@Suxiaoqing}

read -p "请输入 Bazel 构建目标（默认：pineapple）: " BAZEL_TARGET
BAZEL_TARGET=${BAZEL_TARGET:-pineapple}

read -p "是否使用 patch_linux 工具修补内核？(y/n，默认：y): " USE_PATCH_LINUX
USE_PATCH_LINUX=${USE_PATCH_LINUX:-y}

read -p "是否应用 lz4kd 补丁？(y/n，默认：y): " APPLY_LZ4KD
APPLY_LZ4KD=${APPLY_LZ4KD:-y}

echo "===== 配置信息 ====="
echo "SoC 分支: $SOC_BRANCH"
echo "manifest: $MANIFEST_FILE"
echo "后缀: -$CUSTOM_SUFFIX"
echo "构建目标: $BAZEL_TARGET"
echo "使用 patch_linux: $USE_PATCH_LINUX"
echo "应用 lz4kd 补丁: $APPLY_LZ4KD"
echo "==================="

# ===== 安装依赖 =====
sudo apt-get update
sudo apt-get install -y git curl zip perl make gcc python3

# ===== 安装 repo 工具 =====
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/repo
chmod a+x ~/repo
sudo mv ~/repo /usr/local/bin/repo

# ===== 初始化仓库 =====
repo init -u https://github.com/OnePlusOSS/kernel_manifest.git -b refs/heads/oneplus/${SOC_BRANCH} -m ${MANIFEST_FILE} --depth=1
repo sync -j16 --fail-fast

cd ./kernel_platform

# ===== 清除 abi 文件、去除 -dirty 后缀 =====
rm common/android/abi_gki_protected_exports_* || true
rm msm-kernel/android/abi_gki_protected_exports_* || true

for f in common/scripts/setlocalversion msm-kernel/scripts/setlocalversion external/dtc/scripts/setlocalversion; do
  sed -i 's/ -dirty//g' "$f"
  sed -i '$i res=$(echo "$res" | sed '\''s/-dirty//g'\'')' "$f"
done

# ===== 替换版本后缀 =====
for f in ./common/scripts/setlocalversion ./msm-kernel/scripts/setlocalversion ./external/dtc/scripts/setlocalversion; do
  sed -i "\$s|echo \"\\\$res\"|echo \"-${CUSTOM_SUFFIX}\"|" "$f"
done

# ===== 拉取 KernelSU 并设置版本号 =====
curl -LSs "https://raw.githubusercontent.com/ShirkNeko/SukiSU-Ultra/main/kernel/setup.sh" | bash -s susfs-dev
cd KernelSU
KSU_VERSION=$(expr $(/usr/bin/git rev-list --count main) "+" 10606)
export KSU_VERSION=$KSU_VERSION
sed -i "s/DKSU_VERSION=12800/DKSU_VERSION=${KSU_VERSION}/" kernel/Makefile

# ===== 克隆补丁仓库 =====
cd ../
git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-android14-6.1
git clone https://github.com/Xiaomichael/kernel_patches.git
git clone https://github.com/ShirkNeko/SukiSU_patch.git

# ===== 应用 SUSFS 补丁 =====
cp ./susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch ./common/
cp ./kernel_patches/next/syscall_hooks.patch ./common/
cp ./susfs4ksu/kernel_patches/fs/* ./common/fs/
cp ./susfs4ksu/kernel_patches/include/linux/* ./common/include/linux/
cd ./common
patch -p1 < 50_add_susfs_in_gki-android14-6.1.patch || true
cp ../kernel_patches/69_hide_stuff.patch ./
patch -p1 -F 3 < 69_hide_stuff.patch
patch -p1 -F 3 < syscall_hooks.patch
cd ../

# ===== 选择性应用 LZ4KD 补丁 =====
if [[ "$APPLY_LZ4KD" == "y" || "$APPLY_LZ4KD" == "Y" ]]; then
  echo ">>> 正在应用 lz4kd 补丁..."
  cp -r ./SukiSU_patch/other/zram/lz4k/include/linux/* ./common/include/linux/
  cp -r ./SukiSU_patch/other/zram/lz4k/lib/* ./common/lib
  cp -r ./SukiSU_patch/other/zram/lz4k/crypto/* ./common/crypto
  cp ./SukiSU_patch/other/zram/zram_patch/6.1/lz4kd.patch ./common/
  cd ./common
  patch -p1 -F 3 < lz4kd.patch || true
  cd ../
else
  echo ">>> 跳过 lz4kd 补丁应用"
fi

# ===== 添加 defconfig 配置项 =====
cat >> ./common/arch/arm64/configs/gki_defconfig <<EOF
CONFIG_KSU=y
CONFIG_KPM=y
CONFIG_KSU_SUSFS_SUS_SU=n
CONFIG_KSU_MANUAL_HOOK=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SUS_OVERLAYFS=n
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_ZSMALLOC=y
CONFIG_CRYPTO_LZ4HC=y
CONFIG_CRYPTO_LZ4K=y
CONFIG_CRYPTO_LZ4KD=y
CONFIG_CRYPTO_842=y
EOF

# ===== 禁用 defconfig 检查 =====
sed -i 's/check_defconfig//' ./common/build.config.gki

# ===== 再次替换版本后缀 =====
for f in ./common/scripts/setlocalversion ./msm-kernel/scripts/setlocalversion ./external/dtc/scripts/setlocalversion; do
  sed -i "\$s|echo \"\\\$res\"|echo \"-${CUSTOM_SUFFIX}\"|" "$f"
done

# ===== 编译内核 =====
./build_with_bazel.py -t "$BAZEL_TARGET" gki

# ===== 选择性使用 patch_linux =====
if [[ "$USE_PATCH_LINUX" == "y" || "$USE_PATCH_LINUX" == "Y" ]]; then
  echo ">>> 使用 patch_linux 工具处理输出..."
  cd /out/msm-kernel-${BAZEL_TARGET}-gki/dist
  curl -LO https://github.com/ShirkNeko/SukiSU_KernelPatch_patch/releases/download/0.11-beta/patch_linux
  chmod +x patch_linux
  ./patch_linux
  rm -f Image
  mv oImage Image
else
  echo ">>> 跳过 patch_linux 操作"
fi
