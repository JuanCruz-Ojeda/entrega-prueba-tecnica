import os

from flask import Flask, jsonify
import redis


REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
REDIS_PORT = int(os.environ.get("REDIS_PORT", 6379))


app = Flask(__name__)
r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, socket_connect_timeout=2)


@app.route("/")
def root():
    return jsonify(service="mini-app", status="ok")


@app.route("/health")
def health():
    return jsonify(status="healthy"), 200


@app.route("/cache-test")
def cache_test():
    try:
        key = "hits"
        r.incr(key)
        value = r.get(key).decode("utf-8")
        return jsonify(redis_host=REDIS_HOST, hits=value), 200
    except Exception as e:
        return jsonify(error=str(e), redis_host=REDIS_HOST), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
