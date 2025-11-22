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
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "none")
INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)
AMI_ID=$(curl -s http://169.254.169.254/latest/meta-data/ami-id)

# Create Stark Industries HTML Page
cat <<EOF > $${WEBROOT}/index.html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to Stark Industries | ${project_name} | ${environment_name}</title>
<meta charset="UTF-8">
<style>

body {
  background-color: #0b0b0b;
  color: #00eaff;
  font-family: Arial, Helvetica, sans-serif;
  text-align: center;
  padding-top: 50px;
  margin: 0;
}

h1 {
  font-size: 60px;
  text-transform: uppercase;
  letter-spacing: 5px;
  margin-bottom: 10px;
  animation: glow 2s infinite alternate;
}

@keyframes glow {
  from { text-shadow: 0 0 10px #00eaff; }
  to { text-shadow: 0 0 30px #00eaff, 0 0 60px #00eaff; }
}

h2 {
  font-size: 26px;
  font-weight: 300;
  margin-bottom: 30px;
  color: #9aefff;
}

.arc-reactor {
  margin: 40px auto;
  width: 260px;
  height: 260px;
  border-radius: 50%;
  border: 12px solid #00eaff;
  box-shadow: 0 0 30px #00eaff, inset 0 0 30px #00eaff;
  animation: spin 6s linear infinite;
}

.core {
  width: 140px;
  height: 140px;
  margin: 0 auto;
  margin-top: 52px;
  border-radius: 50%;
  background: radial-gradient(circle, #00eaff, #003f4f, #000);
  box-shadow: 0 0 40px #00eaff;
  animation: pulse 2s infinite alternate;
}

@keyframes spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}

@keyframes pulse {
  from { transform: scale(1); }
  to { transform: scale(1.08); }
}

.metadata {
  margin: 40px auto;
  background: rgba(255,255,255,0.05);
  border: 1px solid rgba(0,234,255,0.2);
  padding: 20px;
  width: 60%;
  border-radius: 12px;
  color: #d9ffff;
  text-align: left;
}

.metadata h3 {
  text-align: center;
  margin-bottom: 20px;
  color: #86f7ff;
}

.metadata p {
  font-size: 16px;
  margin: 8px 0;
}

#apiResult {
  background: rgba(0,0,0,0.4);
  padding: 15px;
  border-radius: 10px;
  color: #9aefff;
  font-size: 14px;
  white-space: pre-wrap;
  border: 1px solid #00eaff33;
  margin-top: 20px;
}

button.fetch-btn, button.upload-btn {
  padding: 12px 24px;
  background-color: #00eaff;
  border: none;
  border-radius: 8px;
  color: black;
  font-size: 18px;
  font-weight: bold;
  cursor: pointer;
  margin-bottom: 20px;
  box-shadow: 0 0 15px #00eaff;
}

#uploadStatus {
  background: rgba(0,0,0,0.4);
  padding: 10px;
  border-radius: 10px;
  color: #9aefff;
  border: 1px solid #00eaff33;
  white-space: pre-wrap;
}

.footer {
  margin-top: 50px;
  font-size: 14px;
  color: #7fbbc7;
}

</style>
</head>
<body>

<h1>Stark Industries</h1>
<h2>${project_name} — ${environment_name}</h2>

<div class="arc-reactor">
  <div class="core"></div>
</div>

<div class="metadata">
  <h3>EC2 Instance Metadata</h3>

  <p><b>Instance ID:</b> ${"$"}{INSTANCE_ID}</p>
  <p><b>Public IP:</b> ${"$"}{PUBLIC_IP}</p>

  <h3>Live API Metadata</h3>

  <button class="fetch-btn" onclick="fetchMetadata()">🚀 Fetch Live Metadata</button>

  <pre id="apiResult">Click the button to load data...</pre>

  <!-- 🚀 NEW SECTION — S3 UPLOAD UI -->
  <h3>Upload a File to S3</h3>
  <input type="file" id="fileInput" />
  <button class="upload-btn" onclick="startUpload()">📤 Upload File</button>
  <pre id="uploadStatus">No upload started.</pre>
</div>

<script>
async function fetchMetadata() {
  const output = document.getElementById("apiResult");
  output.innerHTML = "Fetching metadata from Stark API...";
  try {
    const response = await fetch("${api_url}");
    const data = await response.json();
    output.innerHTML = JSON.stringify(data, null, 2);
  } catch (err) {
    output.innerHTML = "Error: " + err;
  }
}

/* ⭐ NEW FUNCTION — S3 UPLOAD */
async function startUpload() {
  const file = document.getElementById("fileInput").files[0];
  const status = document.getElementById("uploadStatus");

  if (!file) {
    status.innerText = "❗ Select a file first.";
    return;
  }

  status.innerText = "Requesting presigned URL...";

  try {
    // request presigned URL from your new API Gateway endpoint
    const presign = await fetch("${upload_api_url}", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
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
      headers: { "Content-Type": file.type },
      body: file
    });

    if (!upload.ok) {
      status.innerText = "Upload failed: " + upload.statusText;
      return;
    }

    status.innerText =
      "✅ Upload successful!\n" +
      "S3 Key: " + data.key + "\n" +
      "Replication → Lambda → DynamoDB → SNS will trigger shortly.";

  } catch (err) {
    status.innerText = "Error: " + err;
  }
}
</script>

<div class="footer">
  Powered by Terraform • AWS EC2 • Nginx • Iron Man UI v2 • Live API • S3 Uploads
</div>

</body>
</html>
EOF

systemctl restart nginx
