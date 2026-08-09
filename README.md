# Flask App CI/CD

A Flask web app with a full CI/CD pipeline: GitHub Actions → Jenkins → Docker Hub → app EC2.

Two persistent EC2 instances:
- **Jenkins** — CI server (runs the pipeline itself, no ephemeral agents).
- **app** — hosts the running Flask app; pulls the new Docker image and restarts on each deploy.

## App

- `src/app.py` — Flask server. Routes:
  - `GET /` → renders `templates/index.html`
  - `GET /api/hello` → JSON `{"message": "Hello World!"}`
- `templates/index.html` + `static/` — frontend assets.

### Run locally

```bash
python3 -m pip install -r requirements.txt
python3 src/app.py            # http://localhost:3000
```

Or with Docker:

```bash
docker-compose up --build     # http://localhost:3000
```

### Test

```bash
python3 -m pytest
```

## Pipeline flow

```
[push to main] → [GitHub Actions] → [Jenkins container]
      Jenkins (JCasC-defined job) runs: pytest → docker build (git sha + build-N tags) → docker push to Docker Hub
      Jenkins SSHs to app EC2 → docker compose pull → docker compose up -d
```

### Jenkins stages (`Jenkinsfile`)

1. **Checkout** — pull source.
2. **Test** — install deps, run pytest.
3. **Set Version** — compute `GIT_SHA` and `BUILD_TAG_NAME`.
4. **Build Image** — `docker build` (via host Docker socket) with two tags.
5. **Push Image** — `docker login` Docker Hub, push both tags.
6. **Deploy** — scp `docker-compose.yml` to app EC2, `docker compose pull` the `:GIT_SHA` image, restart the container.

## Infrastructure (terraform/ + ansible/ + jenkins/)

- `terraform/` provisions the Jenkins EC2, the app EC2, and their security groups.
- `jenkins/` defines the **Jenkins container**: `Dockerfile` (plugins + build tools), `jenkins.yaml` (JCasC: `dockerhub` credential + `my-flask-app` pipeline job, all in code), and `docker-compose.yml`.
- `ansible/` installs Docker on both hosts, then builds + runs the Jenkins container (on the Jenkins host) and prepares the app host.

### Deploy key

The Ansible `jenkins` role writes the deploy private key to `/etc/jenkins/ssh/app-key.pem` (mounted into the container at `/var/jenkins_home/.ssh/app-key.pem`). The `app` role adds its public half to the app EC2's `~/.ssh/authorized_keys`.

## Fill in these placeholders before running

| Placeholder | Files | Value |
|---|---|---|
| `yourusername/flask-app` | `Jenkinsfile`, `docker-compose.yml`, `terraform/terraform.tfvars` | Your Docker Hub username/image. **Image must be public** so EC2 can `docker pull` it. |
| `APP_PUBLIC_IP` | `Jenkinsfile` (`APP_HOST`) | From `terraform output app_public_ip`. |
| `APP_EC2_PUBLIC_IP` | `ansible/inventory.yml` | From `terraform output app_public_ip`. |
| `JENKINS_EC2_PUBLIC_IP` | `ansible/inventory.yml` | From `terraform output jenkins_public_ip`. |
| `YOUR_PUBLIC_IP` | `terraform/terraform.tfvars` | Your public IP (as CIDR, e.g. `203.0.113.5/32`). |
| `~/.ssh/my-key.pem` | `ansible/inventory.yml` | SSH key for both EC2 hosts. |
| `app_deploy_public_key` / `app_deploy_private_key` | `ansible/group_vars/jenkins.yml` | Jenkins deploy keypair (pub → app host, priv → Jenkins container). |
| `jenkins_dockerhub_username` / `jenkins_dockerhub_password` | `ansible/group_vars/jenkins.yml` | Docker Hub credentials for the `dockerhub` Jenkins credential. |
| `jenkins_repo_url` / `jenkins_remote_token` | `ansible/group_vars/jenkins.yml` | Repo the job builds + the remote trigger token (== GitHub `JENKINS_TOKEN`). |
| `JENKINS_URL` | GitHub secret + `group_vars/jenkins.yml` | `http://<jenkins-public-ip>:8080` (no domain in lab). |
| `JENKINS_TOKEN` | GitHub secret | Same value as `jenkins_remote_token`. |

## Infrastructure setup (step by step)

Run these in order. **You only do this once.**

> **Order matters.** The EC2 instances must **exist first** before any other operation (Ansible, Jenkins config, GitHub secrets). Start with **Step 3**. Every later step depends on the two instance IPs Terraform outputs.

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.6 (local machine)
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/index.html) >= 2.9 (local machine)
- AWS CLI configured (`aws configure`) with credentials that can create EC2 + SGs
- A **Docker Hub** account and a **public** repo `yourusername/flask-app`
- Your public IP, found via: `curl ifconfig.me`

### Step 1 — Create SSH keys

Generate a key pair you'll use to reach both EC2 hosts:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/my-key.pem -N ""
```

> Keep `~/.ssh/my-key.pem` private. The **public** half (`~/.ssh/my-key.pem.pub`) must be registered as an AWS EC2 key pair named **exactly** `my-key` (matching `ssh_key_name`) **in the region you deploy to** — AWS Console → EC2 → Key Pairs → Import Key Pair, paste the `.pub` contents. Terraform references this name via `key_name`.

### Step 2 — Fill in Terraform values

Edit `terraform/terraform.tfvars`:

```hcl
aws_region            = "ap-southeast-1"
project_name          = "flask-app"
jenkins_instance_type = "t3.medium"
app_instance_type     = "t3.micro"
public_ip_cidr        = "YOUR_PUBLIC_IP/32"   # from `curl ifconfig.me`
docker_image          = "yourusername/flask-app"
ssh_key_name          = "my-key"              # AWS key pair name (must already exist in the region)
```

### Step 3 — CREATE the EC2 instances first (Terraform)

> **This must run before every other step.** Do not run Ansible, configure Jenkins, or set GitHub secrets until both instances exist.

Easiest way (runs `init` if needed, `apply`, and prints both IPs):

```bash
./scripts/create-infra.sh
```

Or step-by-step:

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

Read the outputs (your two instance IPs):

```bash
terraform output
# jenkins_public_ip = "X.X.X.X"
# app_public_ip     = "Y.Y.Y.Y"
```

Confirm both instances are reachable before continuing:

```bash
ssh -i ~/.ssh/my-key.pem ubuntu@X.X.X.X 'echo jenkins ok'
ssh -i ~/.ssh/my-key.pem ubuntu@Y.Y.Y.Y 'echo app ok'
```

> The SG opens port 22 only to your `public_ip_cidr`, and both instances use the `ssh_key_name` key pair for SSH access.

**What these outputs feed downstream:**
- `jenkins_public_ip` → `ansible/inventory.yml` + GitHub secret `JENKINS_URL`
- `app_public_ip` → `ansible/inventory.yml` + `Jenkinsfile` (`APP_HOST`)

### Step 4 — Configure the hosts (Ansible)

Edit `ansible/inventory.yml` with the real IPs from `terraform output`:

```yaml
jenkins:
  hosts:
    jenkins:
      ansible_host: "JENKINS_EC2_PUBLIC_IP"
      ansible_user: ubuntu
      ansible_ssh_private_key_file: "~/.ssh/my-key.pem"
app:
  hosts:
    app:
      ansible_host: "APP_EC2_PUBLIC_IP"
      ansible_user: ubuntu
      ansible_ssh_private_key_file: "~/.ssh/my-key.pem"
```

Generate a keypair Jenkins uses to SSH into the app host for deploys:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/app-deploy.pem -N ""
# public half -> app_deploy_public_key (group_vars)
cat ~/.ssh/app-deploy.pem.pub
# private half -> app_deploy_private_key (group_vars)
cat ~/.ssh/app-deploy.pem
```

Set Jenkins secrets in `ansible/group_vars/jenkins.yml` (git-ignored; optionally wrap with `ansible-vault`):

```yaml
jenkins_dockerhub_username: yourusername
jenkins_dockerhub_password: yourpassword
jenkins_remote_token: your-jenkins-token       # must match GitHub secret JENKINS_TOKEN
jenkins_repo_url: https://github.com/yourusername/my-ci-cd.git
jenkins_url: http://localhost:8080
app_deploy_public_key: "ssh-ed25519 AAAA... your-key"
app_deploy_private_key: "-----BEGIN OPENSSH PRIVATE KEY-----..."
```

Run Ansible (installs Docker on both hosts; on the Jenkins host it builds + runs the **Jenkins container** and on the app host prepares it for deploys):

```bash
ansible-playbook -i ansible/inventory.yml ansible/playbook.yml
```

> Requires collections: `ansible.posix` → `ansible-galaxy collection install ansible.posix`.

### Step 5 — Jenkins runs as a container (auto-configured)

Jenkins is **not** installed manually. The Ansible `jenkins` role builds and starts it via docker compose (`jenkins/docker-compose.yml`) on the Jenkins EC2.

- The container image (`jenkins/Dockerfile`) includes build tools (docker CLI, aws-cli, python/pytest, git) and Jenkins plugins.
- The `my-flask-app` **pipeline job and the `dockerhub` credential are defined in code** via JCasC (`jenkins/jenkins.yaml`) and created automatically on first start — no manual job setup.
- The pipeline builds images through the host's Docker socket and deploys to the app EC2 over SSH.

Only optional setup after it starts:

1. Open `http://<jenkins-public-ip>:8080` and log in to set an admin password (JCasC handles the job + credential; you just create a login).
2. (Optional) Test the job manually with *Build Now*.

### Step 6 — Point GitHub at Jenkins (no domain)

Set two **repository secrets** (Settings → Secrets and variables → Actions):

- `JENKINS_URL` = `http://<jenkins-public-ip>:8080`
- `JENKINS_TOKEN` = the token from Step 5.6

### Step 7 — Verify the full flow

```bash
# push to main (or click "Run workflow" in Actions tab)
git push origin main
```

GitHub Actions → Jenkins → build + push → deploy to app EC2. Check the app:

```bash
curl http://<app-public-ip>:3000/api/hello
# {"message":"Hello World!"}
```

---

## Required external setup (one-time summary)

1. **Terraform** — `cd terraform && terraform init && terraform apply -auto-approve`.
2. **Ansible** — edit `inventory.yml` + `group_vars/jenkins.yml`, then `ansible-playbook -i ansible/inventory.yml ansible/playbook.yml`. This builds + starts the Jenkins container (jobs + credentials auto-defined by JCasC) and prepares the app host.
3. **Jenkins** — log in at `http://<jenkins-ip>:8080` to set an admin password. The `my-flask-app` job, `dockerhub` credential, and deploy key are all provisioned automatically.
4. **GitHub secrets** — `JENKINS_URL` and `JENKINS_TOKEN` (the same value as `jenkins_remote_token`).

> **Note:** In this lab there is no DNS/domain. GitHub Actions reaches Jenkins by public IP over HTTP (`JENKINS_URL`), and the Jenkins security group (port 8080) is open to the internet. Tighten this before any production use.

---

# Full walkthrough: from instances to working CI/CD

Follow top to bottom. This is the complete path from creating the EC2 instances to shipping the app through the pipeline.

## 0. Prerequisites

On your local machine:

```bash
# Terraform, Ansible, AWS CLI
terraform --version
ansible --version
aws configure

# Ansible collection used by the app role
ansible-galaxy collection install ansible.posix
```

What you need handy:
- AWS credentials that can create EC2 + security groups
- A **Docker Hub** account with a **public** repo `yourusername/flask-app`
- Your public IP: `curl ifconfig.me`

## 1. Create SSH keys

```bash
# key to reach both EC2 hosts (used by ansible inventory + terraform)
ssh-keygen -t ed25519 -f ~/.ssh/my-key.pem -N ""

# keypair Jenkins uses to deploy to the app host
ssh-keygen -t ed25519 -f ~/.ssh/app-deploy.pem -N ""
cat ~/.ssh/app-deploy.pem.pub   # -> app_deploy_public_key
cat ~/.ssh/app-deploy.pem       # -> app_deploy_private_key (into vault)
```

Import `~/.ssh/my-key.pem.pub` into AWS as an EC2 key pair named **`my-key`** (AWS Console → EC2 → Key Pairs → Import Key Pair), in your deploy region.

## 2. Set up the Ansible vault

Ansible reads the vault password via `/etc/ansible/.ansible-vault.py`. Create it once:

```bash
# install the password client script
sudo cp ansible/.ansible-vault.py.example /etc/ansible/.ansible-vault.py
sudo chmod 700 /etc/ansible/.ansible-vault.py

# create the password file it reads (or set $ANSIBLE_VAULT_PASS)
sudo sh -c 'echo "CHANGE_ME_VAULT_PASSWORD" > /etc/ansible/.vault_pass'
sudo chmod 600 /etc/ansible/.vault_pass
```

Create and encrypt the secrets file:

```bash
cp ansible/group_vars/jenkins/vault.yml.example ansible/group_vars/jenkins/vault.yml
ansible-vault encrypt ansible/group_vars/jenkins/vault.yml   # prompts for password
ansible-vault edit ansible/group_vars/jenkins/vault.yml       # fill in real values
```

Set the non-secret values:

- `ansible/group_vars/jenkins.yml` → `jenkins_repo_url` (your repo), `jenkins_url`.
- `ansible/group_vars/app.yml` → `app_deploy_public_key` (paste the `.pub` from step 1).

## 3. Create the instances (Terraform — must run first)

```bash
# fill in terraform/terraform.tfvars (public_ip_cidr, docker_image, ssh_key_name)
./scripts/create-infra.sh
# prints: jenkins_public_ip = X.X.X.X   app_public_ip = Y.Y.Y.Y
```

> Instances must exist before anything else. Confirm SSH works:
> `ssh -i ~/.ssh/my-key.pem ubuntu@X.X.X.X 'echo ok'`

## 4. Fill the Ansible inventory

Edit `ansible/inventory.yml` with the two IPs from step 3:

```yaml
jenkins:
  hosts:
    jenkins:
      ansible_host: "X.X.X.X"
      ansible_user: ubuntu
      ansible_ssh_private_key_file: "~/.ssh/my-key.pem"
app:
  hosts:
    app:
      ansible_host: "Y.Y.Y.Y"
      ansible_user: ubuntu
      ansible_ssh_private_key_file: "~/.ssh/my-key.pem"
```

## 5. Run Ansible (provisions both hosts)

```bash
# runs from repo root; ansible.cfg sets inventory, roles, and the vault client
ansible-playbook ansible/playbook.yml
```

What it does:
- Both hosts: installs Docker + compose.
- **Jenkins host**: writes the deploy private key, templates `.env` + compose, then `docker compose up -d --build` — starts the Jenkins container. JCasC auto-creates the `dockerhub` credential and the `my-flask-app` pipeline job.
- **App host**: prepares `~/flask-app/` and adds the Jenkins deploy public key to `authorized_keys`.

## 6. Jenkins

1. Open `http://X.X.X.X:8080` and log in; set an admin password.
2. (Optional) Open the **my-flask-app** job and run **Build Now** to test before wiring GitHub.

## 7. GitHub secrets

In your repo: Settings → Secrets and variables → Actions → New repository secret:

- `JENKINS_URL` = `http://X.X.X.X:8080`
- `JENKINS_TOKEN` = the value you set as `jenkins_remote_token` in the vault (must match)

## 8. Verify the full pipeline

```bash
git add -A && git commit -m "trigger CI"
git push origin main        # GitHub Actions -> Jenkins (main only) -> build+push -> deploy
```

Watch the job in Jenkins, then test the live app:

```bash
curl http://Y.Y.Y.Y:3000/api/hello
# {"message":"Hello World!"}
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `ansible-playbook` can't find roles/inventory | Run from repo root so `ansible.cfg` is picked up. |
| `No vault password was found` | Confirm `/etc/ansible/.ansible-vault.py` is executable + the file/env it reads exists. |
| `app_deploy_public_key` undefined on app host | It must be in `ansible/group_vars/app.yml` (not jenkins vars). |
| Jenkins container won't start / job missing | Check `docker logs jenkins`; JCasC prints config errors at first boot. |
| Build triggers but nothing runs | Token mismatch: GitHub `JENKINS_TOKEN` must equal vault `jenkins_remote_token`. |
| Cannot reach Jenkins from GitHub | Jenkins SG port 8080 must be open to the internet (`public_ip_cidr = 0.0.0.0/0`). |
