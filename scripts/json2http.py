import os
from flask import Flask, jsonify, send_from_directory, abort, url_for
from flask_wtf.csrf import CSRFProtect

app = Flask(__name__)
app.config['JSONIFY_PRETTYPRINT_REGULAR'] = True

# SonarQube CSRF protection
csrf = CSRFProtect()
csrf.init_app(app)

BASE_DIR = os.path.normpath('/opt')


@app.route('/')
def list_json_files():
    json_files = []
    for root, _, files in os.walk(BASE_DIR):
        # Calculate depth relative to BASE_DIR
        rel_root = os.path.relpath(root, BASE_DIR)
        depth = 0 if rel_root == '.' else rel_root.count(os.sep) + 1

        if depth > 1:
            continue  # skip folders deeper than second level

        for file in files:
            if file.endswith('.json'):
                rel_path = os.path.relpath(os.path.join(root, file), BASE_DIR)
                json_files.append(
                    url_for('serve_json', subpath=rel_path, _external=True)
                )

    return jsonify(json_files)

@app.route(f"{BASE_DIR}/<path:subpath>")
def serve_json(subpath):
    # Explicitly reject path traversal attempts
    if ".." in subpath or subpath.startswith("/"):
        abort(400, "Invalid path")

    # Optionally, only allow .json files
    if not subpath.endswith(".json"):
        abort(403, "Only JSON files are allowed")

    try:
        return send_from_directory(BASE_DIR, subpath, mimetype='application/json')
    except FileNotFoundError:
        abort(404, "File not found")
    except Exception as e:
        abort(500, f"Error reading file: {str(e)}")

if __name__ == '__main__':
    app.run()
