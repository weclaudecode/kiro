# Packaging

Three options, in increasing order of size and cold-start cost.

## Zip with `requirements.txt`

The simplest option. Install dependencies into a directory, zip it with the handler, upload. The deployment package limit is 50 MB zipped, 250 MB unzipped (including any layers).

```
pip install --target ./package --platform manylinux2014_x86_64 \
    --only-binary=:all: --python-version 3.12 -r requirements.txt
cp app.py ./package/
( cd package && zip -r ../function.zip . )
```

The `--platform manylinux2014_x86_64` flag is critical when building on macOS or Windows — it forces pip to download Linux wheels instead of building from source for the local platform. For ARM Lambdas use `manylinux2014_aarch64`.

A ready-to-use build script is provided in `scripts/build_zip.sh`.

## Layers

A layer is a separately versioned zip mounted at `/opt` at runtime. Use layers to share heavy dependencies (boto3 patches, ORM, ML libraries) across multiple functions.

```
mkdir -p layer/python
pip install --target ./layer/python --platform manylinux2014_x86_64 \
    --only-binary=:all: --python-version 3.12 -r layer-requirements.txt
( cd layer && zip -r ../layer.zip python )
aws lambda publish-layer-version --layer-name shared-deps --zip-file fileb://layer.zip
```

Layers count against the 250 MB unzipped limit. A function may attach up to 5 layers. Layer versions are immutable; bumping a dep means publishing a new version and updating the function.

The official AWS-managed Powertools layer is generally preferable to bundling Powertools yourself — see the `aws-lambda-powertools-python-layer-v3` ARNs published by AWS per region.

## Container images

Up to 10 GB image size, custom runtimes, full control over the OS layer. Cold starts are slower than zip (typically 1-3s extra on first init), but Lambda caches frequently-used layers across invocations.

```dockerfile
FROM public.ecr.aws/lambda/python:3.12

COPY requirements.txt .
RUN pip install -r requirements.txt --target "${LAMBDA_TASK_ROOT}"

COPY app.py ${LAMBDA_TASK_ROOT}

CMD ["app.handler"]
```

A ready-to-use multi-stage `Dockerfile` is provided in `assets/Dockerfile`.

Build, push to ECR, and configure the function to use the image URI. Use container images when:

- Dependencies exceed the 250 MB layer limit
- A custom system library is needed
- The same image is used in both Lambda and a non-Lambda runtime (ECS, local development)

For SAM users, `sam build --use-container` runs the build inside the official Lambda build image and produces correct Linux wheels regardless of the host OS.

## CI/CD

Pipelines that build and deploy zip or container Lambdas — including building on the right Linux/architecture and producing deterministic artifacts — are covered in the `gitlab-pipeline` skill (or your platform's equivalent). Avoid building Lambda artifacts on a developer macOS or Windows host without the `--platform` flag; native-built wheels will fail at runtime.

## Architecture choice

Set the function architecture to `arm64` (Graviton) unless a dependency only ships x86_64 wheels. Build with `--platform manylinux2014_aarch64` to match. Graviton is typically 20% cheaper per GB-second and equivalent or faster on most Python workloads.
