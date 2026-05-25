# Container Lambda for Python 3.12 — multi-stage to keep the final image lean
# and to avoid baking pip / build artifacts into the runtime layer.
#
# Build:
#   docker build -t my-lambda:latest .
#
# Smoke test locally with the Runtime Interface Emulator (bundled in the base):
#   docker run -p 9000:8080 my-lambda:latest
#   curl -XPOST "http://localhost:9000/2015-03-31/functions/function/invocations" \
#        -d '{"order_id":"abc","amount_cents":100,"customer_id":"c1"}'
#
# Push:
#   aws ecr get-login-password --region "$REGION" | docker login --username AWS \
#     --password-stdin "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
#   docker tag my-lambda:latest "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/my-lambda:latest"
#   docker push "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/my-lambda:latest"

# ---- Build stage --------------------------------------------------------------
FROM public.ecr.aws/lambda/python:3.12 AS build

# Install build deps if any wheels need compiling. Most pure-Python and
# manylinux wheels do not, but psycopg, cryptography, lxml, etc. may.
# RUN dnf install -y gcc libpq-devel && dnf clean all

COPY requirements.txt /tmp/requirements.txt

RUN pip install --no-cache-dir \
        --target /var/task \
        -r /tmp/requirements.txt

# ---- Runtime stage ------------------------------------------------------------
FROM public.ecr.aws/lambda/python:3.12

# Copy installed dependencies from the build stage.
COPY --from=build /var/task ${LAMBDA_TASK_ROOT}

# Copy application code last so source changes do not bust the deps layer.
COPY src/ ${LAMBDA_TASK_ROOT}/

# Update to match the actual handler module.function path.
CMD ["app.handler"]
