# Building a Full GitOps + CI/CD Pipeline on My k8s-kvm-lab Cluster

I set out to stop deploying by hand and build a real pipeline: push code → it gets built, scanned, pushed to my registry, and deployed - automatically. This is what I did, brief but complete, step by step.

**Stack:** GitLab (source + CI) → Harbor (private registry) → ArgoCD (GitOps CD) → my own Kubernetes cluster.


## 1. Built `lab-status` - my own app, containerized properly

Wrote a tiny Flask app, then a Dockerfile following key practices from [Sysdig's Dockerfile security guide](https://www.sysdig.com/learn-cloud-native/dockerfile-best-practices):

- **Non-root user** - `USER appuser`, verified with `docker run --rm lab-status:v1 whoami` → `appuser`, not `root`
- **Multi-stage build** - dependencies installed in a `builder` stage, only the final artifacts copied into the runtime image, no build tools shipped
- **Minimal base image** - `python:3.12-slim`
- **`.dockerignore`** - kept `.git`, `__pycache__`, `.env` out of the build context entirely

Built, tagged, and pushed to Harbor:
```bash
docker build -t lab-status:v1 .
docker tag lab-status:v1 <NodeIP>:8081/library/lab-status:v1
docker push <NodeIP>:8081/library/lab-status:v1
```

![lab-status and flask-backend sitting in Harbor](images/03-harbor-repositories.png)

Wrote the Deployment + Service manifest, committed it, created the ArgoCD Application, synced - two healthy pods running.


## 2. Built the missing CI half - GitLab CI/CD

ArgoCD only covers **CD** (git → cluster). Getting from **code push → built image** needed real CI.

**Installed a GitLab Runner directly on `master`**, since GitLab's shared runners can't reach my private `<NodeIP>` network:
```bash
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
sudo apt install gitlab-runner
sudo gitlab-runner register --url https://gitlab.com --token <registration-token> --executor shell
```
Chose **shell executor** deliberately - jobs run directly on `master` where Docker, `kubectl`, and `git` already work, no Docker-in-Docker complexity needed for a single-node lab runner.

**Created a Harbor Robot Account** scoped to just `Repository: Pull + Push` - not `admin` - so a leaked CI credential can only push images, nothing else.

**Stored secrets as protected, masked GitLab CI/CD variables** - never in the pipeline file itself:

![CI/CD variables: GIT_PUSH_TOKEN, HARBOR_PASS, HARBOR_USER, all masked and protected](../images/ci-cd_variables.png)

**Wrote `.gitlab-ci.yml`:**
```yaml
stages:
  - build
  - update-manifest

variables:
  IMAGE_NAME: <NodeIP>:8081/library/lab-status
  IMAGE_TAG: $CI_COMMIT_SHORT_SHA
  APP_PATH: apps/lab-status

build-image:
  stage: build
  tags: [lab-master]
  rules:
    - if: '$CI_COMMIT_MESSAGE !~ /\[skip ci\]/'
      changes: [apps/lab-status/**/*]
  script:
    - echo "$HARBOR_PASS" | docker login <NodeIP>:8081 -u "$HARBOR_USER" --password-stdin
    - docker build -t $IMAGE_NAME:$IMAGE_TAG $APP_PATH
    - docker push $IMAGE_NAME:$IMAGE_TAG

update-manifest:
  stage: update-manifest
  tags: [lab-master]
  rules:
    - if: '$CI_COMMIT_MESSAGE !~ /\[skip ci\]/'
      changes: [apps/lab-status/**/*]
  script:
    - 'sed -i "s|image: .*lab-status:.*|image: $IMAGE_NAME:$IMAGE_TAG|" $APP_PATH/deployment.yaml'
    - git config user.email "emmuigai@safaricom.co.ke"
    - git config user.name "GitLab CI"
    - git remote set-url origin https://scripted.muigai:${GIT_PUSH_TOKEN}@gitlab.com/safaricom-plc-group/container-platform.git
    - git add $APP_PATH/deployment.yaml
    - 'git commit -m "ci: update lab-status image to $IMAGE_TAG [skip ci]"'
    - git push origin HEAD:main
```

**`[skip ci]` is load-bearing** - without it, the CI job's own commit back to `main` would re-trigger itself, forever.

Every push into `apps/lab-status/` now automatically: builds the image, tags it with the commit SHA, pushes to Harbor, rewrites the deployment manifest, and commits that change back - for ArgoCD to pick up and deploy.

![Full pipeline history in GitLab](../images/Debugging.png)



## The debugging, honestly - three real bugs, not one

**1. YAML swallowed my own shell commands.** Any list item containing `key: ` (colon + space) - even buried inside a `sed` or `git commit` string - gets parsed by YAML as a mapping, not text. Fix: wrap the whole line in single quotes.

**2. Docker refused to talk to Harbor over plain HTTP.** Needed `insecure-registries` set in `/etc/docker/daemon.json`, since Harbor here runs HTTP-only, no TLS.

![Debugging the HTTPS-vs-HTTP Harbor connection error inside a failed job log](../images/job.png)

**3. Restarting Docker killed Harbor, and the runner lost socket access.** Two separate side effects of the same fix: Harbor's containers (which run on that same Docker daemon) needed `./startup.sh` to come back up, and `gitlab-runner` needed adding to the `docker` group again, since restarting Docker reset socket permissions.

Each one traced back with the actual job logs, not guesswork - `docker info | grep "Insecure Registries"` as root vs. as `gitlab-runner` was what finally exposed the permissions gap.


## The result

![Pipeline passing end to end](../images/07-pipeline-passed.png)

```
edit app.py → git push
    → GitLab Runner triggers automatically
    → build-image: docker build → docker login → docker push to Harbor
    → update-manifest: rewrites deployment.yaml, commits [skip ci], pushes
    → ArgoCD detects the new commit → sync → pod redeployed
```

Confirmed the deployed pod's image tag matched the exact commit hash CI built from:
```bash
kubectl get pods -l app=lab-status -o jsonpath='{.items[0].spec.containers[0].image}'
# <NodeIP>:8081/library/lab-status:41ac4f2e
```
No manual Docker or `kubectl` command touched that pod after the `git push`.


## Resources

- [Argo CD Getting Started (official)](https://argo-cd.readthedocs.io/en/stable/getting_started/)
- [GitLab Runner installation docs](https://docs.gitlab.com/runner/install/)
- [GitLab CI/CD YAML reference](https://docs.gitlab.com/ee/ci/yaml/)
- [Harbor Robot Accounts docs](https://goharbor.io/docs/latest/working-with-projects/project-configuration/create-robot-accounts/)
- [Sysdig - Top Dockerfile best practices for container security](https://www.sysdig.com/learn-cloud-native/dockerfile-best-practices)
- [Awesome GitOps - curated resource list](https://github.com/weaveworks/awesome-gitops)