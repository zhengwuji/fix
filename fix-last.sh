#!/usr/bin/env bash
# 自动检测并修复 last 命令
# 兼容：Debian 13（使用 wtmpdb）以及旧版 Debian/Ubuntu（使用 util-linux）

set -e

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

create_last_wrapper() {
    # 给 Debian 13 这类没有 /usr/bin/last 但有 wtmpdb 的系统用
    if ! have_cmd wtmpdb; then
        echo "[!] 系统中没有 wtmpdb，无法创建 last 包装脚本。"
        return 1
    fi

    echo "[*] 创建 /usr/local/bin/last 包装脚本 (调用 wtmpdb last)..."

    cat >/usr/local/bin/last <<'EOF'
#!/usr/bin/env bash
# 兼容旧习惯：让 "last" 实际调用 "wtmpdb last"
exec wtmpdb last "$@"
EOF

    chmod +x /usr/local/bin/last
    echo "    已创建: /usr/local/bin/last"
}

echo "[*] 检测是否为 root 用户..."
if [ "$(id -u)" -ne 0 ]; then
    echo "[!] 请使用 root 权限运行本脚本（sudo 或直接 root）。"
    exit 1
fi

echo "[*] 检测系统类型..."
ID=""
VERSION_ID=""
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "    检测到系统: ${PRETTY_NAME:-未知}"
else
    echo "[!] 无法读取 /etc/os-release，将按通用方式处理。"
fi

echo "[*] 检测 last 命令..."
if have_cmd last; then
    echo "    last 已存在: $(command -v last)"
else
    echo "    last 未找到，尝试安装或兼容处理..."

    # 若已有 wtmpdb，则优先创建包装脚本
    if have_cmd wtmpdb; then
        echo "    检测到系统已安装 wtmpdb，创建 last 包装脚本..."
        create_last_wrapper || true
    fi

    # 再检查一次 last 是否已经可用
    if ! have_cmd last; then
        echo "[*] 尝试使用包管理器安装相关组件..."

        if have_cmd apt; then
            apt update

            # 对 Debian 13 及以上使用 wtmpdb
            if [ "$ID" = "debian" ] && [ -n "$VERSION_ID" ] && [ "${VERSION_ID%%.*}" -ge 13 ] 2>/dev/null; then
                echo "    检测到 Debian $VERSION_ID，安装 wtmpdb 与 libpam-wtmpdb..."
                apt install -y wtmpdb libpam-wtmpdb
                # 安装后创建 last 包装脚本
                create_last_wrapper || true
            else
                echo "    非 Debian 13，安装 util-linux（传统 last 所在包）..."
                apt install -y util-linux
            fi
        else
            echo "[!] 未找到 apt，无法自动安装，请手动安装 util-linux 或 wtmpdb。"
        fi
    fi

    # 最终确认 last 是否存在
    if have_cmd last; then
        echo "    last 已可用: $(command -v last)"
    else
        echo "[!] 尝试安装/兼容后仍未找到 last，请手动检查系统环境。"
        exit 1
    fi
fi

echo "[*] 检查 /var/log/wtmp ..."
if [ -e /var/log/wtmp ]; then
    echo "    /var/log/wtmp 已存在。"
else
    echo "    /var/log/wtmp 不存在，正在创建..."
    touch /var/log/wtmp
fi

echo "[*] 设置 /var/log/wtmp 权限..."
chmod 664 /var/log/wtmp || echo "[!] chmod 失败，请手动检查权限。"

# 尝试设置所属用户和组（Debian 通常是 root:utmp）
if getent group utmp >/dev/null 2>&1; then
    chown root:utmp /var/log/wtmp || echo "[!] chown 失败，请手动检查。"
else
    chown root:root /var/log/wtmp || echo "[!] chown 失败，请手动检查。"
fi

echo "[*] 尝试运行 last (只显示前 10 行)..."
if last 2>/dev/null | head -n 10; then
    echo
    echo "[✅] last 正常工作了。"
else
    echo
    echo "[⚠️] last 运行失败，可能当前系统还没有任何登录记录，或日志数据库为空。"
fi
