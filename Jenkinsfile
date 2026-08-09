pipeline {
    agent any

    environment {
        DOCKER_IMAGE = 'vannabothcd/flask-app'

        APP_HOST = 'APP_PUBLIC_IP'
        APP_USER = 'ubuntu'
        APP_SSH_KEY = '/var/jenkins_home/.ssh/app-key.pem'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                sh 'git config --global user.name "vannaboth" && git config --global user.email "vannaboth100@gmail.com"'
            }
        }

        stage('Test') {
            steps {
                sh '''
                    python3 -m pytest
                '''
            }
        }

        stage('Set Version') {
            steps {
                script {
                    env.GIT_SHA = sh(
                        script: 'git rev-parse --short=12 HEAD',
                        returnStdout: true
                    ).trim()

                    env.BUILD_TAG_NAME = "build-${env.BUILD_NUMBER}"
                }
            }
        }

        stage('Build Image') {
            steps {
                script {
                    sh """
                        docker build \\
                            --tag ${DOCKER_IMAGE}:${GIT_SHA} \\
                            --tag ${DOCKER_IMAGE}:${BUILD_TAG_NAME} \\
                            .
                    """
                }
            }
        }

        stage('Push Image') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub',
                        usernameVariable: 'DOCKER_USERNAME',
                        passwordVariable: 'DOCKER_PASSWORD'
                    )
                ]) {
                    sh """
                        docker login --username ${DOCKER_USERNAME} \\
                            --password ${DOCKER_PASSWORD}

                        docker push ${DOCKER_IMAGE}:${GIT_SHA}
                        docker push ${DOCKER_IMAGE}:${BUILD_TAG_NAME}
                    """
                }
            }
        }

        stage('Deploy') {
            steps {
                sh """
                    scp -i ${APP_SSH_KEY} -o StrictHostKeyChecking=no \\
                        docker-compose.yml \\
                        ${APP_USER}@${APP_HOST}:/home/${APP_USER}/flask-app/

                    ssh -i ${APP_SSH_KEY} -o StrictHostKeyChecking=no \\
                        ${APP_USER}@${APP_HOST} '
                        cd /home/${APP_USER}/flask-app &&
                        export DOCKER_IMAGE=${DOCKER_IMAGE}:${GIT_SHA} &&
                        docker compose pull &&
                        docker compose up -d
                    '
                """
            }
        }
    }
}
