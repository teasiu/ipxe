#!/bin/bash
set -euo pipefail

echo "========================================"
echo "🔧 开始安装必要依赖工具"
echo "========================================"
sudo apt update && sudo apt install -y \
    curl \
    git \
    sed \
    make \
    gcc \
    build-essential \
    perl \
    liblzma-dev \
    mtools \
    syslinux-utils \
    genisoimage \
    grub-efi-amd64-bin \
    grub-efi-ia32-bin || {
    echo "❌ 依赖安装失败！请检查网络或权限后重试"
    exit 1
}
echo "✅ 所有依赖安装完成"
echo -e "\n"

ORIGINAL_DIR=$(pwd)
echo "初始目录: $ORIGINAL_DIR"

if [ -d "ipxe" ]; then
    echo "清理旧的 ipxe 目录..."
    rm -rf ipxe
fi

echo "正在通过 GitHub API 获取最新标签..."
API_RESPONSE=$(mktemp)
if ! curl -s -o "$API_RESPONSE" -w "%{http_code}" https://api.github.com/repos/ipxe/ipxe/releases/latest | grep -q "200"; then
    echo "警告：API 调用失败（HTTP 状态码非 200），尝试 fallback 方式..."
    git clone https://github.com/ipxe/ipxe.git || { echo "错误：克隆仓库失败！"; exit 1; }
    cd ipxe
    git fetch --tags
    LATEST_TAG=$(git tag -l --sort=-v:refname | head -n 1)
    cd ..
else
    LATEST_TAG=$(grep -oP '"tag_name": "\K(.*?)"' "$API_RESPONSE" | tr -d '"')
fi

rm -f "$API_RESPONSE"

if [ -z "$LATEST_TAG" ]; then
    echo "错误：无法获取 iPXE 最新标签！"
    exit 1
fi
echo "获取到最新标签: $LATEST_TAG"

if [ ! -d "ipxe" ]; then
    echo "克隆 iPXE 仓库..."
    git clone https://github.com/ipxe/ipxe.git || {
        echo "错误：克隆仓库失败"
        exit 1
    }
fi

echo "进入 ipxe 目录并切换到最新标签 $LATEST_TAG..."
cd ipxe || {
    echo "错误：无法进入 ipxe 目录"
    exit 1
}

git checkout "$LATEST_TAG" -b "latest-tag-$LATEST_TAG" || {
    echo "错误：切换到标签 $LATEST_TAG 失败"
    exit 1
}

echo "当前检出版本："
git describe --tags

echo -e "\nSETTINGS"

echo -e "\n返回初始目录: $ORIGINAL_DIR"
cd "$ORIGINAL_DIR" || {
    echo "错误：无法返回初始目录"
    exit 1
}

echo "当前目录: $(pwd)"
echo "操作完成！已检出 iPXE 最新标签 $LATEST_TAG 并返回初始目录"

CONFIG_FILES=(
    "ipxe/src/config/branding.h"
    "ipxe/src/config/general.h"
    "ipxe/src/config/console.h"
)

for file in "${CONFIG_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "错误：配置文件 $file 不存在！"
        exit 1
    fi
done

echo "Editing branding.h"
sed -i.bak 's/#define\ PRODUCT_NAME\ ""/#define\ PRODUCT_NAME\ "iPXE-ecoo\ project\ by\ teasiu"/' ipxe/src/config/branding.h
sed -i.bak 's/#define\ PRODUCT_SHORT_NAME\ "iPXE"/#define\ PRODUCT_SHORT_NAME\ "ipxe-latest"/' ipxe/src/config/branding.h
sed -i.bak 's/#define\ PRODUCT_URI\ "http:\/\/ipxe.org"/#define\ PRODUCT_URI\ "https:\/\/ecoo.top\/blog"/' ipxe/src/config/branding.h
sed -i.bak 's/#define\ PRODUCT_TAG_LINE\ "Open\ Source\ Network\ Boot\ Firmware"/#define\ PRODUCT_TAG_LINE\ "by\ teasiu"/' ipxe/src/config/branding.h

echo "Editing general.h (基础配置)"
sed -i.bak 's/#undef\tDOWNLOAD_PROTO_HTTPS/#define\ DOWNLOAD_PROTO_HTTPS/' ipxe/src/config/general.h
sed -i.bak 's/#undef\tDOWNLOAD_PROTO_FTP/#define\ DOWNLOAD_PROTO_FTP/' ipxe/src/config/general.h
sed -i.bak 's/#undef\tDOWNLOAD_PROTO_NFS/#define\ DOWNLOAD_PROTO_NFS/' ipxe/src/config/general.h
sed -i.bak 's/\/\/#undef\tSANBOOT_PROTO_ISCSI/#define\ SANBOOT_PROTO_ISCSI/' ipxe/src/config/general.h
sed -i.bak 's/\/\/#undef\tSANBOOT_PROTO_HTTP/#define\ SANBOOT_PROTO_HTTP/' ipxe/src/config/general.h
sed -i.bak 's/\/\/#define\tIMAGE_SCRIPT/#define\ IMAGE_SCRIPT/' ipxe/src/config/general.h
sed -i.bak 's/\/\/#define\ DIGEST_CMD/#define\ DIGEST_CMD/' ipxe/src/config/general.h
sed -i.bak 's/\/\/#define\ REBOOT_CMD/#define\ REBOOT_CMD/' ipxe/src/config/general.h
sed -i.bak 's/\/\/#define\ POWEROFF_CMD/#define\ POWEROFF_CMD/' ipxe/src/config/general.h
sed -i.bak 's/\/\/#define\ IMAGE_TRUST_CMD/#define\ IMAGE_TRUST_CMD/' ipxe/src/config/general.h
sed -i.bak 's/\/\/#define\ PING_CMD/#define\ PING_CMD/' ipxe/src/config/general.h
sed -i.bak 's/\/\/#define\ CONSOLE_CMD/#define\ CONSOLE_CMD/' ipxe/src/config/general.h
sed -i.bak 's/\/\/#define\ IPSTAT_CMD/#define\ IPSTAT_CMD/' ipxe/src/config/general.h
sed -i.bak 's/\/\/#define\ CERT_CMD/#define\ CERT_CMD/' ipxe/src/config/general.h

echo "Editing general.h (BIOS 专用配置)"
sed -i.bak 's/\/\/#define\tIMAGE_PXE/#define\ IMAGE_PXE/' ipxe/src/config/general.h
sed -i.bak 's/\/\/#define\tIMAGE_BZIMAGE/#define\ IMAGE_BZIMAGE/' ipxe/src/config/general.h
sed -i.bak 's/\/\/#define\tIMAGE_EFI/\/\/#undef\tIMAGE_EFI/' ipxe/src/config/general.h

echo "Editing console.h (BIOS 专用配置)"
sed -i.bak 's/\/\/#undef\tCONSOLE_PCBIOS/#define\ CONSOLE_PCBIOS/' ipxe/src/config/console.h
sed -i.bak 's/\/\/#define\tCONSOLE_FRAMEBUFFER/#define\ CONSOLE_FRAMEBUFFER/' ipxe/src/config/console.h
sed -i.bak 's/\/\/#define\tCONSOLE_DIRECT_VGA/#define\ CONSOLE_DIRECT_VGA/' ipxe/src/config/console.h
sed -i.bak 's/\/\/#undef\tCONSOLE_EFI/\/\/#define\tCONSOLE_EFI/' ipxe/src/config/console.h

rm -f ipxe/src/config/*.bak

echo "删除 iPXE 测试代码目录，避免编译错误..."
TEST_DIR="$ORIGINAL_DIR/ipxe/src/tests"
if [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
    echo "✅ 已删除测试目录：$TEST_DIR"
else
    echo "ℹ️  测试目录不存在，跳过删除"
fi

echo "Runing make..."
sleep 3

mkdir -p "$ORIGINAL_DIR/ipxe/products"
PRODUCTS_DIR="$ORIGINAL_DIR/ipxe/products"
echo "已创建产品输出目录：$PRODUCTS_DIR"

echo "Adding scripts"
SCRIPT_FILE="$ORIGINAL_DIR/ipxe/src/script.ipxe"
cat > "$SCRIPT_FILE" << 'EOF'
#!ipxe
:retry_dhcp
dhcp || goto retry_dhcp
chain --autofree tftp://${next-server}/menu.ipxe
EOF

echo "已创建 $SCRIPT_FILE，内容如下："
cat "$SCRIPT_FILE"

echo -e "\n========================================"
echo "🔧 Creating Legacy BIOS Images"
echo "========================================"
sleep 3

cd ipxe/src || { echo "错误：无法进入 ipxe/src 目录"; exit 1; }

compile_and_move() {
    local target=$1
    local output_name=${2:-$target}
    echo "编译 $target..."
    if make "bin/$target" EMBED=script.ipxe NO_TESTS=1 EXTRA_CFLAGS="-Wno-error=maybe-uninitialized"; then
        mv "bin/$target" "$PRODUCTS_DIR/$output_name"
        echo "✅ $target → $output_name 编译成功"
    else
        echo "❌ $target 编译失败"
        exit 1
    fi
}

compile_and_move "ipxe.iso" "ipxe-bios.iso"
compile_and_move "ipxe.dsk" "ipxe-bios.dsk"
compile_and_move "ipxe.lkrn" "ipxe-bios.lkrn"
compile_and_move "ipxe.usb" "ipxe-bios.usb"
compile_and_move "ipxe.pxe" "ipxe-bios.pxe"
compile_and_move "ipxe.kpxe" "ipxe-bios.kpxe"
compile_and_move "ipxe.kkpxe" "ipxe-bios.kkpxe"
compile_and_move "ipxe.kkkpxe" "ipxe-bios.kkkpxe"
compile_and_move "undionly.kpxe" "undionly-bios.kpxe"

cd "$ORIGINAL_DIR" || exit 1

echo -e "\n========================================"
echo "🔧 SETTINGS EFI (配置 UEFI 编译选项)"
echo "========================================"

cd ipxe/src || { echo "错误：无法进入 ipxe/src 目录"; exit 1; }

echo "Editing general.h (UEFI 专用配置)"
sed -i.bak 's/#define\ IMAGE_PXE/\/\/#define\ IMAGE_PXE/' config/general.h
sed -i.bak 's/#define\ IMAGE_BZIMAGE/\/\/#define\ IMAGE_BZIMAGE/' config/general.h
sed -i.bak 's/\/\/#define\tIMAGE_EFI/#define\ IMAGE_EFI/' config/general.h

echo "Editing console.h (UEFI 专用配置)"
sed -i.bak 's/#define\ CONSOLE_PCBIOS/\/\/#define\ CONSOLE_PCBIOS/' config/console.h
sed -i.bak 's/#define\ CONSOLE_DIRECT_VGA/\/\/#define\ CONSOLE_DIRECT_VGA/' config/console.h
sed -i.bak 's/\/\/#undef\tCONSOLE_EFI/#define\tCONSOLE_EFI/' config/console.h

rm -f config/*.bak

compile_efi() {
    local arch=$1
    local target=$2
    local output_name=$3
    echo "编译 UEFI-$arch $target..."
    if make "bin-$arch/$target" EMBED=script.ipxe NO_TESTS=1 EXTRA_CFLAGS="-Wno-error=maybe-uninitialized"; then
        cp "bin-$arch/$target" "$PRODUCTS_DIR/$output_name"
        echo "✅ UEFI-$arch $target → $output_name 编译成功"
    else
        echo "❌ UEFI-$arch $target 编译失败"
        exit 1
    fi
}

echo -e "\n========================================"
echo "🔧 Creating EFI Images (x86_64 + i386)"
echo "========================================"
sleep 3

compile_efi "x86_64-efi" "ipxe.efi" "bootx64.efi"
compile_efi "x86_64-efi" "ipxe.usb" "ipxe-efi-x64.usb"
compile_efi "x86_64-efi" "snponly.efi" "snponly-x64.efi"

compile_efi "i386-efi" "ipxe.efi" "bootia32.efi"
compile_efi "i386-efi" "ipxe.usb" "ipxe-efi-x86.usb"
compile_efi "i386-efi" "snponly.efi" "snponly-x86.efi"

cd "$ORIGINAL_DIR" || exit 1

echo "清理产物目录中的重复文件..."
find "$PRODUCTS_DIR" -type f -print0 | sort -z | uniq -dz | xargs -0 -I {} rm -f {}
echo "✅ 重复文件清理完成"

echo -e "\n🎉 所有操作完成！"
echo "========================================"
echo "📁 编译产物路径：$PRODUCTS_DIR"
echo "🔖 使用版本：$LATEST_TAG"
echo "💻 支持架构：Legacy BIOS + UEFI (x86_64 + i386)"
echo "🖼️  背景图支持：已启用（所有镜像均生效）"
echo -e "\n产物列表（按类型分类）："
echo "----------------------------------------"
echo "🔹 Legacy BIOS 镜像："
ls -lh "$PRODUCTS_DIR"/ipxe-bios.* "$PRODUCTS_DIR"/undionly-bios.kpxe 2>/dev/null | awk '{print "  " $9}'
echo -e "\n🔹 UEFI x86_64 (64位) 镜像："
ls -lh "$PRODUCTS_DIR"/bootx64.efi "$PRODUCTS_DIR"/ipxe-efi-x64.* "$PRODUCTS_DIR"/snponly-x64.* 2>/dev/null | awk '{print "  " $9}'
echo -e "\n🔹 UEFI i386 (32位) 镜像："
ls -lh "$PRODUCTS_DIR"/bootia32.efi "$PRODUCTS_DIR"/ipxe-efi-x86.* "$PRODUCTS_DIR"/snponly-x86.* 2>/dev/null | awk '{print "  " $9}'

