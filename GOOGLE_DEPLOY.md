# Google App Engine Deployment Guide (usa-input)

This guide provides step-by-step instructions for deploying the Project Voice backend to the `usa-input` Google Cloud project.

## Prerequisites

- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) installed and initialized.
- Node.js and npm installed.
- Python 3.12 installed.

## Step 1: Authentication and Project Configuration

Ensure you are authenticated and using the correct project:

```bash
gcloud auth login
gcloud config set project usa-input
```

## Step 2: Prepare Application Configuration

Create or update your `app.yaml` file. For the `tuned-model` service, the configuration should look like this:

```yaml
runtime: python312
service: tuned-model

env_variables:
  API_KEY: "YOUR_GEMINI_API_KEY_HERE"
  SECRET_KEY: "YOUR_SECRET_KEY_HERE"
  GOOGLE_APPLICATION_CREDENTIALS: "project-voice-476504-c2364420bcb1.json"

handlers:
- url: /static
  static_dir: static
  secure: always

- url: /*
  script: auto
  secure: always
```

**Note:** Ensure that `project-voice-476504-c2364420bcb1.json` (the service account key) is present in the root directory.

**API Key:** The `API_KEY` can be found in the Google Cloud Console at [this link](https://pantheon.corp.google.com/apis/credentials/key/5d7bb1b8-5642-4b3a-8c9a-2ae4b891ed97?project=usa-input). It is named `Gemini_API_for_tuned_model_service_by_zezhang`.

## Step 3: Install Dependencies

Install the necessary Node.js and Python dependencies:

```bash
# Install npm dependencies (ignoring scripts if environment issues occur)
npm install --no-audit --no-fund --ignore-scripts

# Install Python dependencies
pip install -r requirements.txt
```

## Step 4: Build the Frontend

Bundle and minify the frontend assets. If the full `npm run build` fails (e.g., due to Storybook issues), use the direct `esbuild` command:

```bash
# Build i18n
npm run build:i18n

# Bundle frontend
./node_modules/.bin/esbuild src/index.ts --bundle --minify --outfile=static/index.js
```

## Step 5: Deploy to App Engine

Deploy the service to App Engine. Use `--no-promote` if you want to test the version before routing all traffic to it.

```bash
# Standard deployment (promotes to 100% traffic)
gcloud app deploy app.yaml

# Deployment without immediate traffic promotion
gcloud app deploy app.yaml --no-promote
```

## Step 6: Verify Deployment

Once the deployment is complete, you can view the service in your browser or check the logs:

```bash
# Open the service in the browser
gcloud app browse -s tuned-model

# Tail the logs
gcloud app logs tail -s tuned-model
```

## Maintenance Commands

- **List Versions:** `gcloud app versions list --service=tuned-model`
- **Stop a Version:** `gcloud app versions stop VERSION_ID --service=tuned-model`
- **Delete a Version:** `gcloud app versions delete VERSION_ID --service=tuned-model`
- **Split Traffic:** `gcloud app services set-traffic tuned-model --splits VERSION1=0.5,VERSION2=0.5`
