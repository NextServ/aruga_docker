# 🧾 ARUGA Accounting & Payroll
Local Docker Edition  
Version v0.0.2
Owned by: SERVIO TECHNOLOGIES
==================================================
1. ⚙️ SYSTEM OVERVIEW
==================================================

ARUGA is a local accounting and payroll system built on:

- 🏗️ Frappe Framework
- 📊 ERPNext
- 👥 HRMS
- 🛠️ Custom ARUGA Modules

The system runs entirely inside Docker containers on your computer.  
🌐 No internet connection is required after installation.

--------------------------------------------------

==================================================
2. 🌐 ACCESSING ARUGA
==================================================

Open your browser and go to:


➡️ [http://localhost:8080](http://localhost:8080)

Login Credentials:

- 👤 Username: Administrator  
- 🔑 Password: servio_aruga

⚠️ **IMPORTANT:** Change your Administrator password after first login.

--------------------------------------------------

==================================================
3. 🐳 DOCKER INFORMATION
==================================================

ARUGA runs using Docker containers.

To check running containers:

    docker ps

You should see containers like:

🖥️ backend

💾 db

🔄 redis

🌐 nginx
--------------------------------------------------

START ARUGA (if stopped):

    docker compose -f compose/compose.custom_local.yaml up -d

STOP ARUGA:

    docker compose -f compose/compose.custom_local.yaml down

RESTART ARUGA:

    docker compose -f compose/compose.custom_local.yaml restart

--------------------------------------------------

==================================================
4. 🗄️ DATABASE INFORMATION
==================================================

Database: MariaDB (inside Docker)

🔑 Root Password (internal only): frappe

⚙️ You do NOT need to manage the database manually.

--------------------------------------------------

==================================================
5. 🗂️ INSTALLATION LOCATION
==================================================

Installed Directory:

C:\Users\<YourUser>\aruga_docker

Important folders:

compose/
apps/
sites/
README.md

--------------------------------------------------

==================================================
6. ⚠️ RESETTING SYSTEM (WARNING)
==================================================

To completely reset ARUGA and delete ALL data:

    docker compose -f compose/compose.custom_local.yaml down -v

This deletes:
- Database
- Uploaded files
- All accounting data

Use carefully.

--------------------------------------------------

==================================================
7. 💾 BACKUP & RESTORE
==================================================

To create a backup:

    docker compose -f compose/compose.custom_local.yaml exec backend bench --site localhost backup

Backup files will be inside:

sites/localhost/private/backups/

--------------------------------------------------

==================================================
8. 🛠️ TROUBLESHOOTING
==================================================

If ARUGA does not open:

1. Make sure Docker Desktop is running.
2. Run:
       docker ps
3. If containers are not running:
       docker compose -f compose/compose.custom_local.yaml up -d
4. Restart Docker Desktop if needed.

If port 8080 does not open:
Make sure no other application is using port 8080.

--------------------------------------------------

==================================================
9. 🧩 INSTALLED APPLICATION
==================================================

Core:
- frappe
- erpnext
- hrms

Custom:
- aruga_acct
- aruga_pay
- aruga_main

--------------------------------------------------

==================================================
10. 📞 SUPPORT
==================================================

ARUGA Local Edition
For technical support contact your system provider.

This system runs locally on your computer.

==================================================
🏁 END OF GUIDE
==================================================
