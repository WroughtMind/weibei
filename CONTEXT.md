# Domain Context

- **Course workspace**: The current collection of materials, notes, relations, study sessions, and learning memory. It is the Agent's durable scope; it is not the currently open file.
- **Material**: A source document used as course evidence, such as a PDF, HTML page, text file, or non-notebook Markdown file.
- **Notebook**: A user-editable course note. A notebook can be linked to many materials, and a material can be linked to many notebooks.
- **Note-source link**: A durable relation saying that a notebook uses or discusses a material. Opening a file does not create this relation.
- **Study location**: Observed navigation state for a material, including its last page or section and visit time. It is recorded by the app rather than inferred by the model.
- **Learning memory**: Durable user learning state such as goals, understood concepts, confusions, next steps, and preferences. Every entry keeps its origin and evidence; it is not course-source evidence.
- **Study session**: A recoverable conversation around a learning goal. Sessions persist across material navigation and own their messages, summary, focus items, and suggested study phase.
- **Study flow**: A flexible phase suggestion for orienting, exploring, close reading, note-making, recall, consolidation, or planning. The user can move between phases at any time.
