#!/usr/bin/env bash
# 自动检测并修复 last 命令（适配 Debian/Ubuntu 系）

set -e

echo "[*] 检测是否为 root 用户..."
if [ "$(id -u)" -ne 0 ]; then
    echo "[!] 请使用 root 权限运行本脚本（sudo 或直接 root）。"
    exit 1
fi

echo "[*] 检测系统类型..."
if [ -r /etc/os-release ]; then
    . /etc/os-release
    echo "    检测到系统: ${PRETTY_NAME}"
else
    echo "[!] 无法识别系统类型，继续尝试但可能失败。"
fi

echo "[*] 检测 last 命令..."
if command -v last >/dev/null 2>&1; then
    echo "    last 已存在: $(command -v last)"
else
    echo "    last 未找到，准备安装 util-linux..."
    # 对 Debian/Ubuntu 系使用 apt 安装
    if command -v apt >/dev/null 2>&1; then
        apt update
        apt install -y util-linux
    else
        echo "[!] 未找到 apt，请确认系统为 Debian/Ubuntu 系，再手动安装 util-linux。"
        exit 1
    fi

    if command -v last >/dev/null 2>&1; then
        echo "    last 安装成功: $(command -v last)"
    else
        echo "[!] 安装 util-linux 后仍未找到 last，请手动检查。"
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
    # 如果没有 utmp 组，就保持默认 root:root
    chown root:root /var/log/wtmp || echo "[!] chown 失败，请手动检查。"
fi

echo "[*] 尝试运行 last (只显示前 10 行)..."
if last 2>/dev/null | head -n 10; then
    echo
    echo "[✅] last 正常工作了。"
else
    echo
    echo "[⚠️] last 运行失败，可能是系统还没有登录记录，或日志格式有问题。"
fi
