import os
import sys
import vertexai
from vertexai.agent_engines import AdkApp
# Add the project root to the Python path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

# Import the agent from the modelarmor module
from modelarmor.agent import root_agent

project = os.getenv("GOOGLE_CLOUD_PROJECT")
location = os.getenv("GOOGLE_CLOUD_LOCATION")
staging_bucket = os.getenv("STAGING_BUCKET")
# endpoint_id = os.getenv("AIP_ENDPOINT_ID")

# project = "data-vpc-sc-demo"
# location ="us-east4"
# Initialize the Vertex AI SDK
vertexai.init(
    project=project,  # Replace with your Google Cloud project ID
    location=location,
    staging_bucket= staging_bucket# Replace with your desired region (e.g., "us-central1")
 )

# Build and deploy the agent
agent = AdkApp(
    agent = root_agent,
    enable_tracing=True,
)

print(f"Agent '{agent.name}' deployed with resource name: '{agent.resource_name}'")

# remote_app = ae.create(
#     agent_engine = agent,
#     requirements = [
#         "google-cloud-aiplatform[adk,agent_engines]",
#         "google-cloud-modelarmor", # Added this requirement
#         "google-adk",              # Added this requirement
#         "pydantic==2.11.7",        # Added these based on your error message
#         "cloudpickle==3.1.1"       # Added these based on your error message
#     ]
# )

print(f"Deployment finished!")