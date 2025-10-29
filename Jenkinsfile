pipeline {
    agent any
    environment {
        DOCKER_IMAGE = "chouleang/podinfo"
        GKE_CLUSTER = "go-hello-cluster"
        GKE_ZONE = "asia-southeast1-a"
        PROJECT_ID = "it-enviroment"
        NAMESPACE = "podinfo"
    }
    
    triggers {
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
                    mkdir -p bin
                    
                    # Install kubectl
                    echo "Installing kubectl..."
                    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                    chmod +x kubectl
                    mv kubectl bin/
                    
                    # Install Google Cloud SDK
                    echo "Installing Google Cloud SDK..."
                    # Download and install gcloud
                    curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz
                    tar -xf google-cloud-cli-linux-x86_64.tar.gz
                    ./google-cloud-sdk/install.sh --quiet --path-update false --usage-reporting false --command-completion false
                    
                    # Create symlinks to our bin directory
                    ln -sf $PWD/google-cloud-sdk/bin/gcloud bin/gcloud
                    ln -sf $PWD/google-cloud-sdk/bin/gsutil bin/gsutil
                    
                    # Install required gcloud components
                    echo "Installing gcloud components..."
                    ./google-cloud-sdk/bin/gcloud components install kubectl gke-gcloud-auth-plugin --quiet
                    
                    echo "✅ Tools installed successfully"
                    echo "kubectl version:"
                    bin/kubectl version --client
                    echo "gcloud version:"
                    bin/gcloud --version
                '''
            }
        }
        
        stage('Test') {
            steps {
                sh '''
                    echo "🧪 Running tests..."
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
                sh '''
                    echo "🏗️ Building with BuildKit..."
                    cd go
                    DOCKER_BUILDKIT=1 docker build \\
                        --tag ${DOCKER_IMAGE}:${BUILD_ID} \\
                        --tag ${DOCKER_IMAGE}:latest \\
                        --progress=plain \\
                        .
                    echo "✅ Build completed"
                '''
            }
        }
        
        stage('Push to Docker Hub') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'docker-hub-credentials',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh '''
                        echo "📦 Pushing to Docker Hub..."
                        docker login -u $DOCKER_USER -p $DOCKER_PASS
                        docker push ${DOCKER_IMAGE}:${BUILD_ID}
                        docker push ${DOCKER_IMAGE}:latest
                        echo "✅ Images pushed to Docker Hub"
                    '''
                }
            }
        }
        
        stage('Deploy to GKE') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'gcp-service-account', variable: 'GCP_CREDENTIALS')]) {
                        sh """
                            echo "🚀 Deploying to GKE..."
                            
                            # Use installed tools
                            export PATH="\$PWD/bin:\$PATH"
                            
                            # Authenticate to GCP
                            gcloud auth activate-service-account --key-file=\${GCP_CREDENTIALS}
                            
                            # Get GKE cluster credentials
                            gcloud container clusters get-credentials \${GKE_CLUSTER} --zone \${GKE_ZONE} --project \${PROJECT_ID}
                            
                            echo "✅ GKE access configured"
                            
                            # Create namespace if not exists
                            kubectl create namespace \${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
                            
                            # Apply all GKE manifests from gke/ directory
                            echo "📁 Applying GKE manifests..."
                            kubectl apply -f gke/ -n \${NAMESPACE}
                            
                            # Update deployment with new image
                            echo "🔄 Updating deployment with new image..."
                            kubectl set image deployment/podinfo podinfo=${DOCKER_IMAGE}:\${BUILD_ID} -n \${NAMESPACE} --record
                            
                            # Wait for rollout to complete
                            echo "⏳ Waiting for deployment to be ready..."
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
                            
                            # Use installed tools
                            export PATH="\$PWD/bin:\$PATH"
                            
                            gcloud auth activate-service-account --key-file=\${GCP_CREDENTIALS}
                            gcloud container clusters get-credentials \${GKE_CLUSTER} --zone \${GKE_ZONE} --project \${PROJECT_ID}
                            
                            # Get service endpoint
                            SERVICE_IP=\$(kubectl get service podinfo -n \${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                            
                            if [ -n "\$SERVICE_IP" ]; then
                                echo "🌐 PodInfo is available at: http://\${SERVICE_IP}"
                                
                                # Wait for service to be ready and test endpoints
                                echo "🧪 Testing endpoints..."
                                timeout 120 bash -c 'until curl -f http://\${SERVICE_IP}/healthz; do sleep 5; done'
                                curl -f http://\${SERVICE_IP}/readyz && echo "✅ Readiness check passed"
                                curl -f http://\${SERVICE_IP}/version && echo "✅ Version endpoint working"
                                
                                echo "✅ Smoke test passed! PodInfo is running correctly."
                            else
                                echo "⚠️ Service IP not yet assigned, skipping smoke test"
                                kubectl get service podinfo -n \${NAMESPACE}
                            fi
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
                rm -rf bin google-cloud-cli-linux-x86_64.tar.gz google-cloud-sdk kubectl || true
            '''
        }
        success {
            script {
                echo "🎉 Pipeline SUCCESS!"
                echo "📦 Image: ${DOCKER_IMAGE}:${env.BUILD_ID}"
                echo "🔗 Build URL: ${env.BUILD_URL}"
                
                # Try to get service IP for final output
                withCredentials([file(credentialsId: 'gcp-service-account', variable: 'GCP_CREDENTIALS')]) {
                    sh """
                        mkdir -p bin
                        curl -LO "https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" 2>/dev/null || true
                        chmod +x kubectl 2>/dev/null || true
                        mv kubectl bin/ 2>/dev/null || true
                        
                        curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz 2>/dev/null || true
                        tar -xf google-cloud-cli-linux-x86_64.tar.gz 2>/dev/null || true
                        ln -sf \$PWD/google-cloud-sdk/bin/gcloud bin/gcloud 2>/dev/null || true
                        
                        export PATH="\$PWD/bin:\$PATH" 2>/dev/null || true
                        
                        gcloud auth activate-service-account --key-file=\${GCP_CREDENTIALS} 2>/dev/null || true
                        gcloud container clusters get-credentials \${GKE_CLUSTER} --zone \${GKE_ZONE} --project \${PROJECT_ID} 2>/dev/null || true
                        SERVICE_IP=\$(kubectl get service podinfo -n \${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Not available")
                        
                        if [ -n "\$SERVICE_IP" ] && [ "\$SERVICE_IP" != "Not available" ]; then
                            echo "🌐 Application URL: http://\${SERVICE_IP}"
                            echo "📊 Metrics: http://\${SERVICE_IP}/metrics"
                        fi
                    """
                }
            }
        }
        failure {
            echo "❌ Pipeline FAILED - Check Jenkins logs for details"
            echo "🔗 Build URL: ${env.BUILD_URL}"
        }
    }
}