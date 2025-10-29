pipeline {
    agent any
    environment {
        DOCKER_IMAGE = "chouleang/podinfo"
        GKE_CLUSTER = "go-hello-cluster"
        GKE_ZONE = "asia-southeast1-a"
        PROJECT_ID = "it-enviroment"
        NAMESPACE = "podinfo"
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
                    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                    chmod +x kubectl
                    mv kubectl bin/
                    
                    echo "✅ Tools installed"
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
                            
                            export PATH="\$PWD/bin:\$PATH"
                            
                            gcloud auth activate-service-account --key-file=\${GCP_CREDENTIALS}
                            gcloud container clusters get-credentials \${GKE_CLUSTER} --zone \${GKE_ZONE} --project \${PROJECT_ID}
                            
                            # Create namespace if not exists
                            kubectl create namespace \${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
                            
                            # Apply all GKE manifests (from gke/ directory)
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
                            export PATH="\$PWD/bin:\$PATH"
                            
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
                        export PATH="\$PWD/bin:\$PATH"
                        gcloud auth activate-service-account --key-file=\${GCP_CREDENTIALS}
                        gcloud container clusters get-credentials \${GKE_CLUSTER} --zone \${GKE_ZONE} --project \${PROJECT_ID}
                        SERVICE_IP=\$(kubectl get service podinfo -n \${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                    """
                }
                
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