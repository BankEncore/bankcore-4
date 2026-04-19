# ADR [0000]: [Short, Descriptive Title]

* **Status:** [Proposed | Accepted | Deprecated | Superseded by ADR-000]
* **Date:** YYYY-MM-DD
* **Deciders:** [List of stakeholders/engineers involved]
* **Consulted:** [List of experts or teams consulted]

---

## 1. Context and Problem Statement
Describe the issue we are facing. What is the technical or business requirement that necessitates a change or a decision? 

> **Tip:** Keep this objective. Frame it as a problem to be solved, not just a desire for a new shiny tool.

## 2. Decision Drivers
List the key factors that influenced this decision. For example:
* Need for high availability (99.9%).
* Minimizing operational overhead.
* Compatibility with existing CI/CD pipelines.
* Budget constraints.

## 3. Considered Options
Briefly list the alternatives that were evaluated. 

| Option | Pros | Cons |
| :--- | :--- | :--- |
| **Option A** | Fast implementation, low cost. | High technical debt, poor scaling. |
| **Option B** | Industry standard, robust support. | Steep learning curve, expensive. |
| **Option C** | Perfect technical fit. | Custom-built, high maintenance. |

## 4. Decision Outcome
**Chosen Option: [Option Name]**

Explain why this choice was made. How does it satisfy the decision drivers better than the alternatives?

### Technical Consequences
* **Positive:** (e.g., "Reduced latency by 200ms," "Easier onboarding for new devs.")
* **Negative:** (e.g., "Adds a new dependency to the stack," "Requires manual migration.")
* **Neutral:** (e.g., "Requires a one-time training session.")

---

## 5. Implementation Plan
* [ ] Step 1: Proof of Concept.
* [ ] Step 2: Security Review.
* [ ] Step 3: Production Rollout.

## 6. More Information
Link to any relevant documentation, whitepapers, or meeting notes that provide deeper context.

---

### Best Practices for ADRs
* **Keep it concise:** If it takes more than 10 minutes to read, it’s probably too long.
* **Be honest about the "Cons":** Every decision has a trade-off. Documenting the downsides builds trust and prepares the team for future hurdles.
* **Store them in Git:** Keep your ADRs in the same repository as the code they describe. This ensures the documentation evolves alongside the system.