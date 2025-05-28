# mdrunner

**mdrunner** automatically parses, executes, and validates code blocks embedded in Markdown files. It is especially useful for ensuring documentation examples remain runnable, testable, and up-to-date as part of our CI and development workflow.

## Features

- Parse Markdown files for embedded code blocks (e.g., \`bash\`).
- Execute commands in Docker containers for reproducible environments.
- Support inline annotations to control behaviour:
  - `# description: ...` — describe the block
  - `# skip` — skip execution
  - `# timeout: 60` — custom timeout per block (default: 30s)
  - `# env: new` — run in a fresh container (default is reused container)
- Honors YAML frontmatter to skip validation on an entire document:

  ```yaml
  ---
  validate: false
  ---
  ```

- Capture and report stdout/stderr.
- Fails on timeouts or non-zero exit codes.

## Requirements

- Python 3.7+
- Docker
- Python packages: `pip3 install pyyaml`

## Usage

```bash
python3 mdrunner.py <file_path>
```

Each code block is executed in a Docker environment, and its output is printed. If any block fails (due to timeout or a non-zero exit code), the process will terminate immediately with a non-zero exit status — making it CI-friendly and ensuring broken examples are caught early.

## Examples

Check the [examples](./examples/) folder.
