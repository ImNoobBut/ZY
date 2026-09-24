import json
import urllib.request

req = urllib.request.Request(
    "http://127.0.0.1:8081/v1/devices/register",
    data=json.dumps({"displayName": "Zy Flutter"}).encode(),
    headers={
        "Content-Type": "application/json",
        "Origin": "http://localhost:7357",
    },
    method="POST",
)
with urllib.request.urlopen(req) as r:
    body = json.load(r)
    print("status", r.status)
    print("acao", r.headers.get("Access-Control-Allow-Origin"))
    print("pairingCode", body["pairingCode"])
