from google.adk.agents import Agent
from google.genai import types
from agent import guardrail_function

# Mock tools for CVE data
def search_nist_cve(query: str):
    """Searches the NIST database for CVEs related to the query."""
    return f"Found NIST CVE-2024-1234 for {query}. Severity: High."

def search_mitre_cve(query: str):
    """Searches the MITRE database for CVEs related to the query."""
    return f"Found MITRE CVE-2024-5678 for {query}. Description: Buffer overflow."

def get_gcp_remediation(cve_id: str):
    """Provides Google Cloud remediation steps for a given CVE."""
    return f"Remediation for {cve_id} on GCP: Update to the latest patch level and enable Cloud Armor."

# Define Agents

nist_agent = Agent(
    name="nist_agent",
    model="gemini-2.5-flash",
    description="Agent specialized in finding CVEs from NIST.",
    instruction="You are a security analyst. Use the `search_nist_cve` tool to find CVE information from NIST.",
    tools=[search_nist_cve],
    before_model_callback=guardrail_function
)

mitre_agent = Agent(
    name="mitre_agent",
    model="gemini-2.5-flash",
    description="Agent specialized in finding CVEs from MITRE.",
    instruction="You are a security analyst. Use the `search_mitre_cve` tool to find CVE information from MITRE.",
    tools=[search_mitre_cve],
    before_model_callback=guardrail_function
)

remediation_agent = Agent(
    name="remediation_agent",
    model="gemini-2.5-flash",
    description="Agent specialized in providing GCP remediation instructions.",
    instruction="You are a cloud security expert. Use the `get_gcp_remediation` tool to provide fix instructions for CVEs on Google Cloud.",
    tools=[get_gcp_remediation],
    before_model_callback=guardrail_function
)
