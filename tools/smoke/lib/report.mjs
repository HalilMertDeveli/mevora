const STEP_NAMES = [
  "Registration",
  "Age 18+",
  "Profile",
  "Photo 1",
  "Photo 2",
  "Photo 3",
  "Moderation",
  "Discover",
  "Like",
  "Match",
  "Message",
  "Block",
  "Report",
  "Delete Account",
];

export class SmokeReporter {
  constructor(options = {}) {
    this.environment = options.environment ?? "unknown";
    this.firebaseProject = options.firebaseProject ?? "unknown";
    this.platform = options.platform ?? "node";
    this.results = STEP_NAMES.map((name) => ({name, status: "BLOCKED", detail: ""}));
    this.failedStep = null;
    this.failedReason = "";
    this.cleanupStatus = "BLOCKED";
  }

  pass(index, detail = "") {
    this.results[index].status = "PASS";
    this.results[index].detail = detail;
  }

  fail(index, expected, actual, error = "") {
    this.results[index].status = "FAIL";
    this.results[index].detail = `expected=${expected}; actual=${actual}; error=${error}`;
    if (this.failedStep == null) {
      this.failedStep = STEP_NAMES[index];
      this.failedReason = this.results[index].detail;
    }
  }

  block(index, reason) {
    this.results[index].status = "BLOCKED";
    this.results[index].detail = reason;
  }

  render() {
    const lines = [
      "MEVORA PRODUCTION SMOKE TEST",
      "",
      `Environment: ${this.environment}`,
      `Firebase: ${this.firebaseProject}`,
      `App Version: ${process.env.SMOKE_APP_VERSION ?? "n/a"}`,
      `Platform: ${this.platform}`,
      `Device: ${process.env.SMOKE_DEVICE ?? "node"}`,
      `OS: ${process.platform}`,
      "",
    ];
    this.results.forEach((step, index) => {
      lines.push(`[${index + 1}] ${step.name.padEnd(18)} ${step.status}${step.detail ? ` — ${step.detail}` : ""}`);
    });
    lines.push("");
    lines.push(`FINAL RESULT: ${this.failedStep ? "FAIL" : "PASS"}`);
    if (this.failedStep) {
      lines.push(`Failed Step: ${this.failedStep}`);
      lines.push(`Reason: ${this.failedReason}`);
    }
    lines.push("");
    lines.push(`Cleanup: ${this.cleanupStatus}`);
    return lines.join("\n");
  }
}

export {STEP_NAMES};
