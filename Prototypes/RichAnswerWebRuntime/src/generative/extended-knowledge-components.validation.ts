import { createParser } from "@openuidev/react-lang";
import { extendedKnowledgeComponentExamples } from "./extended-knowledge-components.examples";
import { weiBeiGenerativeLibrary } from "./library";

export function validateExtendedKnowledgeComponentExamples() {
  const parser = createParser(weiBeiGenerativeLibrary.toJSONSchema(), "RichAnswerRoot");
  return Object.entries(extendedKnowledgeComponentExamples).map(([name, source]) => {
    const result = parser.parse(source);
    return {
      name,
      hasRoot: result.root !== null,
      incomplete: result.meta.incomplete,
      unresolved: result.meta.unresolved,
      errors: result.meta.errors,
    };
  });
}
