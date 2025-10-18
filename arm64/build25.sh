#!/bin/bash
set -e
echo "🔧 开始处理设备固件..."
REPO_SETTINGS="${REPO_SETTINGS}"
NETWORK_SETTINGS="${NETWORK_SETTINGS}"
OUTPUT_DIR="${PACKAGED_OUTPUTPATH:-out}"

# 通用分区处理函数
process_partition() {
    local FILE="$1"
    local PART_NUM="$2"
    local PROCESS_TYPE="$3"
    echo "🎯 执行$PROCESS_TYPE配置处理..."
    LOOP_DEV=$(sudo losetup --find --show "$FILE")
    echo "📌 创建loop设备: $LOOP_DEV"
    sudo partprobe "$LOOP_DEV"
    # 动态获取分区设备
    PARTITION="${LOOP_DEV}p$PART_NUM"
    [ ! -e "$PARTITION" ] && PARTITION="${LOOP_DEV}$PART_NUM"
    if [ ! -e "$PARTITION" ]; then
        echo "⚠️ 无法找到分区${PART_NUM}设备，跳过配置"
        sudo losetup -d "$LOOP_DEV"
        return 1
    fi
    MOUNT_DIR=$(mktemp -d)
    sudo mount "$PARTITION" "$MOUNT_DIR"
    
    case "$PROCESS_TYPE" in
        "贝壳云环境")
            sudo sed -i 's/\(extraargs=.*\)$/\1 net.ifnames=0 biosdevname=0/' "$MOUNT_DIR/armbianEnv.txt"
            echo "✅ 修改后的armbianEnv.txt内容:"
            sudo cat "$MOUNT_DIR/armbianEnv.txt"
            ;;
        "脚本")
            # 修改amlogic检查脚本
            FIRMWARE_SCRIPT="$MOUNT_DIR/usr/share/amlogic/amlogic_check_firmware.sh"
            if sudo test -f "$FIRMWARE_SCRIPT"; then
                sudo sed -i \
                    's@{ print \$0 "</li>"; exit }@{ found=\$0 "</li>" } END{print found}@' \
                    "$FIRMWARE_SCRIPT"
                    echo "✅ 修改后的检查脚本内容:"
                    sudo grep -A2 'li_block=' "$FIRMWARE_SCRIPT"
            fi
            
            # 修改amlogic配置
            AMLOGIC_CONFIG="$MOUNT_DIR/etc/config/amlogic"
            if sudo test -f "$AMLOGIC_CONFIG"; then
                sudo sed -i \
                    -e "s|option amlogic_firmware_repo.*|option amlogic_firmware_repo 'https://github.com/${REPO_SETTINGS}'|" \
                    -e "s|option amlogic_firmware_tag.*|option amlogic_firmware_tag 'RELEASE-${NETWORK_SETTINGS}'|" \
                    "$AMLOGIC_CONFIG"
                echo "✅ 修改后的amlogic配置:"
                sudo grep -E "option amlogic_firmware_(repo|tag)" "$AMLOGIC_CONFIG"
            fi
            ;;
    esac

    sudo umount "$MOUNT_DIR"
    sudo rm -rf "$MOUNT_DIR"
    sudo losetup -d "$LOOP_DEV"
    sync
    echo "✅ ${PROCESS_TYPE}配置完成"
}

# 主处理流程
for FILE in $OUTPUT_DIR/*.img.gz; do
    [ ! -f "$FILE" ] && continue
    
    echo "🔧 处理固件: $(basename "$FILE")"
    UNZIPPED_FILE="${FILE%.gz}"
    gunzip -k "$FILE"
    
    # 贝壳云特殊处理
    if [[ "$FILE" == *"beikeyun"* ]]; then
        process_partition "$UNZIPPED_FILE" 1 "贝壳云环境"
    fi
    
    # 通用脚本处理
    process_partition "$UNZIPPED_FILE" 2 "脚本"
    
    # 更新校验信息
    echo "🔏 更新SHA校验文件..."
    gzip -f "$UNZIPPED_FILE"
    NEW_SHA256=$(sha256sum "$FILE" | awk '{print $1}')
    SHA_FILE="${FILE}.sha"
    [ -f "$SHA_FILE" ] && echo "$(head -c 64 "$SHA_FILE") $NEW_SHA256" > "$SHA_FILE"
    
    echo "✅ 固件处理完成: $(basename "$FILE")"
    echo "----------------------------------------"
done

echo "🎉 所有设备固件处理完成!"
