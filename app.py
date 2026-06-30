from flask import Flask
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry.instrumentation.flask import FlaskInstrumentor
import logging
import random
import time

configure_azure_monitor()  # reads APPLICATIONINSIGHTS_CONNECTION_STRING

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)  # ensure AppRequests telemetry under gunicorn

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


@app.route("/")
def home():
    logger.info("home endpoint hit")
    return "OK", 200


@app.route("/slow")
def slow():
    delay = random.uniform(0.5, 2.0)
    time.sleep(delay)
    logger.info("slow endpoint hit, delay=%.2f", delay)
    return f"slow {delay:.2f}s", 200


@app.route("/error")
def error():
    logger.error("about to raise demo exception")
    raise ValueError("Demo exception for App Insights")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
