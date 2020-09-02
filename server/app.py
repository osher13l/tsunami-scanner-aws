from flask import Flask, request, jsonify
from flask_restful import Resource, Api
import os
import subprocess
import json
import boto3
import time

app = Flask(__name__)
api = Api(app)

tsunami_script="./run_scan.bash"

class HelloWorld(Resource):
    def get(self):
        return {'hello': 'world'}
 


class TsunamiScan(Resource):
    def get(self):
        ip = request.args.get('ip')
        print(ip)
        return self.scan(ip)

    def scan(self, ip):
        process = subprocess.Popen([tsunami_script,ip], stdout=subprocess.PIPE)
        process.wait()
        with open('/tmp/tsunami-output.json') as json_file:
            data = json.load(json_file)
        print(data)
        self.put_on_s3(ip)        
        return data

    def put_on_s3(self, ip):
        bucket_name = os.getenv("BUCKET_NAME")
        file_name = ip+"_"+time.strftime("%Y%m%d-%H%M%S")
        s3_path = "/tsunami_results" + file_name + ".json"
        #s3.Bucket(bucket_name).put_object(Key=s3_path, Body=scan_results)
        s3.Bucket(bucket_name).upload_file('/tmp/tsunami-output.json',s3_path)

    def post(self):
        data=request.json["ips_to_scan"]
        self.scan_ips(data)
        return jsonify({'scan':'completed'})
    def scan_ips(self, data):
        for ip in data:
            self.push_to_sqs(ip)
    def push_to_sqs(self,ip):
        response = sqs.send_message(
            QueueUrl=queue_url,
            MessageGroupId="scan",
            MessageBody=(
                ip
            )
        )
        #print(response)

api.add_resource(HelloWorld, '/')
api.add_resource(TsunamiScan, '/scan')
if __name__ == '__main__':
    sqs = boto3.client('sqs', region_name=os.getenv('REGION_NAME', None), aws_access_key_id=os.getenv('AWS_ACCESS_KEY', None), aws_secret_access_key=os.getenv('AWS_SECRET_KEY', None))
    s3 = boto3.resource('s3', region_name=os.getenv('REGION_NAME', None), aws_access_key_id=os.getenv('AWS_ACCESS_KEY', None), aws_secret_access_key=os.getenv('AWS_SECRET_KEY', None))
    queue_url = os.getenv('AWS_SQS_QUEUE', None)
    app.run(debug=True, host='0.0.0.0')
