import json
import requests
import os
import boto3
import time

def handler(event, context):
    #data = json.dumps(event)
    ip = event["Records"][0]["body"]
    #ip = event["body"]
    alb_dns = os.getenv("alb_dns")
    bucket_name = os.getenv("bucket_name")
    try:
        requests.get("http://{}/scan?ip={}".format(alb_dns, ip), timeout=0.0000000001)
    except requests.exceptions.ReadTimeout: 
        pass
    #scan_results = res.json()
    #bucket_name = os.getenv("BUCKET_NAME")
    #file_name = ip+"_"+time.strftime("%Y%m%d-%H%M%S")
    #s3_path = "/tsunami_results" + file_name
    #s3 = boto3.resource("s3")
    #s3.Bucket(bucket_name).put_object(Key=s3_path, Body=scan_results)
    #return scan_results
