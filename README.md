# tsunami-scanner-aws
AWS implemantaion for https://github.com/google/tsunami-security-scanner
Deployment using Terraform.

In order to deploy the system run the following steps:

git clone https://github.com/osher13l/tsunami-scanner-aws.git

cd tsunami-scanner-aws/terraform

mv terraform.tfvars.example terraform.tfvars

edit terraform.tfvars with your preferred region ,credentials(make sure you use terraform user with admin permission) and default subnets.

run terraform init

run terraform apply
terraform will output the lb dns name

Now you can run the application by sending POST request to the following URL:
http://<load_balancer_dns>/scan
You should send application/json in the following format:
{
"ips_to_scan": [
   "127.0.0.1"
 ]
}

You can check the result of the scan in the created S3 bucket called: tsunami-results-bucket after few minutes.
