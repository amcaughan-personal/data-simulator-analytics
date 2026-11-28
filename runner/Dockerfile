# The dbt runner's Lambda image: AWS's Lambda Python base, dbt and the Athena adapter at the
# versions in uv.lock (installed with their hashes checked), and the dbt project.
# Build it with scripts/build-image.sh (from the repo root), which exports the requirements first.
# checkov:skip=CKV_DOCKER_2:Lambda images have no health check; Lambda manages the container
# checkov:skip=CKV_DOCKER_3:Lambda runs the image as its own unprivileged user
FROM public.ecr.aws/lambda/python:3.14@sha256:ada43e932bb0126f892fd935622eaab1199129865d7164ae66a06bcbbd975be0 AS dependencies

# One dependency (mmh3, pinned by dbt-athena) has no prebuilt wheel for this Python, so this
# stage has a compiler. Only the installed packages are copied into the final image.
RUN dnf install -y gcc && dnf clean all
COPY build/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --require-hashes --target /opt/dependencies -r /tmp/requirements.txt

FROM public.ecr.aws/lambda/python:3.14@sha256:ada43e932bb0126f892fd935622eaab1199129865d7164ae66a06bcbbd975be0

COPY --from=dependencies /opt/dependencies ${LAMBDA_TASK_ROOT}

# The project goes in its own directory: ${LAMBDA_TASK_ROOT}/dbt is the dbt package itself.
COPY dbt ${LAMBDA_TASK_ROOT}/project
COPY runner/*.py ${LAMBDA_TASK_ROOT}/runner/

# dbt writes its working files (compiled SQL, logs) under /tmp, the only writable path.
ENV DBT_PROJECT_DIR=${LAMBDA_TASK_ROOT}/project \
    DBT_TARGET_PATH=/tmp/dbt/target \
    DBT_LOG_PATH=/tmp/dbt/logs \
    HOME=/tmp

CMD ["runner.handler.handler"]
