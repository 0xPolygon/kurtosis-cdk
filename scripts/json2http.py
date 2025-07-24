from flask import Flask, jsonify, send_file, abort, url_for
import os

app = Flask(__name__)
app.config['JSONIFY_PRETTYPRINT_REGULAR'] = True

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
    file_path = os.path.normpath(os.path.join(BASE_DIR, subpath))
    if not file_path.startswith(BASE_DIR + os.sep):
        abort(403, "Access to the requested file is forbidden.")
    if os.path.isfile(file_path) and file_path.endswith('.json'):
        try:
            return send_file(file_path, mimetype='application/json')
        except Exception as e:
            abort(500, f"Failed to read file: {str(e)}")
    else:
        abort(404, f"JSON file not found: {subpath}")

if __name__ == '__main__':
    app.run()
