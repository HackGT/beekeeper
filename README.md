# Beekeeper
HackGT's application deployment service.

## Introduction and Motivation
HackGT stores all deployment configuration in [Beehive](https://github.com/HackGT/beehive), a special repository inside our GitHub organization. Each deployment file in Beehive corrseponds to a single deployment of an application running in our Kubernetes cluster. Beekeeper serves as an intermediary between Beehive and Kubernetes. The service is responsible for reading in new application configurations from Beehive and generating appropriate Kubernetes objects that can be fed to the cluster orchestrator.

## Jobs
### UpdateDeploymentJob
This job is responsible for creating or updating a single deployment. This involves templating out Kubernetes configurations, wiring DNS via Cloudflare's API, and reporting status via the GitHub deployment API.

### DeleteDeploymentJob
This job is responsble for cleaning up a deployment that is removed. The job removes the corresponding Kubernetes `Deployment` and `Service` objects and removes the DNS entry for the deployment.

## Endpoints
### `/api/github_webhooks`
This endpoint recieves webhooks when GitHub pushes are made to `HackGT/beehive`. The push is diffed with the previous repository head, and jobs are spanwed for  added/modified (UpdateDeploymentJob) and deleted (DeleteDeploymentJob) application configurations.

### `/api/version_updates`
This endpoints recieves hooks from Google Cloud Build when a commit is finished building for any HackGT application. The commit a list of running deployments, and, if any are from the same repository, an UpdateDeploymentJob is initiated for the deployments matching. For example, if a new commit was pushed to `master` of `HackGT/registration`, any currently deployed instances of `HackGT/registration` that track the `master` branch would be updated to the new commit.
