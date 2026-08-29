import { AgentWorkerServer } from "./server";

const parentPort = process.parentPort;
if (!parentPort) throw new Error("agent-worker-parent-port-missing");

new AgentWorkerServer(parentPort).listen();
