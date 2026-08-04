#%%
import os
# pyrefly: ignore [missing-import]
from dotenv import load_dotenv
from typing import Optional
# pyrefly: ignore [missing-import]
from google.genai import types
# pyrefly: ignore [missing-import]
from google.adk.agents import Agent
# pyrefly: ignore [missing-import]
from google.adk.tools import google_search
# pyrefly: ignore [missing-import]
from google.adk.models import LlmResponse, LlmRequest
# pyrefly: ignore [missing-import]
from google.adk.agents.callback_context import CallbackContext
# pyrefly: ignore [missing-import]
from google.api_core.client_options import ClientOptions
# pyrefly: ignore [missing-import]
from google.cloud import modelarmor_v1
load_dotenv()

_client = None

def get_model_armor_client():
    global _client
    if _client is None:
        loc = os.getenv("GOOGLE_CLOUD_LOCATION") or "us-central1"
        _client = modelarmor_v1.ModelArmorClient(
            transport="rest",
            client_options=ClientOptions(api_endpoint=f"modelarmor.{loc}.rep.googleapis.com")
        )
    return _client


def model_armor_analyze(prompt: str):
    project = os.getenv("GOOGLE_CLOUD_PROJECT")
    location = os.getenv("GOOGLE_CLOUD_LOCATION")
    endpoint_id = os.getenv("AIP_ENDPOINT_ID")

    if not all([project, location, endpoint_id]):
        print("[ModelArmor] Warning: Missing required env vars (GOOGLE_CLOUD_PROJECT, GOOGLE_CLOUD_LOCATION, AIP_ENDPOINT_ID)")
        return None, None, None

    print(f"[ModelArmor] Analyzing prompt (len={len(prompt)})")
    print(f"[ModelArmor] Using endpoint: projects/{project}/locations/{location}/templates/{endpoint_id}")
    
    try:
        user_prompt_data = modelarmor_v1.DataItem(text=prompt)
        request = modelarmor_v1.SanitizeUserPromptRequest(
            name=f"projects/{project}/locations/{location}/templates/{endpoint_id}",
            user_prompt_data=user_prompt_data    
        )
        
        client = get_model_armor_client()
        response = client.sanitize_user_prompt(request=request)
        print(response)
        
        filter_results = response.sanitization_result.filter_results
        jailbreak = filter_results.get("pi_and_jailbreak")
        sensitive_data = filter_results.get("sdp")
        malicious_content = filter_results.get("malicious_uris")

        return jailbreak, sensitive_data, malicious_content
    except Exception as e:
        print(f"[ModelArmor] Error analyzing prompt with Model Armor: {e}")
        return None, None, None


def _is_match_found(filter_obj) -> bool:
    if not filter_obj:
        return False
    match_state = getattr(filter_obj, "match_state", None)
    if match_state is None:
        return False
    return (
        match_state == modelarmor_v1.FilterMatchState.MATCH_FOUND
        or getattr(match_state, "name", "") == "MATCH_FOUND"
    )


def extract_pii_info_types(sdp_filter_result: modelarmor_v1.SdpFilterResult) -> list:
    info_types = []
    if sdp_filter_result.inspect_result and sdp_filter_result.inspect_result.findings:
        for finding in sdp_filter_result.inspect_result.findings:
            if finding.info_type and finding.info_type.name not in info_types:
                info_types.append(finding.info_type.name)
    if not info_types and sdp_filter_result.deidentify_result and sdp_filter_result.deidentify_result.info_types:
        for it in sdp_filter_result.deidentify_result.info_types:
            name = getattr(it, "name", str(it))
            if name not in info_types:
                info_types.append(name)
    return info_types


def guardrail_function(callback_context: CallbackContext, llm_request: LlmRequest) -> Optional[LlmResponse]:
    agent_name = callback_context.agent_name
    print(f"[Callback] Before model call for agent: {agent_name}")

    pii_found = callback_context.state.get("PII", False)

    # Search backwards through contents for the latest user text message
    last_user_message = ""
    if llm_request.contents:
        for content in reversed(llm_request.contents):
            if content.role == "user" and content.parts:
                for part in content.parts:
                    text = getattr(part, "text", None)
                    if text:
                        last_user_message = text
                        break
                if last_user_message:
                    break

    print(f"[Callback] Inspecting last user message: '{last_user_message}'")

    # If we are in a pending PII confirmation state, process the user's Yes/No reply.
    if pii_found:
        user_reply = str(last_user_message).strip().lower()
        if user_reply == "yes":
            callback_context.state["PII"] = False
            # Allow the request to proceed
            return None
        elif user_reply == "no":
            callback_context.state["PII"] = False
            return LlmResponse(
                content=types.Content(
                    role="model",
                    parts=[types.Part(text="Please rephrase your query without personal information.")]
                )
            )
        else:
            return LlmResponse(
                content=types.Content(
                    role="model",
                    parts=[types.Part(text="Please respond Yes/No to continue")]
                )
            )

    if not last_user_message.strip():
        return None

    # First-time analysis of the prompt
    jailbreak, sensitive_data, malicious_content = model_armor_analyze(str(last_user_message))
    
    if sensitive_data and sensitive_data.sdp_filter_result and sensitive_data.sdp_filter_result.inspect_result:
        if _is_match_found(sensitive_data.sdp_filter_result):
            callback_context.state["PII"] = True
            info_types = extract_pii_info_types(sensitive_data.sdp_filter_result)
            info_types_str = ", ".join(info_types) if info_types else "Personal Data"
            return LlmResponse(
                content=types.Content(
                    role="model",
                    parts=[types.Part(
                        text=f"Your query has identified the following personal information:\n{info_types_str}\n\nWould you like to continue? (Yes/No)"
                    )],
                )
            )

    if jailbreak and jailbreak.pi_and_jailbreak_filter_result:
        if _is_match_found(jailbreak.pi_and_jailbreak_filter_result):
            return LlmResponse(
                content=types.Content(
                    role="model",
                    parts=[types.Part(text="Break Reason: Jailbreak")]
                )
            )

    if malicious_content and malicious_content.malicious_uri_filter_result:
        if _is_match_found(malicious_content.malicious_uri_filter_result):
            return LlmResponse(
                content=types.Content(
                    role="model",
                    parts=[types.Part(text="Break Reason: Malicious Content")]
                )
            )

    return None


root_agent = Agent(
    name="root_agent",
    model="gemini-2.5-flash",
    description="You are an Artificial General Intelligence",
    instruction="Answer any question using your `google_search_tool` as your grounding",
    before_model_callback=guardrail_function,
    tools=[google_search]
)
