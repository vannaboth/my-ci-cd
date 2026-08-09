# Flask App CI/CD

A Flask app deployed with a full CI/CD pipeline:

```
push to main → GitHub Actions → Jenkins → Docker Hub → app EC2
```

Two persistent EC2 instances:
- **Jenkins** — CI server (runs the pipeline itself).
- **app** — runs the Flask app; pulls the new image and restarts on each deploy.

## The app

- `src/app.py` — Flask server. Routes: `GET /` (page), `GET /api/hello` (JSON `{"message": "Hello World!"}`).
- `templates/` + `static/` — frontend.

### Run locally

```bash
python3 -m pip install -r requirements.txt
python3 src/app.py          # http://localhost:3000
```

### Test

```bash
python3 -m pytest
```

## How it works

1. Push to `main` → GitHub Actions calls Jenkins.
2. Jenkins (container, job auto-created by JCasC) runs the `Jenkinsfile`:
   - **Test** — pytest
   - **Build** — `docker build` (image tagged with git SHA + build number)
   - **Push** — push image to Docker Hub
   - **Deploy** — SSH to app EC2 → `docker compose pull` + `docker compose up -d`
3. App is live on the app EC2.

## Setup (do this once)

> **Order matters.** Create the EC2 instances **first** — everything after depends on their IPs.

### 1. Prerequisites

- Terraform >= 1.6, Ansible >= 2.9, AWS CLI on your machine
- Docker Hub account with a **public** repo `yourname/flask-app`
- Your public IP: `curl ifconfig.me`

```bash
ansible-galaxy collection install ansible.posix
```

### 2. SSH keys

```bash
# key to reach both EC2 hosts
ssh-keygen -t ed25519 -f ~/.ssh/my-key.pem -N ""

# keypair Jenkins uses to deploy to the app host
ssh-keygen -t ed25519 -f ~/.ssh/app-deploy.pem -N ""
```

The `my-key` pair is imported into AWS **automatically** by `create-infra.sh` (from `~/.ssh/my-key.pem.pub`) — no manual console step needed.

### 3. Fill in config values

Copy the templates and edit them:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp ansible/group_vars/all/vault.yml.example ansible/group_vars/all/vault.yml
ansible-vault encrypt ansible/group_vars/all/vault.yml   # then: ansible-vault edit
```

Set these (see the [placeholders table](#placeholders) below):
- `terraform.tfvars` — Docker Hub image, key name. (Leave `public_ip_cidr` unset — no static IP; SGs default to open.)
- `ansible/group_vars/jenkins.yml` — repo URL.
- `ansible/group_vars/app.yml` — `app_deploy_public_key` (paste `app-deploy.pem.pub`).
- vault (`vault.yml`) — Docker Hub login, remote token, `app_deploy_private_key`.

Set up the Ansible vault password once (script + password file):

```bash
sudo cp ansible/.ansible-vault.py.example /etc/ansible/.ansible-vault.py
sudo chmod 700 /etc/ansible/.ansible-vault.py
sudo sh -c 'echo "YOUR_VAULT_PASSWORD" > /etc/ansible/.vault_pass'
sudo chmod 600 /etc/ansible/.vault_pass
```

### 4. Create the instances (must run first)

Since you don't use a static public IP, `public_ip_cidr` is left unset — the security groups default to `0.0.0.0/0` (open to the internet). No IP is hardcoded anywhere.

```bash
# prompts for AWS keys, then creates instances; prints both IPs
./scripts/login-aws.sh
```

The script grabs the auto-allocated IPs and writes them straight into `ansible/inventory.yml`, so no manual editing is needed.

Note the outputs (you'll use them later):
- `jenkins_public_ip` = X.X.X.X
- `app_public_ip` = Y.Y.Y.Y

### 5. Check the Ansible inventory

The inventory is auto-filled by the script — verify `ansible/inventory.yml` now has your two IPs.

### 6. Run Ansible

```bash
ansible-playbook ansible/playbook.yml
```

This installs Docker on both hosts, starts the **Jenkins container** (job + credentials auto-defined by JCasC), and prepares the app host for deploys.

### 7. Jenkins login

Open `http://X.X.X.X:8080` and set an admin password. (Optional: run the `my-flask-app` job manually with *Build Now* to test.)

### 8. GitHub secrets

Repo → Settings → Secrets and variables → Actions:

- `JENKINS_URL` = `http://X.X.X.X:8080`
- `JENKINS_TOKEN` = the value you set as `jenkins_remote_token` in the vault (must match)

### 9. Verify

```bash
git push origin main
curl http://Y.Y.Y.Y:3000/api/hello
# {"message":"Hello World!"}
```

## Placeholders

| What | Where |
|---|---|
| Docker Hub image (`yourname/flask-app`, must be **public**) | `terraform.tfvars`, `Jenkinsfile`, `docker-compose.yml` |
| Your public IP (not set — no static IP) | SG defaults to `0.0.0.0/0`; set `public_ip_cidr` only to lock down |
| SSH key pair name (`my-key`) | `terraform.tfvars` (`ssh_key_name`) |
| App + Jenkins EC2 IPs (auto) | `ansible/inventory.yml` — filled by `create-infra.sh` |
| Docker Hub login | `ansible/group_vars/jenkins/vault.yml` |
| Jenkins remote token (`jenkins_remote_token`) | `ansible/group_vars/jenkins/vault.yml` |
| Jenkins deploy keypair | `app_deploy_public_key` (app.yml) + `app_deploy_private_key` (vault) |
| Repo URL | `ansible/group_vars/jenkins.yml` |
| `JENKINS_URL` / `JENKINS_TOKEN` | GitHub secrets |

## Troubleshooting

| Symptom | Fix |
|---|---|
| `ansible-playbook` can't find roles/inventory | Run from repo root so `ansible.cfg` is picked up. |
| `No vault password was found` | Make `/etc/ansible/.ansible-vault.py` executable and the password file/env exists. |
| `app_deploy_public_key` undefined on app host | Put it in `ansible/group_vars/app.yml`. |
| Jenkins won't start / job missing | `docker logs jenkins`; JCasC logs config errors at first boot. |
| Build triggers but nothing runs | Token mismatch: GitHub `JENKINS_TOKEN` must equal vault `jenkins_remote_token`. |
| Can't reach Jenkins from GitHub | Jenkins SG port 8080 open to internet (`public_ip_cidr = 0.0.0.0/0`). |

> **Note:** This is a lab — no domain. GitHub reaches Jenkins by public IP over HTTP, and Jenkins's port 8080 is open to the internet. Tighten both before production use.
