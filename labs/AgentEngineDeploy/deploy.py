import os
import sys
# pyrefly: ignore [missing-import]
import vertexai
# pyrefly: ignore [missing-import]
from vertexai.agent_engines import AdkApp
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from agent import root_agent

project = os.getenv("GOOGLE_CLOUD_PROJECT")
location = os.getenv("GOOGLE_CLOUD_LOCATION")
staging_bucket = os.getenv("STAGING_BUCKET")

if not all([project, location, staging_bucket]):
    raise EnvironmentError(
        "Missing required environment variables: "
        "GOOGLE_CLOUD_PROJECT, GOOGLE_CLOUD_LOCATION, and STAGING_BUCKET must all be set."
    )

vertexai.init(
    project=project,
    location=location,
    staging_bucket=staging_bucket,
)

agent = AdkApp(
    agent=root_agent,
    enable_tracing=True,
)

print(f"Agent '{root_agent.name}' deployed with resource name: '{agent.resource_name}'")
print(f"Deployment finished!")
