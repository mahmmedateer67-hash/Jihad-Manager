#!/bin/bash
# ============================================================
# Jihad Manager - سكربت التثبيت الرئيسي
# الإصدار: 1.0
# المطور: Jihad
# ============================================================
set -e

# ألوان
RED='\033[38;5;196m'
GREEN='\033[38;5;46m'
YELLOW='\033[38;5;226m'
BLUE='\033[38;5;39m'
PURPLE='\033[38;5;135m'
RESET='\033[0m'
BOLD='\033[1m'

# التحقق من صلاحيات الجذر
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ خطأ: يجب تشغيل هذا السكربت بصلاحيات root.${RESET}"
   exit 1
fi

echo -e "${BOLD}${PURPLE}=====================================================${RESET}"
echo -e "${BOLD}${GREEN}         🚀 Jihad Manager - التثبيت 🚀              ${RESET}"
echo -e "${BOLD}${PURPLE}=====================================================${RESET}"

# الروابط الرسمية من GitHub
GITHUB_USER="mahmmedateer67-hash"
GITHUB_REPO="Jihad-Manager"
BRANCH="main"
BASE_RAW="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}"

MENU_URL="${BASE_RAW}/jihad_menu.sh"
SSHD_URL="${BASE_RAW}/ssh/sshd_config"

# تثبيت المتطلبات الأساسية
echo -e "${BLUE}⚙️ جاري تثبيت المتطلبات الأساسية...${RESET}"
apt-get update -qq > /dev/null 2>&1
for pkg in curl wget jq bc net-tools; do
    if ! command -v $pkg &> /dev/null; then
        apt-get install -y -qq $pkg > /dev/null 2>&1
        echo -e "${GREEN}✅ تم تثبيت $pkg${RESET}"
    fi
done

# تنزيل سكربت القائمة الرئيسي
echo -e "${BLUE}📥 جاري تنزيل Jihad Menu...${RESET}"
wget -4 -q -O /usr/local/bin/jihad "${MENU_URL}"
chmod +x /usr/local/bin/jihad
echo -e "${GREEN}✅ تم تثبيت سكربت القائمة.${RESET}"

# إعداد SSH
echo -e "${BLUE}🔐 جاري تطبيق إعدادات SSH...${RESET}"
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP="/etc/ssh/sshd_config.backup.$(date +%F-%H%M%S)"

# نسخة احتياطية
cp "$SSHD_CONFIG" "$BACKUP"
echo -e "${GREEN}✅ نسخة احتياطية: $BACKUP${RESET}"

# تنزيل إعدادات SSH
wget -4 -q -O "$SSHD_CONFIG" "$SSHD_URL"
chmod 600 "$SSHD_CONFIG"

# التحقق من صحة الإعدادات
if ! sshd -t 2>/dev/null; then
    echo -e "${RED}❌ إعدادات SSH غير صالحة! جاري الاستعادة...${RESET}"
    cp "$BACKUP" "$SSHD_CONFIG"
    exit 1
fi

# إعادة تشغيل SSH
if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
    echo -e "${GREEN}✅ تم إعادة تشغيل SSH.${RESET}"
else
    echo -e "${YELLOW}⚠️ يرجى إعادة تشغيل SSH يدوياً.${RESET}"
fi

# إنشاء مجلد الإعدادات
mkdir -p /etc/jihad
touch /etc/jihad/users.db

# تشغيل الإعداد الأولي
echo -e "${BLUE}⚙️ جاري الإعداد الأولي...${RESET}"
bash /usr/local/bin/jihad --install-setup 2>/dev/null || true

echo -e "\n${BOLD}${GREEN}=====================================================${RESET}"
echo -e "${BOLD}${GREEN}     ✅ تم تثبيت Jihad Manager بنجاح!              ${RESET}"
echo -e "${BOLD}${GREEN}=====================================================${RESET}"
echo -e "${YELLOW}اكتب ${BOLD}jihad${RESET}${YELLOW} في أي وقت لفتح القائمة.${RESET}\n"
