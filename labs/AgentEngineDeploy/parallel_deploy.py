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
    query = "CVE-2024-1234"
    print(f"Starting parallel execution for query: {query}")
    
    with tracer.start_as_current_span("parallel_agent_execution"):
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            # Submit tasks for each agent
            future_nist = executor.submit(run_agent, nist_agent, query)
            future_mitre = executor.submit(run_agent, mitre_agent, query)
            
            # Wait for CVE fetchers to complete before remediation?
            # The prompt asks for "parallel adk agent observability".
            # We can run them all in parallel, but remediation might need input.
            # For the sake of "parallel" demo, we'll run remediation on the query directly
            # or maybe we can chain them. 
            # Let's run NIST and MITRE in parallel, then Remediation.
            # But to show "all agent run in parallel" as requested:
            # "As well have all the agent run in parallel"
            # So I will run all 3 in parallel.
            future_remediation = executor.submit(run_agent, remediation_agent, query)
            
            futures = [future_nist, future_mitre, future_remediation]
            
            for future in concurrent.futures.as_completed(futures):
                print(f"Result: {future.result()}")

if __name__ == "__main__":
    main()
