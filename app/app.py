import os
import socket
import redis
from flask import Flask, jsonify

app = Flask(__name__)
cache = redis.Redis(host=os.getenv("REDIS_HOST", "redis"), port=6379)

@app.route("/")
def home():
    return jsonify(served_by=socket.gethostname(), hits=cache.incr("hits"))

@app.route("/health")
def health():
    return jsonify(status="ok")
