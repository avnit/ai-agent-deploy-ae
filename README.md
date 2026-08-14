# content-repo-template
Template for Git Whisperer content repositories.

<!-- ARCH-DIAGRAM:START -->

## Architecture

> Auto-generated architecture diagram. See [`docs/context-map.md`](docs/context-map.md) for the full context map (core application, containers/cloud, and database connections).

```mermaid
flowchart TD
  User([User / Client])
  App["ai-agent-deploy-ae<br/><small>agent.py</small><br/>FastAPI + Uvicorn"]
  AI["Vertex AI / Gemini<br/>(LLM / Agent Engine)"]
  DB0[("PostgreSQL / AlloyDB")]
  DB1[("BigQuery (analytics)")]
  SVC0["Firebase / Firestore"]
  Deploy["Google Cloud Run"]
  User --> App
  App --> AI
  App --> DB0
  App --> DB1
  App --> SVC0
  App -.deploy.-> Deploy
```

<!-- ARCH-DIAGRAM:END -->
