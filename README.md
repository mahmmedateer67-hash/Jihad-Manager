# 🚀 Jihad Manager

**Jihad Manager** is a comprehensive server management tool designed for easy VPN/tunnel setup and user management on Linux servers.

---

## ✨ Features

- **User Management** — Create, delete, renew, lock/unlock users with connection limits
- **DNSTT (DNS Tunneling / Slow DNS)** — Full DNS tunnel setup with key generation
- **Domain Management (IONOS API)** — Create/delete DNS records (A & NS) automatically
- **SSH Configuration** — Custom SSH settings with banner support
- **Connection Monitoring** — Real-time traffic and connection monitoring

---

## ⚡ Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/mahmmedateer67-hash/Jihad-Manager/main/jihad_install.sh)
```

---

## 📋 Usage

After installation, simply type:

```bash
jihad
```

---

## 🔐 Security

- API keys are stored locally in `/etc/jihad/ionos.conf` (never uploaded to GitHub)
- SSH configuration includes security hardening
- All credentials are prompted on first use and saved securely

---

## 📁 Project Structure

```
Jihad-Manager/
├── jihad_install.sh    # Main installer script
├── jihad_menu.sh       # Main menu script (all features)
├── ssh/
│   └── sshd_config     # Custom SSH configuration
├── docs/
│   └── jihad_guide.md  # Full Arabic usage guide
├── LICENSE             # MIT License
└── README.md           # This file
```

---

## 🌐 دليل الاستخدام بالعربية

للاطلاع على الدليل الكامل بالعربية: [docs/jihad_guide.md](docs/jihad_guide.md)

### التثبيت السريع:
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/mahmmedateer67-hash/Jihad-Manager/main/jihad_install.sh)
```

### بعد التثبيت اكتب:
```bash
jihad
```

---

## 📄 License

MIT License — See [LICENSE](LICENSE) for details.

---

**Developed by Jihad** 🛡️
