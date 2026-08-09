FROM jenkins/jenkins:lts-jdk21

USER root

# ---------------------------------------------------------
# System packages
# ---------------------------------------------------------
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        openssh-client \
        ca-certificates \
        curl \
        unzip \
        python3 \
        python3-pip \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*


# ---------------------------------------------------------
# Docker CLI
# Talks to the host Docker daemon through /var/run/docker.sock
# ---------------------------------------------------------
RUN curl -fsSL \
        "https://download.docker.com/linux/static/stable/x86_64/docker-27.5.1.tgz" \
        -o /tmp/docker.tgz \
    && tar -xzf /tmp/docker.tgz -C /tmp \
    && cp /tmp/docker/docker /usr/local/bin/docker \
    && chmod +x /usr/local/bin/docker \
    && rm -rf /tmp/docker /tmp/docker.tgz


# ---------------------------------------------------------
# AWS CLI
# ---------------------------------------------------------
RUN curl -fsSL \
        "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
        -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip


# ---------------------------------------------------------
# Python virtual environment
# Used by Jenkins pipeline for application tests
# ---------------------------------------------------------
COPY requirements.txt /tmp/requirements.txt

RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir \
        -r /tmp/requirements.txt \
    && rm -f /tmp/requirements.txt

ENV PATH="/opt/venv/bin:$PATH"


# ---------------------------------------------------------
# Jenkins plugins
# ---------------------------------------------------------
COPY plugins.txt /usr/share/jenkins/plugins.txt

RUN jenkins-plugin-cli \
        --plugin-file /usr/share/jenkins/plugins.txt


# ---------------------------------------------------------
# Git identity for the Jenkins user (needed for the
# "Create a tag for every build" SCM behavior, which runs
# before the Jenkinsfile body)
# ---------------------------------------------------------
COPY set-git-identity.groovy \
    /usr/share/jenkins/ref/init.groovy.d/set-git-identity.groovy


# ---------------------------------------------------------
# Jenkins Configuration as Code
# ---------------------------------------------------------
COPY jenkins.yaml \
    /usr/share/jenkins/ref/casc_configs/jenkins.yaml

ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/ref/casc_configs/jenkins.yaml


# ---------------------------------------------------------
# Run Jenkins as the jenkins user
# ---------------------------------------------------------
USER jenkins