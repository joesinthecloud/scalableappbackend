## Project: Load-Driven Autoscaling Backend on AWS ECS

### Tech Stack
AWS ECS (Fargate), Application Load Balancer, Terraform, CloudWatch, Docker, Locust, Python, GitHub

---

## Architecture Overview

             ┌─────────────────────────────┐
             │  Load Generator (Locust)    │
             │  ECS One-Off Task            │
             └──────────────┬──────────────┘
                            │ HTTP Traffic
                            ▼
             ┌─────────────────────────────┐
             │ Application Load Balancer    │
             │ (Health Checks + Routing)   │
             └──────────────┬──────────────┘
                            │
          ┌─────────────────┴─────────────────┐
          │ ECS Service (Fargate)               │
          │ Auto-Scaled Containers              │
          │ Min: 2 | Max: 6                     │
          └─────────────────┬─────────────────┘
                            │
                    ┌───────▼────────┐
                    │ Stateless API   │
                    │ / and /health   │
                    └────────────────┘

    flowchart TB
      %% =========================
      %% Internet + ALB
      %% =========================
      U[Users / Clients] -->|HTTP :80| ALB[Application Load Balancer\nscalableappbackend-dev-alb]
      ALB --> L80[Listener :80]
      L80 --> TG[Target Group\nscalableappbackend-dev-tg\nHealth check: /health\nTarget port: 80]
    
      %% =========================
      %% VPC + Networking
      %% =========================
      subgraph VPC[VPC 10.0.0.0/16\nscalableappbackend-dev]
        direction TB
    
        IGW[Internet Gateway]
    
        subgraph Public[Public Subnets\nus-east-1a + us-east-1b]
          direction TB
          ALB
          RTpub[Public Route Table\n0.0.0.0/0 -> IGW]
        end
    
        subgraph Private[Private Subnets\nus-east-1a + us-east-1b]
          direction TB
    
          subgraph ECSCluster[ECS Cluster\nscalableappbackend-dev-cluster]
            direction TB
    
            SVC[ECS Service\nscalableappbackend-dev-service\nDesiredCount: 2-6]
            TASKS[App Tasks (Fargate)\nContainer Port: 80\nRoutes: / and /health]
            LOCUST[Locust One-Off Task (Fargate)\n50 users, 3 min\nHits ALB DNS]
          end
    
          RTpriv[Private Route Table\n(no IGW default route shown)]
        end
    
        %% Route associations
        Public --- RTpub
        Private --- RTpriv
        IGW --- RTpub
      end
    
      %% ALB target routing into ECS tasks
      TG --> TASKS
    
      %% Locust traffic to ALB (internal test)
      LOCUST -->|HTTP traffic| ALB
    
      %% =========================
      %% Security Groups
      %% =========================
      SGALB[SG: ALB\nInbound: 80 from 0.0.0.0/0\nOutbound: 80 to ECS SG]
      SGECS[SG: ECS Service\nInbound: 80 from ALB SG\nOutbound: VPC endpoints]
      SGLOC[SG: Locust Task\nOutbound: 80 to ALB]
    
      ALB --- SGALB
      TASKS --- SGECS
      LOCUST --- SGLOC
    
      %% =========================
      %% Container Registry
      %% =========================
      subgraph ECR[ECR]
        direction TB
        ECRAPP[ECR Repo: scalableappbackend-dev-app\nTag: dev]
        ECRLOC[ECR Repo: scalableappbackend-dev-locust]
      end
    
      ECRAPP -->|image pull| TASKS
      ECRLOC -->|image pull| LOCUST
    
      %% =========================
      %% VPC Endpoints (Private Networking)
      %% =========================
      subgraph VPCE[VPC Endpoints (Interface/Gateway)]
        direction TB
        EP_ECR_API[Interface VPCE: ecr.api]
        EP_ECR_DKR[Interface VPCE: ecr.dkr]
        EP_LOGS[Interface VPCE: logs]
        EP_S3[Gateway VPCE: s3]
        EP_DDB[Gateway VPCE: dynamodb]
      end
    
      TASKS --> EP_ECR_API
      TASKS --> EP_ECR_DKR
      TASKS --> EP_LOGS
      TASKS --> EP_S3
      TASKS --> EP_DDB
    
      LOCUST --> EP_ECR_API
      LOCUST --> EP_ECR_DKR
      LOCUST --> EP_LOGS
    
      %% =========================
      %% Observability + Autoscaling
      %% =========================
      subgraph CW[CloudWatch]
        direction TB
        LOGS[Log Group\n/ecs/scalableappbackend-dev-app]
        METRICS[Metrics\nALB RequestCountPerTarget\nECS CPUUtilization]
        ALARMS[TargetTracking Alarms\nHigh/Low]
      end
    
      TASKS --> LOGS
      LOCUST --> LOGS
      ALB --> METRICS
      TASKS --> METRICS
      METRICS --> ALARMS
    
      subgraph AAS[Application Auto Scaling]
        direction TB
        POL_REQ[Policy: ALBRequestCountPerTarget\nTargetValue: 50]
        POL_CPU[Policy: ECSServiceAverageCPUUtilization\nTargetValue: 50]
      end
    
      ALARMS --> AAS
      AAS -->|Adjust DesiredCount| SVC
      POL_REQ --- AAS
      POL_CPU --- AAS
    
      %% =========================
      %% IAM (Execution + Task Roles)
      %% =========================
      subgraph IAM[IAM]
        direction TB
        EXECROLE[ECS Task Execution Role\nPull from ECR\nWrite logs to CloudWatch]
        TASKROLE[ECS Task Role\n(app permissions if needed)]
      end
    
      EXECROLE --> TASKS
      EXECROLE --> LOCUST
      TASKROLE --> TASKS

Autoscaling Signals:
• ALB RequestCountPerTarget
• ECS Service CPU Utilization

Observability:
• CloudWatch Metrics & Alarms
• ECS Scaling Activities
• Load Test Logs

---

## 1. Problem Statement (Situation)

Modern customer-facing services experience **unpredictable traffic patterns**.  
Teams often over-provision capacity to avoid outages, resulting in unnecessary cloud spend, or under-provision and suffer degraded performance during spikes.

The challenge was to design a backend that:
- Scales **only when real traffic exists**
- Responds automatically without manual intervention
- Maintains low latency under load
- Scales back down to reduce cost when traffic subsides

---

## 2. Solution Design & Implementation (Task + Action)

### Infrastructure & Design Decisions
- **Stateless ECS Fargate service** behind an Application Load Balancer
- **Infrastructure as Code** using Terraform for repeatability and auditability
- **Health-checked targets** to ensure zero-downtime scaling
- Horizontal scaling chosen over vertical scaling to improve fault tolerance

### Autoscaling Strategy
Implemented **target-tracking autoscaling** using two complementary signals:

**Primary: Request-Based Scaling**
```hcl
predefined_metric_type = "ALBRequestCountPerTarget"
target_value           = 50
```
This ensures scaling is driven by actual per-task load, not averages.

  ### Secondary: CPU Utilization Safety Net
  ```hcl
  predefined_metric_type = "ECSServiceAverageCPUUtilization"
  target_value           = 50
  ```
  Service bounds:
  ```hcl
  min_capacity = 2
  max_capacity = 6
  ```
  Cooldowns were configured to prevent oscillation during rapid traffic changes.

---

## 3. Validation via Load Testing (Action)

To validate scaling behavior, I executed load tests inside AWS, not locally.

### Test Configuration
•	Locust deployed as a one-off ECS task
•	50 concurrent users
•	5 users per second ramp-up
•	3-minute sustained load
•	Endpoints tested: / and /health

### Observed Traffic
•	~67,000 total requests
•	~375 requests per second
•	0% error rate
•	Median latency: ~3–4 ms
•	p99 latency: ~31 ms

---

## 4. Results & Measured Impact (Result)

### Automatic Scale-Out

During sustained load:
	•	ECS service scaled from 2 → 6 tasks
	•	Triggered by ALB request-based CloudWatch alarms
	•	All tasks registered as healthy in the target group

    Successfully set desired count to 6
    Triggered by ALB RequestCountPerTarget alarm

### Stability Under Load
•	Zero failed requests
•	No unhealthy targets
•	Consistent latency across scaled tasks

### Automatic Scale-In

After traffic stopped:
	•	Service scaled down from 6 → 5 → minimum
	•	No manual intervention required

This confirms elastic growth and recovery, not just scale-out.

---

## 5. Business Impact
•	Reliability
  •	Automatically absorbs traffic spikes without downtime
•	Cost Optimization
  •	Scales down during idle periods, reducing unnecessary spend
•	Operational Efficiency
  •	Eliminates manual scaling decisions and on-call intervention
•	Production Readiness
  •	Health-aware scaling prevents cascading failures
  •	Reproducible infrastructure supports faster iteration

This architecture mirrors real-world backend patterns used in high-scale environments.

---

## 6. Evidence of Success
•	CloudWatch scaling activities show successful scale-out events
•	ECS service metrics confirm desired and running counts matched
•	Target group health checks confirm all tasks remained healthy
•	Load test logs confirm sustained throughput with zero errors

---

## 7. Future Improvements

Planned enhancements include:
•	Latency-based autoscaling using custom CloudWatch metrics
•	Blue/green or canary deployments
•	WAF integration for edge protection
•	Distributed tracing for request-level observability
•	Automated CI/CD pipeline with GitHub Actions
•	Chaos testing (task and AZ failure simulation)

---

## Key Takeaway

This project demonstrates:
•	Production-grade autoscaling design
•	Load-driven decision making
•	Infrastructure as code discipline
•	Measurable performance and reliability outcomes

It reflects how scalable backend systems are designed, validated, and operated in real-world environments.

















  
