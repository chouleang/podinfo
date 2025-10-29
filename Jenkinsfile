pipeline {
    agent none // No global agent
    
    environment {
        DOCKER_REGISTRY = "chouleangma"
        DOCKER_IMAGE_NAME = "podinfo"
        GKE_CLUSTER = "your-gke-cluster-name"
        GKE_ZONE = "your-cluster-zone"
        PROJECT_ID = "your-gcp-project-id"
        NAMESPACE = "podinfo"
    }
    
    stages {
        // STAGE 1: CI - Build and Test in Docker Container
        stage('CI - Build and Test') {
            agent {
                docker {
                    image 'golang:1.21-alpine'
                    args '--privileged -v /var/run/docker.sock:/var/run/docker.sock'
                }
            }
            environment {
                DOCKER_BUILDKIT = "1"
            }
            steps {
                checkout scm
                sh '''
                    echo "🏗️ CI Phase: Building and Testing..."
                    cd go
                    
                    # Run tests
                    echo "🧪 Running tests..."
                    go test ./... -v
                    go vet ./...
                    
                    # Build with BuildKit
                    echo "🔨 Building Docker image..."
                    docker build \\
                        --tag ${DOCKER_REGISTRY}/${DOCKER_IMAGE_NAME}:${BUILD_ID} \\
                        --tag ${DOCKER_REGISTRY}/${DOCKER_IMAGE_NAME}:latest \\
                        --progress=plain \\
                        .
                    
                    echo "✅ CI phase completed"
                '''
            }
            post {
                success {
                    sh '''
                        echo "📦 Pushing to Docker Hub..."
                        docker login -u $DOCKER_USER -p $DOCKER_PASS
                        docker push ${DOCKER_REGISTRY}/${DOCKER_IMAGE_NAME}:${BUILD_ID}
                        docker push ${DOCKER_REGISTRY}/${DOCKER_IMAGE_NAME}:latest
                        echo "✅ Images pushed to Docker Hub"
                    '''
                }
            }
        }
        
        // STAGE 2: CD - Deploy to GKE in Google Cloud SDK Container
        stage('CD - Deploy to GKE') {
            agent {
                docker {
                    image 'google/cloud-sdk:alpine'
                    args '--entrypoint='
                }
            }
            steps {
                script {
                    withCredentials([file(credentialsId: 'gcp-service-account', variable: 'GCP_CREDENTIALS')]) {
                        sh """
                            echo "🚀 CD Phase: Deploying to GKE..."
                            
                            # Authenticate to GCP
                            gcloud auth activate-service-account --key-file=\${GCP_CREDENTIALS}
                            
                            # Get GKE cluster credentials
                            gcloud container clusters get-credentials ${GKE_CLUSTER} --zone ${GKE_ZONE} --project ${PROJECT_ID}
                            
                            echo "✅ GKE access configured"
                            
                            # Create namespace if not exists
                            kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
                            
                            # Apply Kubernetes manifests
                            echo "📁 Applying Kubernetes manifests..."
                            kubectl apply -f k8s/ -n ${NAMESPACE}
                            
                            # Update deployment with new image
                            echo "🔄 Updating deployment with new image..."
                            kubectl set image deployment/podinfo podinfo=${DOCKER_REGISTRY}/${DOCKER_IMAGE_NAME}:${BUILD_ID} -n ${NAMESPACE} --record
                            
                            # Wait for rollout to complete
                            echo "⏳ Waiting for deployment to be ready..."
                            kubectl rollout status deployment/podinfo -n ${NAMESPACE} --timeout=300s
                            
                            echo "✅ CD phase completed!"
                        """
                    }
                }
            }
        }
        
        // STAGE 3: Verification
        stage('Verify Deployment') {
            agent {
                docker {
                    image 'google/cloud-sdk:alpine'
                    args '--entrypoint='
                }
            }
            steps {
                script {
                    withCredentials([file(credentialsId: 'gcp-service-account', variable: 'GCP_CREDENTIALS')]) {
                        sh """
                            gcloud auth activate-service-account --key-file=\${GCP_CREDENTIALS}
                            gcloud container clusters get-credentials ${GKE_CLUSTER} --zone ${GKE_ZONE} --project ${PROJECT_ID}
                            
                            echo "📊 Deployment status:"
                            kubectl get all -n ${NAMESPACE}
                            
                            # Get service external IP
                            SERVICE_IP=\$(kubectl get service podinfo -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                            
                            if [ -n "\$SERVICE_IP" ]; then
                                echo "🎉 PodInfo is available at: http://\${SERVICE_IP}"
                                
                                # Test endpoints using curl (install if needed)
                                apk add --no-cache curl
                                curl -f http://\${SERVICE_IP}/healthz && echo " ✅ Health check passed"
                                curl -f http://\${SERVICE_IP}/readyz && echo " ✅ Readiness check passed"
                                
                                echo ""
                                echo "📋 Deployment Summary:"
                                echo "🌐 URL: http://\${SERVICE_IP}"
                                echo "🐳 Image: ${DOCKER_REGISTRY}/${DOCKER_IMAGE_NAME}:${BUILD_ID}"
                            else
                                echo "⏳ LoadBalancer IP not yet assigned"
                            fi
                        """
                    }
                }
            }
        }
    }
    
    post {
        always {
            echo "🏁 Pipeline execution completed"
        }
        success {
            echo "🎉 SUCCESS: PodInfo CI/CD completed!"
        }
        failure {
            echo "❌ FAILED: Pipeline execution failed"
        }
    }
}