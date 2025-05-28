import logging
import re
import sys
import subprocess
import uuid
import yaml

DEFAULT_TIMEOUT_SECONDS = 30


class CodeBlock:
    def __init__(self, index, language, tags, commands):
        self.index = index
        self.language = language
        self.tags = tags
        self.commands = commands

    @property
    def description(self):
        return self.tags.get("description")

    @property
    def environment(self):
        return self.tags.get("env", "reuse").lower()

    @property
    def timeout(self):
        try:
            return int(self.tags.get("timeout", DEFAULT_TIMEOUT_SECONDS))
        except ValueError:
            logger.warning(
                f"Invalid timeout value in block #{self.index}. Using default.")
            return DEFAULT_TIMEOUT_SECONDS

    def should_skip(self):
        return "skip" in self.tags


class MarkdownDocument:
    def __init__(self, filepath):
        self.filepath = filepath
        self.code_blocks = []

    def parse(self):
        with open(self.filepath, "r", encoding="utf-8") as f:
            content = f.read()

        metadata, content = self._parse_frontmatter(content)
        if metadata.get("validate", True) is False:
            logger.info("Skipping validation.")
            return

        self.code_blocks = self._extract_code_blocks(content)

    def _parse_frontmatter(self, content):
        if content.startswith("---"):
            parts = content.split("---", 2)
            if len(parts) >= 3:
                try:
                    metadata = yaml.safe_load(parts[1])
                    return metadata or {}, parts[2]
                except yaml.YAMLError:
                    logger.warning("Failed to parse frontmatter")
        return {}, content

    def _extract_code_blocks(self, content):
        pattern = re.compile(r"```(\w+)?\n(.*?)```", re.DOTALL)
        matches = pattern.findall(content)

        blocks = []
        for i, (language, code) in enumerate(matches):
            tags = {}
            commands = []
            for line in code.strip().splitlines():
                if line.startswith("#"):
                    line = line[1:].strip()
                    if ": " in line:
                        k, v = line.split(": ", 1)
                        tags[k.strip()] = v.strip()
                    elif line:
                        tags[line.strip()] = "true"
                else:
                    commands.append(line)
            blocks.append(CodeBlock(i+1, language, tags, commands))
        return blocks


class ContainerRunner:
    def __init__(self, image="debian:bookworm-slim"):
        self.image = image
        self.container_id = self._start_container()

    def _start_container(self):
        container_name = f"mdrunner-{uuid.uuid4().hex[:8]}"
        result = subprocess.run(
            ["docker", "run", "-dit", "--rm", "--name",
                container_name, self.image, "/bin/bash"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True
        )
        return container_name

    def run(self, script, environment, timeout):
        if environment == "new":
            if self.container_id:
                subprocess.run(["docker", "rm", "-f", self.container_id],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.container_id = self._start_container()

        try:
            logger.debug(f"Container ID: {self.container_id}")
            result = subprocess.run(
                ["docker", "exec", self.container_id, "/bin/bash", "-c", script],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout,
                text=True,
                check=True
            )
            return result.stdout
        except subprocess.TimeoutExpired as e:
            raise TimeoutError(
                f"Command timed out after {timeout}s\n{e.stdout or ''}")
        except subprocess.CalledProcessError as e:
            raise RuntimeError(
                f"Non-zero exit code {e.returncode}:\n{e.stderr}")

    def cleanup(self):
        if self.container_id:
            subprocess.run(["docker", "rm", "-f", self.container_id],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.container_id = None


class CodeExecutor:
    def __init__(self, runner):
        self.runner = runner

    def run(self, block: CodeBlock):
        logger.info(
            f"▶️ Block id={block.index} description={block.description or 'N/A'}")
        if block.should_skip():
            logger.info("🚫 Code block skipped.")
            return

        if block.language == "bash":
            try:
                output = self.runner.run(
                    script="\n".join(block.commands),
                    timeout=block.timeout,
                    environment=block.environment
                )
                logger.info(f"Output:\n{output}")
            except subprocess.TimeoutExpired as e:
                logger.error(
                    f"Timeout exceeded: {block.timeout}s.\nPartial output (if any):\n{e.stdout or ''}")
                sys.exit(1)
            except subprocess.CalledProcessError as e:
                logger.error(f"Error (exit code {e.returncode}):\n{e.stderr}")
                sys.exit(1)
        else:
            logger.warning(f"Unsupported language: {block.language}")


def main(filepath):
    logger.info(f"Parsing markdown file: '{filepath}'")
    doc = MarkdownDocument(filepath)
    doc.parse()
    if not doc.code_blocks:
        return
    logger.debug(f"Extracted {len(doc.code_blocks)} code blocks.")

    runner = ContainerRunner()
    executor = CodeExecutor(runner)
    for block in doc.code_blocks:
        executor.run(block)

    logger.info("All code blocks have been processed.")
    runner.cleanup()


if __name__ == "__main__":
    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format="%(levelname)s: %(message)s"
    )
    logger = logging.getLogger(__name__)

    # Show usage if no arguments are provided.
    if len(sys.argv) != 2:
        logger.error("Usage: python3 mdparser.py <markdown_file>")
        sys.exit(1)

    main(sys.argv[1])
