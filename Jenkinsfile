pipeline {
    agent any
    environment {
        // Your Docker Hub credentials
        DOCKER_REGISTRY = "docker.io"
        DOCKER_IMAGE = "chouleang/podinfo"
        
        // GKE configuration
        GKE_CLUSTER = "go-hello-cluster"
        GKE_ZONE = "asia-southeast1-a"
        PROJECT_ID = "it-enviroment"
        NAMESPACE = "podinfo"
        
        // Set PATH globally for all stages
        CUSTOM_BIN_PATH = "${WORKSPACE}/bin"
        PATH = "${CUSTOM_BIN_PATH}:${PATH}"
    }
    
    triggers {
        // Trigger on push to main branch
        pollSCM('H/5 * * * *')
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
                sh 'echo "📦 Building commit: $(git log --oneline -n 1)"'
            }
        }
        
        stage('Install Tools') {
            steps {
                sh '''
                    echo "📦 Installing tools..."
                    
                    # Create bin directory in workspace
                    mkdir -p bin
                    
                    # Install kubectl
                    echo "Installing kubectl..."
                    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                    chmod +x kubectl
                    mv kubectl bin/
                    
                    # Install gke-gcloud-auth-plugin (required for GKE)
                    echo "Installing gke-gcloud-auth-plugin..."
                    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                    chmod +x kubectl
                    mv kubectl bin/
                    
                    # Install gcloud components
                    echo "Installing gcloud components..."
                    gcloud components install kubectl gke-gcloud-auth-plugin --quiet || true
                    
                    echo "✅ Tools installed successfully"
                    echo "PATH: $PATH"
                    which kubectl || echo "kubectl not in PATH"
                    which gcloud || echo "gcloud not in PATH"
                '''
            }
        }        
        stage('Test') {
            steps {
                sh '''
                    echo "🧪 Running tests..."
                    echo "Current PATH: $PATH"
                    if [ -d "go" ]; then
                        cd go
                        go test ./... -v
                        go vet ./...
                    else
                        echo "No Go source found, skipping tests"
                    fi
                '''
            }
        }
        
        stage('Build with BuildKit') {
            steps {
                script {
                    sh """
                        echo "🏗️ Building with BuildKit..."
                        
                        # Check if we have a custom Dockerfile, otherwise use official image
                        if [ -f "Dockerfile" ]; then
                            docker build \\
                                --tag ${DOCKER_IMAGE}:\${BUILD_ID} \\
                                --tag ${DOCKER_IMAGE}:latest \\
                                --progress=plain \\
                                .
                        else
                            echo "No Dockerfile found, will use official PodInfo image"
                        fi
                    """
                }
            }
        }
        
        stage('Push to Docker Hub') {
            steps {
                script {
                    withCredentials([usernamePassword(
                        credentialsId: 'docker-hub-credentials',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )]) {
                        sh """
                            echo "📦 Pushing to Docker Hub..."
                            docker login -u \$DOCKER_USER -p \$DOCKER_PASS
                            
                            if [ -f "Dockerfile" ]; then
                                docker push ${DOCKER_IMAGE}:\${BUILD_ID}
                                docker push ${DOCKER_IMAGE}:latest
                                echo "✅ Custom image pushed to Docker Hub"
                            else
                                echo "ℹ️ Using official PodInfo image, skipping push"
                            fi
                        """
                    }
                }
            }
        }
        
        stage('Deploy to GKE') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'gcp-service-account', variable: 'GCP_CREDENTIALS')]) {
                        sh """
                            echo "🚀 Deploying to GKE..."
                            echo "Current PATH: $PATH"
                            echo "kubectl path: $(which kubectl)"
                            echo "gcloud path: $(which gcloud)"
                            
                            gcloud auth activate-service-account --key-file=\${GCP_CREDENTIALS}
                            gcloud container clusters get-credentials \${GKE_CLUSTER} --zone \${GKE_ZONE} --project \${PROJECT_ID}
                            
                            # Create namespace if not exists
                            kubectl create namespace \${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
                            
                            # Update deployment with custom image if built, otherwise use official
                            if [ -f "Dockerfile" ]; then
                                echo "🔄 Using custom built image"
                                kubectl set image deployment/podinfo podinfo=${DOCKER_IMAGE}:\${BUILD_ID} -n \${NAMESPACE} --record
                            else
                                echo "🔄 Using official PodInfo image"
                                kubectl set image deployment/podinfo podinfo=ghcr.io/stefanprodan/podinfo:6.5.2 -n \${NAMESPACE} --record
                            fi
                            
                            # Apply all Kubernetes manifests
                            kubectl apply -f k8s/ -n \${NAMESPACE}
                            
                            # Wait for rollout to complete
                            kubectl rollout status deployment/podinfo -n \${NAMESPACE} --timeout=300s
                            
                            echo "✅ Deployment completed!"
                        """
                    }
                }
            }
        }
        
        stage('Smoke Test') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'gcp-service-account', variable: 'GCP_CREDENTIALS')]) {
                        sh """
                            echo "🔍 Running smoke test..."
                            gcloud auth activate-service-account --key-file=\${GCP_CREDENTIALS}
                            gcloud container clusters get-credentials \${GKE_CLUSTER} --zone \${GKE_ZONE} --project \${PROJECT_ID}
                            
                            # Get service endpoint
                            SERVICE_IP=\$(kubectl get service podinfo -n \${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                            echo "🌐 Testing PodInfo at: http://\${SERVICE_IP}"
                            
                            # Wait for service to be ready and test endpoints
                            timeout 120 bash -c 'until curl -f http://\${SERVICE_IP}/healthz; do sleep 5; done'
                            curl -f http://\${SERVICE_IP}/readyz
                            curl -f http://\${SERVICE_IP}/version
                            
                            echo "✅ Smoke test passed! PodInfo is running correctly."
                        """
                    }
                }
            }
        }
    }
    
    post {
        always {
            sh '''
                echo "🧹 Cleaning up..."
                docker system prune -f || true
            '''
        }
        success {
            script {
                withCredentials([file(credentialsId: 'gcp-service-account', variable: 'GCP_CREDENTIALS')]) {
                    sh """
                        gcloud auth activate-service-account --key-file=\${GCP_CREDENTIALS}
                        gcloud container clusters get-credentials \${GKE_CLUSTER} --zone \${GKE_ZONE} --project \${PROJECT_ID}
                        SERVICE_IP=\$(kubectl get service podinfo -n \${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                    """
                }
                
                // Send notification
                echo "🎉 Pipeline SUCCESS!"
                echo "📦 Image: ${DOCKER_IMAGE}:${env.BUILD_ID}"
                echo "🌐 URL: http://${SERVICE_IP}"
                echo "📊 Metrics: http://${SERVICE_IP}/metrics"
            }
        }
        failure {
            echo "❌ Pipeline FAILED - Check Jenkins logs for details"
        }
    }
}