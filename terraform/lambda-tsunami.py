import json
import requests
import os

def handler(event, context):
    data = json.dumps(event)
    ip = data["Records"][0]["body"]
    alb_dns = os.getenv("ALB_DNS")
    res = requests.get("{}/scan?ip={}".format(alb_dns, ip))
    scan_results = res.json()
    return scan_results
