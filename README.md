# README #

This README would normally document whatever steps are necessary to get your application up and running.

### How do I get set up? ###

```
Install aws-cli - https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
Configure aws profile e.g - https://sergiiblog.com/devops-basics-how-to-work-with-multiple-aws-accounts-using-aws-cli/
export AWS_PROFILE=your_profile_name

Test connection: aws sts get-caller-identity
```

### How to work with terraform? ###
```
terraform apply -var-file ../env.tfvars
terraform destroy -var-file ../env.tfvars

Sequence of running modules:
1. pre-init - enough to run once to create s3 bucket and dynamoDB table for keeping  terrafrom state and locks
2. network
3. bastion

In case deployment with docker swarm
4. ec2 + ansible

In case deployment at ECS:
4. ecs-iam-profile
5. ecs-ec2
6. ecs-cluster

```
### How to work with ansible? ###
```
ansible-playbook playbooks/ping.yml -i inventories/dev/hosts --extra-vars "variable_host=dev"
ansible-playbook playbooks/full_es_env.yml -i inventories/dev/hosts --extra-vars "variable_host=dev"
```

### How to check if cluster is up and working properly? ###
```
curl 'http://172.27.72.50:9200/_cluster/health?pretty'
curl 'http://localhost:9200/_cluster/health?pretty'
```

## How to work with ECR? ###
```
docker login -u AWS -p $(aws ecr get-login-password --region ${REGION}) ${ACCOUND_ID}.dkr.ecr.${REGION}.amazonaws.com
docker build . -t ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:latest
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:latest
```

## SSH config example ###
Host *
  ServerAliveInterval 600
  PasswordAuthentication no
  AddressFamily inet

Host udemy-dev-bastion
    HostName x.x.x.x #chanage it at bastion IP address
    User ubuntu
    IdentitiesOnly yes
    IdentityFile ~/.sergii-blog-keys/dev-bastion-2 #change it at your_folder_name/key_name
    AddKeysToAgent yes
    ForwardAgent yes

Host udemy-dev-app-a
    HostName 172.27.72.50
    User ec2-user #user depends at AMI
    IdentitiesOnly yes
    IdentityFile ~/.sergii-blog-keys/dev-ec2-2 #change it at your_folder_name/key_name
    ProxyJump udemy-dev-bastion

Host udemy-dev-app-b
    HostName 172.27.72.100
    User ec2-user #user depends at AMI
    IdentitiesOnly yes
    IdentityFile ~/.sergii-blog-keys/dev-ec2-2 #change it at your_folder_name/key_name
    ProxyJump udemy-dev-bastion

Host udemy-dev-app-c
    HostName 172.27.72.100
    User ec2-user #user depends at AMI
    IdentitiesOnly yes
    IdentityFile ~/.sergii-blog-keys/dev-ec2-2 #change it at your_folder_name/key_name
    ProxyJump udemy-dev-bastion

Host estunnel
    HostName x.x.x.x  #chenage it at bastion IP address
    User ubuntu
    IdentitiesOnly yes
    IdentityFile ~/.sergii-blog-keys/dev-bastion-2
    LocalForward 19999 vpc-opensearch-dev-xxuadei7isleen5gdddkln6eci.eu-central-1.es.amazonaws.com/_dashboards:443