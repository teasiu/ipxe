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

echo "========================================"
echo "🧹 清理旧的构建环境"
echo "========================================"
if [ -d "ipxe" ]; then
    echo "正在删除旧的 ipxe 目录..."
    rm -rf ipxe
fi
if [ -d "ipxe/products" ]; then
    echo "正在删除旧的产物目录..."
    rm -rf ipxe/products
fi
echo "✅ 清理完成"
echo -e "\n"

echo "========================================"
echo "🔍 正在获取 iPXE 最新标签"
echo "========================================"
LATEST_TAG=""
API_URL="https://api.github.com/repos/ipxe/ipxe/tags"
TMP_RESPONSE=$(mktemp)

echo "尝试通过 GitHub API 获取标签列表..."
HTTP_CODE=$(curl -s -w "%{http_code}" -o "$TMP_RESPONSE" "$API_URL")

if [ "$HTTP_CODE" -eq 200 ]; then
    echo "API 调用成功，正在解析最新标签..."
    
    if command -v jq &> /dev/null; then
        LATEST_TAG=$(jq -r '.[0].name' "$TMP_RESPONSE")
    elif command -v python3 &> /dev/null; then
        LATEST_TAG=$(python3 -c "import sys, json; print(json.load(sys.stdin)[0]['name'])" < "$TMP_RESPONSE")
    else
        echo "警告: jq 或 python3 未安装，使用 grep/cut 解析 (可能不稳定)。"
        LATEST_TAG=$(grep -m 1 -o '"name": "[^"]*' "$TMP_RESPONSE" | cut -d '"' -f4)
    fi

    if [ -n "$LATEST_TAG" ] && [ "$LATEST_TAG" != "null" ]; then
        echo "✅ 通过 API 成功获取最新标签: $LATEST_TAG"
    else
        echo "警告: API 调用成功，但未找到有效的标签。将尝试 fallback 方式..."
        LATEST_TAG=""
    fi
else
    echo "警告: API 调用失败 (HTTP 状态码: $HTTP_CODE)。将尝试 fallback 方式..."
fi

if [ -z "$LATEST_TAG" ]; then
    echo "ℹ️  Fallback: 尝试通过克隆仓库获取最新标签..."
    
    echo "正在克隆 iPXE 仓库..."
    git clone --quiet https://github.com/ipxe/ipxe.git || {
        echo "错误：克隆仓库失败"
        exit 1
    }
    
    cd ipxe
    git fetch --tags --quiet
    LATEST_TAG=$(git tag -l --sort=-v:refname | head -n 1)
    cd ..
    echo "✅ 通过 fallback 方式获取最新标签: $LATEST_TAG"
fi

rm -f "$TMP_RESPONSE"

if [ -z "$LATEST_TAG" ]; then
    echo "❌ 错误：无法通过任何方式获取 iPXE 最新标签！"
    exit 1
fi
echo -e "\n"

echo "========================================"
echo "📥 准备代码和编译环境"
echo "========================================"

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

git checkout "$LATEST_TAG" -b "build-$LATEST_TAG" || {
    echo "错误：切换到标签 $LATEST_TAG 失败"
    exit 1
}

echo "当前检出版本："
git describe --tags

echo -e "\n返回初始目录: $ORIGINAL_DIR"
cd "$ORIGINAL_DIR" || {
    echo "错误：无法返回初始目录"
    exit 1
}

echo "当前目录: $(pwd)"
echo -e "\n"

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

echo "========================================"
echo "⚙️  开始配置源码"
echo "========================================"

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

#echo "删除 iPXE 测试代码目录，避免编译错误..."
#TEST_DIR="$ORIGINAL_DIR/ipxe/src/tests"
#if [ -d "$TEST_DIR" ]; then
#    rm -rf "$TEST_DIR"
#    echo "✅ 已删除测试目录：$TEST_DIR"
#else
#    echo "ℹ️  测试目录不存在，跳过删除"
#fi
echo -e "\n"

echo "========================================"
echo "📝 添加启动脚本"
echo "========================================"
SCRIPT_FILE="$ORIGINAL_DIR/ipxe/src/script.ipxe"
cat > "$SCRIPT_FILE" << 'EOF'
#!ipxe
:retry_dhcp
dhcp || goto retry_dhcp
chain --autofree tftp://${next-server}/menu.ipxe
EOF

echo "已创建 $SCRIPT_FILE"
echo -e "\n"

echo "========================================"
echo "🔧 检测 GCC 版本以确定编译选项"
echo "========================================"
if command -v gcc &> /dev/null; then
    GCC_VERSION=$(gcc -dumpversion | cut -d '.' -f1)
    echo "检测到 GCC 主版本号: $GCC_VERSION"
else
    echo "❌ 错误：未找到 GCC 编译器！"
    exit 1
fi

if [ "$GCC_VERSION" -eq 10 ]; then
    echo "GCC 版本为 10.x，应用对应编译选项..."
    
    compile_and_move() {
        local target=$1
        local output_name=${2:-$target}
        echo "编译 $target..."
        if make "bin/$target" EMBED=script.ipxe; then
            mv "bin/$target" "$PRODUCTS_DIR/$output_name"
            echo "✅ $target → $output_name 编译成功"
        else
            echo "❌ $target 编译失败"
            exit 1
        fi
    }

    compile_efi() {
        local arch=$1
        local target=$2
        local output_name=$3
        echo "编译 UEFI-$arch $target..."
        if make "bin-$arch/$target" EMBED=script.ipxe; then
            cp "bin-$arch/$target" "$PRODUCTS_DIR/$output_name"
            echo "✅ UEFI-$arch $target → $output_name 编译成功"
        else
            echo "❌ UEFI-$arch $target 编译失败"
            exit 1
        fi
    }

elif [ "$GCC_VERSION" -gt 10 ]; then
    echo "GCC 版本大于 10 (${GCC_VERSION})，应用兼容编译选项..."
    
    compile_and_move() {
        local target=$1
        local output_name=${2:-$target}
        echo "编译 $target..."
        if make "bin/$target" EMBED=script.ipxe NO_TESTS=1 EXTRA_CFLAGS="-Wno-error=maybe-uninitialized -Wno-error=array-bounds"; then
            mv "bin/$target" "$PRODUCTS_DIR/$output_name"
            echo "✅ $target → $output_name 编译成功"
        else
            echo "❌ $target 编译失败"
            exit 1
        fi
    }

    compile_efi() {
        local arch=$1
        local target=$2
        local output_name=$3
        echo "编译 UEFI-$arch $target..."
        if make "bin-$arch/$target" EMBED=script.ipxe NO_TESTS=1 EXTRA_CFLAGS="-Wno-error=maybe-uninitialized -Wno-error=array-bounds"; then
            cp "bin-$arch/$target" "$PRODUCTS_DIR/$output_name"
            echo "✅ UEFI-$arch $target → $output_name 编译成功"
        else
            echo "❌ UEFI-$arch $target 编译失败"
            exit 1
        fi
    }

else
    echo "GCC 版本小于 10 (${GCC_VERSION})，应用兼容编译选项..."
    
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
fi

echo -e "\n========================================"
echo "🔧 开始编译 Legacy BIOS 镜像"
echo "========================================"
sleep 3

mkdir -p "$ORIGINAL_DIR/ipxe/products"
PRODUCTS_DIR="$ORIGINAL_DIR/ipxe/products"
echo "已创建产品输出目录：$PRODUCTS_DIR"

cd ipxe/src || { echo "错误：无法进入 ipxe/src 目录"; exit 1; }

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
echo -e "\n"

echo "========================================"
echo "🔧 重新配置以编译 UEFI 镜像"
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

echo -e "\n========================================"
echo "🔧 开始编译 EFI 镜像 (x86_64 + i386)"
echo "========================================"
sleep 3

compile_efi "x86_64-efi" "ipxe.efi" "bootx64.efi"
compile_efi "x86_64-efi" "ipxe.usb" "ipxe-efi-x64.usb"
compile_efi "x86_64-efi" "snponly.efi" "snponly-x64.efi"

compile_efi "i386-efi" "ipxe.efi" "bootia32.efi"
compile_efi "i386-efi" "ipxe.usb" "ipxe-efi-x86.usb"
compile_efi "i386-efi" "snponly.efi" "snponly-x86.efi"

cd "$ORIGINAL_DIR" || exit 1
echo -e "\n"

echo "========================================"
echo "🧹 清理和整理"
echo "========================================"
echo "清理产物目录中的重复文件..."
find "$PRODUCTS_DIR" -type f -print0 | sort -z | uniq -dz | xargs -0 -I {} rm -f {}
echo "✅ 重复文件清理完成"
echo -e "\n"

echo "🎉 所有操作完成！"
echo "========================================"
echo "📁 编译产物路径：$PRODUCTS_DIR"
echo "🔖 使用版本：$LATEST_TAG"
echo "💻 支持架构：Legacy BIOS + UEFI (x86_64 + i386)"
echo -e "\n产物列表（按类型分类）："
echo "----------------------------------------"
echo "🔹 Legacy BIOS 镜像："
ls -lh "$PRODUCTS_DIR"/ipxe-bios.* "$PRODUCTS_DIR"/undionly-bios.kpxe 2>/dev/null | awk '{print "  " $9}'
echo -e "\n🔹 UEFI x86_64 (64位) 镜像："
ls -lh "$PRODUCTS_DIR"/bootx64.efi "$PRODUCTS_DIR"/ipxe-efi-x64.* "$PRODUCTS_DIR"/snponly-x64.* 2>/dev/null | awk '{print "  " $9}'
echo -e "\n🔹 UEFI i386 (32位) 镜像："
ls -lh "$PRODUCTS_DIR"/bootia32.efi "$PRODUCTS_DIR"/ipxe-efi-x86.* "$PRODUCTS_DIR"/snponly-x86.* 2>/dev/null | awk '{print "  " $9}'

