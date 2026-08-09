FROM jenkins/jenkins:lts-jdk21

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        openssh-client \
        ca-certificates \
        curl \
        unzip \
        python3 \
        python3-pip \
        python3-venv \
        docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip && ./aws/install \
    && rm -rf awscliv2.zip aws

RUN python3 -m pip install --no-cache-dir pytest

RUN jenkins-plugin-cli --plugins \
        configuration-as-code \
        workflow-aggregator \
        git \
        credentials-binding \
        docker-workflow \
        pipeline-stage-view \
        parameterized-remote-trigger

COPY jenkins.yaml /usr/share/jenkins/ref/casc_configs/jenkins.yaml

ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/ref/casc_configs/jenkins.yaml

USER jenkins
