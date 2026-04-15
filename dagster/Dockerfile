FROM python:3.12-slim

RUN pip install --no-cache-dir \
    dagster==1.11.9 \
    dagster-graphql==1.11.9 \
    dagster-webserver==1.11.9 \
    dagster-postgres==0.27.9

ENV DAGSTER_HOME=/opt/dagster/dagster_home
RUN mkdir -p $DAGSTER_HOME

COPY dagster.yaml workspace.yaml $DAGSTER_HOME/

WORKDIR $DAGSTER_HOME
