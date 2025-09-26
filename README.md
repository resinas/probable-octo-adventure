# 🚀 Conferia Backend Deployment Guide

This document explains how to deploy Conferia backend on **Google Cloud** using Docker, Docker Compose, and the provided deployment scripts.

## Requirements

Before starting, make sure you have the following installed:

- [Docker](https://docs.docker.com/get-docker/) (with **Docker Buildx** enabled)  
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) (`gcloud`)  

You also need:

- A **DockerHub account** to push your backend image  
- A **Google Cloud account** with permissions to create and configure virtual machines  

## 1. Prepare Your Docker Image

You need a Docker image of the [backend](https://github.com/conferia/backend) uploaded to **DockerHub**, since the deployment process uses it directly. 

### Build & Push Your Own Image

```bash
docker buildx build --platform linux/amd64 -t <your-username>/<your-backend>:latest .

docker push <your-username>/<your-backend>:latest
```

**⚠️ Mac Users:**
By default, Docker on macOS builds images for Apple processors, which are not compatible. Always specify --platform linux/amd64 when building.

## 2. Download the Deployment Repository

Clone the repository:

```bash
git clone https://github.com/resinas/probable-octo-adventure

cd probable-octo-adventure
```

## 3. Update the Docker Image Reference

Edit `docker-compose.yml`:
- Go to line 37
- Replace the image with your DockerHub image, e.g.:

```yaml
image: <your-username>/<your-backend>:latest
```

## 4. Configure Deployment Parameters

Open `deploy.sh` to check the parameters at the top (lines 5-36). You can edit the default values directly in the script or specify them as environment variables. Most parameters have sensible defaults, so unless you have specific requirements, you can leave them unchanged.

## 5. Run the Deployment Script

Execute:

```bash
./deploy.sh
```

This script will:
- Create and configure the required virtual machines in google cloud.
- Launch all services
- Configure automatic backups for the database and User-uploaded image files

## 6. Configure DNS

Once the script finishes, it will display an IP address. Use this IP to configure your DNS. This domain (or IP) will be the backend endpoint.


## 7. Configure the Frontend

Point [Conferia frontend](https://github.com/Conferia/frontend) to your backend:
- Edit the file: `backend.config.ts`
- Set the backend URL to your DNS name or IP.

This configuration is required regardless of where the backend runs (Google Cloud or a university server).

## 8. Accessing the Database (Optional)

To query the database remotely, use the helper script:

```bash
VM=... ZONE=... MYSQL_PASSWORD=... ./exec_sql_remote.sh path/to/file.sql
```

Like in `deploy.sh`, you can find the configuration variables at the top of the script (lines 5-11).

## 9. Cleanup

If you need to remove everything that was created in Google Cloud by the deployment, use:

```bash
PROJECT_ID=... ZONE=... VM_NAME=... GCS_BUCKET=... ./cleanup.sh
```

This script will delete all virtual machines, storage, and related resources that were created during deployment.

