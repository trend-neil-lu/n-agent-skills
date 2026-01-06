---
name: github-actions-gcp
description: Create GitHub Actions workflows for GCP Cloud Run CI/CD with reusable composite actions. Triggers on 'github actions gcp', 'cloud run ci/cd', 'gcp workflow', 'deploy cloud run github'.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# GitHub Actions for GCP Cloud Run CI/CD

Create production-ready GitHub Actions workflows for GCP Cloud Run deployment with reusable composite actions.

## Workflow Structure

```text
.github/
├── workflows/
│   ├── build.yml                 # Reusable build workflow
│   ├── release.yml               # CI: Push to main → Deploy to Dev
│   ├── test-and-publish-for-pr.yml  # PR: Build and publish for testing
│   ├── promote-to-prod.yml       # Promote from Dev to Prod
│   ├── manual-deploy.yml         # Manual deployment trigger
│   └── security-scan.yml         # Scheduled security scans
├── cloud-run/
│   ├── dev.yaml                  # Cloud Run Service config (Dev)
│   ├── staging.yaml              # Cloud Run Service config (Staging)
│   └── prod.yaml                 # Cloud Run Service config (Prod)
└── cloud-run-jobs/
    └── dev.yaml                  # Cloud Run Job config (Dev)
```

## Reusable Composite Actions

### GCP Authentication (Workload Identity Federation)

```yaml
# actions/gcp-auth/action.yml
name: 'Authenticate to Google Cloud'
description: 'Authenticate to GCP using Workload Identity Federation'

inputs:
  workload_identity_provider:
    description: 'GCP Workload Identity Provider'
    required: true
  service_account:
    description: 'GCP Service Account email'
    required: true
  environment:
    description: 'Environment label (dev, staging, prod)'
    required: false
    default: ''

runs:
  using: 'composite'
  steps:
    - name: Authenticate to Google Cloud
      uses: google-github-actions/auth@v2
      with:
        workload_identity_provider: ${{ inputs.workload_identity_provider }}
        service_account: ${{ inputs.service_account }}

    - name: Set up Cloud SDK
      uses: google-github-actions/setup-gcloud@v2

    - name: Output summary
      shell: bash
      run: |
        {
          echo "## GCP Authentication"
          echo ""
          if [ -n "${{ inputs.environment }}" ]; then
            echo "- **Environment**: ${{ inputs.environment }}"
          fi
          echo "- **Service Account**: ${{ inputs.service_account }}"
        } >> "$GITHUB_STEP_SUMMARY"
```

### GCP Artifact Registry Push

```yaml
# actions/gcp-artifact-registry-push/action.yml
name: 'Push Docker image to GCP Artifact Registry'
description: 'Push Docker image to GCP Artifact Registry'

inputs:
  project_id:
    description: 'GCP Project ID'
    required: true
  repository:
    description: 'Artifact Registry repository name'
    required: true
  region:
    description: 'Region (asia, us, europe)'
    required: true
  image_name:
    description: 'Docker image name'
    required: true
  version:
    description: 'Version tag'
    required: true
  branch:
    description: 'Branch name for tagging'
    required: false
    default: ''
  git_sha:
    description: 'Git SHA for tagging'
    required: false
    default: ''
  push_latest:
    description: 'Push latest tag'
    required: false
    default: 'false'
  source_image:
    description: 'Source image (default: {image_name}:latest)'
    required: false
    default: ''

outputs:
  image_url:
    description: 'Primary image URL with version tag'
    value: ${{ steps.push.outputs.image_url }}
  registry:
    description: 'Full registry path'
    value: ${{ steps.push.outputs.registry }}

runs:
  using: 'composite'
  steps:
    - name: Configure Docker for Artifact Registry
      shell: bash
      run: |
        gcloud auth configure-docker ${{ inputs.region }}-docker.pkg.dev --quiet

    - name: Tag and push Docker image
      id: push
      shell: bash
      env:
        PROJECT_ID: ${{ inputs.project_id }}
        REPOSITORY: ${{ inputs.repository }}
        REGION: ${{ inputs.region }}
        IMAGE_NAME: ${{ inputs.image_name }}
        VERSION: ${{ inputs.version }}
        BRANCH: ${{ inputs.branch }}
        GIT_SHA: ${{ inputs.git_sha }}
        PUSH_LATEST: ${{ inputs.push_latest }}
        SOURCE_IMAGE: ${{ inputs.source_image }}
      run: |
        REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}"
        LOCAL_IMAGE="${SOURCE_IMAGE:-${IMAGE_NAME}:latest}"

        echo "registry=${REGISTRY}" >> "$GITHUB_OUTPUT"
        echo "image_url=${REGISTRY}/${IMAGE_NAME}:${VERSION}" >> "$GITHUB_OUTPUT"

        # Push version tag
        docker tag ${LOCAL_IMAGE} ${REGISTRY}/${IMAGE_NAME}:${VERSION}
        docker push ${REGISTRY}/${IMAGE_NAME}:${VERSION}

        # Push branch tags
        if [ -n "${BRANCH}" ]; then
          docker tag ${LOCAL_IMAGE} ${REGISTRY}/${IMAGE_NAME}:${VERSION}-${BRANCH}
          docker push ${REGISTRY}/${IMAGE_NAME}:${VERSION}-${BRANCH}
          docker tag ${LOCAL_IMAGE} ${REGISTRY}/${IMAGE_NAME}:${BRANCH}
          docker push ${REGISTRY}/${IMAGE_NAME}:${BRANCH}
        fi

        # Push SHA tag
        if [ -n "${GIT_SHA}" ]; then
          SHORT_SHA="${GIT_SHA:0:8}"
          docker tag ${LOCAL_IMAGE} ${REGISTRY}/${IMAGE_NAME}:sha-${SHORT_SHA}
          docker push ${REGISTRY}/${IMAGE_NAME}:sha-${SHORT_SHA}
        fi

        # Push latest tag
        if [ "${PUSH_LATEST}" = "true" ]; then
          docker tag ${LOCAL_IMAGE} ${REGISTRY}/${IMAGE_NAME}:latest
          docker push ${REGISTRY}/${IMAGE_NAME}:latest
        fi
```

### Cloud Run Service Deploy (with Rollback)

```yaml
# actions/gcp-cloudrun-service-deploy/action.yml
name: 'Deploy to Cloud Run Service'
description: 'Deploy Docker image to Cloud Run Service with rollback support'

inputs:
  service_name:
    description: 'Cloud Run service name'
    required: true
  region:
    description: 'GCP region (e.g., asia-east1)'
    required: true
  image:
    description: 'Full Docker image URL'
    required: true
  config_path:
    description: 'Path to Cloud Run YAML config'
    required: true
  version:
    description: 'Version tag for labeling'
    required: false
    default: ''
  enable_rollback:
    description: 'Enable automatic rollback on failure'
    required: false
    default: 'true'

outputs:
  service_url:
    description: 'Cloud Run service URL'
    value: ${{ steps.deploy.outputs.service_url }}
  revision:
    description: 'Deployed revision name'
    value: ${{ steps.verify.outputs.revision }}

runs:
  using: 'composite'
  steps:
    - name: Get current revision for rollback
      id: current_revision
      shell: bash
      env:
        SERVICE_NAME: ${{ inputs.service_name }}
        REGION: ${{ inputs.region }}
      run: |
        CURRENT_REVISION=$(gcloud run services describe ${SERVICE_NAME} \
          --region=${REGION} \
          --format='value(status.latestReadyRevisionName)' 2>/dev/null || echo "")

        if [ -n "$CURRENT_REVISION" ]; then
          echo "current_revision=${CURRENT_REVISION}" >> "$GITHUB_OUTPUT"
          echo "has_current_revision=true" >> "$GITHUB_OUTPUT"
        else
          echo "has_current_revision=false" >> "$GITHUB_OUTPUT"
        fi

    - name: Prepare Cloud Run configuration
      shell: bash
      env:
        IMAGE: ${{ inputs.image }}
        VERSION: ${{ inputs.version }}
        CONFIG_PATH: ${{ inputs.config_path }}
        REGION: ${{ inputs.region }}
      run: |
        cp ${CONFIG_PATH} /tmp/cloud-run.yaml
        sed -i "s|IMAGE_PLACEHOLDER|${IMAGE}|g" /tmp/cloud-run.yaml
        if [ -n "${VERSION}" ]; then
          sed -i "s|VERSION_PLACEHOLDER|${VERSION}|g" /tmp/cloud-run.yaml
        fi

    - name: Deploy to Cloud Run
      id: deploy
      shell: bash
      env:
        SERVICE_NAME: ${{ inputs.service_name }}
        REGION: ${{ inputs.region }}
      run: |
        gcloud run services replace /tmp/cloud-run.yaml --region=${REGION}

        SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
          --region=${REGION} --format='value(status.url)')
        echo "service_url=${SERVICE_URL}" >> "$GITHUB_OUTPUT"

    - name: Wait for service to be ready
      shell: bash
      env:
        SERVICE_NAME: ${{ inputs.service_name }}
        REGION: ${{ inputs.region }}
      run: |
        for i in {1..30}; do
          STATUS=$(gcloud run services describe ${SERVICE_NAME} \
            --region=${REGION} --format='value(status.conditions[0].status)')
          if [ "$STATUS" = "True" ]; then
            echo "Service is ready"
            exit 0
          fi
          sleep 10
        done
        exit 1

    - name: Verify deployment
      id: verify
      shell: bash
      env:
        SERVICE_NAME: ${{ inputs.service_name }}
        REGION: ${{ inputs.region }}
      run: |
        LATEST_REVISION=$(gcloud run services describe ${SERVICE_NAME} \
          --region=${REGION} --format='value(status.latestReadyRevisionName)')
        echo "revision=${LATEST_REVISION}" >> "$GITHUB_OUTPUT"

    - name: Rollback on failure
      if: failure() && steps.current_revision.outputs.has_current_revision == 'true' && inputs.enable_rollback == 'true'
      shell: bash
      env:
        SERVICE_NAME: ${{ inputs.service_name }}
        REGION: ${{ inputs.region }}
        CURRENT_REVISION: ${{ steps.current_revision.outputs.current_revision }}
      run: |
        echo "Deployment failed, rolling back to ${CURRENT_REVISION}"
        gcloud run services update-traffic ${SERVICE_NAME} \
          --region=${REGION} --to-revisions=${CURRENT_REVISION}=100
```

### Cloud Run Job Deploy

```yaml
# actions/gcp-cloudrun-job-deploy/action.yml
name: 'Deploy to Cloud Run Job'
description: 'Deploy Docker image to Cloud Run Job'

inputs:
  job_name:
    description: 'Cloud Run job name'
    required: true
  region:
    description: 'GCP region'
    required: true
  image:
    description: 'Full Docker image URL'
    required: true
  config_path:
    description: 'Path to Cloud Run Job YAML config'
    required: true
  version:
    description: 'Version tag'
    required: false
    default: ''
  execute_after_deploy:
    description: 'Execute job after deployment'
    required: false
    default: 'false'
  wait_for_execution:
    description: 'Wait for job execution'
    required: false
    default: 'false'

outputs:
  job_uri:
    description: 'Cloud Run job URI'
    value: ${{ steps.deploy.outputs.job_uri }}
  execution_name:
    description: 'Execution name (if executed)'
    value: ${{ steps.execute.outputs.execution_name }}

runs:
  using: 'composite'
  steps:
    - name: Prepare configuration
      shell: bash
      env:
        IMAGE: ${{ inputs.image }}
        VERSION: ${{ inputs.version }}
        CONFIG_PATH: ${{ inputs.config_path }}
        REGION: ${{ inputs.region }}
      run: |
        cp ${CONFIG_PATH} /tmp/cloud-run-job.yaml
        sed -i "s|IMAGE_PLACEHOLDER|${IMAGE}|g" /tmp/cloud-run-job.yaml
        if [ -n "${VERSION}" ]; then
          sed -i "s|VERSION_PLACEHOLDER|${VERSION}|g" /tmp/cloud-run-job.yaml
        fi

    - name: Deploy Cloud Run Job
      id: deploy
      shell: bash
      env:
        JOB_NAME: ${{ inputs.job_name }}
        REGION: ${{ inputs.region }}
      run: |
        gcloud run jobs replace /tmp/cloud-run-job.yaml --region=${REGION}
        JOB_URI=$(gcloud run jobs describe ${JOB_NAME} \
          --region=${REGION} --format='value(metadata.selfLink)')
        echo "job_uri=${JOB_URI}" >> "$GITHUB_OUTPUT"

    - name: Execute job
      id: execute
      if: inputs.execute_after_deploy == 'true'
      shell: bash
      env:
        JOB_NAME: ${{ inputs.job_name }}
        REGION: ${{ inputs.region }}
        WAIT: ${{ inputs.wait_for_execution }}
      run: |
        if [ "${WAIT}" = "true" ]; then
          EXECUTION=$(gcloud run jobs execute ${JOB_NAME} --region=${REGION} --wait --format='value(metadata.name)')
        else
          EXECUTION=$(gcloud run jobs execute ${JOB_NAME} --region=${REGION} --format='value(metadata.name)')
        fi
        echo "execution_name=${EXECUTION}" >> "$GITHUB_OUTPUT"
```

## Workflow Templates

### Build Workflow (Reusable)

```yaml
# .github/workflows/build.yml
name: 'Build'

on:
  workflow_call:
  workflow_dispatch:

permissions:
  contents: read
  issues: read
  checks: write
  pull-requests: write

env:
  TERM: xterm-color
  FORCE_COLOR: 3

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install uv
        uses: astral-sh/setup-uv@v4
        with:
          enable-cache: true

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version-file: ".python-version"

      - name: Install dependencies
        run: uv sync --all-extras

      - name: Check formatting
        run: uv run ruff format --check src tests

      - name: Lint
        run: uv run ruff check src tests

      - name: Type check
        run: uv run pyright src

      - name: Run unit tests
        run: uv run pytest -m "not integration" --junitxml=report.xml --cov --cov-report=xml

      - name: Publish test results
        uses: EnricoMi/publish-unit-test-result-action@v2
        if: always()
        with:
          files: report.xml

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: false
          tags: |
            ${{ github.event.repository.name }}:${{ github.sha }}
            ${{ github.event.repository.name }}:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max
          outputs: type=docker,dest=/tmp/image.tar

      - name: Store Docker image
        uses: actions/upload-artifact@v4
        with:
          name: docker-image
          path: /tmp/image.tar

      - name: Store version metadata
        uses: actions/upload-artifact@v4
        with:
          name: version-metadata
          path: version.json
```

### Release Workflow (Push to Main)

```yaml
# .github/workflows/release.yml
name: '[CI] Release to Dev'

on:
  push:
    branches: [main]

permissions:
  contents: write
  id-token: write
  issues: read
  checks: write
  pull-requests: write

env:
  IMAGE_NAME: <your-image-name>

jobs:
  build:
    name: Build and test
    uses: ./.github/workflows/build.yml
    secrets: inherit

  setup:
    name: Setup version
    runs-on: ubuntu-latest
    outputs:
      version_already_published: ${{ steps.check.outputs.exists }}
      version: ${{ steps.version.outputs.version }}
      branch: ${{ steps.branch.outputs.branch }}
    steps:
      - uses: actions/checkout@v4

      - name: Get version
        id: version
        run: echo "version=$(jq -r .version version.json)" >> "$GITHUB_OUTPUT"

      - name: Get branch
        id: branch
        run: echo "branch=${GITHUB_REF#refs/heads/}" >> "$GITHUB_OUTPUT"

      - name: Check if version exists
        id: check
        run: |
          if git ls-remote --tags origin | grep -q "refs/tags/${{ steps.version.outputs.version }}$"; then
            echo "exists=true" >> "$GITHUB_OUTPUT"
          else
            echo "exists=false" >> "$GITHUB_OUTPUT"
          fi

  publish:
    name: Publish to Artifact Registry (${{ matrix.region }})
    runs-on: ubuntu-latest
    needs: [build, setup]
    if: needs.setup.outputs.version_already_published == 'false'
    strategy:
      matrix:
        region: [asia, us, europe]
    steps:
      - name: Download Docker image
        uses: actions/download-artifact@v4
        with:
          name: docker-image
          path: /tmp

      - name: Load Docker image
        run: docker load -i /tmp/image.tar

      - name: Authenticate to GCP
        uses: ./.github/actions/gcp-auth
        with:
          workload_identity_provider: ${{ vars.GCP_WIF_PROVIDER_DEV }}
          service_account: ${{ vars.GCP_SA_DEV }}

      - name: Push to Artifact Registry
        uses: ./.github/actions/gcp-artifact-registry-push
        with:
          project_id: ${{ vars.GCP_PROJECT_DEV }}
          repository: ${{ matrix.region }}-registry
          region: ${{ matrix.region }}
          image_name: ${{ env.IMAGE_NAME }}
          version: ${{ needs.setup.outputs.version }}
          branch: ${{ needs.setup.outputs.branch }}
          git_sha: ${{ github.sha }}
          push_latest: 'true'

  deploy:
    name: Deploy to Dev
    runs-on: ubuntu-latest
    needs: [setup, publish]
    if: needs.setup.outputs.version_already_published == 'false'
    environment: dev
    steps:
      - uses: actions/checkout@v4

      - name: Authenticate to GCP
        uses: ./.github/actions/gcp-auth
        with:
          workload_identity_provider: ${{ vars.GCP_WIF_PROVIDER_DEV }}
          service_account: ${{ vars.GCP_SA_DEV }}

      - name: Deploy to Cloud Run
        uses: ./.github/actions/gcp-cloudrun-service-deploy
        with:
          service_name: ${{ vars.SERVICE_NAME_DEV }}
          region: asia-east1
          image: asia-docker.pkg.dev/${{ vars.GCP_PROJECT_DEV }}/asia-registry/${{ env.IMAGE_NAME }}:${{ needs.setup.outputs.version }}
          config_path: .github/cloud-run/dev.yaml
          version: ${{ needs.setup.outputs.version }}

  tag:
    name: Create Git tag
    runs-on: ubuntu-latest
    needs: [setup, deploy]
    if: needs.setup.outputs.version_already_published == 'false'
    steps:
      - name: Create tag
        uses: actions/github-script@v7
        with:
          script: |
            try {
              await github.rest.git.getRef({
                owner: context.repo.owner,
                repo: context.repo.repo,
                ref: 'tags/${{ needs.setup.outputs.version }}'
              });
            } catch (error) {
              if (error.status === 404) {
                await github.rest.git.createRef({
                  owner: context.repo.owner,
                  repo: context.repo.repo,
                  ref: 'refs/tags/${{ needs.setup.outputs.version }}',
                  sha: context.sha
                });
              }
            }
```

### PR Workflow

```yaml
# .github/workflows/test-and-publish-for-pr.yml
name: '[PR] Test & Build'

on:
  pull_request:
    branches: [main]

permissions:
  contents: read
  id-token: write
  issues: read
  checks: write
  pull-requests: write

jobs:
  build:
    name: Build and test
    uses: ./.github/workflows/build.yml
    secrets: inherit

  publish-pr:
    name: Publish PR image
    runs-on: ubuntu-latest
    needs: [build]
    environment: dev
    steps:
      - uses: actions/checkout@v4

      - name: Download Docker image
        uses: actions/download-artifact@v4
        with:
          name: docker-image
          path: /tmp

      - name: Load Docker image
        run: docker load -i /tmp/image.tar

      - name: Get version
        id: version
        run: echo "version=$(jq -r .version version.json)" >> "$GITHUB_OUTPUT"

      - name: Authenticate to GCP
        uses: ./.github/actions/gcp-auth
        with:
          workload_identity_provider: ${{ vars.GCP_WIF_PROVIDER_DEV }}
          service_account: ${{ vars.GCP_SA_DEV }}

      - name: Configure Docker
        run: gcloud auth configure-docker asia-docker.pkg.dev

      - name: Push PR image
        env:
          PR_NUMBER: ${{ github.event.pull_request.number }}
          REGISTRY: asia-docker.pkg.dev/${{ vars.GCP_PROJECT_DEV }}/asia-registry
        run: |
          docker tag ${{ github.event.repository.name }}:latest ${REGISTRY}/${{ github.event.repository.name }}:pr-${PR_NUMBER}
          docker push ${REGISTRY}/${{ github.event.repository.name }}:pr-${PR_NUMBER}

      - name: Output deployment info
        env:
          PR_NUMBER: ${{ github.event.pull_request.number }}
          REGISTRY: asia-docker.pkg.dev/${{ vars.GCP_PROJECT_DEV }}/asia-registry
        run: |
          {
            echo "## PR Image Published"
            echo ""
            echo "**Image**: \`${REGISTRY}/${{ github.event.repository.name }}:pr-${PR_NUMBER}\`"
            echo ""
            echo "### Deploy for testing:"
            echo "\`\`\`bash"
            echo "gcloud run deploy test-pr-${PR_NUMBER} \\"
            echo "  --image=${REGISTRY}/${{ github.event.repository.name }}:pr-${PR_NUMBER} \\"
            echo "  --region=asia-east1"
            echo "\`\`\`"
          } >> "$GITHUB_STEP_SUMMARY"
```

## Cloud Run Service Configuration

```yaml
# .github/cloud-run/dev.yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: <service-name>-dev
  labels:
    cloud.googleapis.com/location: asia-east1
    environment: dev
    managed-by: github-actions
  annotations:
    run.googleapis.com/ingress: internal-and-cloud-load-balancing
    run.googleapis.com/launch-stage: BETA
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: '1'
        autoscaling.knative.dev/maxScale: '50'
        run.googleapis.com/cpu-throttling: 'false'
        run.googleapis.com/startup-cpu-boost: 'true'
        run.googleapis.com/execution-environment: gen2
    spec:
      containerConcurrency: 80
      timeoutSeconds: 300
      serviceAccountName: <sa>@<project>.iam.gserviceaccount.com
      containers:
      - image: IMAGE_PLACEHOLDER
        ports:
        - name: http1
          containerPort: 8080
        env:
        - name: LOG_LEVEL
          value: INFO
        resources:
          limits:
            cpu: '2'
            memory: 2Gi
        startupProbe:
          httpGet:
            path: /startup
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 10
          failureThreshold: 12
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          periodSeconds: 30
          failureThreshold: 3
```

## Required GitHub Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `GCP_WIF_PROVIDER_DEV` | Workload Identity Provider | `projects/123/locations/global/...` |
| `GCP_SA_DEV` | Service Account email | `sa@project.iam.gserviceaccount.com` |
| `GCP_PROJECT_DEV` | GCP Project ID | `my-project-dev` |
| `SERVICE_NAME_DEV` | Cloud Run service name | `my-service-dev` |

## Best Practices

### Workflow Organization

- Use `workflow_call` for reusable workflows
- Use composite actions for common steps
- Use matrix strategy for multi-region deployments
- Use GitHub environments for deployment approvals

### Security

- Use Workload Identity Federation (no service account keys)
- Use environment-specific service accounts
- Enable deployment protection rules
- Use `id-token: write` permission for OIDC

### Versioning

- Use `version.json` for version management
- Create Git tags after successful deployment
- Skip deployment if version already published
- Use semantic versioning

### Rollback

- Store current revision before deployment
- Automatic rollback on deployment failure
- Use traffic splitting for canary deployments

## References

- [Cloud Run YAML Reference](https://cloud.google.com/run/docs/reference/yaml/v1)
- [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [GitHub Actions](https://docs.github.com/en/actions)
