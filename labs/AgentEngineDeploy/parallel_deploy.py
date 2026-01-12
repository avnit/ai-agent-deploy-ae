import concurrent.futures
import time
from cve_agents import nist_agent, mitre_agent, remediation_agent
from observability import tracer
from opentelemetry import trace

def run_agent(agent, query):
    """Runs a single agent with a query, wrapped in a trace."""
    with tracer.start_as_current_span(f"run_{agent.name}") as span:
        span.set_attribute("agent.name", agent.name)
        span.set_attribute("agent.query", query)
        
        print(f"[{agent.name}] Starting processing for: {query}")
        
        # Simulate agent processing and tool usage
        # In a real scenario, we would call agent.query(query) or similar
        # Here we manually invoke the tool associated with the agent for demonstration
        
        result = ""
        try:
            # Simulate some processing time
            time.sleep(1)
            
            if agent.tools:
                tool = agent.tools[0]
                # Assuming the tool function takes the query as the first argument
                # For remediation, we might need to pass a CVE ID found by previous agents
                # But for parallel demo, we'll just pass the query
                tool_result = tool(query)
                result = f"Agent {agent.name} result: {tool_result}"
            else:
                result = f"Agent {agent.name} processed {query}"
                
            span.set_attribute("agent.result", result)
            print(f"[{agent.name}] Finished: {result}")
            return result
        except Exception as e:
            span.record_exception(e)
            print(f"[{agent.name}] Error: {e}")
            return str(e)

def main():
    # Get query from user input or default
    print("Enter CVE query (or press Enter for default 'CVE-2024-1234'):")
    user_query = input()
    if not user_query:
        user_query = "CVE-2024-1234"
        
    print(f"Starting execution for query: {user_query}")
    
    with tracer.start_as_current_span("agent_orchestration"):
        # Phase 1: Research (Parallel)
        print("\n--- Phase 1: Research (Parallel) ---")
        research_results = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            future_nist = executor.submit(run_agent, nist_agent, user_query)
            future_mitre = executor.submit(run_agent, mitre_agent, user_query)
            
            futures = [future_nist, future_mitre]
            for future in concurrent.futures.as_completed(futures):
                try:
                    result = future.result()
                    research_results.append(result)
                    print(f"Research Result: {result}")
                except Exception as e:
                    print(f"Research Agent failed: {e}")

        # Phase 2: Remediation (Sequential, using research context)
        print("\n--- Phase 2: Remediation (Sequential) ---")
        
        # Combine research results into a context for the remediation agent
        combined_context = f"Query: {user_query}\n"
        combined_context += "Research Findings:\n" + "\n".join(research_results)
        
        # Run remediation agent
        # Note: In a real scenario, we'd pass this context as part of the prompt or a specific tool argument.
        # For this demo, we'll pass the combined context as the 'query' to the agent wrapper.
        remediation_result = run_agent(remediation_agent, combined_context)
        
        print("\n--- Final Report ---")
        print(remediation_result)

if __name__ == "__main__":
    main()
