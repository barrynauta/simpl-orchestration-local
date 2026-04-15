"""
Patched repository.py for local evaluation stack.

Registers both the original S3-based jobs and local CSV jobs that read/write
from /data/ inside the container. No S3 configuration required for local jobs.

Sample input data is pre-loaded at /data/sample_input.csv.
Output will be written to /data/output_<job>.csv.
"""
from dagster import Definitions
from util_services.resources import s3_resource
from util_services.custom_json_logger import simpl_json_logger
from dataframe_level_anonymisation.jobs import (
    k_anonymity_job_s3,
    l_diversity_job_s3,
    t_closeness_job_s3,
    k_anonymity_job,
    l_diversity_job,
    t_closeness_job,
)

defs = Definitions(
    jobs=[
        # S3-based jobs (require S3/MinIO configuration)
        k_anonymity_job_s3,
        l_diversity_job_s3,
        t_closeness_job_s3,
        # Local CSV jobs (no S3 required — read/write from /data/)
        k_anonymity_job,
        l_diversity_job,
        t_closeness_job,
    ],
    resources={"s3": s3_resource.configured({"resource_name": "selfS3"})},
    loggers={"simpl": simpl_json_logger}
)
