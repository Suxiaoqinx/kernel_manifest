#!/bin/bash
set -e

export CONFIG="gtneo6"
export ANYKERNEL_BRANCH="android14-6.1"
export SUSFS_BRANCH="gki-android14-6.1"
export SUSFS_VERSION="v1.5.5"

sudo apt-get update
sudo apt-get install -y git curl zip perl make gcc python3

mkdir -p ./git-repo
curl -o ./git-repo/repo https://storage.googleapis.com/git-repo-downloads/repo
chmod a+x ./git-repo/repo

mkdir -p "$CONFIG"
cd "$CONFIG"
./git-repo/repo init -u https://github.com/Suxiaoqinx/kernel_manifest.git \
    -b realme/sm8650 -m ${CONFIG}.xml --depth=1
./git-repo/repo sync -c -j$(nproc --all) --no-tags --fail-fast

cd kernel_platform
rm common/android/abi_gki_protected_exports_* || echo "No protected exports!"
rm msm-kernel/android/abi_gki_protected_exports_* || echo "No protected exports!"
sed -i 's/ -dirty//g' ./common/scripts/setlocalversion
sed -i 's/ -dirty//g' ./msm-kernel/scripts/setlocalversion
sed -i 's/ -dirty//g' ./external/dtc/scripts/setlocalversion
sed -i '$i res=$(echo "$res" | sed '\''s/-dirty//g'\'')' ./common/scripts/setlocalversion
sed -i '$i res=$(echo "$res" | sed '\''s/-dirty//g'\'')' ./msm-kernel/scripts/setlocalversion
sed -i '$i res=$(echo "$res" | sed '\''s/-dirty//g'\'')' ./external/dtc/scripts/setlocalversion
sed -i '$s|echo "\$res"|echo "\-oki-Coolapk@Suxiaoqing"|' ./common/scripts/setlocalversion   
sed -i '$s|echo "\$res"|echo "\-oki-Coolapk@Suxiaoqing"|' ./msm-kernel/scripts/setlocalversion
sed -i '$s|echo "\$res"|echo "\-oki-Coolapk@Suxiaoqing"|' ./external/dtc/scripts/setlocalversion

curl -LSs "https://raw.githubusercontent.com/ShirkNeko/SukiSU-Ultra/main/kernel/setup.sh" | bash -s susfs-dev
cd KernelSU
KSU_VERSION=$(expr $(/usr/bin/git rev-list --count main) "+" 10606)
echo "KSUVER=$KSU_VERSION" >> GITHUB_ENV
export KSU_VERSION=$KSU_VERSION
sed -i "s/DKSU_VERSION=12800/DKSU_VERSION=${KSU_VERSION}/" kernel/Makefile

cd ../../
git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-android14-6.1
git clone https://github.com/Xiaomichael/kernel_patches.git
git clone https://github.com/ShirkNeko/SukiSU_patch.git

cd ./kernel_platform
cp ../susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch ./common/
cp ../kernel_patches/next/syscall_hooks.patch ./common/
cp ../susfs4ksu/kernel_patches/fs/* ./common/fs/
cp ../susfs4ksu/kernel_patches/include/linux/* ./common/include/linux/
cp -r ../SukiSU_patch/other/zram/lz4k/include/linux/* ./common/include/linux
cp -r ../SukiSU_patch/other/zram/lz4k/lib/* ./common/lib
cp -r ../SukiSU_patch/other/zram/lz4k/crypto/* ./common/crypto

cd ./common
patch -p1 < 50_add_susfs_in_gki-android14-6.1.patch || true
cp ../../kernel_patches/69_hide_stuff.patch ./
patch -p1 -F 3 < 69_hide_stuff.patch
patch -p1 -F 3 < syscall_hooks.patch
cp ../../SukiSU_patch/other/zram/zram_patch/6.1/lz4kd.patch ./
patch -p1 -F 3 < lz4kd.patch || true

echo "CONFIG_KSU=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KPM=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SUS_SU=n" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_MANUAL_HOOK=y" >> ./common/arch/arm64/configs/gki_defconfig      
echo "CONFIG_KSU_SUSFS=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SUS_PATH=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SUS_MOUNT=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SUS_KSTAT=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SUS_OVERLAYFS=n" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_TRY_UMOUNT=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SPOOF_UNAME=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_ENABLE_LOG=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_OPEN_REDIRECT=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_ZSMALLOC=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_CRYPTO_LZ4HC=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_CRYPTO_LZ4K=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_CRYPTO_LZ4KD=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_CRYPTO_842=y" >> ./common/arch/arm64/configs/gki_defconfig
sed -i 's/check_defconfig//' ./common/build.config.gki

sed -i '$s|echo "\$res"|echo "\-oki-Coolapk@Suxiaoqing"|' ./common/scripts/setlocalversion  
sed -i '$s|echo "\$res"|echo "\-oki-Coolapk@Suxiaoqing"|' ./msm-kernel/scripts/setlocalversion
sed -i '$s|echo "\$res"|echo "\-oki-Coolapk@Suxiaoqing"|' ./external/dtc/scripts/setlocalversion

cd ../../
./oplus/build/oplus_build_kernel.sh pineapple gki

cd kernel_workspace/kernel_platform/out/msm-kernel-pineapple-gki/dist
curl -LO https://github.com/ShirkNeko/SukiSU_KernelPatch_patch/releases/download/0.11-beta/patch_linux
chmod +x patch_linux
./patch_linux
rm -f Image
mv oImage Image
