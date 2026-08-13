# 🚀 openSUSE Tumbleweed Post-Install Script

A comprehensive, automated configuration script (`install.sh`) designed for fresh installations of **openSUSE Tumbleweed**. The script fully automates the process of system optimization, adding key repositories, updating packages, installing software (multimedia, tools, gaming), and customizing the terminal shell.

## ⚡ Main Features

### 1. Repository Management & System Update
* **PackageKit lock:** Temporarily stops background services to avoid conflicts with the Zypper database.
* **Extra repositories:** Automatically adds **Packman** (codecs), **Games**, **Emulators**, **Emulators:Wine**, **Google Chrome**, and **Brave Browser** repositories.
* **Full upgrade:** Performs a full distribution upgrade (`zypper dup`) with vendor changes allowed (`--allow-vendor-change`).

### 2. Software Installation & Cleanup
* **Browsers:** Google Chrome and Brave Browser.
* **Bloatware removal:** Removes unnecessary pre-installed packages (e.g. `nano`, `opensuse-welcome-launcher`, `qrca`).
* **Main application set (64-bit):** System tools (`fastfetch`, `git`, `mc`), multimedia (`gimp`, `kdenlive`, `audacity`, `elisa`, `mixxx`), messaging apps (`telegram-desktop`, `qbittorrent`), and developer tools (`cmake`, `meson`).
* **External packages:** Automatically downloads the latest RPM packages from GitHub releases (`ls-fg`, `ls-fg-vk`), dedicated **Discord** installation, and a gaming launcher via **Flatpak** (`Faugus Launcher`).

### 3. Automatic GPU Detection & Early KMS
* The script automatically identifies the installed graphics card (**NVIDIA**, **AMD**, or **Intel**).
* Configures the appropriate kernel modules in `dracut` for **Early KMS** (early graphics mode loading).
* Installs required 32-bit libraries for optimal gaming and compatibility layer performance (e.g. `wine-staging-32bit`, `mangohud-32bit`, `libgamemodeauto0-32bit`).

### 4. Virtualization & Firewall
* Installs a complete virtualization stack: `virt-manager`, `qemu-kvm`, `libvirt`, and UEFI packages (`OVMF`).
* Automatically adds the current user to the `libvirt` and `kvm` system groups (manage VMs without root privileges).
* Configures `firewalld` (adds the `virbr0` virtual interface to the appropriate zone along with network rules).

### 5. System Optimization & Personalization
* **SSD optimization:** Enables the periodic `fstrim.timer` service for block-level SSD trimming.
* **Log cleanup:** Clears the `journalctl` system journal (retaining only the last 2 days of logs).
* **Hide systemd-boot:** If the system uses `systemd-boot`, the script configures it to boot the default entry instantly (`timeout 0`).
* **Fast DNS:** Configures Cloudflare's secure and fast DNS servers (`1.1.1.1` and `1.0.0.1`) directly in NetworkManager.
* **Modern Terminal (ZSH):** Installs the ZSH shell, the **Oh My Zsh** framework, and the **Powerlevel10k** theme. The script also enforces Polish character encoding (`pl_PL.UTF-8`) and adds an automatic `fastfetch` call on every terminal launch.

---

## 🚀 How to Run

> ⚠️ **IMPORTANT:** Do **NOT** run this script directly from the root account (e.g. via `su` or `sudo ./install.sh`). Run it as a regular user — the script will request administrator privileges at the appropriate moment.
>
> 🔄 **NOTE:** After all tasks complete successfully, the script will **automatically restart the system** after 3 seconds to apply configuration changes (user groups, kernel modules, DNS).

Run the following commands in your terminal:

# 1. Clone your repository
```bash
git clone https://github.com/bartko4321/opensuse-config.git
```


# 2. Enter the downloaded folder
```bash
cd opensuse-config
```

# 3. Make the install.sh script executable
```bash
chmod +x install.sh
```

# 4. Run the script as a regular user
```bash
./install.sh
```

---

### ☕ Support the Project

If you find this tool helpful and it saved you some time, consider buying me a coffee to support further development! 

[![Buy Me A Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://buymeacoffee.com/bartekszczecinski)

---

## 🔒 Security & Sudo Permissions

At startup, the script creates a temporary config file `/etc/sudoers.d/99-temp-installer`, which allows the Zypper package manager to install software without prompting for the user's password throughout the lengthy installation process. This file is **completely and safely removed** at the end of the script, just before the machine reboots.

---
If you find this project useful, leave a star! ⭐

## 📄 License

This project is released under the free MIT License. You are free to modify and adapt it to your own needs.
