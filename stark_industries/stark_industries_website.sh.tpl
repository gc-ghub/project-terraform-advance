#!/bin/bash
set -e

# Detect OS and install Nginx
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" == "ubuntu" ]]; then
        apt update -y
        apt install -y nginx curl
        systemctl enable nginx
        systemctl start nginx
        WEBROOT="/var/www/html"
    elif [[ "$ID" == "amzn" || "$ID" == "amazon" ]]; then
        yum update -y
        amazon-linux-extras install nginx1 -y
        yum install -y curl
        systemctl enable nginx
        systemctl start nginx
        WEBROOT="/usr/share/nginx/html"
    else
        echo "Unsupported OS: $ID"
        exit 1
    fi
fi

# Fetch instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "none")

# Create Stark Industries HTML Page
cat <<'EOF' > /tmp/index.html.template
<!DOCTYPE html>
<html>
<head>
<title>Welcome to Stark Industries</title>
<meta charset="UTF-8">

<style>
body {
  background-color: #0b0b0b;
  color: #00eaff;
  font-family: Arial, Helvetica, sans-serif;
  margin: 0;
  padding: 0;
}

/* --- HEADER --- */
.header {
  text-align: center;
  padding-top: 50px;
}

h1 {
  font-size: 60px;
  text-transform: uppercase;
  letter-spacing: 5px;
  margin-bottom: 10px;
  animation: glow 2s infinite alternate;
  cursor: pointer;
}

@keyframes glow {
  from { text-shadow: 0 0 10px #00eaff; }
  to { text-shadow: 0 0 30px #00eaff, 0 0 60px #00eaff; }
}

h2 {
  font-size: 26px;
  font-weight: 300;
  color: #9aefff;
}

/* --- ARC REACTOR SMALL + TOP LEFT --- */
.arc-reactor {
  position: absolute;
  top: 20px;
  left: 20px;
  width: 100px;
  height: 100px;
  border-radius: 50%;
  border: 6px solid #00eaff;
  box-shadow: 0 0 20px #00eaff, inset 0 0 20px #00eaff;
  animation: spin 6s linear infinite;
}

.core {
  width: 55px;
  height: 55px;
  margin: 17px auto;
  border-radius: 50%;
  background: radial-gradient(circle, #00eaff, #003f4f, #000);
  box-shadow: 0 0 20px #00eaff;
  animation: pulse 2s infinite alternate;
}

@keyframes spin {
  0%   { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}

@keyframes pulse {
  from { transform: scale(1); }
  to   { transform: scale(1.08); }
}

/* --- MAIN EC2 METADATA BOX --- */
.metadata-box {
  width: 60%;
  margin: 50px auto 20px auto;
  padding: 20px;
  background: rgba(255,255,255,0.05);
  border: 1px solid rgba(0,234,255,0.2);
  border-radius: 12px;
  text-align: left;
  color: #d9ffff;
}
.metadata-box h3 {
  text-align: center; 
  color: #86f7ff;
}

/* --- TWO COLUMN LAYOUT --- */
.columns {
  display: flex;
  justify-content: center;
  gap: 30px;
  width: 90%;
  margin: 40px auto;
}

.column {
  flex: 1;
  background: rgba(255,255,255,0.05);
  border: 1px solid rgba(0,234,255,0.2);
  padding: 20px;
  border-radius: 12px;
  color: #d9ffff;
}

.column h3 {
  text-align: center;
  color: #86f7ff;
  margin-top: 0;
}

/* Result boxes */
pre {
  background: rgba(0,0,0,0.4);
  padding: 15px;
  border-radius: 10px;
  border: 1px solid #00eaff33;
  white-space: pre-wrap;
  color: #9aefff;
}

/* Buttons */
button {
  padding: 12px 24px;
  background-color: #00eaff;
  border: none;
  border-radius: 8px;
  color: black;
  font-size: 18px;
  font-weight: bold;
  cursor: pointer;
  margin: 10px 0;
  box-shadow: 0 0 15px #00eaff;
}
</style>
</head>

<body>

<!-- ARC REACTOR -->
<div class="arc-reactor"><div class="core"></div></div>

<!-- HEADER -->
<div class="header">
  <h1 onclick="location.href='/'">Stark Industries</h1>
  <h2>{{PROJECT_NAME}} — {{ENVIRONMENT_NAME}}</h2>
</div>

<!-- EC2 METADATA -->
<div class="metadata-box">
  <h3>EC2 Instance Metadata</h3>
  <p><b>Instance ID:</b> {{INSTANCE_ID}}</p>
  <p><b>Public IP:</b> {{PUBLIC_IP}}</p>
</div>

<!-- TWO COLUMNS -->
<div class="columns">

  <!-- LEFT COLUMN -->
  <div class="column">
    <h3>Live API Metadata</h3>
    <button onclick="fetchMetadata()">🚀 Fetch Live Metadata</button>
    <pre id="apiResult">Click the button to load data...</pre>
  </div>

  <!-- RIGHT COLUMN -->
  <div class="column">
    <h3>Upload a File to S3</h3>
    <input type="file" id="fileInput" />
    <button onclick="startUpload()">📤 Upload File</button>
    <pre id="uploadStatus">No upload started.</pre>
  </div>

</div>

<script>
const METADATA_API = "{{API_URL}}";
const PRESIGN_API  = "{{UPLOAD_API_URL}}";

async function fetchMetadata() {
  const output = document.getElementById("apiResult");
  output.innerHTML = "Fetching metadata...";
  try {
    const res = await fetch(METADATA_API);
    output.innerHTML = JSON.stringify(await res.json(), null, 2);
  } catch (err) {
    output.innerHTML = "Error: " + err;
  }
}

async function startUpload() {
  const file = document.getElementById("fileInput").files[0];
  const status = document.getElementById("uploadStatus");

  if (!file) {
    status.innerText = "❗ Select a file first.";
    return;
  }

  status.innerText = "Requesting presigned URL...";

  try {
    const presign = await fetch(PRESIGN_API, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({
        filename: file.name,
        content_type: file.type
      })
    });

    const data = await presign.json();

    if (!data.url) {
      status.innerText = "Failed: " + JSON.stringify(data);
      return;
    }

    status.innerText = "Uploading to S3...";

    const upload = await fetch(data.url, {
      method: "PUT",
      headers: {"Content-Type": file.type},
      body: file
    });

    if (!upload.ok) {
      status.innerText = "Upload failed: " + upload.statusText;
      return;
    }

    /* VS CODE FRIENDLY (NO RED LINES) */
    status.innerText = `✅ Upload successful!
S3 Key: $${data.key}
Replication → Lambda → DynamoDB → SNS will trigger shortly.`;

  } catch (err) {
    status.innerText = "Error: " + err;
  }
}
</script>

</body>
</html>
EOF

# Replace tokens using sed
sed -e "s|{{PROJECT_NAME}}|${project_name}|g" \
    -e "s|{{ENVIRONMENT_NAME}}|${environment_name}|g" \
    -e "s|{{INSTANCE_ID}}|$INSTANCE_ID|g" \
    -e "s|{{PUBLIC_IP}}|$PUBLIC_IP|g" \
    -e "s|{{API_URL}}|${api_url}|g" \
    -e "s|{{UPLOAD_API_URL}}|${upload_api_url}|g" \
    /tmp/index.html.template > $${WEBROOT}/index.html

systemctl restart nginx
