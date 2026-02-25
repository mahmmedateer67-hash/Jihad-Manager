#!/bin/bash

# إعادة تعيين الألوان
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_UL='\033[4m'

# لوحة ألوان جميلة
C_RED='\033[38;5;196m'      # أحمر ساطع
C_GREEN='\033[38;5;46m'     # أخضر نيون
C_YELLOW='\033[38;5;226m'   # أصفر ساطع
C_BLUE='\033[38;5;39m'      # أزرق سماوي عميق
C_PURPLE='\033[38;5;135m'   # بنفسجي فاتح
C_CYAN='\033[38;5;51m'      # سماوي
C_WHITE='\033[38;5;255m'    # أبيض ساطع
C_GRAY='\033[38;5;245m'     # رمادي
C_ORANGE='\033[38;5;208m'   # برتقالي

# أسماء مستعارة دلالية للألوان
C_TITLE=$C_PURPLE
C_CHOICE=$C_CYAN
C_PROMPT=$C_BLUE
C_WARN=$C_YELLOW
C_DANGER=$C_RED
C_STATUS_A=$C_GREEN
C_STATUS_I=$C_GRAY
C_ACCENT=$C_ORANGE

# المتغيرات العالمية والمسارات الخاصة بـ Jihad
DB_DIR="/etc/jihad"
DB_FILE="$DB_DIR/users.db"
INSTALL_FLAG_FILE="$DB_DIR/.install"

DNSTT_SERVICE_FILE="/etc/systemd/system/dnstt.service"
DNSTT_BINARY="/usr/local/bin/dnstt-server"
DNSTT_KEYS_DIR="$DB_DIR/dnstt"
DNSTT_CONFIG_FILE="$DB_DIR/dnstt_info.conf"
DNS_INFO_FILE="$DB_DIR/dns_info.conf"

SSH_BANNER_FILE="/etc/bannerssh"

LIMITER_SCRIPT="/usr/local/bin/jihad-limiter.sh"
LIMITER_SERVICE="/etc/systemd/system/jihad-limiter.service"

# متغيرات IONOS API
IONOS_BASE_URL="https://api.hosting.ionos.com/dns"
IONOS_ZONE_ID=""
IONOS_API_KEY=""
IONOS_BASE_DOMAIN="02iuk.shop"
IONOS_CONF="/etc/jihad/ionos.conf"

# تحميل إعدادات IONOS من ملف محلي آمن (لا يتم رفعه على GitHub)
if [ -f "$IONOS_CONF" ]; then
    source "$IONOS_CONF"
fi

# دالة لإعداد مفاتيح IONOS إذا لم تكن موجودة
setup_ionos_keys() {
    if [[ -z "$IONOS_API_KEY" || -z "$IONOS_ZONE_ID" ]]; then
        echo -e "${C_YELLOW}⚠️ مفاتيح IONOS API غير مُعدّة. يرجى إدخالها الآن:${C_RESET}"
        read -p "👉 أدخل IONOS API Key: " input_api_key
        read -p "👉 أدخل IONOS Zone ID: " input_zone_id
        read -p "👉 أدخل الدومين الأساسي (مثال: 02iuk.shop): " input_domain
        
        mkdir -p /etc/jihad
        cat > "$IONOS_CONF" <<EOCONF
# إعدادات IONOS API - ملف سري لا ترفعه على GitHub
IONOS_API_KEY="$input_api_key"
IONOS_ZONE_ID="$input_zone_id"
IONOS_BASE_DOMAIN="${input_domain:-02iuk.shop}"
EOCONF
        chmod 600 "$IONOS_CONF"
        source "$IONOS_CONF"
        echo -e "${C_GREEN}✅ تم حفظ إعدادات IONOS بأمان في $IONOS_CONF${C_RESET}"
    fi
}

SELECTED_USER=""
UNINSTALL_MODE="interactive"

# التحقق من صلاحيات الجذر
if [[ $EUID -ne 0 ]]; then
   echo -e "${C_RED}❌ خطأ: يتطلب هذا السكربت صلاحيات الجذر للتشغيل.${C_RESET}"
   exit 1
fi

# دالة لعرض البانر (الشعار) الخاص بـ Jihad
show_banner() {
    clear
    echo -e "${C_BOLD}${C_PURPLE}=====================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}         🚀 Jihad Manager - إدارة الخادم 🚀         ${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}=====================================================${C_RESET}"
    echo -e "${C_YELLOW}مرحباً بك يا جهاد! هنا يمكنك إدارة خادمك بسهولة.${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}=====================================================${C_RESET}\n"
}

# دالة للتحقق من توفر البيئة (jq و curl ضروريان)
check_environment() {
    echo -e "${C_BLUE}⚙️ جاري التحقق من المتطلبات الأساسية (jq, curl, wget, bc)...${C_RESET}"
    for cmd in bc jq curl wget; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${C_YELLOW}⚠️ تحذير: '$cmd' غير موجود. جاري التثبيت...${C_RESET}"
            apt-get update > /dev/null 2>&1 && apt-get install -y $cmd || {
                echo -e "${C_RED}❌ خطأ: فشل تثبيت '$cmd'. يرجى تثبيته يدوياً.${C_RESET}"
                exit 1
            }
        fi
    done
    echo -e "${C_GREEN}✅ جميع المتطلبات الأساسية متوفرة.${C_RESET}"
}

# دالة الإعداد الأولي
initial_setup() {
    echo -e "${C_BLUE}⚙️ جاري تهيئة إعدادات Jihad Manager...${C_RESET}"
    check_environment
    
    mkdir -p "$DB_DIR"
    touch "$DB_FILE"
    
    echo -e "${C_BLUE}🔹 جاري تهيئة خدمة تحديد المستخدمين...${C_RESET}"
    setup_limiter_service
    
    if [ ! -f "$INSTALL_FLAG_FILE" ]; then
        touch "$INSTALL_FLAG_FILE"
    fi
    echo -e "${C_GREEN}✅ اكتمل الإعداد بنجاح.${C_RESET}"
}

# دالة للتحقق من صحة عنوان IPv4
_is_valid_ipv4() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# دالة للتحقق من المنافذ وفتحها في جدار الحماية
check_and_open_firewall_port() {
    local port="$1"
    local protocol="${2:-tcp}"
    local firewall_detected=false

    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        firewall_detected=true
        if ! ufw status | grep -qw "$port/$protocol"; then
            echo -e "${C_YELLOW}🔥 جدار حماية UFW نشط والمنفذ ${port}/${protocol} مغلق.${C_RESET}"
            read -p "👉 هل تريد فتح هذا المنفذ الآن؟ (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                ufw allow "$port/$protocol"
                echo -e "${C_GREEN}✅ تم فتح المنفذ ${port}/${protocol} في UFW.${C_RESET}"
            else
                echo -e "${C_RED}❌ تحذير: لم يتم فتح المنفذ ${port}/${protocol}. قد لا تعمل الخدمة بشكل صحيح.${C_RESET}"
                return 1
            fi
        else
             echo -e "${C_GREEN}✅ المنفذ ${port}/${protocol} مفتوح بالفعل في UFW.${C_RESET}"
        fi
    fi

    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall_detected=true
        if ! firewall-cmd --list-ports --permanent | grep -qw "$port/$protocol"; then
            echo -e "${C_YELLOW}🔥 firewalld نشط والمنفذ ${port}/${protocol} غير مفتوح.${C_RESET}"
            read -p "👉 هل تريد فتح هذا المنفذ الآن؟ (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                firewall-cmd --add-port="$port/$protocol" --permanent
                firewall-cmd --reload
                echo -e "${C_GREEN}✅ تم فتح المنفذ ${port}/${protocol} في firewalld.${C_RESET}"
            else
                echo -e "${C_RED}❌ تحذير: لم يتم فتح المنفذ ${port}/${protocol}. قد لا تعمل الخدمة بشكل صحيح.${C_RESET}"
                return 1
            fi
        else
            echo -e "${C_GREEN}✅ المنفذ ${port}/${protocol} مفتوح بالفعل في firewalld.${C_RESET}"
        fi
    fi

    if ! $firewall_detected; then
        echo -e "${C_BLUE}ℹ️ لم يتم الكشف عن جدار حماية نشط (UFW أو firewalld). نفترض أن المنافذ مفتوحة.${C_RESET}"
    fi
    return 0
}

# دالة للتحقق من المنافذ الحرة
check_and_free_ports() {
    local ports_to_check=("$@")
    for port in "${ports_to_check[@]}"; do
        echo -e "\n${C_BLUE}🔎 جاري التحقق مما إذا كان المنفذ $port متاحاً...${C_RESET}"
        local conflicting_process_info
        conflicting_process_info=$(ss -lntp | grep ":$port\s" || ss -lunp | grep ":$port\s")
        
        if [[ -n "$conflicting_process_info" ]]; then
            local conflicting_pid
            conflicting_pid=$(echo "$conflicting_process_info" | grep -oP 'pid=\K[0-9]+' | head -n 1)
            local conflicting_name
            conflicting_name=$(echo "$conflicting_process_info" | grep -oP 'users:\(\("(\K[^"]+)\' | head -n 1)
            
            echo -e "${C_YELLOW}⚠️ تحذير: المنفذ $port مستخدم بواسطة العملية '${conflicting_name:-غير معروف}' (PID: ${conflicting_pid:-N/A}).${C_RESET}"
            read -p "👉 هل تريد محاولة إيقاف هذه العملية الآن؟ (y/n): " kill_confirm
            if [[ "$kill_confirm" == "y" || "$kill_confirm" == "Y" ]]; then
                echo -e "${C_GREEN}🛑 جاري إيقاف العملية PID $conflicting_pid...${C_RESET}"
                systemctl stop "$(ps -p "$conflicting_pid" -o comm=)" &>/dev/null || kill -9 "$conflicting_pid"
                sleep 2
                
                if ss -lntp | grep -q ":$port\s" || ss -lunp | grep -q ":$port\s"; then
                     echo -e "${C_RED}❌ فشل تحرير المنفذ $port. يرجى التعامل معه يدوياً. جاري الإلغاء.${C_RESET}"
                     return 1
                else
                     echo -e "${C_GREEN}✅ تم تحرير المنفذ $port بنجاح.${C_RESET}"
                fi
            else
                echo -e "${C_RED}❌ لا يمكن المتابعة بدون تحرير المنفذ $port. جاري الإلغاء.${C_RESET}"
                return 1
            fi
        else
            echo -e "${C_GREEN}✅ المنفذ $port متاح للاستخدام.${C_RESET}"
        fi
    done
    return 0
}

# دالة لإعداد خدمة تحديد المستخدمين (limiter service)
setup_limiter_service() {
    # منطق محدث: لا يوجد تسجيل، قفل ذكي لمدة 120 ثانية
    cat > "$LIMITER_SCRIPT" << 'EOF'
#!/bin/bash
DB_FILE="/etc/jihad/users.db"

# حلقة مستمرة مع نوم محسّن
while true; do
    if [[ ! -f "$DB_FILE" ]]; then
        sleep 30
        continue
    fi
    
    current_ts=$(date +%s)
    
    # قراءة المستخدمين من قاعدة البيانات والتحقق من صلاحيتهم وحدود الاتصال
    while IFS=: read -r user pass expiry limit; do
        [[ -z "$user" || "$user" == \#* ]] && continue
        
        # --- التحقق من انتهاء الصلاحية ---
        # يتم التحقق من انتهاء الصلاحية فقط إذا كان هناك تاريخ انتهاء صلاحية صالح
        if [[ "$expiry" != "Never" && "$expiry" != "" ]]; then
             expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
             if [[ $expiry_ts -lt $current_ts && $expiry_ts -ne 0 ]]; then
                if ! passwd -S "$user" | grep -q " L "; then
                    usermod -L "$user" &>/dev/null
                    killall -u "$user" -9 &>/dev/null
                fi
                continue
             fi
        fi
        
        # --- التحقق من حد الاتصال ---
        online_count=$(pgrep -c -u "$user" sshd)
        if ! [[ "$limit" =~ ^[0-9]+$ ]]; then limit=1; fi
        
        if [[ "$online_count" -gt "$limit" ]]; then
            if ! passwd -S "$user" | grep -q " L "; then
                usermod -L "$user" &>/dev/null
                killall -u "$user" -9 &>/dev/null
                (sleep 120; usermod -U "$user" &>/dev/null) & 
            else
                killall -u "$user" -9 &>/dev/null
            fi
        fi
    done < "$DB_FILE"
    
    # زيادة وقت النوم إلى 25 ثانية لتقليل حمل وحدة المعالجة المركزية
    sleep 25
done
EOF
    chmod +x "$LIMITER_SCRIPT"

    cat > "$LIMITER_SERVICE" << EOF
[Unit]
Description=Jihad Active User Limiter
After=network.target

[Service]
Type=simple
ExecStart=$LIMITER_SCRIPT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # قتل أي عملية تحديد قديمة لمنع تعليق systemctl restart
    pkill -f "jihad-limiter" 2>/dev/null

    if ! systemctl is-active --quiet jihad-limiter; then
        systemctl daemon-reload
        systemctl enable jihad-limiter &>/dev/null
        systemctl start jihad-limiter --no-block &>/dev/null
        
    else
        # إعادة التشغيل إذا كانت الخدمة تعمل بالفعل لتطبيق المنطق الجديد
        systemctl restart jihad-limiter --no-block &>/dev/null
        
    fi
}

# دالة للحصول على حالة المستخدم
get_user_status() {
    local u=$1
    local user_entry=$(grep "^$u:" "$DB_FILE")
    if [[ -z "$user_entry" ]]; then
        echo -e "${C_DIM}غير مدار${C_RESET}"
        return
    fi

    local expiry=$(echo "$user_entry" | cut -d: -f3)
    local current_ts=$(date +%s)
    local expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)

    if passwd -S "$u" | grep -q " L "; then
        echo -e "${C_YELLOW}مغلق${C_RESET}"
    elif [[ $expiry_ts -lt $current_ts && $expiry_ts -ne 0 ]]; then
        echo -e "${C_RED}منتهي الصلاحية${C_RESET}"
    else
        echo -e "${C_GREEN}نشط${C_RESET}"
    fi
}

# دالة لعرض قائمة المستخدمين واختيار مستخدم
_select_user_interface() {
    local title=$1
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}$title${C_RESET}"
    echo -e "${C_CYAN}=====================================================${C_RESET}"
    
    local users_array=()
    if [[ -s "$DB_FILE" ]]; then
        while IFS=: read -r user pass expiry limit; do
            [[ -z "$user" || "$user" == \#* ]] && continue
            users_array+=("$user")
        done < <(sort "$DB_FILE")
    fi

    if [ ${#users_array[@]} -eq 0 ]; then
        echo -e "\n${C_YELLOW}ℹ️ لا يوجد مستخدمون مدارون حالياً.${C_RESET}"
        SELECTED_USER="NO_USERS"
        return
    fi

    echo -e "\n${C_CYAN}اختر مستخدماً من القائمة:${C_RESET}"
    for i in "${!users_array[@]}"; do
        printf "  ${C_GREEN}[%2d]${C_RESET} %s\n" "$((i+1))" "${users_array[$i]}"
    done
    echo -e "  ${C_RED} [ 0]${C_RESET} ↩️ إلغاء"
    
    local choice
    while true; do
        read -p "👉 أدخل رقم المستخدم: " choice
        if [[ "$choice" == "0" ]]; then
            SELECTED_USER=""
            echo -e "\n${C_YELLOW}❌ تم الإلغاء.${C_RESET}"
            return
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -le "${#users_array[@]}" ]; then
            SELECTED_USER="${users_array[$((choice-1))]}"
            break
        else
            echo -e "${C_RED}❌ اختيار غير صالح. يرجى المحاولة مرة أخرى.${C_RESET}"
        fi
    done
}

# ==================================================================
# وظائف إدارة المستخدمين
# ==================================================================

# دالة لإنشاء مستخدم جديد
create_user() {
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ➕ إنشاء مستخدم جديد ---${C_RESET}"
    local username
    while true; do
        read -p "👉 أدخل اسم المستخدم الجديد: " username
        if [[ -z "$username" ]]; then
            echo -e "${C_RED}❌ اسم المستخدم لا يمكن أن يكون فارغاً.${C_RESET}"
        elif id "$username" &>/dev/null; then
            echo -e "${C_RED}❌ اسم المستخدم '$username' موجود بالفعل. يرجى اختيار اسم آخر.${C_RESET}"
        else
            break
        fi
    done

    local password
    while true; do
        read -p "👉 أدخل كلمة المرور للمستخدم الجديد: " password
        if [[ -z "$password" ]]; then
            echo -e "${C_RED}❌ كلمة المرور لا يمكن أن تكون فارغة.${C_RESET}"
        else
            break
        fi
    done

    local days
    while true; do
        read -p "👉 أدخل عدد أيام صلاحية الحساب (مثال: 30) أو '0' للمدة غير المحدودة: " days
        if [[ "$days" =~ ^[0-9]+$ ]]; then
            break
        else
            echo -e "${C_RED}❌ عدد أيام غير صالح. يرجى إدخال رقم.${C_RESET}"
        fi
    done

    local expiry_date
    if [[ "$days" == "0" ]]; then
        expiry_date="Never"
    else
        expiry_date=$(date -d "+$days days" +%Y-%m-%d)
    fi

    local limit
    while true; do
        read -p "👉 أدخل الحد الأقصى لعدد الاتصالات المتزامنة (مثال: 1): " limit
        if [[ "$limit" =~ ^[0-9]+$ && "$limit" -ge 1 ]]; then
            break
        else
            echo -e "${C_RED}❌ حد اتصال غير صالح. يرجى إدخال رقم صحيح أكبر من أو يساوي 1.${C_RESET}"
        fi
    done

    useradd -m -s /bin/bash "$username" &>/dev/null
    echo "$username:$password" | chpasswd
    if [[ "$expiry_date" != "Never" ]]; then
        chage -E "$expiry_date" "$username"
    fi

    echo "$username:$password:$expiry_date:$limit" >> "$DB_FILE"

    echo -e "\n${C_GREEN}✅ تم إنشاء المستخدم '$username' بنجاح!${C_RESET}"
    echo -e "${C_YELLOW}اسم المستخدم: $username${C_RESET}"
    echo -e "${C_YELLOW}كلمة المرور: $password${C_RESET}"
    echo -e "${C_YELLOW}تاريخ انتهاء الصلاحية: $expiry_date${C_RESET}"
    echo -e "${C_YELLOW}حد الاتصالات: $limit${C_RESET}"
}

# دالة لحذف مستخدم
delete_user() {
    _select_user_interface "--- 🗑️ حذف مستخدم ---"
    local username=$SELECTED_USER
    if [[ -z "$username" ]]; then return; fi

    read -p "👉 هل أنت متأكد أنك تريد حذف المستخدم '$username' نهائياً؟ (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo -e "\n${C_YELLOW}❌ تم إلغاء الحذف.${C_RESET}"
        return
    fi

    echo -e "${C_BLUE}🔌 جاري إنهاء الاتصالات النشطة للمستخدم $username...${C_RESET}"
    killall -u "$username" -9 &>/dev/null
    sleep 1

    userdel -r "$username" &>/dev/null
    if [ $? -eq 0 ]; then
         echo -e "\n${C_GREEN}✅ تم حذف مستخدم النظام '$username' بنجاح.${C_RESET}"
    else
         echo -e "\n${C_RED}❌ فشل حذف مستخدم النظام '$username'.${C_RESET}"
    fi

    sed -i "/^$username:/d" "$DB_FILE"
    echo -e "${C_GREEN}✅ تم إزالة المستخدم '$username' بالكامل من قاعدة البيانات.${C_RESET}"
}

# دالة لتعديل مستخدم
edit_user() {
    _select_user_interface "--- ✏️ تعديل مستخدم ---"
    local username=$SELECTED_USER
    if [[ -z "$username" ]]; then return; fi

    while true; do
        clear; show_banner; echo -e "${C_BOLD}${C_PURPLE}--- تعديل المستخدم: ${C_YELLOW}$username${C_PURPLE} ---${C_RESET}"
        echo -e "\nاختر تفصيلاً لتعديله:\n"
        printf "  ${C_GREEN}[ 1]${C_RESET} %-35s\n" "🔑 تغيير كلمة المرور"
        printf "  ${C_GREEN}[ 2]${C_RESET} %-35s\n" "🗓️ تغيير تاريخ انتهاء الصلاحية"
        printf "  ${C_GREEN}[ 3]${C_RESET} %-35s\n" "📶 تغيير حد الاتصالات"
        echo -e "\n  ${C_RED}[ 0]${C_RESET} ✅ إنهاء التعديل"; echo; read -p "👉 أدخل اختيارك: " edit_choice
        case $edit_choice in
            1)
               local new_pass=""
               while true; do
                   read -p "أدخل كلمة المرور الجديدة: " new_pass
                   if [[ -z "$new_pass" ]]; then
                       echo -e "${C_RED}❌ كلمة المرور لا يمكن أن تكون فارغة. يرجى المحاولة مرة أخرى.${C_RESET}"
                   else
                       break
                   fi
               done
               echo "$username:$new_pass" | chpasswd
               local current_line; current_line=$(grep "^$username:" "$DB_FILE"); local expiry; expiry=$(echo "$current_line" | cut -d: -f3); local limit; limit=$(echo "$current_line" | cut -d: -f4)
               sed -i "s/^$username:.*/$username:$new_pass:$expiry:$limit/" "$DB_FILE"
               echo -e "\n${C_GREEN}✅ تم تغيير كلمة المرور للمستخدم '$username' بنجاح.${C_RESET}"
               echo -e "كلمة المرور الجديدة: ${C_YELLOW}$new_pass${C_RESET}"
               ;;
            2) read -p "أدخل مدة الصلاحية الجديدة (بالأيام من اليوم): " days
               if [[ "$days" =~ ^[0-9]+$ ]]; then
                   local new_expire_date; new_expire_date=$(date -d "+$days days" +%Y-%m-%d); chage -E "$new_expire_date" "$username"
                   local current_line; current_line=$(grep "^$username:" "$DB_FILE"); local pass; pass=$(echo "$current_line" | cut -d: -f2); local limit; limit=$(echo "$current_line" | cut -d: -f4)
                   sed -i "s/^$username:.*/$username:$pass:$new_expire_date:$limit/" "$DB_FILE"
                   echo -e "\n${C_GREEN}✅ تم تعيين تاريخ انتهاء الصلاحية للمستخدم '$username' إلى ${C_YELLOW}$new_expire_date${C_RESET}."
               else echo -e "\n${C_RED}❌ عدد أيام غير صالح.${C_RESET}"; fi ;;
            3) read -p "أدخل الحد الأقصى الجديد لعدد الاتصالات المتزامنة: " new_limit
               if [[ "$new_limit" =~ ^[0-9]+$ ]]; then
                   local current_line; current_line=$(grep "^$username:" "$DB_FILE"); local pass; pass=$(echo "$current_line" | cut -d: -f2); local expiry; expiry=$(echo "$current_line" | cut -d: -f3)
                   sed -i "s/^$username:.*/$username:$pass:$expiry:$new_limit/" "$DB_FILE"
                   echo -e "\n${C_GREEN}✅ تم تعيين حد الاتصالات للمستخدم '$username' إلى ${C_YELLOW}$new_limit${C_RESET}."
               else echo -e "\n${C_RED}❌ حد غير صالح.${C_RESET}"; fi ;;
            0) return ;;
            *) echo -e "\n${C_RED}❌ خيار غير صالح.${C_RESET}" ;;
        esac
        echo -e "\nاضغط ${C_YELLOW}[Enter]${C_RESET} للمتابعة..." && read -r
    done
}

# دالة لقفل مستخدم
lock_user() {
    _select_user_interface "--- 🔒 قفل مستخدم ---"
    local u=$SELECTED_USER
    if [[ -z "$u" ]]; then return; fi

    usermod -L "$u"
    if [ $? -eq 0 ]; then
        killall -u "$u" -9 &>/dev/null
        echo -e "\n${C_GREEN}✅ تم قفل المستخدم '$u' وإنهاء الجلسات النشطة.${C_RESET}"
    else
        echo -e "\n${C_RED}❌ فشل قفل المستخدم '$u'.${C_RESET}"
    fi
}

# دالة لفتح مستخدم
unlock_user() {
    _select_user_interface "--- 🔓 فتح مستخدم ---"
    local u=$SELECTED_USER
    if [[ -z "$u" ]]; then return; fi

    usermod -U "$u"
    if [ $? -eq 0 ]; then
        echo -e "\n${C_GREEN}✅ تم فتح المستخدم '$u'.${C_RESET}"
    else
        echo -e "\n${C_RED}❌ فشل فتح المستخدم '$u'.${C_RESET}"
    fi
}

# دالة لتجديد صلاحية مستخدم
renew_user() {
    _select_user_interface "--- 🔄 تجديد صلاحية مستخدم ---"
    local u=$SELECTED_USER
    if [[ -z "$u" ]]; then return; fi

    read -p "👉 أدخل عدد الأيام لتمديد الحساب: " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "\n${C_RED}❌ عدد غير صالح.${C_RESET}"
        return
    fi

    local new_expire_date; new_expire_date=$(date -d "+$days days" +%Y-%m-%d)
    chage -E "$new_expire_date" "$u"

    local line; line=$(grep "^$u:" "$DB_FILE")
    local pass; pass=$(echo "$line"|cut -d: -f2)
    local limit; limit=$(echo "$line"|cut -d: -f4)
    sed -i "s/^$u:.*/$u:$pass:$new_expire_date:$limit/" "$DB_FILE"

    echo -e "\n${C_GREEN}✅ تم تجديد صلاحية المستخدم '$u'. تاريخ الانتهاء الجديد هو ${C_YELLOW}${new_expire_date}${C_RESET}."
}

# دالة لعرض قائمة المستخدمين
list_users() {
    clear; show_banner
    if [[ ! -s "$DB_FILE" ]]; then
        echo -e "\n${C_YELLOW}ℹ️ لا يوجد مستخدمون مدارون حالياً.${C_RESET}"
        return
    fi
    echo -e "${C_BOLD}${C_PURPLE}--- 📋 المستخدمون المدارون ---${C_RESET}"
    echo -e "${C_CYAN}======================================================================${C_RESET}"
    printf "${C_BOLD}${C_WHITE}%-20s | %-12s | %-15s | %-20s${C_RESET}\n" "اسم المستخدم" "ينتهي في" "الاتصالات" "الحالة"
    echo -e "${C_CYAN}----------------------------------------------------------------------${C_RESET}"
    
    while IFS=: read -r user pass expiry limit; do
        local online_count
        online_count=$(pgrep -c -u "$user" sshd | wc -l)
        
        local status
        status=$(get_user_status "$user")

        local plain_status
        plain_status=$(echo -e "$status" | sed 's/\x1b\[[0-9;]*m//g')
        
        local connection_string="$online_count / $limit"

        local line_color="$C_WHITE"
        case $plain_status in
            *"نشط"*) line_color="$C_GREEN" ;;
            *"مغلق"*) line_color="$C_YELLOW" ;;
            *"منتهي الصلاحية"*) line_color="$C_RED" ;;
            *"غير مدار"*) line_color="$C_DIM" ;;
        esac

        printf "${line_color}%-20s ${C_RESET}| ${C_YELLOW}%-12s ${C_RESET}| ${C_CYAN}%-15s ${C_RESET}| %-20s\n" "$user" "$expiry" "$connection_string" "$status"
    done < <(sort "$DB_FILE")
    echo -e "${C_CYAN}======================================================================${C_RESET}\n"
}

# دالة لتنظيف المستخدمين منتهية الصلاحية
cleanup_expired() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🧹 تنظيف المستخدمين منتهية الصلاحية ---${C_RESET}"
    
    local expired_users=()
    local current_ts
    current_ts=$(date +%s)

    if [[ ! -s "$DB_FILE" ]]; then
        echo -e "\n${C_GREEN}✅ قاعدة بيانات المستخدمين فارغة. لا يوجد مستخدمون منتهية الصلاحية.${C_RESET}"
        return
    fi
    
    while IFS=: read -r user pass expiry limit; do
        local expiry_ts
        expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
        
        if [[ $expiry_ts -lt $current_ts && $expiry_ts -ne 0 ]]; then
            expired_users+=("$user")
        fi
    done < "$DB_FILE"

    if [ ${#expired_users[@]} -eq 0 ]; then
        echo -e "\n${C_GREEN}✅ لا يوجد مستخدمون منتهية الصلاحية.${C_RESET}"
        return
    fi

    echo -e "${C_YELLOW}⚠️ تم العثور على المستخدمين التالية أسماؤهم منتهية الصلاحية:${C_RESET}"
    for u in "${expired_users[@]}"; do
        echo -e "  - ${C_RED}$u${C_RESET}"
    done

    read -p "👉 هل أنت متأكد أنك تريد حذف هؤلاء المستخدمين؟ (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo -e "\n${C_YELLOW}❌ تم إلغاء التنظيف.${C_RESET}"
        return
    fi

    for u in "${expired_users[@]}"; do
        echo -e "${C_BLUE}🗑️ جاري حذف المستخدم '$u'...${C_RESET}"
        killall -u "$u" -9 &>/dev/null
        userdel -r "$u" &>/dev/null
        sed -i "/^$u:/d" "$DB_FILE"
        echo -e "${C_GREEN}✅ تم حذف المستخدم '$u' بنجاح.${C_RESET}"
    done
    echo -e "\n${C_GREEN}✅ اكتمل تنظيف المستخدمين منتهية الصلاحية.${C_RESET}"
}

# ==================================================================
# وظائف DNSTT (أنفاق DNS / Slow DNS)
# ==================================================================

# دالة لعرض تفاصيل DNSTT
show_dnstt_details() {
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📡 تفاصيل DNSTT ---${C_RESET}"
    if [ -f "$DNSTT_CONFIG_FILE" ]; then
        source "$DNSTT_CONFIG_FILE"
        echo -e "\n${C_GREEN}=====================================================${C_RESET}"
        echo -e "${C_GREEN}            📡 تفاصيل اتصال DNSTT             ${C_RESET}"
        echo -e "${C_GREEN}=====================================================${C_RESET}"
        echo -e "\n${C_WHITE}تفاصيل اتصالك:${C_RESET}"
        echo -e "  - ${C_CYAN}نطاق النفق:${C_RESET} ${C_YELLOW}$TUNNEL_DOMAIN${C_RESET}"
        echo -e "  - ${C_CYAN}المفتاح العام:${C_RESET}    ${C_YELLOW}$PUBLIC_KEY${C_RESET}"
        if [[ -n "$FORWARD_DESC" ]]; then
            echo -e "  - ${C_CYAN}إعادة التوجيه إلى:${C_RESET} ${C_YELLOW}$FORWARD_DESC${C_RESET}"
        else
            echo -e "  - ${C_CYAN}إعادة التوجيه إلى:${C_RESET} ${C_YELLOW}غير معروف (التكوين مفقود)${C_RESET}"
        fi
        if [[ -n "$MTU_VALUE" ]]; then
            echo -e "  - ${C_CYAN}قيمة MTU:${C_RESET}     ${C_YELLOW}$MTU_VALUE${C_RESET}"
        fi
        if [[ "$DNSTT_RECORDS_MANAGED" == "false" && -n "$NS_DOMAIN" ]]; then
             echo -e "  - ${C_CYAN}سجل NS:${C_RESET}     ${C_YELLOW}$NS_DOMAIN${C_RESET}"
        fi
        
        if [[ "$FORWARD_DESC" == *"V2Ray"* ]]; then
             echo -e "  - ${C_CYAN}الإجراء المطلوب:${C_RESET} ${C_YELLOW}تأكد من أن خدمة V2Ray (vless/vmess/trojan) تستمع على المنفذ 8787 (بدون TLS)${C_RESET}"
        elif [[ "$FORWARD_DESC" == *"SSH"* ]]; then
             echo -e "  - ${C_CYAN}الإجراء المطلوب:${C_RESET} ${C_YELLOW}تأكد من تكوين عميل SSH الخاص بك لاستخدام نفق DNS.${C_RESET}"
        fi
        echo -e "\n${C_GREEN}=====================================================${C_RESET}\n"
    else
        echo -e "\n${C_YELLOW}ℹ️ لم يتم تثبيت DNSTT أو لم يتم العثور على ملف التكوين.${C_RESET}"
    fi
}

# دالة لتثبيت DNSTT
install_dnstt() {
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚀 تثبيت DNSTT (نفق DNS) ---${C_RESET}"
    if systemctl is-active --quiet dnstt; then
        echo -e "\n${C_YELLOW}ℹ️ DNSTT مثبت بالفعل ويعمل. يرجى إلغاء تثبيته أولاً إذا كنت ترغب في إعادة التكوين.${C_RESET}"
        return
    fi

    check_and_free_ports 53 udp || return
    check_and_open_firewall_port 53 udp || return

    echo -e "\n${C_BLUE}🔄 جاري تحديث قائمة الحزم...${C_RESET}"
    apt-get update > /dev/null 2>&1
    echo -e "${C_BLUE}📦 جاري تثبيت curl و unzip...${C_RESET}"
    apt-get install -y curl unzip > /dev/null 2>&1

    echo -e "\n${C_BLUE}🛑 جاري إيقاف وتعطيل systemd-resolved لتحرير المنفذ 53...${C_RESET}"
    systemctl stop systemd-resolved &>/dev/null
    systemctl disable systemd-resolved &>/dev/null
    chattr -i /etc/resolv.conf &>/dev/null # التأكد من أن الملف قابل للكتابة
    echo "nameserver 1.1.1.1" > /etc/resolv.conf
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    chattr +i /etc/resolv.conf &>/dev/null # جعل الملف غير قابل للتعديل
    echo -e "${C_GREEN}✅ تم تحرير المنفذ 53 وتكوين DNS.${C_RESET}"

    echo -e "\n${C_BLUE}🌐 جاري الكشف عن معمارية النظام...${C_RESET}"
    local arch=$(uname -m)
    local dnstt_download_url=""
    if [[ "$arch" == "x86_64" ]]; then
        dnstt_download_url="https://github.com/wangyu-/dnstt/releases/download/20230626/dnstt-server-linux-amd64-20230626.zip"
        echo -e "${C_BLUE}ℹ️ تم الكشف عن معمارية x86_64 (amd64).${C_RESET}"
    elif [[ "$arch" == "aarch64" ]]; then
        dnstt_download_url="https://github.com/wangyu-/dnstt/releases/download/20230626/dnstt-server-linux-arm64-20230626.zip"
        echo -e "${C_BLUE}ℹ️ تم الكشف عن معمارية ARM64.${C_RESET}"
    else
        echo -e "${C_RED}❌ معمارية غير مدعومة: $arch. لا يمكن تثبيت DNSTT.${C_RESET}"
        return
    fi

    echo -e "\n${C_GREEN}📥 جاري تنزيل ثنائي DNSTT...${C_RESET}"
    local temp_zip="/tmp/dnstt.zip"
    wget -q --show-progress -O "$temp_zip" "$dnstt_download_url"
    if [ $? -ne 0 ]; then
        echo -e "${C_RED}❌ فشل تنزيل ثنائي DNSTT. يرجى التحقق من الاتصال بالإنترنت أو الرابط.${C_RESET}"
        return
    fi
    unzip -o "$temp_zip" -d /tmp/ > /dev/null
    mv /tmp/dnstt-server-linux-* "$DNSTT_BINARY"
    chmod +x "$DNSTT_BINARY"
    rm -f "$temp_zip"
    echo -e "${C_GREEN}✅ تم تنزيل وتثبيت ثنائي DNSTT.${C_RESET}"

    echo -e "\n${C_BLUE}🔐 جاري توليد مفاتيح DNSTT...${C_RESET}"
    mkdir -p "$DNSTT_KEYS_DIR"
    local private_key_file="$DNSTT_KEYS_DIR/server.key"
    local public_key_file="$DNSTT_KEYS_DIR/server.pub"
    
    "$DNSTT_BINARY" -gen-key -f "$private_key_file" > /dev/null 2>&1
    "$DNSTT_BINARY" -gen-pubkey -f "$private_key_file" > "$public_key_file"
    
    local public_key=$(cat "$public_key_file")
    echo -e "${C_GREEN}✅ تم توليد المفاتيح بنجاح.${C_RESET}"
    echo -e "${C_YELLOW}المفتاح العام: $public_key${C_RESET}"

    local tunnel_domain
    read -p "👉 أدخل نطاق النفق الفرعي الذي سيتم استخدامه (مثال: tunnel.yourdomain.com): " tunnel_domain
    if [[ -z "$tunnel_domain" ]]; then
        echo -e "${C_RED}❌ نطاق النفق لا يمكن أن يكون فارغاً. جاري الإلغاء.${C_RESET}"
        return
    fi

    local forward_target
    echo -e "\n${C_CYAN}اختر الوجهة التي سيعيد DNSTT توجيه حركة المرور إليها:${C_RESET}"
    echo -e "  ${C_GREEN}[ 1]${C_RESET} SSH (المنفذ 22)"
    echo -e "  ${C_GREEN}[ 2]${C_RESET} V2Ray (المنفذ 8787 - بدون TLS)"
    read -p "👉 أدخل اختيارك [1]: " forward_choice
    forward_choice=${forward_choice:-1}

    local forward_desc
    if [[ "$forward_choice" == "1" ]]; then
        forward_target="127.0.0.1:22"
        forward_desc="SSH (المنفذ 22)"
    elif [[ "$forward_choice" == "2" ]]; then
        forward_target="127.0.0.1:8787"
        forward_desc="V2Ray (المنفذ 8787)"
    else
        echo -e "${C_RED}❌ اختيار غير صالح. جاري الإلغاء.${C_RESET}"
        return
    fi

    local mtu_value
    read -p "👉 أدخل قيمة MTU (عادة 1300-1400) [1350]: " mtu_value
    mtu_value=${mtu_value:-1350}
    if ! [[ "$mtu_value" =~ ^[0-9]+$ ]]; then
        echo -e "${C_RED}❌ قيمة MTU غير صالحة. جاري الإلغاء.${C_RESET}"
        return
    fi

    echo -e "\n${C_GREEN}📝 جاري إنشاء ملف خدمة systemd لـ DNSTT...${C_RESET}"
    cat > "$DNSTT_SERVICE_FILE" <<EOF
[Unit]
Description=DNSTT Server
After=network.target

[Service]
Type=simple
ExecStart=$DNSTT_BINARY -udp :53 -privkey "$private_key_file" -dom "$tunnel_domain" -mtu "$mtu_value" -sock "$forward_target"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    echo -e "\n${C_GREEN}💾 جاري حفظ معلومات تكوين DNSTT...${C_RESET}"
    cat > "$DNSTT_CONFIG_FILE" <<EOF
TUNNEL_DOMAIN="$tunnel_domain"
PUBLIC_KEY="$public_key"
FORWARD_TARGET="$forward_target"
FORWARD_DESC="$forward_desc"
MTU_VALUE="$mtu_value"
DNSTT_RECORDS_MANAGED="false"
EOF

    echo -e "\n${C_GREEN}▶️ جاري تمكين وبدء خدمة DNSTT...${C_RESET}"
    systemctl daemon-reload
    systemctl enable dnstt.service
    systemctl start dnstt.service
    sleep 2

    if systemctl is-active --quiet dnstt; then
        echo -e "\n${C_GREEN}✅ نجاح: تم تثبيت DNSTT ويعمل بنجاح.${C_RESET}"
        show_dnstt_details
        echo -e "${C_YELLOW}⚠️ تذكر أن تقوم بإنشاء سجل NS لنطاق النفق الفرعي ($tunnel_domain) يشير إلى عنوان IP الخاص بالخادم.${C_RESET}"
        echo -e "   يمكنك استخدام قائمة إدارة الدومينات لإنشاء سجل NS تلقائياً."
    else
        echo -e "\n${C_RED}❌ خطأ: فشلت خدمة DNSTT في البدء.${C_RESET}"
        echo -e "${C_YELLOW}ℹ️ عرض آخر 15 سطراً من سجل الخدمة للتشخيص:${C_RESET}"
        journalctl -u dnstt.service -n 15 --no-pager
    fi
}

# دالة لإلغاء تثبيت DNSTT
uninstall_dnstt() {
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🗑️ إلغاء تثبيت DNSTT ---${C_RESET}"
    if [ ! -f "$DNSTT_SERVICE_FILE" ]; then
        echo -e "${C_YELLOW}ℹ️ DNSTT غير مثبت، جاري التخطي.${C_RESET}"
        return
    fi

    echo -e "${C_GREEN}🛑 جاري إيقاف وتعطيل خدمة DNSTT...${C_RESET}"
    systemctl stop dnstt.service &>/dev/null
    systemctl disable dnstt.service &>/dev/null
    echo -e "${C_GREEN}🗑️ جاري إزالة ملف خدمة systemd...${C_RESET}"
    rm -f "$DNSTT_SERVICE_FILE"
    echo -e "${C_GREEN}🗑️ جاري إزالة الثنائي وملفات المفاتيح والتكوين...${C_RESET}"
    rm -f "$DNSTT_BINARY"
    rm -rf "$DNSTT_KEYS_DIR"
    rm -f "$DNSTT_CONFIG_FILE"
    systemctl daemon-reload
    
    echo -e "${C_YELLOW}ℹ️ جاري إعادة جعل /etc/resolv.conf قابلاً للكتابة مرة أخرى...${C_RESET}"
    chattr -i /etc/resolv.conf &>/dev/null

    echo -e "\n${C_GREEN}✅ تم إلغاء تثبيت DNSTT بنجاح.${C_RESET}"
}

# ==================================================================
# وظائف إدارة الدومينات (IONOS API)
# ==================================================================

# دالة لجلب وعرض جميع سجلات DNS من IONOS
ionos_list_records() {
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📋 سجلات DNS من IONOS ---${C_RESET}"
    echo -e "${C_BLUE}🌐 جاري جلب السجلات من $IONOS_BASE_DOMAIN...${C_RESET}"

    local response
    response=$(curl -s -X GET "$IONOS_BASE_URL/v1/zones/$IONOS_ZONE_ID/records" \
                     -H "X-API-Key: $IONOS_API_KEY" \
                     -H "Content-Type: application/json")

    if echo "$response" | jq -e 'has("messages")' > /dev/null; then
        echo -e "${C_RED}❌ خطأ في API: ${C_RESET}"
        echo "$response" | jq -r '.messages[].text' | sed 's/^/    /'
        return 1
    fi

    local record_count=$(echo "$response" | jq '.items | length')

    if [ "$record_count" -eq 0 ]; then
        echo -e "\n${C_YELLOW}ℹ️ لا توجد سجلات DNS لهذا النطاق.${C_RESET}"
        return 0
    fi

    echo -e "\n${C_CYAN}=====================================================================================================${C_RESET}"
    printf "${C_BOLD}${C_WHITE}%-3s | %-30s | %-5s | %-15s | %-10s | %-30s${C_RESET}\n" "#" "الاسم" "النوع" "المحتوى" "TTL" "ID"
    echo -e "${C_CYAN}-----------------------------------------------------------------------------------------------------"${C_RESET}

    echo "$response" | jq -r '.items[] | .id, .name, .type, .content, .ttl' | \
    while IFS=$'\n' read -r id && IFS=$'\n' read -r name && IFS=$'\n' read -r type && IFS=$'\n' read -r content && IFS=$'\n' read -r ttl; do
        local i=$((i+1))
        printf "${C_WHITE}%-3s ${C_RESET}| ${C_YELLOW}%-30s ${C_RESET}| ${C_GREEN}%-5s ${C_RESET}| ${C_CYAN}%-15s ${C_RESET}| %-10s | ${C_DIM}%-30s${C_RESET}\n" \
               "$i" "$name" "$type" "$content" "$ttl" "$id"
    done
    echo -e "${C_CYAN}=====================================================================================================${C_RESET}\n"
    return 0
}

# دالة لإنشاء سجلات DNS (A و NS)
ionos_create_records() {
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ➕ إنشاء سجلات DNS جديدة (IONOS) ---${C_RESET}"
    echo -e "${C_YELLOW}⚠️ سيتم إنشاء سجلين: سجل A يشير إلى IP الخادم الحالي، وسجل NS لنفق DNS.${C_RESET}"

    local sub_domain_name
    while true; do
        read -p "👉 أدخل الاسم الفرعي الذي تريده (مثال: jihad، سيصبح jihad.$IONOS_BASE_DOMAIN): " sub_domain_name
        if [[ -z "$sub_domain_name" ]]; then
            echo -e "${C_RED}❌ الاسم الفرعي لا يمكن أن يكون فارغاً.${C_RESET}"
        elif [[ "$sub_domain_name" =~ [^a-zA-Z0-9-] ]]; then
            echo -e "${C_RED}❌ الاسم الفرعي يجب أن يحتوي على أحرف إنجليزية وأرقام وشرطات فقط.${C_RESET}"
        else
            break
        fi
    done

    local full_domain_a="$sub_domain_name.$IONOS_BASE_DOMAIN"
    local full_domain_ns="tun.$sub_domain_name.$IONOS_BASE_DOMAIN"

    local server_ip
    server_ip=$(curl -s ipinfo.io/ip)
    if ! _is_valid_ipv4 "$server_ip"; then
        echo -e "${C_RED}❌ فشل الحصول على عنوان IP العام للخادم أو أنه غير صالح. جاري الإلغاء.${C_RESET}"
        return 1
    fi
    echo -e "${C_BLUE}ℹ️ تم الكشف عن عنوان IP للخادم: $server_ip${C_RESET}"

    echo -e "\n${C_BLUE}📝 جاري إعداد بيانات سجلات DNS...${C_RESET}"
    local json_payload="[
        {
            \"name\": \"$full_domain_a\",
            \"type\": \"A\",
            \"content\": \"$server_ip\",
            \"ttl\": 3600
        },
        {
            \"name\": \"$full_domain_ns\",
            \"type\": \"NS\",
            \"content\": \"$full_domain_a\",
            \"ttl\": 3600
        }
    ]"

    echo -e "${C_GREEN}🌐 جاري إرسال طلب إنشاء السجلات إلى IONOS API...${C_RESET}"
    local response
    response=$(curl -s -X POST "$IONOS_BASE_URL/v1/zones/$IONOS_ZONE_ID/records" \
                     -H "X-API-Key: $IONOS_API_KEY" \
                     -H "Content-Type: application/json" \
                     -d "$json_payload")

    if echo "$response" | jq -e 'has("messages")' > /dev/null; then
        echo -e "${C_RED}❌ خطأ في API أثناء إنشاء السجلات: ${C_RESET}"
        echo "$response" | jq -r '.messages[].text' | sed 's/^/    /'
        return 1
    else
        echo -e "\n${C_GREEN}✅ تم إنشاء سجلات DNS بنجاح!${C_RESET}"
        echo -e "${C_YELLOW}تم إنشاء سجل A لـ: $full_domain_a -> $server_ip${C_RESET}"
        echo -e "${C_YELLOW}تم إنشاء سجل NS لـ: $full_domain_ns -> $full_domain_a${C_RESET}"
        echo -e "${C_BLUE}ℹ️ قد يستغرق تحديث سجلات DNS بعض الوقت.${C_RESET}"
    fi
    return 0
}

# دالة لحذف سجلات DNS بذكاء
ionos_delete_records() {
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🗑️ حذف سجلات DNS (IONOS) ---${C_RESET}"
    echo -e "${C_YELLOW}⚠️ سيتم البحث عن جميع السجلات التي تحتوي على الاسم الذي تدخله وحذفها.${C_RESET}"

    local search_name
    while true; do
        read -p "👉 أدخل الاسم الكامل أو جزء من الاسم للسجلات التي تريد حذفها (مثال: jihad.02iuk.shop أو tun.jihad.02iuk.shop): " search_name
        if [[ -z "$search_name" ]]; then
            echo -e "${C_RED}❌ الاسم لا يمكن أن يكون فارغاً.${C_RESET}"
        else
            break
        fi
    done

    echo -e "${C_BLUE}🌐 جاري جلب السجلات للبحث عن '$search_name' في $IONOS_BASE_DOMAIN...${C_RESET}"
    local response
    response=$(curl -s -X GET "$IONOS_BASE_URL/v1/zones/$IONOS_ZONE_ID/records" \
                     -H "X-API-Key: $IONOS_API_KEY" \
                     -H "Content-Type: application/json")

    if echo "$response" | jq -e 'has("messages")' > /dev/null; then
        echo -e "${C_RED}❌ خطأ في API: ${C_RESET}"
        echo "$response" | jq -r '.messages[].text' | sed 's/^/    /'
        return 1
    fi

    local records_to_delete=()
    local record_ids=()
    local i=0
    while IFS=$'\n' read -r id && IFS=$'\n' read -r name && IFS=$'\n' read -r type && IFS=$'\n' read -r content && IFS=$'\n' read -r ttl; do
        if [[ "$name" == *"$search_name"* ]]; then
            records_to_delete+=("ID: $id, الاسم: $name, النوع: $type, المحتوى: $content")
            record_ids+=("$id")
        fi
    done < <(echo "$response" | jq -r '.items[] | .id, .name, .type, .content, .ttl')

    if [ ${#records_to_delete[@]} -eq 0 ]; then
        echo -e "\n${C_YELLOW}ℹ️ لم يتم العثور على سجلات مطابقة لـ '$search_name'.${C_RESET}"
        return 0
    fi

    echo -e "\n${C_YELLOW}⚠️ تم العثور على السجلات التالية للحذف:${C_RESET}"
    for record_info in "${records_to_delete[@]}"; do
        echo -e "  - ${C_RED}$record_info${C_RESET}"
    done

    read -p "👉 هل أنت متأكد أنك تريد حذف هذه السجلات؟ (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo -e "\n${C_YELLOW}❌ تم إلغاء الحذف.${C_RESET}"
        return
    fi

    for record_id in "${record_ids[@]}"; do
        echo -e "${C_BLUE}🗑️ جاري حذف السجل ID: $record_id...${C_RESET}"
        local delete_response
        delete_response=$(curl -s -X DELETE "$IONOS_BASE_URL/v1/zones/$IONOS_ZONE_ID/records/$record_id" \
                               -H "X-API-Key: $IONOS_API_KEY")
        
        if [ $? -eq 0 ] && [[ -z "$(echo "$delete_response" | grep -i 'error')" ]]; then
            echo -e "${C_GREEN}✅ تم حذف السجل ID: $record_id بنجاح.${C_RESET}"
        else
            echo -e "${C_RED}❌ فشل حذف السجل ID: $record_id. الاستجابة: $delete_response${C_RESET}"
        fi
    done
    echo -e "\n${C_GREEN}✅ اكتملت عملية حذف السجلات.${C_RESET}"
    return 0
}

# قائمة إدارة الدومينات الفرعية
domain_management_menu() {
    setup_ionos_keys
    while true; do
        show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- 🌐 إدارة الدومينات (IONOS) ---${C_RESET}"
        echo -e "${C_CYAN}=====================================================${C_RESET}"
        echo -e "${C_YELLOW}النطاق الأساسي: $IONOS_BASE_DOMAIN${C_RESET}"
        echo -e "\nاختر إجراءً:\n"
        printf "  ${C_GREEN}[ 1]${C_RESET} %-35s\n" "📋 عرض جميع سجلات DNS"
        printf "  ${C_GREEN}[ 2]${C_RESET} %-35s\n" "➕ إنشاء سجلات DNS (A و NS)"
        printf "  ${C_GREEN}[ 3]${C_RESET} %-35s\n" "🗑️ حذف سجلات DNS"
        echo -e "\n  ${C_RED}[ 0]${C_RESET} ↩️ العودة إلى القائمة الرئيسية"
        echo -e "${C_CYAN}=====================================================${C_RESET}\n"

        read -p "👉 أدخل اختيارك: " choice
        case $choice in
            1) ionos_list_records ;;
            2) ionos_create_records ;;
            3) ionos_delete_records ;;
            0) break ;;
            *) echo -e "\n${C_RED}❌ خيار غير صالح. يرجى المحاولة مرة أخرى.${C_RESET}" ;;
        esac
        echo -e "\nاضغط ${C_YELLOW}[Enter]${C_RESET} للمتابعة..." && read -r
    done
}

# ==================================================================
# وظائف SSH وإعداداته
# ==================================================================

# دالة لإدارة لافتة SSH
ssh_banner_menu() {
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📜 إدارة لافتة SSH ---${C_RESET}"
    echo -e "${C_CYAN}=====================================================${C_RESET}"
    echo -e "\nاختر إجراءً:\n"
    printf "  ${C_GREEN}[ 1]${C_RESET} %-35s\n" "➕ إنشاء/تعديل لافتة SSH"
    printf "  ${C_GREEN}[ 2]${C_RESET} %-35s\n" "🗑️ حذف لافتة SSH"
    printf "  ${C_GREEN}[ 3]${C_RESET} %-35s\n" "👀 عرض لافتة SSH الحالية"
    echo -e "\n  ${C_RED}[ 0]${C_RESET} ↩️ العودة إلى القائمة الرئيسية"
    echo -e "${C_CYAN}=====================================================${C_RESET}\n"

    read -p "👉 أدخل اختيارك: " choice
    case $choice in
        1) 
            echo -e "${C_BLUE}📝 أدخل النص الذي تريده للافتة SSH. اضغط Enter ثم Ctrl+D عند الانتهاء.${C_RESET}"
            cat > "$SSH_BANNER_FILE"
            echo -e "${C_GREEN}✅ تم حفظ لافتة SSH الجديدة.${C_RESET}"
            echo -e "${C_YELLOW}ℹ️ ستحتاج إلى إعادة تشغيل خدمة SSH لتطبيق التغييرات.${C_RESET}"
            read -p "👉 هل تريد إعادة تشغيل SSH الآن؟ (y/n): " restart_confirm
            if [[ "$restart_confirm" == "y" || "$restart_confirm" == "Y" ]]; then
                systemctl restart sshd &>/dev/null || service sshd restart &>/dev/null
                echo -e "${C_GREEN}✅ تم إعادة تشغيل خدمة SSH.${C_RESET}"
            fi
            ;;
        2) 
            if [ -f "$SSH_BANNER_FILE" ]; then
                read -p "👉 هل أنت متأكد أنك تريد حذف لافتة SSH؟ (y/n): " delete_confirm
                if [[ "$delete_confirm" == "y" || "$delete_confirm" == "Y" ]]; then
                    rm -f "$SSH_BANNER_FILE"
                    echo -e "${C_GREEN}✅ تم حذف لافتة SSH.${C_RESET}"
                    echo -e "${C_YELLOW}ℹ️ ستحتاج إلى إعادة تشغيل خدمة SSH لتطبيق التغييرات.${C_RESET}"
                    read -p "👉 هل تريد إعادة تشغيل SSH الآن؟ (y/n): " restart_confirm
                    if [[ "$restart_confirm" == "y" || "$restart_confirm" == "Y" ]]; then
                        systemctl restart sshd &>/dev/null || service sshd restart &>/dev/null
                        echo -e "${C_GREEN}✅ تم إعادة تشغيل خدمة SSH.${C_RESET}"
                    fi
                else
                    echo -e "${C_YELLOW}❌ تم إلغاء الحذف.${C_RESET}"
                fi
            else
                echo -e "${C_YELLOW}ℹ️ لا توجد لافتة SSH حالياً.${C_RESET}"
            fi
            ;;
        3) 
            if [ -f "$SSH_BANNER_FILE" ]; then
                echo -e "\n${C_BOLD}${C_CYAN}--- محتوى لافتة SSH الحالية ---${C_RESET}"
                cat "$SSH_BANNER_FILE"
                echo -e "${C_BOLD}${C_CYAN}-----------------------------------${C_RESET}\n"
            else
                echo -e "${C_YELLOW}ℹ️ لا توجد لافتة SSH حالياً.${C_RESET}"
            fi
            ;;
        0) break ;;
        *) echo -e "\n${C_RED}❌ خيار غير صالح. يرجى المحاولة مرة أخرى.${C_RESET}" ;;
    esac
    echo -e "\nاضغط ${C_YELLOW}[Enter]${C_RESET} للمتابعة..." && read -r
}

# ==================================================================
# وظائف مراقبة الاتصالات
# ==================================================================

# دالة لمراقبة الاتصالات الحية
simple_live_monitor() {
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📊 مراقبة الاتصالات الحية ---${C_RESET}"
    echo -e "${C_CYAN}=====================================================${C_RESET}"
    echo -e "${C_YELLOW}جاري عرض الاتصالات النشطة. اضغط Ctrl+C للإيقاف.${C_RESET}\n"

    echo -e "${C_BOLD}${C_WHITE}%-20s | %-15s | %-15s | %-10s${C_RESET}\n" "المستخدم" "من" "المنفذ" "PID"
    echo -e "${C_CYAN}----------------------------------------------------${C_RESET}"

    # استخدام watch لعرض الاتصالات المحدثة كل 2 ثانية
    watch -n 2 "ss -tnp | grep sshd | awk '{print \$6, \$5, \$7}' | sed -E 's/.*users:\(\"(.*)\",pid=([0-9]+),fd=.*\)/\1 \2/' | while read -r user_pid_info; do
        local user=$(echo \"$user_pid_info\" | awk '{print \$1}')
        local pid=$(echo \"$user_pid_info\" | awk '{print \$2}')
        local remote_ip_port=$(echo \"$user_pid_info\" | awk '{print \$3}')
        local remote_ip=$(echo \"$remote_ip_port\" | cut -d: -f1)
        local remote_port=$(echo \"$remote_ip_port\" | cut -d: -f2)
        printf \"${C_WHITE}%-20s ${C_RESET}| ${C_YELLOW}%-15s ${C_RESET}| ${C_GREEN}%-15s ${C_RESET}| ${C_CYAN}%-10s${C_RESET}\\n\" \"$user\" \"$remote_ip\" \"$remote_port\" \"$pid\"
    done"

    echo -e "\n${C_GREEN}✅ انتهت مراقبة الاتصالات الحية.${C_RESET}\n"
}

# ==================================================================
# القائمة الرئيسية
# ==================================================================

main_menu() {
    while true; do
        show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- القائمة الرئيسية لـ Jihad Manager ---${C_RESET}"
        echo -e "${C_CYAN}=====================================================${C_RESET}"
        echo -e "\nاختر وظيفة:\n"
        printf "  ${C_GREEN}[ 1]${C_RESET} %-35s\n" "👤 إدارة المستخدمين"
        printf "  ${C_GREEN}[ 2]${C_RESET} %-35s\n" "📡 DNSTT (أنفاق DNS / Slow DNS)"
        printf "  ${C_GREEN}[ 3]${C_RESET} %-35s\n" "🌐 إدارة الدومينات (IONOS API)"
        printf "  ${C_GREEN}[ 4]${C_RESET} %-35s\n" "⚙️ إعدادات SSH"
        printf "  ${C_GREEN}[ 5]${C_RESET} %-35s\n" "📊 مراقبة الاتصالات"
        echo -e "\n  ${C_RED}[ 0]${C_RESET} ↩️ خروج"
        echo -e "${C_CYAN}=====================================================${C_RESET}\n"

        read -p "👉 أدخل اختيارك: " choice
        case $choice in
            1) user_management_menu ;;
            2) dnstt_menu ;;
            3) domain_management_menu ;;
            4) ssh_settings_menu ;;
            5) simple_live_monitor ;;
            0) 
                echo -e "\n${C_GREEN}👋 شكراً لاستخدامك Jihad Manager. إلى اللقاء!${C_RESET}\n"
                exit 0
                ;;
            *) echo -e "\n${C_RED}❌ خيار غير صالح. يرجى المحاولة مرة أخرى.${C_RESET}" ;;
        esac
        echo -e "\nاضغط ${C_YELLOW}[Enter]${C_RESET} للعودة إلى القائمة الرئيسية..." && read -r
    done
}

# ==================================================================
# القوائم الفرعية
# ==================================================================

user_management_menu() {
    while true; do
        show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- 👤 إدارة المستخدمين ---${C_RESET}"
        echo -e "${C_CYAN}=====================================================${C_RESET}"
        echo -e "\nاختر إجراءً:\n"
        printf "  ${C_GREEN}[ 1]${C_RESET} %-35s\n" "➕ إنشاء مستخدم جديد"
        printf "  ${C_GREEN}[ 2]${C_RESET} %-35s\n" "🗑️ حذف مستخدم"
        printf "  ${C_GREEN}[ 3]${C_RESET} %-35s\n" "✏️ تعديل مستخدم"
        printf "  ${C_GREEN}[ 4]${C_RESET} %-35s\n" "🔒 قفل مستخدم"
        printf "  ${C_GREEN}[ 5]${C_RESET} %-35s\n" "🔓 فتح مستخدم"
        printf "  ${C_GREEN}[ 6]${C_RESET} %-35s\n" "🔄 تجديد صلاحية مستخدم"
        printf "  ${C_GREEN}[ 7]${C_RESET} %-35s\n" "📋 عرض قائمة المستخدمين"
        printf "  ${C_GREEN}[ 8]${C_RESET} %-35s\n" "🧹 تنظيف المستخدمين منتهية الصلاحية"
        echo -e "\n  ${C_RED}[ 0]${C_RESET} ↩️ العودة إلى القائمة الرئيسية"
        echo -e "${C_CYAN}=====================================================${C_RESET}\n"

        read -p "👉 أدخل اختيارك: " choice
        case $choice in
            1) create_user ;;
            2) delete_user ;;
            3) edit_user ;;
            4) lock_user ;;
            5) unlock_user ;;
            6) renew_user ;;
            7) list_users ;;
            8) cleanup_expired ;;
            0) break ;;
            *) echo -e "\n${C_RED}❌ خيار غير صالح. يرجى المحاولة مرة أخرى.${C_RESET}" ;;
        esac
        echo -e "\nاضغط ${C_YELLOW}[Enter]${C_RESET} للمتابعة..." && read -r
    done
}

dnstt_menu() {
    while true; do
        show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- 📡 DNSTT (أنفاق DNS / Slow DNS) ---${C_RESET}"
        echo -e "${C_CYAN}=====================================================${C_RESET}"
        echo -e "\nاختر إجراءً:\n"
        printf "  ${C_GREEN}[ 1]${C_RESET} %-35s\n" "🚀 تثبيت/تكوين DNSTT"
        printf "  ${C_GREEN}[ 2]${C_RESET} %-35s\n" "📋 عرض تفاصيل DNSTT"
        printf "  ${C_GREEN}[ 3]${C_RESET} %-35s\n" "🗑️ إلغاء تثبيت DNSTT"
        echo -e "\n  ${C_RED}[ 0]${C_RESET} ↩️ العودة إلى القائمة الرئيسية"
        echo -e "${C_CYAN}=====================================================${C_RESET}\n"

        read -p "👉 أدخل اختيارك: " choice
        case $choice in
            1) install_dnstt ;;
            2) show_dnstt_details ;;
            3) uninstall_dnstt ;;
            0) break ;;
            *) echo -e "\n${C_RED}❌ خيار غير صالح. يرجى المحاولة مرة أخرى.${C_RESET}" ;;
        esac
        echo -e "\nاضغط ${C_YELLOW}[Enter]${C_RESET} للمتابعة..." && read -r
    done
}

ssh_settings_menu() {
    while true; do
        show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- ⚙️ إعدادات SSH ---${C_RESET}"
        echo -e "${C_CYAN}=====================================================${C_RESET}"
        echo -e "\nاختر إجراءً:\n"
        printf "  ${C_GREEN}[ 1]${C_RESET} %-35s\n" "📜 إدارة لافتة SSH (SSH Banner)"
        echo -e "\n  ${C_RED}[ 0]${C_RESET} ↩️ العودة إلى القائمة الرئيسية"
        echo -e "${C_CYAN}=====================================================${C_RESET}\n"

        read -p "👉 أدخل اختيارك: " choice
        case $choice in
            1) ssh_banner_menu ;;
            0) break ;;
            *) echo -e "\n${C_RED}❌ خيار غير صالح. يرجى المحاولة مرة أخرى.${C_RESET}" ;;
        esac
        echo -e "\nاضغط ${C_YELLOW}[Enter]${C_RESET} للمتابعة..." && read -r
    done
}

# ==================================================================
# نقطة الدخول للسكربت
# ==================================================================

# إذا تم استدعاء السكربت مع وسيط '--install-setup'، قم بتشغيل الإعداد الأولي
if [[ "$1" == "--install-setup" ]]; then
    initial_setup
else
    # وإلا، اعرض القائمة الرئيسية
    main_menu
fi
