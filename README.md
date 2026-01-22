# ssh-rsync-bridge

Secure server-to-server file transfer using **rsync over SSH with temporary keys**.

The data is transferred **directly between servers**, your local machine is used only for orchestration and never acts as a buffer.

---

## ✨ Features

- Server A → Server B rsync (no local data transfer)
- Temporary SSH keys generated per run
- Automatic key cleanup after completion
- Works with password or SSH-key login
- Uses standard Linux tools only (`ssh`, `rsync`)
- Safe cleanup even on failure (`trap`)

---

## 🧠 How it works


1. Script generates a temporary SSH key locally
2. Key is installed on both servers
3. Source server generates a temporary rsync key
4. That key is authorized on destination server
5. `rsync` runs directly from Server A → Server B
6. All temporary keys are removed automatically

---

## ⚙️ Configuration

### ✅ What you need to do

1. Copy the example file:

```bash
cp env.example .env