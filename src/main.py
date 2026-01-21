from fastapi import FastAPI

app = FastAPI(title="scalable-app-backend")

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/")
def root():
    return {"message": "hello from ecs"}
