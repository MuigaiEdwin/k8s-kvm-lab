from flask import Flask, jsonify
import socket
import os

app = Flask(__name__)

@app.route('/')
def home():
    return jsonify({
        "message": "Hello from the backend !Scripted spinning the Containers, hahaha!!",
        "hostname": socket.gethostname(),
        "version": "v1.0"
    })

@app.route('/health')
def health():
    return jsonify({"status": "healthy"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
