from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor, ConsoleSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource

def setup_observability(service_name="cve-multi-agent-service"):
    """Sets up OpenTelemetry tracing."""
    resource = Resource(attributes={
        "service.name": service_name
    })

    provider = TracerProvider(resource=resource)
    
    # Use ConsoleSpanExporter for demonstration purposes in the terminal
    console_exporter = ConsoleSpanExporter()
    processor = BatchSpanProcessor(console_exporter)
    provider.add_span_processor(processor)

    # Also try to setup OTLP exporter if needed, but console is good for immediate verification
    # otlp_exporter = OTLPSpanExporter(endpoint="http://localhost:4317", insecure=True)
    # otlp_processor = BatchSpanProcessor(otlp_exporter)
    # provider.add_span_processor(otlp_processor)

    trace.set_tracer_provider(provider)
    return trace.get_tracer(__name__)

tracer = setup_observability()
