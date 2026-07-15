# Domain Context

- **Course workspace**: The current collection of materials, notes, relations, study sessions, and learning memory. It is the Agent's durable scope; it is not the currently open file.
- **Material**: A source document used as course evidence, such as a PDF, HTML page, text file, or non-notebook Markdown file.
- **Notebook**: A user-editable course note. A notebook can be linked to many materials, and a material can be linked to many notebooks.
- **Note-source link**: A durable relation saying that a notebook uses or discusses a material. Opening a file does not create this relation.
- **Study location**: Observed navigation state for a material, including its last PDF page or stable HTML section id, section title, and visit time. It is recorded by the app rather than inferred by the model.
- **Learning memory**: Durable user learning state such as goals, understood concepts, confusions, next steps, and preferences. Every entry keeps its origin and evidence; it is not course-source evidence. An active memory can be resolved only from an explicit current-turn user statement or demonstrated performance in the current conversation.
- **Study session**: A recoverable conversation around a learning goal. Sessions persist across material navigation and own all messages, a rolling summary, bounded earlier-turn excerpts, focus items, and the suggested study phase. PI runs are clean; WeiBei injects this durable continuity every turn.
- **Study flow**: A flexible phase suggestion for orienting, exploring, close reading, note-making, recall, consolidation, or planning. The user can move between phases at any time.
- **Course search index**: A local persistent full-text index. PDF text layers are extracted in a separately monitored helper with CPU, resident-memory, output, and timeout limits; scanned pages are then OCRed incrementally. Truncated or failed pages are terminal partial evidence until the source file changes, so incomplete indexing is exposed instead of retried on every question or treated as a complete search.
