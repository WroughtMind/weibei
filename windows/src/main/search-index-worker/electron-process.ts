import path from "node:path";
import { utilityProcess } from "electron";
import type {
  SearchIndexUtilityProcess,
  SearchIndexUtilityProcessSpawner,
} from "./client";

export function makeSearchIndexUtilityProcessSpawner(): SearchIndexUtilityProcessSpawner {
  return () => utilityProcess.fork(
    path.join(__dirname, "search-index-worker.cjs"),
    [],
    {
      serviceName: "WeiBei Search Index",
      stdio: "ignore",
      env: utilityEnvironment(process.env),
    },
  ) as SearchIndexUtilityProcess;
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
  return Object.fromEntries(
    allowed.flatMap((name) => source[name] === undefined
      ? []
      : [[name, source[name] as string]]),
  );
}
