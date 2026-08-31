import crypto from "node:crypto";
import fs from "node:fs";

const allowed = new Set(["pr.opened", "pr.merged", "deployment.completed", "incident.opened"]);
const type = process.env.INPUT_EVENT_TYPE;
if (!allowed.has(type)) {
  console.log(`::warning::Unsupported LumvaleOS event ${type}; event not emitted.`);
  process.exit(0);
}
const repository = process.env.GITHUB_REPOSITORY || "unknown";
const run = process.env.GITHUB_RUN_ID || "unknown";
const ref = process.env.GITHUB_SHA || "unknown";
const id = crypto.createHash("sha256").update(`${repository}|${type}|${run}|${ref}`).digest("hex");
const event = {
  specversion: "1.0", id, type, source: `github:${repository}`,
  time: new Date().toISOString(), workspace_id: process.env.INPUT_WORKSPACE_ID ||
    crypto.createHash("sha256").update(repository).digest("hex").slice(0, 32),
  subject: ref, data: { repository, run_id: run, ref },
};
const url = process.env.INPUT_INGRESS_URL;
if (!url) {
  const path = `${process.env.RUNNER_TEMP || "."}/lumvaleos-playbook-event-${id}.json`;
  fs.writeFileSync(path, JSON.stringify(event));
  console.log(`::notice::LumvaleOS ingress is not configured; preserved event at ${path}.`);
  process.exit(0);
}
try {
  const response = await fetch(url, {
    method: "POST", headers: {"content-type": "application/cloudevents+json",
      ...(process.env.INPUT_INGRESS_TOKEN ? {authorization: `Bearer ${process.env.INPUT_INGRESS_TOKEN}`} : {}),
      "idempotency-key": id}, body: JSON.stringify(event),
  });
  if (!response.ok) console.log(`::warning::LumvaleOS event emission returned HTTP ${response.status}; originating goal remains unchanged.`);
} catch (error) {
  console.log(`::warning::LumvaleOS event emission failed: ${error.name}; originating goal remains unchanged.`);
}
