# Docker — Simple App

A Node.js Express app containerized with Docker.

## Install Docker

> Guide: https://docs.docker.com/desktop/

**macOS**
```sh
brew install --cask docker
```

**Linux (Ubuntu/Debian)**
```sh
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER  # run docker without sudo (re-login required)
```

**Windows** — Download [Docker Desktop](https://www.docker.com/products/docker-desktop)

Verify installation:
```sh
docker --version
```

---

## Common Commands

### Build

```sh
# Build image with a tag
docker build -t simple-app .

# Build with a specific tag version
docker build -t simple-app:1.0.0 .

# Bake the application version into the image (shown on the home page, default: 0)
docker build --build-arg APP_VERSION=2 -t simple-app:v2 .
```

### Configuration

Every variable is optional. An unset or empty variable uses its default.

| Variable | Default | Purpose |
|---|---|---|
| `PORT` | `8080` | Listening port |
| `BACKGROUND_COLOR` | `#283E5B` | Home page background |
| `APP_ENV` | `local` | Environment name shown on the home page (for example `dev`, `prod`) |
| `APP_VERSION` | `0` | Version shown on the home page. Set at build time with `--build-arg`, and `-e APP_VERSION=...` overrides it at run time |
| `LOG_LEVEL` | `info` | `error`, `warn`, `info`, or `debug`. Any other value falls back to `info` |

Other endpoints: `/healthz` (returns `{"status":"ok"}`), `/users`, `/products`.

### Push to Docker Hub and ECR

Images are built for `linux/amd64` and `linux/arm64`, so they run on x86 and Graviton nodes. `docker buildx ... --push` builds and pushes in one step, so no separate `docker push` is needed.

**Docker Hub (vietaws)**
```sh
# Log in (use a Docker Hub access token as password)
docker login -u vietaws

# Build and push
docker buildx build --platform linux/amd64,linux/arm64 \
  -t vietaws/demo:v1 \
  -t vietaws/demo:latest --push .

docker buildx build --platform linux/amd64,linux/arm64 \
--build-arg APP_VERSION=1  -t vietaws/eks:v1 -t vietaws/eks:home -t vietaws/eks:app1 -t vietaws/eks:app2 -t vietaws/eks:orders -t vietaws/eks:payments --push .

docker buildx build --platform linux/amd64,linux/arm64 \
--build-arg APP_VERSION=1 -t vietaws/eks:v1 --push .
```

**Amazon ECR (private)**
```sh
# Create the repository once
aws ecr create-repository --repository-name demo --region ap-southeast-1

# Log in to the registry
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin \
  274595021951.dkr.ecr.ap-southeast-1.amazonaws.com

# Build and push
docker buildx build --platform linux/amd64,linux/arm64 \
  -t 274595021951.dkr.ecr.ap-southeast-1.amazonaws.com/demo:v1 \
  -t 274595021951.dkr.ecr.ap-southeast-1.amazonaws.com/demo:latest --push .


docker buildx build --platform linux/amd64,linux/arm64 \
-t 274595021951.dkr.ecr.ap-southeast-1.amazonaws.com/demo:v2 \
--build-arg APP_VERSION=2 --push .
```

**Push to both registries in one build**
```sh
docker buildx build --platform linux/amd64,linux/arm64 \
  -t vietaws/demo:v1 \
  -t 274595021951.dkr.ecr.ap-southeast-1.amazonaws.com/demo:v1 --push .
```

**Verify**
```sh
docker buildx imagetools inspect vietaws/demo:v1
aws ecr describe-images --repository-name demo --region ap-southeast-1
```

**Single-platform alternative** (tag and push a local image)
```sh
docker build -t demo .
docker tag demo vietaws/demo:v1 && docker push vietaws/demo:v1
docker tag demo 274595021951.dkr.ecr.ap-southeast-1.amazonaws.com/demo:v1 && docker push 274595021951.dkr.ecr.ap-southeast-1.amazonaws.com/demo:v1
```

Notes:
- ECR login tokens expire after 12 hours. Re-run the login command when push fails with `no basic auth credentials`.
- The IAM identity needs `ecr:GetAuthorizationToken` plus push permissions (`ecr:BatchCheckLayerAvailability`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, `ecr:PutImage`) on the repository.
- If buildx reports that multi-platform is unsupported, run `docker buildx create --use` once.

### Images

```sh
# List all local images
docker images

# Remove an image
docker rmi simple-app
```

### Run

```sh
# Run container locally (detached, port mapped)
docker run -d -p 8081:8080 --name simple-app1 simple-app

# Run with environment variables
docker run -d -p 8082:8080 -e BACKGROUND_COLOR=green --name simple-app2 simple-app

# Run interactively (foreground)
docker run -it --rm -p 8083:8080 simple-app
```

App will be available at: http://localhost:8081

### Containers

```sh
# List running containers
docker ps

# List all containers (including stopped)
docker ps -a

# Stop a container
docker stop simple-app

# Remove a container
docker rm simple-app
```

### Exec

```sh
# Open a shell inside a running container
docker exec -it simple-app sh

# Run a one-off command
docker exec simple-app node --version
```

### Logs

```sh
# View container logs
docker logs simple-app

# Follow logs in real time
docker logs -f simple-app

# Show last 50 lines
docker logs --tail 50 simple-app
```