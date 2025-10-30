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
        
        stage('Test') {
            steps {
                sh '''
                    echo "🧪 Running tests..."
                    export PATH="$PWD/bin:$PWD/google-cloud-sdk/bin:$PATH"
                    
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
                        export PATH="$PWD/bin:$PWD/google-cloud-sdk/bin:$PATH"
                        
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
                            export PATH="$PWD/bin:$PWD/google-cloud-sdk/bin:$PATH"
                            docker login -u \$DOCKER_USER -p \$DOCKER_PASS
                            
                            if [ -f "Dockerfile" ]; then
                                docker push ${DOCKER_IMAGE}:\${BUILD_ID}
                                docker push ${DOCKER_IMAGE}:latest
                                echo "✅ Custom image pushed to Docker Hub"
                                echo "Success Build"
                            else
                                echo "ℹ️ Using official PodInfo image, skipping push"
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
            '''
        }
        
    }
}
