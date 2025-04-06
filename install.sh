#!/bin/bash

# رنگ‌ها برای نمایش زیبا
GREEN='\033[0;32m'
NC='\033[0m'

clear
echo -e "${GREEN}Torrent-to-OneDrive نصب در حال شروع است...${NC}"

# نصب پیش‌نیازها
sudo apt update
sudo apt install -y python3 python3-pip python3-venv git curl unzip

# ایجاد فولدر پروژه
mkdir -p /opt/torrent2onedrive && cd /opt/torrent2onedrive

# کلون بک‌اند
echo -e "${GREEN}دریافت بک‌اند FastAPI...${NC}"
git clone https://github.com/your-backend-repo-url backend
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# اضافه کردن API انتقال فایل با rclone
echo -e "${GREEN}ساخت upload_to_onedrive.py...${NC}"
cat <<EOF > app/api/upload_to_onedrive.py
from fastapi import APIRouter
import subprocess

router = APIRouter()

@router.post("/upload-to-onedrive")
def upload_to_onedrive(local_path: str, remote_path: str = ""):
    remote = f"onedrive:{remote_path}" if remote_path else "onedrive:"
    try:
        result = subprocess.run(
            ["rclone", "move", local_path, remote, "--progress"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        return {"stdout": result.stdout, "stderr": result.stderr}
    except Exception as e:
        return {"error": str(e)}
EOF

# ثبت روت در main.py
sed -i "/from fastapi import FastAPI/a from app.api import upload_to_onedrive" main.py
sed -i "/app = FastAPI()/a app.include_router(upload_to_onedrive.router)" main.py

# راه‌اندازی بک‌اند به صورت systemd
cat <<EOF | sudo tee /etc/systemd/system/torrent-backend.service
[Unit]
Description=Torrent2OneDrive Backend
After=network.target

[Service]
User=root
WorkingDirectory=/opt/torrent2onedrive/backend
ExecStart=/opt/torrent2onedrive/backend/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable torrent-backend
sudo systemctl start torrent-backend

# نصب rclone
echo -e "${GREEN}نصب rclone...${NC}"
curl https://rclone.org/install.sh | sudo bash

# ایجاد مسیر کانفیگ rclone اگر وجود نداشت
mkdir -p /root/.config/rclone

# اگر فایل کانفیگ داری، می‌تونی اینجا قرار بدی، یا در مراحل بعدی دستی auth کنی
# nano /root/.config/rclone/rclone.conf

# نصب Node.js و فرانت‌اند
echo -e "${GREEN}نصب فرانت React + Vite...${NC}"
cd /opt/torrent2onedrive
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

npm create vite@latest frontend -- --template react
cd frontend
npm install
npm install axios
npm install -D tailwindcss postcss autoprefixer
npx tailwindcss init -p

# اضافه کردن تنظیمات Tailwind
sed -i 's/content: \[\]/content: [".\/index.html", ".\/src\/.**\/*.{js,ts,jsx,tsx}"]/' tailwind.config.js

# ساخت فایل‌های اولیه و آماده‌سازی
mkdir -p src
cat <<EOF > src/index.css
@tailwind base;
@tailwind components;
@tailwind utilities;
EOF

cat <<EOF > src/App.jsx
import { useState } from "react";
import axios from "axios";

function App() {
  const [localPath, setLocalPath] = useState("");
  const [remotePath, setRemotePath] = useState("");
  const [response, setResponse] = useState("");

  const handleUpload = async () => {
    try {
      const res = await axios.post("http://localhost:8000/upload-to-onedrive", {
        local_path: localPath,
        remote_path: remotePath,
      });
      setResponse(JSON.stringify(res.data, null, 2));
    } catch (err) {
      setResponse(err.message);
    }
  };

  return (
    <div className="min-h-screen p-6 bg-gray-100">
      <div className="max-w-xl mx-auto bg-white rounded-2xl shadow p-4">
        <h1 className="text-2xl font-bold mb-4">🚀 آپلود به OneDrive</h1>
        <input
          type="text"
          placeholder="مسیر فایل محلی"
          className="w-full mb-2 p-2 border rounded"
          value={localPath}
          onChange={(e) => setLocalPath(e.target.value)}
        />
        <input
          type="text"
          placeholder="مسیر در OneDrive (اختیاری)"
          className="w-full mb-2 p-2 border rounded"
          value={remotePath}
          onChange={(e) => setRemotePath(e.target.value)}
        />
        <button
          className="bg-blue-500 hover:bg-blue-600 text-white px-4 py-2 rounded"
          onClick={handleUpload}
        >
          آپلود
        </button>
        {response && (
          <pre className="bg-gray-200 p-2 mt-4 rounded text-sm overflow-auto">
            {response}
          </pre>
        )}
      </div>
    </div>
  );
}

export default App;
EOF

cat <<EOF > src/main.jsx
import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import "./index.css";

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
EOF

cat <<EOF > index.html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Torrent2OneDrive</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
EOF

# اجرای dev سرور
npm run dev

echo -e "${GREEN}✅ نصب با موفقیت انجام شد!${NC}"
echo -e "📡 بک‌اند روی http://localhost:8000"
echo -e "🎯 فرانت روی http://localhost:5173"
echo -e "📂 تنظیمات rclone در مسیر /root/.config/rclone/rclone.conf ذخیره میشه"
