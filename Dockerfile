# The dbt runner's Lambda image: AWS's Lambda Python base, dbt and the Athena adapter at the
# versions in uv.lock (installed with their hashes checked), and the dbt project.
# Build it with scripts/build-image.sh, which exports the requirements first.
# checkov:skip=CKV_DOCKER_2:Lambda images have no health check; Lambda manages the container
# checkov:skip=CKV_DOCKER_3:Lambda runs the image as its own unprivileged user
FROM public.ecr.aws/lambda/python:3.14@sha256:497df5d229e6d5c54279a6a48e7f597ff386bd02a9b3b37e788bb881108fc081 AS dependencies

# One dependency (mmh3, pinned by dbt-athena) has no prebuilt wheel for this Python, so this
# stage has a compiler. Only the installed packages are copied into the final image.
RUN dnf install -y gcc && dnf clean all
COPY build/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --require-hashes --target /opt/dependencies -r /tmp/requirements.txt

FROM public.ecr.aws/lambda/python:3.14@sha256:497df5d229e6d5c54279a6a48e7f597ff386bd02a9b3b37e788bb881108fc081

COPY --from=dependencies /opt/dependencies ${LAMBDA_TASK_ROOT}

COPY dbt_project.yml profiles.yml ${LAMBDA_TASK_ROOT}/dbt/
COPY models ${LAMBDA_TASK_ROOT}/dbt/models
COPY data-tests ${LAMBDA_TASK_ROOT}/dbt/data-tests
COPY src/runner ${LAMBDA_TASK_ROOT}/runner

# dbt writes its working files (compiled SQL, logs) under /tmp, the only writable path.
ENV DBT_PROJECT_DIR=${LAMBDA_TASK_ROOT}/dbt \
    DBT_TARGET_PATH=/tmp/dbt/target \
    DBT_LOG_PATH=/tmp/dbt/logs \
    HOME=/tmp

CMD ["runner.handler.handler"]
