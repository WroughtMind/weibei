# Domain Context

- **Course workspace**: A real local course project directory containing its materials, notes, relations, Chats, and learning memory. It is a durable Agent scope; it is not the currently open file.
- **Chat**: A recoverable conversation thread whose scope is fixed when it is created: either global or one course. A course can contain many Chats; their histories stay independent.
- **Material**: A source document used as course evidence, such as a PDF, HTML page, text file, or non-notebook Markdown file.
- **Notebook**: A user-editable course note. A notebook can be linked to many materials, and a material can be linked to many notebooks.
- **Note-source link**: A durable relation saying that a notebook uses or discusses a material. Opening a file does not create this relation.
- **Study location**: Observed navigation state for a material, including its last PDF page or stable HTML section id, section title, and visit time. It is recorded by the app rather than inferred by the model.
- **Course knowledge profile**: A hidden, portable course-level map of sections, concepts, and relations formed only from content the Agent actually read. Chats in the same course share it, but it is navigation rather than source evidence or user learning state; entries tied to a changed source are discarded.
- **Learning memory**: Durable user learning state such as goals, understood concepts, confusions, next steps, and preferences. Every entry keeps its origin and evidence; it is not course-source evidence. An active memory can be resolved only from an explicit current-turn user statement or demonstrated performance in the current conversation.
- **Study session**: The durable app record backing one Chat. It keeps the visible messages, focus items, fixed course scope, and suggested study phase. The same Chat id binds one Pi session, which owns model-facing conversation history and compaction; the app does not replay excerpts when that runtime state is rebuilt.
- **Study flow**: A flexible phase suggestion for orienting, exploring, close reading, note-making, recall, consolidation, or planning. The user can move between phases at any time.
- **Study Agent**: An assistant that works from the material the user is studying and the user's current question. It helps the user understand and explore; it does not own note production or automatic write-back.
- **Rich answer**: A Study Agent response that uses text plus a learning aid when visualization or interaction explains the material better than text alone. A rich answer is not a requirement to decorate every response.
- **Learning aid**: A temporary, question-specific artifact grounded in the studied material, such as an interactive chart, function plot, calculator, simulation, timeline, image overlay, proportion guide, or other manipulable explanation.
- **Answer form**: The medium used for a Study Agent response. The Agent chooses a fitting form by default; the user can request, replace, or later disable rich forms without changing the learning question.
- **Course search index**: A rebuildable local map used to locate relevant passages in course materials and notes. It is neither the Agent's course understanding nor a source of truth; answers still rely on the original passages actually read.
