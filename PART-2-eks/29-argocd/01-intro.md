# 🌈 Benefits

- CI: Code management in a Repository, Commit Code, Testing Code, Build code
  into container image, and store container image in a registry such as: AWS
  CodeCommit, GitHub, GitLab
- CD: Deploy the containers to real k8s env as Pod, Deployment, Service

# 1️⃣ Without ArgoCD

### Aproach 1 - Jenkin

- User commits code to a Repo
- Jenkin CI will test and build code into a docker image
- Jenkin CI will push the container image to a Registry such as: docker hub, ECR
- Jenkin CI will update manifest k8s file
- Use kubectl, helm command to deploy into k8s cluster

### Aproach 2 - AWS

- User commits code to a AWS CodeCommit
- AWS CodeBuild will test and build code into a docker image
- AWS CodeBuild will push the container image to a Registry such as: Amazon ECR
- AWS CodeBuild will update manifest k8s file
- Use kubectl, helm command on AWS CodeBuild to deploy into EKS cluster

### Challenges

- Install and configure helm / kubectl to access k8s cluster
- Configure credentials to access k8s cluster
- Security challenges if hybrid env

# 2️⃣ With ArgoCD

- We are still keeping the CI process to have a correct and lean docker image.
- ArgoCD will work on CD part
- We will have 2 repositories
  - Application repo: store source code of application itself
  - Manifest repo: store k8s manifest such as: service, deployment
- ArgoCD use `polling` mechanism to check changes on Manifest repo (3 minutes
  interval) or configure webhook to push new changes on repo to ArgoCD
- You have to install argoCD in your k8s cluster

**Benefits**:

- Separate of concerns (App repo and Manifest repo)
- Dev team can access App Repo, Ops team can work work Manifest repo
