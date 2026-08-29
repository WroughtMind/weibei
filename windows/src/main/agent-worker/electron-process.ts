import path from "node:path";
import { utilityProcess } from "electron";
import type { AgentUtilityProcess, AgentUtilityProcessSpawner } from "./client";

export function makeAgentUtilityProcessSpawner(): AgentUtilityProcessSpawner {
  return () => utilityProcess.fork(path.join(__dirname, "agent-worker.cjs"), [], {
    serviceName: "WeiBei Agent Network",
    stdio: "ignore",
    env: utilityEnvironment(process.env),
  }) as AgentUtilityProcess;
}

function utilityEnvironment(source: NodeJS.ProcessEnv): Record<string, string> {
  const allowed = [
    "COMSPEC",
    "LANG",
    "LOCALAPPDATA",
    "SYSTEMDRIVE",
    "SYSTEMROOT",
    "TEMP",
    "TMP",
    "USERPROFILE",
    "WINDIR",
  ];
  return Object.fromEntries(allowed.flatMap((name) => source[name] === undefined ? [] : [[name, source[name] as string]]));
}
