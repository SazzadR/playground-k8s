import socket

from flask import Flask

app = Flask(__name__)


@app.route("/")
def home():
    return f"Hello from Kubernetes demo app. Host: {socket.gethostname()}!. Version: 1.1"
