/// One schema step. [version] is the `PRAGMA user_version` reached after the
/// statements run. Migrations are append-only: never edit a released one,
/// add a new one with the next version number instead.
class Migration {
  const Migration(this.version, this.statements);

  final int version;
  final List<String> statements;
}

/// Timestamps are stored as INTEGER milliseconds since the Unix epoch (UTC).
/// Primary keys are TEXT UUIDs. Hierarchy foreign keys use ON DELETE RESTRICT
/// so a parent can never be deleted while children exist (no silent data
/// loss, no orphans); repositories offer an explicit transactional cascade.
/// review_history rows belong to a flashcard and are removed with it.
const List<Migration> allMigrations = [
  Migration(1, [
    '''
CREATE TABLE subjects (
  id          TEXT PRIMARY KEY NOT NULL,
  name        TEXT NOT NULL UNIQUE CHECK (length(trim(name)) > 0),
  description TEXT,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
)''',
    '''
CREATE TABLE books (
  id          TEXT PRIMARY KEY NOT NULL,
  subject_id  TEXT NOT NULL REFERENCES subjects(id) ON DELETE RESTRICT ON UPDATE CASCADE,
  name        TEXT NOT NULL CHECK (length(trim(name)) > 0),
  description TEXT,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  UNIQUE (subject_id, name)
)''',
    '''
CREATE TABLE topics (
  id          TEXT PRIMARY KEY NOT NULL,
  book_id     TEXT NOT NULL REFERENCES books(id) ON DELETE RESTRICT ON UPDATE CASCADE,
  name        TEXT NOT NULL CHECK (length(trim(name)) > 0),
  description TEXT,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  UNIQUE (book_id, name)
)''',
    '''
CREATE TABLE decks (
  id          TEXT PRIMARY KEY NOT NULL,
  topic_id    TEXT NOT NULL REFERENCES topics(id) ON DELETE RESTRICT ON UPDATE CASCADE,
  name        TEXT NOT NULL CHECK (length(trim(name)) > 0),
  description TEXT,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  UNIQUE (topic_id, name)
)''',
    '''
CREATE TABLE flashcards (
  id               TEXT PRIMARY KEY NOT NULL,
  deck_id          TEXT NOT NULL REFERENCES decks(id) ON DELETE RESTRICT ON UPDATE CASCADE,
  target_text      TEXT NOT NULL CHECK (length(trim(target_text)) > 0),
  association_text TEXT,
  definition_text  TEXT,
  image_path       TEXT CHECK (image_path IS NULL OR length(trim(image_path)) > 0),
  image_placement  TEXT NOT NULL DEFAULT 'front'
                   CHECK (image_placement IN ('front', 'back', 'both')),
  created_at       INTEGER NOT NULL,
  updated_at       INTEGER NOT NULL
)''',
    '''
CREATE TABLE review_history (
  id               TEXT PRIMARY KEY NOT NULL,
  flashcard_id     TEXT NOT NULL REFERENCES flashcards(id) ON DELETE CASCADE ON UPDATE CASCADE,
  reviewed_at      INTEGER NOT NULL,
  rating           INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 4),
  due_at           INTEGER,
  interval_days    INTEGER CHECK (interval_days IS NULL OR interval_days >= 0),
  ease_factor      REAL CHECK (ease_factor IS NULL OR ease_factor > 0),
  response_time_ms INTEGER CHECK (response_time_ms IS NULL OR response_time_ms >= 0)
)''',
    '''
CREATE TABLE app_settings (
  key        TEXT PRIMARY KEY NOT NULL CHECK (length(key) > 0),
  value      TEXT NOT NULL,
  updated_at INTEGER NOT NULL
)''',
    'CREATE INDEX idx_books_subject ON books(subject_id)',
    'CREATE INDEX idx_topics_book ON topics(book_id)',
    'CREATE INDEX idx_decks_topic ON decks(topic_id)',
    'CREATE INDEX idx_flashcards_deck ON flashcards(deck_id)',
    'CREATE INDEX idx_review_card_time ON review_history(flashcard_id, reviewed_at)',
    'CREATE INDEX idx_review_due ON review_history(due_at)',
  ]),
  Migration(2, [
    '''
ALTER TABLE flashcards
  ADD COLUMN status TEXT NOT NULL DEFAULT 'learning'
  CHECK (status IN ('learning', 'mastered', 'suspended'))''',
    'ALTER TABLE flashcards ADD COLUMN status_changed_at INTEGER',
    'ALTER TABLE review_history ADD COLUMN session_id TEXT',
    'CREATE INDEX idx_flashcards_status ON flashcards(deck_id, status)',
    'CREATE INDEX idx_review_card_session ON review_history(flashcard_id, session_id)',
  ]),
];
