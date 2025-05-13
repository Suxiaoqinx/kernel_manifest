#!/bin/bash
set -e

echo "=== 更新 APT 并安装依赖包 ==="
sudo apt-get update
sudo apt-get install -y git curl zip perl make gcc python3

echo "=== 安装 repo 工具 ==="
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/repo
chmod a+x ~/repo
sudo mv ~/repo /usr/local/bin/repo

echo "=== 初始化 OnePlus 内核仓库 ==="
repo init -u https://github.com/OnePlusOSS/kernel_manifest.git -b refs/heads/oneplus/sm8650 -m oneplus_ace3_pro_v.xml --depth=1

echo "=== 同步源码（可能需要较长时间） ==="
repo sync -j16 --fail-fast

echo "=== 准备进入 kernel_platform 并处理 setlocalversion 脚本 ==="
cd ./kernel_platform

echo "=== 移除 abi protected exports 文件（如果存在） ==="
rm common/android/abi_gki_protected_exports_* || echo "No protected exports!"
rm msm-kernel/android/abi_gki_protected_exports_* || echo "No protected exports!"

echo "=== 清除 setlocalversion 中的 -dirty 标记，并替换版本标记信息 ==="
for f in common/scripts/setlocalversion msm-kernel/scripts/setlocalversion external/dtc/scripts/setlocalversion; do
  sed -i 's/ -dirty//g' "$f"
  sed -i '$i res=$(echo "$res" | sed '\''s/-dirty//g'\'')' "$f"
  sed -i '$s|echo "\$res"|echo "\-oki-Coolapk@Suxiaoqing"|' "$f"
done

echo "=== 下载并执行 SukiSU 的 setup.sh 脚本（安装 susfs） ==="
curl -LSs "https://raw.githubusercontent.com/ShirkNeko/SukiSU-Ultra/main/kernel/setup.sh" | bash -s susfs-dev

echo "=== 获取 KernelSU 版本号并修改 Makefile ==="
cd KernelSU
KSU_VERSION=$(expr $(/usr/bin/git rev-list --count main) "+" 10606)
export KSU_VERSION=$KSU_VERSION
sed -i "s/DKSU_VERSION=12800/DKSU_VERSION=${KSU_VERSION}/" kernel/Makefile
cd ../

echo "=== 克隆 SukiSU 补丁与 SUSFS 补丁仓库 ==="
git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-android14-6.1
git clone https://github.com/Xiaomichael/kernel_patches.git
git clone https://github.com/ShirkNeko/SukiSU_patch.git

echo "=== 拷贝补丁与源文件 ==="
cp ./susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch ./common/
cp ./kernel_patches/next/syscall_hooks.patch ./common/
cp ./susfs4ksu/kernel_patches/fs/* ./common/fs/
cp ./susfs4ksu/kernel_patches/include/linux/* ./common/include/linux/
cp -r ./SukiSU_patch/other/zram/lz4k/include/linux/* ./common/include/linux
cp -r ./SukiSU_patch/other/zram/lz4k/lib/* ./common/lib
cp -r ./SukiSU_patch/other/zram/lz4k/crypto/* ./common/crypto

echo "=== 应用补丁文件 ==="
cd ./common
patch -p1 < 50_add_susfs_in_gki-android14-6.1.patch || true
cp .././kernel_patches/69_hide_stuff.patch ./
patch -p1 -F 3 < 69_hide_stuff.patch
patch -p1 -F 3 < syscall_hooks.patch
cp .././SukiSU_patch/other/zram/zram_patch/6.1/lz4kd.patch ./
patch -p1 -F 3 < lz4kd.patch || true
cd ../

echo "=== 向 defconfig 添加内核配置项 ==="
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

echo "=== 跳过 defconfig 检查 ==="
sed -i 's/check_defconfig//' ./common/build.config.gki

echo "=== 最终修复版本信息 ==="
for f in ./common/scripts/setlocalversion ./msm-kernel/scripts/setlocalversion ./external/dtc/scripts/setlocalversion; do
  sed -i '$s|echo "\$res"|echo "\-oki-Coolapk@Suxiaoqing"|' "$f"
done

echo "=== 使用 Bazel 开始构建 GKI 内核（目标 pineapple） ==="
./build_with_bazel.py -t pineapple gki

echo "=== 执行 patch_linux 处理输出文件 ==="
cd /out/msm-kernel-pineapple-gki/dist
curl -LO https://github.com/ShirkNeko/SukiSU_KernelPatch_patch/releases/download/0.11-beta/patch_linux
chmod +x patch_linux
./patch_linux
rm -f Image
mv oImage Image

echo "=== 内核构建与补丁处理完成 ✅ ==="
