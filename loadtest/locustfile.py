import os
from locust import HttpUser, task, between

TARGET_HOST = os.getenv("TARGET_HOST", "http://localhost")

class ApiUser(HttpUser):
    host = TARGET_HOST
    wait_time = between(0.05, 0.2)

    @task(5)
    def health(self):
        self.client.get("/health")

    @task(2)
    def root(self):
        self.client.get("/")
