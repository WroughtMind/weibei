import { SearchIndexWorkerServer } from "./server";

const parentPort = process.parentPort;
if (!parentPort) throw new Error("search-index-worker-parent-port-missing");

new SearchIndexWorkerServer(parentPort).listen();
