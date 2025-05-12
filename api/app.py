from flask import Flask, jsonify
import os

# Import routes
from routes.classifier import classifier_blueprint

# Create Flask application
app = Flask(__name__)

# Register blueprints
app.register_blueprint(classifier_blueprint)

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "ok"})

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)
